# Matrix 代码质量与数据安全审计

- 日期：2026-11-18
- 分支：dev20261118
- 范围：`lib/` 全量（149 个 Dart 文件 / 50,306 行）+ 存储、MCP、隧道服务、构建配置
- 维度：① 冗余内容 ② 关键内容泄漏 / 数据安全 ③ 互斥竞争
- 方法：静态阅读 + 结构化检索 + 重复代码窗口哈希度量；所有结论附 `文件:行号` 证据

## 度量基线

| 指标 | 数值 |
| --- | --- |
| Dart 文件 / 行数 | 149 / 50,306 |
| 跨文件重复代码块（10 行窗口，去平凡行） | **675 处** |
| 最大文件 | `core/crypto/jvm_bytecode.dart` 2,441 行；`pages/webshell_interactive_page.dart` 1,765 行 |
| 测试文件 | 38 个（覆盖率未知，无统计） |
| CI | **无**（无 `.github`） |
| 静态检查 | 仅 `flutter_lints`，未启用 `avoid_print` 等 |

---

## 修复进展（2026-11-18，分支 dev20261118）

| 条目 | 状态 | 提交 | 说明 |
| --- | --- | --- | --- |
| C1 终端卡死 | ✅ 已修复 | `0d8fffd` | `_execute` 改为 try/catch/finally，异常落到输出区并必复位 `_executing` |
| C2 失败永久缓存 | ✅ 已修复 | `6dd8adf` | 探测失败清空 memo，下次调用可重试 |
| C3 会话并发 | ✅ 已修复 | `167ac18` | 新增 `SerialQueue`（按 URL 共享），JSP-BHD / JSP-BHD2 / ASPX-BHD / PHP-BHD 全部串行 |
| C4 写锁不一致 | ✅ 已修复 | `a8a76e8` | 锁上移 `services/`，UI 上传/写入/删除与 MCP 共用 `shared` 实例 |
| C5 SessionPool 竞态 | ✅ 已修复 | `6dd8adf` | 缓存创建中的 Future |
| C6 DB 双开 | ✅ 已修复 | `6dd8adf` | 缓存打开中的 Future，失败可重试 |
| L1 凭据落盘 | ⚠️ 部分修复 | `a8a76e8` | 目录 0700 / db 0600 已收敛；**静态加密（Keychain/sqlcipher）仍未做** |
| L2 MCP 日志泄漏 | ✅ 已修复 | `a8a76e8` | password/secret_key/token/cookie 统一遮蔽，content 只记长度 |
| C7 SUO5 启停竞态 | ⏳ 未修 | — | 建议下一批处理 |
| C8 上传取消残留 | ⏳ 未修 | — | 建议 `.part` + 原子 rename |
| L3 TLS 跳过 | ⏳ 未修 | — | 需要产品层决策（显式 insecure 开关） |
| L6 监听默认 0.0.0.0 | ⏳ 未修 | — | 改默认值需评估远程回连场景 |
| R1–R8 冗余 | ⏳ 未修 | — | 结构性问题，建议按 R1/R2/R5 顺序重构 |

验证方式：

- `dart analyze lib`：本次改动无新增 error / warning（剩余为既有 info 与 `jvm_bytecode` 既有 unused 告警）
- `dart run tool/verify/verify_fixes.dart`：**15/15 通过**（串行队列互斥与 FIFO、异常不阻塞、按 key 共享、日志脱敏、权限 0700/0600）
- 说明：本机 Flutter CLI 受文件沙箱限制（无法写 `$FLUTTER_ROOT/bin/cache`），因此未执行 `flutter test`；UI 侧改动以静态分析 + 纯 Dart 组件测试覆盖，未做真机/真目标联调。

---

## 一、冗余内容

### R1【高】输入框装饰样式被复制 25 次 / 10 个文件
`enabledBorder: OutlineInputBorder(...)` 全项目 **25 次**，分布在 `project_management_page.dart`(6)、`webshell_management_page.dart`(4)、`zentao_exp_page.dart`(3)、`thinkphp_exp_page.dart`(3)、`vulhub/struts2_exp_page.dart`(2)、`vulhub/drupal_exp_page.dart`(2) 等 10 个文件。

