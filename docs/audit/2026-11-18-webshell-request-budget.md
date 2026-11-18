# WebShell 请求预算分析：每轮对话发多少请求、发了什么

- 日期：2026-11-18
- 分支：dev20261118
- 口径：**一轮对话** = 终端里提交一条命令 → 收到输出（不含 Tab 补全、文件管理）
- 方法：静态追踪 `executeCommand` → 连接器 → HTTP 调用点；载荷体积按内置资产实测（`wc -c`）
- 局限：未做运行时抓包，请求次数来自代码路径（确定性），体积为估算上限

## 0. 结论先说

1. **命令通道本身没有重复请求**：稳态每条命令 **1 次** HTTP（首次因建会话为 2 次）。
2. 浪费集中在三处：**打开工作区的 5–10 次预热**、**JSP/ASPX 每轮重传 12–20KB 固定载荷**、**HTTPS 目标每条命令重建连接**。
3. 最容易见效的是预热合并 + PATH 扫描改写（低风险，立刻少 3–4 次请求 / 大幅降低目标端 CPU）。

## 1. 每轮对话的请求数

| 连接器 | 首条命令 | 稳态每条 | 依据 |
| --- | --- | --- | --- |
| `php_eval` / `php_b64rot13` | 1 | 1 | `sendPhpCode` 单次 POST（`php_eval_connector.dart:37`） |
| `php_passthru` | 1 | 1 | `sendRawCommand` 单次（`php_passthru_connector.dart:27`） |
| `php_behinder` | 1 | 1 | `_sendPhp` 单次 POST |
| `jsp_behinder` | 2 | 1 | 首次 `_ensureSession` GET + POST（`jsp_behinder_connector.dart:106`） |
| `jsp_behinder_v2` | 2 | 1 | 同上 |
| `jsp_classloader` | 1 | 1 | 每次自带 agent，无会话 GET |
| `jsp_runtime` | 1 | 1 | `sendRawCommand` |
| `aspx_behinder` | 1 | 1 | `_send` 单次 POST |
| `aspx_cmd` | 1 | 1 | 单次 |
| `asp_wscript` | 1 | 1 | 单次 |
| `godzilla` | 2（seed + call） | 1 | `ensureSeeded` 仅首次 |

> `cd` 命令已做成单请求（marker + pwd 合并，`webshell_interactive_page.dart:981`），这块没有浪费。

## 2. 打开工作区的请求清单（真正的"风暴"）

`_TerminalTabState.initState` → `_initDir()`（`webshell_interactive_page.dart:110`）：

| 动作 | 请求数 | 备注 |
| --- | --- | --- |
| `_checkConnection` → `ping()` | 1–2 | 仅当持久化状态未知；`php_behinder` 最坏 2（ECB 失败再试 CBC，`php_behinder_connector.dart:163`），`jsp` 2（含 session GET），`godzilla` 2–3 |
| ping 失败后的 `exec` 回退 | +1 | `webshell_interactive_page.dart:143` |
| `getShellScriptDir()` | 1–5 | `jsp`：sysinfo 1 次 + 最多 4 次 find/pwd（`jsp_webapp_path.dart:99-146`）；`php_behinder`：复合探测最多 4 次重试（`php_behinder_connector.dart:292`） |
| 回落 `getCurrentDir()` | +1 | 脚本目录解析失败时 |
| `fetchEnvVars()` | 1 | |
| `fetchHomeDir()` | 1 | |
| `fetchAvailableCommands()` | 1 | **重命令**：遍历 PATH 每个目录的每个文件（`webshell_interactive_terminal_shared.dart:148`） |

**合计：稳态 5–6 次，最坏 10 次**（JSP 系）。且 `env/home/commands` 三个请求是并发发出的，现在被串行队列排队（`serial_queue.dart`），墙上时间会叠加。

## 3. 每一轮到底发了什么