- 影响：改一次主题色要动 10 个文件；已出现漂移（部分页面 `alpha: 0.5`，部分 `const` 无 alpha）。
- 建议：在 `theme/app_theme.dart` 提供 `AppTheme.inputDecoration({label})`，全量替换。

### R2【高】目录解析/排序逻辑在每个连接器各写一遍
`whereType<FileEntry>` 解析出现在 **7 处 / 6 个文件**（`php_behinder_connector.dart:379`、`jsp_behinder_connector.dart:295`、`jsp_classloader`、`jsp_behinder_v2`、`aspx_behinder`、`php_eval`）；"`..` 置顶 + 目录优先"的比较器在 **7 个文件**里各写了一份。

- 影响：排序规则改动需同步 7 处，易出现某一连接器行为不一致。
- 建议：`ShellConnector` 提供 `parseLsLa()` / `sortEntries()` 单一实现（`shell_exec_connector.dart` 已有同类函数可复用）。

### R3【中】连接器间复制粘贴
- `_sq()` 单引号转义：**5 份**完全相同的实现（`php_eval:90`、`php_behinder:192`、`jsp_behinder:226`、`jsp_classloader:263`、`jsp_behinder_v2:202`）。
- 反弹 shell 命令串：**5 份**（`shell_connector.dart`、`php_eval`、`php_behinder`、`apache_family_services.dart`、`spring_exp_page.dart`）。
- 建议：抽 `ShellQuoting.sq()` 与 `ReverseShellCommand.build({preferScript, lhost, lport})`。

### R4【中】`database_helper.dart` 与 `database_helper_io.dart` 双份实现
FRP/SUO 的 `name/serverAddr/serverPort/token/proxyName/remotePort/localAddr…` 参数与方法签名重复 **10–12 次**（`database_helper.dart:121-164`、`database_helper_io.dart:604-648/796-839`）。

- 说明：`stub + io` 是条件导入的常见写法，但当前把"数据访问 + 参数搬运 + 表结构"都复制了。
- 建议：保留接口层，表结构与 SQL 只写在 io 侧；stub 仅抛 `UnsupportedError`。

### R5【高】目录补全缓存是死代码，且每次 Tab 都发远端命令
`TabCompleter.warmDir()` / `invalidateDir()` 是**空实现**：

```dart
// webshell_interactive_terminal_shared.dart:125,128
Future<void> warmDir(String dir, {bool force = false}) async {}
void invalidateDir(String dir) {}
```

但页面仍在 4 处调用它们（`webshell_interactive_page.dart:935, 1000, 1001, 1012`），且 `_listByPrefix`（`terminal_shared.dart:206`）每次补全都执行远端 `for f in ...` 命令。

- 影响：注释宣称"cd 后使旧目录缓存失效、warmDir 预热"，实际零收益；Tab 补全延迟 = 一次网络往返，弱网下显著卡顿。
- 建议：要么实现缓存（`Map<String, List<Entry>>` + TTL），要么删除 `warmDir/invalidateDir` 与调用点，避免误导。

### R6【低】安装包体积：33 MB `assets/`，其中 ~30 MB 是 11 个 copyfail 二进制
`assets/defaults/payloads/copy-fail/copyfail-go-linux-*` 各 2.6–2.9 MB（`seed_service.dart:183+` 全量注册）。

- 影响：全部打进安装包，但绝大多数用户只用 amd64/arm64。
- 建议：按需下载或只内置 2 个主流架构，其余标记为可选资源。

### R7【低】巨型文件 + 零测试区
`jvm_bytecode.dart` 2,441 行（字节码生成）、`payload_obfuscator.dart` 1,488 行，均无对应测试；`webshell_interactive_page.dart` 1,765 行承载 6 类 UI 职责。

- 建议：`jvm_bytecode` 至少有字节码结构单测（可用 `javap` 校验）；页面按 Tab 拆文件。