| 连接器 | 每轮 body 体积 | 内容 |
| --- | --- | --- |
| `php_passthru` / `jsp_runtime` / `asp_wscript` | < 0.2 KB | 纯命令字符串 |
| `php_eval` | 0.3–0.5 KB | `参数名=<php eval(base64_decode('code'))>`，code 内含 shell_exec→system 选择逻辑 |
| `php_behinder` | ≈1.5 KB | `AES_CBC(C\|php包装{encrypt 函数 + ob_start + JSON + 业务 code})` → base64 |
| `jsp_behinder` | **≈19.8 KB** | 第 1 行 `base64(agent M.class)` = **19,604 B**（`data/jsp_agent_M.b64`）+ 第 2 行 AES 参数 |
| `jsp_classloader` | **≈20.8 KB** | 同一份 19,604 B agent，**再经表单百分号编码**（`jsp_classloader_connector.dart:158` 只保留 `A-Za-z0-9-_.~`，`+` `/` `=` 各膨胀为 3 字节，约 +1.2 KB） |
| `jsp_behinder_v2` | 5–10 KB | 动态生成 class，无 agent 文件，但每次重新生成 |
| `aspx_behinder` | **≈12.3 KB** | `AES( Cmd.dll 9,216 B + 参数 )` → base64（`data/behinder_csharp/Cmd.b64` 12,288 B；FileOperation 为 38,232 B，单轮 ≈51 KB） |
| `godzilla` | ≈14 KB | eval 装载器（seed 时一次 13.7 KB，之后每条装载器 + 参数） |
| `Tab 补全` | 1 请求/次 | 远端 `for f in "$d"/"$p"*` 列目录 |
| `上传` | ⌈size/256KB⌉ + 1 | 分块，成功后还会 `_loadDirectory` 再列一次 |

一句话：**JSP/ASPX 每轮都在重传整个 agent/DLL**。执行 `whoami`（5 字节）→ 上行 19.8 KB / 12.3 KB。

## 4. 可简化清单（按收益排序）

### S1【高】JSP 固定 agent：每条 19.6 KB
- 现状：`jsp_behinder` / `jsp_classloader` 每次都传完整 agent。
- 方案 A：复用注入好的常驻内存马，后续只发参数（项目已有 mem shell 能力）。
- 方案 B：给命令通道做一个 **mini agent**（只做 exec），目标 ≤2 KB。
- 预估：上行流量 −90%。

### S2【高】ASPX 每条 12 KB DLL
- 现状：`_send` 每次 `_load(dll)` 并把 DLL 拼进 body（`aspx_behinder_connector.dart:39-51`）。
- 方案：首次把 DLL 落到目标临时目录/AppDomain，之后只发参数。
- 预估：−12 KB/条。

### S3【高·低风险】把 3 个预热请求合并成 1 个
- 现状：env / HOME / PATH 扫描各一次。
- 方案：一条复合命令 + 分隔符一次性取回（`parseSepOutput` 已有现成解析器，`shell_exec_connector.dart`）。
- 预估：少 2 次往返；会话型连接器少 2 次锁排队。

### S4【高·低风险】PATH 扫描改用 `compgen -c`
- 现状：`for d in $PATH; do for f in "$d"/*; do ...` —— 目标端要 stat 上万个文件。
- 方案：bash 内建 `compgen -c`（或 `compgen -A command`）一条命令出结果；并改为**首次 Tab 才触发**。
- 预估：目标端 CPU/IO 大降，请求数不变。

### S5【中】脚本目录探测收敛
- 现状：JSP 最多 5 次（sysinfo + 4 级 find）；php_behinder 最多 4 次重试。
- 方案：`sysinfo`/`pwd` 一次定胜负，失败直接回退 `pwd`；多级 find 挪到"定位网站根目录"按钮按需触发。
- 预估：少 3–4 次请求、少 1–2 秒。

### S6【中·低风险】复用 HTTP 连接
- 现状：`php_eval`/`php_b64rot13`/`php_passthru`/`jsp_runtime`/`asp_wscript`/`aspx_cmd` 用顶层 `http.post`，每条命令新建连接。
- 方案：与 `jsp_behinder` 一致，持有 `http.Client`。
- 预估：HTTPS 目标每条省 1 个 TCP+TLS 握手（数十 ms）。

### S7【中】Tab 补全加目录缓存
- 现状：每次 Tab 一次远端 glob（R5 清理后确认无缓存）。
- 方案：30s TTL + 写操作失效。
- 预估：连续补全 N 次 → 1 次。

### S8【中】记住 `php_behinder` 加密模式
- 现状：每次 ping 先 ECB、失败再 CBC（2 次），即使上次已确认 CBC（`php_behinder_connector.dart:163`）。
- 方案：把协商结果持久化到连接器字段并在下次优先使用。
- 预估：每次建连少 1 次请求。