### R8【中】质量闸门缺失
无 CI、无覆盖率门槛、`analysis_options.yaml` 仅继承 `flutter_lints`。

- 建议：加 GitHub Actions：`flutter analyze` + `dart test` + 关键连接器的 payload 快照测试。

---

## 二、关键内容泄漏 / 数据安全

### L1【严重】凭据明文落盘，且无任何静态加密
`~/.matrix/matrix.db`（`matrix_storage.dart:15`）中：

```dart
// database_helper_io.dart:136-142
CREATE TABLE webshells (
  ...
  password TEXT,
  secret_key TEXT NOT NULL DEFAULT 'key',
```

- 明文写入点：`webshell.dart:49-56`（`toMap` 含 `password`/`secret_key`）、`mcp/db.dart:130-131`、`database_helper_io.dart:740-750`；FRP token 同样明文（`frp_profiles.token TEXT`，`:188`）。
- 全仓库**无** `sqlcipher` / `flutter_secure_storage` / Keychain 引用；`~/.matrix` 与 `matrix.db` **无 chmod/0600**（无任何权限收敛代码）。
- 泄漏路径：任何能读用户目录的进程（同类木马、恶意插件、Time Machine/iCloud 备份、误打包的 support bundle）可直接取得全部目标口令与 Godzilla 密钥 → 直接接管目标。
- 修复：
  1. 口令/密钥改用 `flutter_secure_storage`（macOS Keychain）或 sqlcipher 加密库；
  2. 退一步至少 `chmod 700` 目录 + `chmod 600` 数据库文件，启动时校正；
  3. 导出/备份功能默认剔除凭据字段。

### L2【高】MCP 活动日志只过滤了 `password`，`secret_key` 原样入日志
```dart
// mcp/handlers.dart:84
.where((entry) => entry.key != 'password')
```

- 后果：`webshell_add` 等调用的 `secret_key` 会进入 MCP 页面日志（`mcp_server_page.dart:134` → 页面 `_log`），并可通过"复制日志"按钮（`:372`）一键带出。
- 修复：敏感键改成白名单/黑名单常量集（`password`, `secret_key`, `token`, `cookie`），并对 `content` 之外的长字段统一 `***`。

### L3【高】TLS 校验存在"一键关闭"通道，且部分服务默认关闭
```dart
// core/http/http_client.dart:47-49
if (!allowBadCertificate) return http.Client();
final io = HttpClient()..badCertificateCallback = (_, __, ___) => true;
```
同类还有 `suo5_client_service.dart:324, 883`、`suo6_client_service.dart:525`、`exp/vulhub/services/runtime_services.dart:387`。

- 现状：`MatrixHttpClient` 的调用方目前多为 `allowBadCertificate: false`（已核对 8 处），但 suo5/suo6 与 runtime_services 是**无条件**接受任意证书。
- 风险：中间人可替换隧道/反弹流量；对"通过 HTTPS 传输 WebShell 口令"的安全假设直接失效。
- 修复：改为显式 `--insecure` 式开关 + 每个目标记忆一次 + UI 明示"已跳过证书校验"；suo5/suo6 至少做成可配置。

### L4【中】控制台日志输出目标 URL，release 下进入系统日志
`webshell_interactive_page.dart:123-146` 的 `matrixConsoleLog('[ping] ... url=${widget.webshell.url}')` 经 `utils/matrix_console_log.dart:13` 的 `print` 输出；macOS release 会落到统一日志（Console.app 可查、可被日志采集器收走）。URL 若带 `user:pass@` 则等同泄漏凭据。

- 修复：日志脱敏（去 userinfo、截断 query），或 debug 构建才输出。

### L5【中，设计使然但需收敛】默认口令 `mAtrix_911` / Godzilla 默认 `key` 写死
`connector_factory.dart:66`、`jsp_classloader_connector.dart:149-154`、内置 payload 与 README 均使用同一默认值。

- 说明：作为"示例 shell 的默认口令"可接受；风险在于用户直接把示例 shell 传上生产后忘记改密。
- 建议：上传内置 payload 时弹出"该 shell 使用公开默认口令"的强提示；连接器检测到 `mAtrix_911` 时在 UI 标红。

### L6【中】反弹 shell 监听默认绑 `0.0.0.0` 且无来源校验
`reverse_shell_service.dart:204`（`startListening({address = '0.0.0.0'})`）。

- 风险：局域网内任意主机可先连入，占用/劫持会话；服务无 token、无白名单。
- 建议：默认 `127.0.0.1`，需要接收远端回连时显式切换并提示防火墙暴露面。

### L7【低】一键复制 URL 到剪贴板
`webshell_management_page.dart:880`。若用户 URL 里带 userinfo，剪贴板会被其他应用读取。建议复制前剥离凭据并提示。

---

## 三、互斥 / 竞态

### C1【高】`_execute` 缺 try/finally：一次异常让终端永久卡死
```dart
// webshell_interactive_page.dart:983
final execResult = await widget.service.executeCommand(sendCmd, workingDir: _currentDir);
...
setState(() { entry.output = ...; _executing = false; });
```

`_executing` 只在正常路径复位。任何抛出（连接器实现缺陷、类型错误、`StateError`、dispose 竞态）都会让 `_executing` 永远为 `true` → 输入框 `readOnly` 永久、后续命令全部被 `if (_executing) return;` 吞掉。

- 修复：`try { ... } finally { if (mounted) setState(() => _executing = false); }`，并把异常渲染成终端里的一行 `[Error]`。

### C2【高】memoized Future 把"首次失败"永久缓存
```dart
// webshell_service.dart:63-70
Future<String?> getShellScriptDirectory() {
  _memoShellScriptDir ??= _connector.getShellScriptDir();
  return _memoShellScriptDir!;
}
```

Future 在创建时即赋值（并发安全，这点没问题），但**失败结果同样被缓存**：首次探测因网络抖动抛错后，该 `WebshellService` 生命周期内每次调用都立即以同一异常失败，无法重试。

- 修复：`catch` 后置空缓存再 rethrow，或只缓存成功值。

### C3【高】只有 php_behinder 做了请求串行化，其余会话型连接器没有
`php_behinder_connector.dart:83-96` 用 `_phpSendGate` 串行化（注释明确写了"冰蝎依赖 Session，并发 POST 易 200+空 body"）。但同样依赖 `Set-Cookie` 会话的 `jsp_behinder_connector.dart:30,67`、`aspx_behinder_connector.dart`、`godzilla_transport.dart:48` **都没有闸门**。

触发路径很明确：打开 WebShell 工作区时，`_TerminalTabState._initDir` 一次性并发发起 3 个真实请求（`webshell_interactive_page.dart:935-938`：`fetchEnvVars` / `fetchHomeDir` / `fetchAvailableCommands`），此外 Tab 补全（`terminal_shared.dart:206`）随时会再插一条。

- 后果：同一连接器上 `_cookies` 被并发 `Set-Cookie` 覆盖、服务端 session 串号、偶发 200 空响应。
- 修复：把 `_phpSendGate` 上提为 `ShellConnector` 的通用 `_sendGate`（或 `SerialQueue`），所有会话型连接器复用。

### C4【中】UI 与 MCP 各持一把锁，互不感知
`RemoteWriteLockCoordinator` 只在 MCP 侧使用（`mcp/handlers.dart:29, 538+`，实例在 `mcp_server_page.dart:43`）；UI 的 `webshell_interactive_file_manager.dart` 上传/写入（`:280`）完全不经过它。

- 后果：MCP 与 UI 同时写同一远端路径 → 互相覆盖、半截文件；锁的语义（"same remote IP + path"）在 UI 侧失效。
- 修复：把锁提升到 `WebshellService`/应用级单例，UI 写操作也 `synchronize()`。

### C5【中】`SessionPool.get` 检查-再创建竞态
```dart
// mcp/session_pool.dart:42-53
if (_sessions.containsKey(shellId)) return _sessions[shellId]!;
final ws = await _lookup(shellId);        // ← await 期间并发调用者也会走到这里
...
_sessions[shellId] = svc;
```