### S9【低】上传/删除后重列目录
- 现状：成功后 `_loadDirectory`（`webshell_interactive_file_manager.dart:334`）。
- 方案：本地增量更新，或延迟到切页刷新。

### S10【低】MCP `shell_list` 全量 ping
- 现状：列出 N 个 shell 就 ping N 次（并行，`webshell_connectivity_service.dart:22`）。
- 方案：默认返回缓存状态，加 `refresh: true` 才探测。

## 5. 两个典型场景总账

**JSP-BHD，打开工作区 + 执行 10 条命令：**
- 请求：open 6–9 + 命令 10 = **16–19 次**
- 上行：open ≈0.5 KB + 命令 10×19.8 KB ≈ **198 KB**

**PHP-eval，同样操作：**
- 请求：open 5 + 命令 10 = **15 次**
- 上行：≈ **6 KB**

→ 同样 10 条命令，JSP 系上行是 PHP 系的 **30 倍**，瓶颈在 S1 而非请求数。

## 6. 建议落地顺序

| 顺序 | 项 | 风险 | 预期 |
| --- | --- | --- | --- |
| 1 | S3 + S4（预热合并 + `compgen -c`） | 低 | 打开少 2 次请求，目标端 CPU 大降 |
| 2 | S6 + S7（连接复用 + 补全缓存） | 低 | HTTPS 每命令省 1 RTT；Tab 省 N-1 次 |
| 3 | S5 + S8（探测收敛 + 记住加密模式） | 低 | 打开少 3–5 次请求 |
| 4 | S1 + S2（agent/DLL 驻留） | 高（协议层） | 上行 −90%，需目标端配合 |

## 7. 实测对比（Docker：PHP 7.2/Apache + Tomcat 8.5）

用 `tool/verify/request_profile.dart` 在连接器与目标之间插入计数代理，
同一交互序列（打开工作区 → 3 条命令 → 2 轮 Tab）实测：

| 目标 | 原始 | 预热合并 + 缓存 | 再取消目录探测 |
| --- | --- | --- | --- |
| PHP `php_eval` | 11 请求 / 7,590 B | 8 请求 / 6,980 B | **8 请求 / 2,945 B** |
| JSP `jsp_runtime` | 11 请求 / 2,948 B | 8 请求 / 2,402 B | **8 请求 / 1,812 B** |

- 打开阶段上行：PHP 4,710 B → **675 B**，JSP 1,236 B → **664 B**
- 目录探测取消后：`open: scriptDir` 从 **4,076 B**（PHP 复合探测载荷）降到 **41 B**（仅 `pwd`）

逐项：

| 步骤 | 改造前 | 改造后 |
| --- | --- | --- |
| 打开（ping + 脚本目录 + 预热） | 5 请求 | **3 请求**（预热合并为 1） |
| 第 2 轮 Tab（目录 + 命令） | 2 请求 | **0 请求**（TTL 缓存命中） |
| 单条命令 | 1 请求 | 1 请求（不变） |

附带发现：PHP 的脚本目录探测单次上传 **4,076 B**（`php_eval` 复合探测载荷），
是打开阶段最大的一笔上行；JSP 走 sysinfo 只有 708 B。该探测已按要求取消。

> 行为变化：终端/文件管理器的初始目录现在是目标**进程 cwd**（如
> `/usr/local/tomcat`），不再是 webshell 脚本所在目录。需要脚本目录的操作
> （一键上传隧道脚本）仍显式调用 `getShellScriptDirectory()`。

复现：

```bash
# 目标：Apache+PHP 与 Tomcat 各起一个容器，放入内置 shell
dart tool/verify/request_profile.dart php_eval http://127.0.0.1:18080/shell.php mAtrix_911 POST new
dart tool/verify/request_profile.dart jsp_runtime http://127.0.0.1:18081/mx/shell.jsp mAtrix_911 GET new
```

## 8. 未验证项

- 无运行时抓包：请求次数来自代码路径，实际可能因重试/超时分支更多（只多不少）。
- `godzilla` 的每条命令 body 体积未逐字节复算（按 13,671 B 资产 + 装载器估算）。
- 未评估目标端 WAF 对 19.8 KB 单请求体的拦截率（体积大本身也可能是触发点）。