- 后果：同一 `shell_id` 并发调用创建两个连接器 → 重复握手、两套 cookie、先创建的被覆盖后泄漏（其 keep-alive 资源无法释放）。
- 修复：缓存 `Future<WebshellService>` 而不是实例（`_futures.putIfAbsent(shellId, () => _create(shellId))`）。

### C6【中】`DatabaseHelper.database` 双开竞态
```dart
// database_helper_io.dart:48-52
Future<Database> get database async {
  if (_database != null) return _database!;
  _database = await _initDatabase();   // ← 并发首次访问会开两次
  return _database!;
}
```

- 后果：启动阶段多页面并发取库时打开两个 SQLite 连接；迁移/种子并发执行，极端情况下 `database is locked` 或重复建表。
- 修复：缓存 Future（`_dbFuture ??= _initDatabase()`），并在 `_initDatabase` 内对建表/迁移加事务。

### C7【中】SUO5 `startProfile` 的 stop→start 非原子
```dart
// suo5_client_service.dart:584-594
if (s.status == Suo5Status.running || ...) await s.stop();
await s.start(config);
```

- 后果：同一 profile 连续点击启动/重启时，两个调用都通过状态检查 → 重复 `ServerSocket.bind` → `Address already in use`，旧 `_server` 句柄被覆盖而泄漏（端口不回退）。
- 修复：`start()` 内部用 `_starting` Future 做互斥（同 C5 的 Future 缓存法）。

### C8【低】上传取消只在分块间生效，目标端留半截文件
`webshell_interactive_file_manager.dart:274-285`：`_uploadCancelled` 仅在下一次分块前检查。

- 后果：取消后远端残留不完整文件（对 webshell 上传尤其危险：半截 PHP/JSP 也可能可执行）。
- 修复：取消时追加"删除已写入临时文件"的补偿操作，先写 `.part` 再原子 `mv`。

---

## 四、优先级与修复顺序

| 优先级 | 条目 | 一句话动作 |
| --- | --- | --- |
| P0 | L1 | 凭据加密（Keychain/sqlcipher）+ 文件权限 0600 |
| P0 | C1 | `_execute` 加 try/finally，异常可见化 |
| P1 | C3 / C4 | 串行化上提到基类；UI 与 MCP 共用写锁 |
| P1 | L2 / L3 | MCP 日志敏感键过滤；TLS 跳过改为显式开关 |
| P1 | C2 | 失败不缓存（探测失败可重试） |
| P2 | C5 / C6 / C7 | 三处"检查-再创建"统一改 Future 缓存 |
| P2 | R1 / R2 / R3 | 抽取主题与解析公共件，消 675 处重复的主要来源 |
| P2 | R5 | 实现或删除 `warmDir/invalidateDir` |
| P3 | L4 / L6 / L7 / R6 / R7 / R8 | 日志脱敏、监听默认值、体积与 CI |

## 五、覆盖矩阵（按本项目裁剪）

| 维度 | 状态 | 说明 |
| --- | --- | --- |
| 注入 / 命令拼接 | ⚠️ 浅覆盖 | 已看 `sq()` 与 base64 封装；未逐连接器追踪全部 sink |
| 认证 / 授权 | ⚠️ 浅覆盖 | MCP 仅 loopback + allowedHosts，无 token（本地多进程可调用） |
| 加密 | ✅ 已覆盖 | 静态加密缺失、TLS 跳过、密钥派生已核对 |
| 文件操作 | ⚠️ 浅覆盖 | 上传取消/半截文件已记录；路径遍历未系统验证 |
| 配置 | ⚠️ 浅覆盖 | 监听地址、默认口令已记录 |
| 供应链 | ❌ 未覆盖 | 未做依赖 CVE 核对（建议 `dart pub outdated` + OSV 扫描） |

> 本报告聚焦用户指定的三个维度，未做完整 OWASP 全量审计。
