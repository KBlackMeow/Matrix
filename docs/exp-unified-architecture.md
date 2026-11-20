# EXP 统一架构决议

- 日期：2026-11-19
- 取代：`docs/exp-universal-console.md`（那份描述的是"一个页面统一 27 个模块"，已废弃；其中 §2 能力矩阵、§4 靶场实测、§8 对抗加固表保留价值，迁移末尾并入本文档）
- 一句话：**12 个页面 → 12 个薄页面（每个 60–90 行）+ 1 套公共底座（spec / 控制器 / 组件）+ 1 个一键扫描页**

## 1. 目录

```
lib/exp/core/
  exploit_module.dart      # 执行契约（保留，27 个适配器不动）
  exp_spec.dart            # 声明契约：ExpSpec / ExpVariant / FieldSpec / ExpIcon
  exp_catalog.dart         # spec ↔ module 绑定与查找
  log_line.dart            # LogLine / LogLevel（不依赖 Flutter）
  exploit_session.dart     # ExploitSessionController（吸收 38 个 action 脚手架）
  module_registry.dart     # 27 个 variant 适配器 + 两个不兼容签名的归一化
  shell_deployer.dart      # 保留（对抗式落盘，见旧文档 §8）
  behinder_payload.dart    # 新：资产 md5 密钥补丁（吸收 5 份复制）
lib/exp/specs/             # 12 个 ExpSpec，一个家族一个文件
lib/exp/ui/                # 统一组件（新）
  exp_tokens.dart          # 语义色 / 间距 / 圆角 / 字号阶梯 / 按钮词表
  exp_icons.dart           # ExpIcon → IconData 的唯一映射
  exp_scaffold.dart        # 页面骨架：信息卡 + 左表单 + 右日志 + 能力位按钮
  exp_fields.dart          # 字段渲染器 text / number / select / toggle
  log_line_style.dart      # LogLine 的着色（语义 → 颜色）
  exp_log_panel.dart       # 日志面板（唯一）
  exp_info_card.dart       # 信息卡（唯一）
  exp_result_banner.dart   # 结果条（唯一）
  exp_shell_card.dart      # shell 卡（唯一）
  shell_handoff.dart       # 新：产物 → 入库 → 跳转（吸收 5 份复制）
lib/pages/exp/
  universal_scan_page.dart # 一键扫描页（原 universal 瘦身重写）
  struts2_page.dart        # 60–90 行
  ...（共 12 个页面）
lib/pages/vulhub/          # 迁移完成后整体删除
```

## 2. 三个契约

**ExpSpec（声明，UI 只读）**

```dart
ExpSpec { id, family, title, subtitle, category, icon,
          variants: List<ExpVariant>, fields: List<FieldSpec> }
ExpVariant { id, label, moduleId,
             capabilities: {check, exec, shell},
             extraFields: List<FieldSpec> }
FieldSpec { key, label, type: text|number|select|switch,
            defaultValue, required, options: List<FieldOption> }
```

- 能力位是 **per-variant**，不是 per-family（S2-052 盲打无回显，s2045 可写文件）。
- 字段值写入已存在但当前零读写的 `ExploitTarget.extra`；这是 12 个旧页面无法被统一壳驱动的唯一结构性原因。
- spec 里可挂 `extraPanel`（逃生舱，给 ThinkPHP 模块选择器、Shiro 爆破结果表）；页面可 override 整个左栏作为真空阀门。

**ExploitSessionController（ChangeNotifier，不引入状态管理库）**

持有 `url / timeout / fieldValues / log(List<LogLine>) / phase / running / outcome / shell`，
暴露 `detect / exec / getShell / auto / cancel`。
吸收 38 个手写 action 脚手架（约 540 行：URL 守卫 → setState → try → catch → finally）。

**ShellHandoff（独立于 session）**
选项目 → `DatabaseHelper().createWebshell` → `Navigator.push(WebshellInteractivePage)`。
它编排跨页面副作用，不属于一次利用会话。

## 3. 27 个 variant → 12 个 spec

| 家族 | variant 数 | 现状行数 | 目标行数 |
| --- | --- | --- | --- |
| Struts2 | 8 | 453 | 90 |
| Spring | 5 | 334 | 90 |
| Drupal | 1 | 384 | 70 |
| ThinkPHP | 3 | 1079 | 120（含逃生舱） |
| Zentao | 1 | 790 | 100（含逃生舱） |
| httpd | 1 | 224 | 70 |
| Nacos | 1 | 275 | 70 |
| WebLogic | 2 | 190 | 70 |
| PHP | 2 | 204 | 70 |
| Tomcat | 1 | 144 | 60 |
| XXL-JOB | 1 | 112 | 60 |
| Shiro | 1 | （app/parts） | 90 |
| 一键扫描 | — | 691 | 200 |
| 公共底座 | — | 496（base+helpers） | 不变，被吸收 |

## 4. 迁移顺序

1. 底座：tokens → LogLine → 组件 → controller → exp_spec / FieldSpec → handoff / payload
2. **Struts2 样板**（4 个动作 + CVE 下拉 + 项目选择器，复杂度中位数偏上）
3. **ThinkPHP、Zentao**（两个巨石，先把组件 API 压定型）
4. vulhub 其余 8 个（机械化，此时应无新增 API）
5. 一键扫描页
6. 删旧文件、改 `exp_registry.dart` 的 import、重写旧文档

每个页面一个 commit：新写 + 删旧，不做原地改写（避免新旧 state 并存）。

## 5. 一键扫描

流水线：

```
流式扫描（27 条，逐条出结果）
  → 结果列表（强度分级：确认命中 / 载荷已发无回显 / 仅特征吻合 / 超时）
  → 用户选择（不自动利用）
  → 利用 → getShell → ShellHandoff
每条结果可深链到对应模块页继续（预填 URL + variant + 已探到的参数）
```

预算（"保守"档）：

- 总数 **90 发**（实测最坏 84，留 7% 余量）
- 墙钟 **90 秒**，到点即停
- **限速 3 发/秒**，避免突发流量触发 WAF 或压垮脆弱服务
- **连续 3 次网络错误熔断**（区分网络错误与业务失败）
- 触发任何上限时必须明示"还有 N 个未扫完"，不允许静默截断

默认全跑（含会修改目标的探测）。因此必须补：

| 副作用 | 处理 |
| --- | --- |
| Tomcat 写入 2 个 JSP | 扫描后自动删除（现在不清理） |
| Spring-22965 写 JSP + 改 valve 配置 | 删文件；配置变更无法回滚，报告标注 |
| XXL-JOB 建任务执行记录 | 无法自动删除，报告标注 |
| Spring-1273 建 /tmp/success | 无害，仅记录 |

扫描启动前一次性提示"本次扫描包含会修改目标状态的探测"，可取消。

## 6. 判定加固

| 问题 | 处理 |
| --- | --- |
| 8 个 Struts2 variant 共用 `54289`（`233*233`） | **每个 variant 分配唯一算术常量**，命中可反查来源；再用 UI 层"证据同源合并"兜底 |
| WebLogic-10271：`code==200\|\|202\|\|500` 单独成立 | 去掉裸状态码，必须同时有 SOAP/XmlDecoder 信号 |
| Spring-8046：`'json-patch'` 字面量可被 415 错误页命中 | 去掉字面量，必须 EL 报错码或 marker 回显 |
| XXL-JOB：`code==200` 即通过，marker 从不校验 | 必须校验注入 marker 回显 |
| Tomcat：裸 `201/204` 判定为漏洞 | 必须 JSP 执行回显 |

每处 predicate 改完做**双对照**：真靶场必须仍命中；普通站点必须不命中。

## 7. 验收结果（2026-11-19 完成）

| 标准 | 结果 |
| --- | --- |
| 12 个模块页合计 < 900 行 | **182 行**（每页 15–17 行，只做声明绑定） |
| `ui_guard` 通过 | ✅ `lib/exp/ui` / `lib/exp/specs` / `lib/pages/exp` 共 3 个目录零违规 |
| `spec_bind` 通过 | ✅ 12 个 spec / 27 个 variant，全部绑定到真实模块 |
| `dart analyze lib` | ✅ 0 error / 0 warning |
| 重复归零 | ✅ 日志解析 0 处、md5 补丁 1 处、项目选择器 1 处、信息卡 1 处 |
| 一键扫描流式 + 预算 | ✅ 已实现（90 请求 / 90 秒 / 3 次每秒 / 连续 3 次失败熔断） |
| marker 唯一性（运行时） | ✅ `tool/verify/scan_marker_regression.dart`：mock 目标恒回 `54289`，8 个 Struts2 变体里**只有 s2005 命中** |
| 真实靶场回归 | ⏳ 需在 vulhub 环境执行 `tool/verify/module_smoke.dart`（本机无靶场） |

行数对比：

| 部分 | 迁移前 | 迁移后 |
| --- | --- | --- |
| 12 个家族页 | 4189 | 182 |
| 一键页 | 691 | 356 |
| 公共外壳（base + helpers） | 496 | 0（被组件层吸收） |
| 组件层 | 0 | 1668 |
| 声明层（12 spec） | 0 | 539 |
| 契约/引擎层 | 0 | 852 |
| **合计** | **5376** | **3597** |

密度下降 33%，但真正的收益是：新增一个 CVE = 加一个 `ExpVariant`（约 8 行），
不改任何 UI 代码。

## 8. 迁移期的已知缺口

1. **参数已接线**（第二轮补齐）：
   - `timeout`：**全部 27 个 adapter** 都把 UI 的超时传进 service（此前被忽略）
   - `path`：struts2 / spring / php / drupal / weblogic（→ `ShellDeployer.preferredDirectory`）
   - `phpPath`：php-backdoor
   - `creds`：spring（Basic Auth，留空回退 admin:admin）
   - `key`：shiro（填了就不爆破）
   仍缺：httpd 的 file/lhost/lport、nacos 的 user/pass/token/sql、tomcat 写入目录、
   thinkphp/zentao 的连接密码、反向 shell 模式——这些依赖"检测/执行/取 shell"之外的
   第四类动作，需要先扩模块接口，暂不塞进表单（`spec_bind` 会拦住没人读的字段）。
2. **密码/自定义载荷**：旧页面允许指定 Behinder 连接密码，新链路统一用随机名与固定口令；
   `BehinderPayload.key16` 已就绪，接进 `getShell` 即可。
3. **扫描请求数是估算值**：`ExploitModule.check` 不透出真实请求数，按家族经验值计账，
   宁可高估（高估只会更早停下）。

## 9. 实靶发现（2026-11-19，本地 vulhub 镜像 + 加固环境）

| 目标 | 现象 | 根因 | 修复 |
| --- | --- | --- | --- |
| Struts2 S2-007 | 检测命中，`exec` 返回 null | 执行用 `Runtime.exec(new String[]{...})` 与 `ProcessBuilder(new String[]{...})`，该 OGNL 版本**不支持数组字面量**，表达式静默失败 | 改用 OGNL list：`ProcessBuilder({'/bin/sh','-c','整条命令'})`，并保留 `exec(String)` 降级 |
| Struts2 S2-007 | 同上 | exec 的表单字段写死 `username/password`，而目标是 `user.action` 的 `name/email`；路径写死 `login.action` | 候选路径 × 两种表单形状全试；`path` 字段接通 |
| 部署的 JSP shell | shell 写入成功、`connect` 永远空 | `jsp_runtime` 连接器把命令包成 `echo … \| base64 -d \| bash`，精简镜像里没有 `base64` | 首次返回空即降级为原文命令，并记住结论（每个 shell 只探测一次） |
| Struts2 S2-005 | exec 报"命令已发送"但无任何输出 | POST 回显链路被 302 吞掉，原实现用一句成功文案掩盖了失败 | 改为 `ExploitNotWorking` 显式失败，不再伪装成功 |
| 全部 | WAF 拦截时 `exec` 返回 null，与"没漏洞"无法区分 | 错误被吞 | 新增 `ExploitBlocked`，日志显示 `被 WAF 拦截 · HTTP 403` |
| 一键扫描（S2-007 靶场） | 27 个变体只跑 26 个，`skipped=1` | 预算按**家族**估算（Struts2 一律记 4），而 S2-007 一个 check 可发 8 次 | 改按**变体**记账（取实测上限）+ 便宜的先跑，实测 27/27 跑完、约 81 发、27 秒 |
| WebLogic-10271 | 「任何路径都回 200 的 SPA」被判成 XMLDecoder RCE | 判定是 `200\|202\|500` 的**或**关系，状态码单独成立 | 必须同时出现 weblogic/wls-wsat/xmldecoder/workcontext 信号 |
| XXL-JOB | `{"code":200,"data":[]}` 的普通接口被判成执行器未授权 | 只校验 `code==200`，注入的 marker 从不验证 | 要求同时存在 `msg` 键（执行器响应特征） |
| Tomcat（WAF 后） | check 成功、exec 把 404 错误页当成命令输出 | shell JSP 的 PUT 被 WAF 拦掉，GET 落到 404 | PUT 被拦抛 `ExploitBlocked`；GET 404/403 抛 `ExploitNotWorking` |
| Struts2 × 4（严格 WAF 下） | 被 403 拦下的变体报成"未检测到"（假阴性） | check 未判定 WAF 拦截，直接落到"特征不存在" | S2-005 / S2-045 / S2-052 / S2-057 补 `looksLikeWafBlock` 判定，改为 `probeFailed` |
| 扫描页（UI） | 被拦变体在结果里完全消失，用户只看到"命中 1 条" | `_hits` 只收 `isHit`，`failed` 被丢弃 | 新增"未测通"区块与计数（`N 个变体没测通……`） |
| 全模块（结构性） | **11/25 个 check 完全不判定 WAF 拦截**——接近一半检测面会把"被拦"报成"没漏洞" | 拦截判定靠各 check 手写，漏了就永久漏 | 统一成 `wafBlockedResult(...)` 一行；新增 `waf_coverage` 守卫强制每个 check 必须处理拦截 |
| Apache httpd | 错误页被当成命令输出 | `execRce` 只看"body 非空"，WAF/路径规范化后返回的 404 页被当结果 | 改用带状态码的 raw 请求；非 200 或 HTML 开头一律跳过 |
| ThinkPHP（实靶） | 写马成功但 `connect` 一直 `[HTTP 404]` | `getShell` 返回的是 **`url + " Pass:c"` 的展示字符串**，被当成 URL 传给连接器（12 处） | 只返回裸 URL；并新增 `_verifiedShell()`：**原生写马必须回显验证**才返回 |
| Spring Cloud Function（实靶） | `exec` 把 Spring 的 500 错误 JSON 当命令输出 | 该镜像关闭了 `server.error.include-message`，本就没有回显通道 | 识别为错误页 → 抛 `ExploitNotWorking('无回显，请用反向 shell')` |
| Spring4Shell（实靶） | check 命中、exec 永远 null | ① `AccessLogValve` 只认**第一次**写入的 prefix，check/exec 各用不同文件名 → exec 拿到 404；② pattern 里的 `%{c1}i/%{c2}i` 取自被记录那次请求的 header，触发/验证/执行三条请求都必须带；③ JSP 用 2048 字节缓冲打印，输出全是空白填充 | 三条一起修：check 直接写"可执行命令"的 JSP（`m4xm`）并用 `cmd=echo marker` 验证，exec 复用同名；所有请求带 pattern header；JSP 改为 `new String(b,0,a)` |
| XXL-JOB（实靶） | 真执行器被判成"未检测到"（**假阴性，上一轮的修复造成的**） | 上一版要求响应带 `msg` 键，而 2.2.0 执行器只回 `{"code":200}` | 判定改为"JSON 键集合 ⊆ {code,msg,content}"：既接受真响应，也拒绝 `{"code":200,"data":[]}` |
| XXL-JOB（实靶） | 打到 admin 端口时把 404 网页当命令输出 | exec 不区分执行器与管理员台 | 网页开头 → 抛 `ExploitNotWorking('打到的不是执行器')`；真执行器回 `任务已提交…无回显` |
| Drupal（实靶） | exec 把安装向导跳转页当命令输出 | 该镜像未完成安装，一切请求 302 到 `/core/install.php` | check/exec 都识别安装向导：前者报"无法判定"，后者抛"命令没有执行" |
| Shiro（实靶） | —（一次通过） | — | check / 内存马 / connect `uid=0` 全部正常 |
| Nacos（实靶） | —（一次通过） | — | check 拿到用户列表 |
| WebLogic 10271 / 14882（实靶） | —（符合预期） | — | 10271 命中并返回 XMLDecoder 的 `ArrayIndexOutOfBoundsException` 特征；14882 命中 302→console.portal |

| Zentao（未上实靶） | shell 验证只认 HTTP 200：任何已存在的同名文件、200 错误页都能通过 | 弱验证（存在性≠可用性） | 改为让 shell 执行 `echo <唯一标记>` 并要求回显；与 ThinkPHP 的 `_verifiedShell` 同一标准 |
| 矩阵化（本轮） | 实靶验证靠手敲，改一次代码就要重来 | 没有可重跑的场景集 | `live_matrix.dart` 固化 9 个单模块用例 + 2 个 WAF 用例（`blockedOnCheck` / `blockedOnExec` 两种期望） |
| 扫描矩阵（本轮） | 扫描只在真靶场上"人眼看结果" | 没有断言"这个靶场应该只命中谁" | `scan_matrix.dart`：6 个靶场 × 命中集合完全相等 |
| Struts2 变体（本轮实靶） | S2-032 / 045 / 052 / 053 / 059 全部**无真阳性证据** | 这五个变体的靶场镜像在本地一直没跑过 | 逐个起镜像验证：**4 个命中**（S2-032、045、052、053、059）；**S2-057 在它自己的 2.3.34-showcase 上打不出信号** → 标为未验证变体，spec hint 写明适用条件 |
| Drupal（第 11 轮） | 镜像不带 settings.php，只能验"未安装"负路径 | 镜像设计就是"先手动装" | `tool/verify/drupal_install.py`：语言→profile→sqlite→**驱动批次**→configure，约 1 分钟装完；完成判定改为"首页标题 Welcome to"（不能用"出现 Log in"——半装也有） |
| Drupal（第 12 轮） | 上一轮结论"装完也打不中"是**错的**：把半装状态当成了装完 | 批次只发了 `op=start`，缺 `rewrite/profile/langcode` 参数导致每轮退回首屏，schema 只建了 24/80 张表 | 用页面给出的完整 batch uri 驱动；装完后 check/exec/shell/connect 全通 |
| Drupal exec 复合命令全废 | `exec` 恒为 null，shell 落盘全失败 | ① `| base64` 直接接在整串命令末尾，只有最后一段被编码；② `#markup` 过 XSS 过滤器，`&&` 变 `&amp;&amp;` | 命令整体 base64 后交给 `sh`，markup 里只剩安全字符；输出再 base64 回传 |
| **守卫自身的盲区**（本轮） | Shiro / Zentao 的 check 写在 `module_registry` 的内联 `checkFn:` 闭包里，`waf_coverage` 只扫 `check*` 方法，**从未覆盖它们** | 守卫的实现假设"check 一定是一个方法" | 扩展守卫扫描内联闭包；两个闭包补 `on ExploitBlocked`；Shiro/Zentao 服务层在 403/429 时抛 `ExploitBlocked`（此前 403 会被判成"不是 Shiro"） |
| 矩阵太慢（本轮） | 17 个用例串行约 20 分钟，实际上没人愿意跑 | 每个用例独占端口/容器，本来就互不依赖 | 改成 worker pool（`--jobs=N`，默认 3），输出按用例缓冲避免交错；5 个用例实测 13 秒 |
| Zentao（鲁棒性套件发现） | 慢目标上 check 挂死 20 秒 | 模块调 `detectZentaoBase` 时**没传超时**，4 个候选各等默认 8 秒 | 传 `t.timeout` |
| Zentao | 全部候选超时却报"未检测到" | 异常被逐个吞掉，最后 return null | 一个响应都没拿到时抛 `ExploitNotWorking`（"没测通"） |
| Apache httpd（鲁棒性套件发现） | UI 上的超时对 httpd **完全无效**，慢目标上拖 16 秒 | `RawHttpClient` 用了自己的 10 秒默认值，没接服务 timeout | `RawHttpClient(timeout: timeout)`；无任何响应时报 `probeFailed` |
| Tomcat（协议层毒饵发现） | **任何对 PUT 回 204 的服务器都被判成 CVE-2017-12615** | 弱判定：`PUT 201/204 ⇒ vulnerable`，文件读不回来也算 | 改为"写入文件读不回 ⇒ 不构成 CVE"，只保留"能写 JSP 且执行回显"这条强判定；真靶场复验仍命中 |
| **弱判定普查**（本轮） | 全库 11 处 `vulnerable` 判定，其中 4 处是"单一弱信号" | 早期为了"不漏"而放宽，代价是误报 | ① **Shiro**：`checkIsShiro()` 只证明"用了 Shiro"，改为必须用默认 key 伪造成功；② **PHP 后门** marker 改服务端计算；③ **httpd** 只认 passwd 结构（`root:...:0:0:`），不再看 `/bin/sh`；④ **Spring Data REST** 删掉 `json-patch` 这类会出现在 415 页面里的词；⑤ **Tomcat** 的 `.txt` 可写分支降级为"不构成 CVE" |
| **Spring 三个变体无实靶**（本轮补上） | `spring-8046` 的判定刚被我收紧过，却从未在真靶场验证；1273/4977 也一样 | 本地有镜像但一直没跑 | 起 `spring-rest-data:2.6.6` / `spring-data-commons:2.0.5` / `spring-security-oauth2:2.0.8` 三个靶场：**收紧后仍全部命中**；再拿 spring4shell 靶场做反面，三者均正确 miss，只有 22965 命中 |
| **回显一切的服务器**（本轮） | 7 个变体把自己的 payload 当成命中 | marker 字面量写在请求里（UA / URL / body / 头），服务端原样回显就匹配 | ① S2-045 marker 改 OGNL 计算 `""+(236*236)`；② PHP-CGI 改 `"PHP_CGI_".(233*233)`；③ Drupal 改 `printf MXDRUPAL_%s <ts>`（格式串与参数分开）；④ Spring4Shell 改 `printf MX22965%s <ts>`；⑤ WebLogic-10271/14882、Spring-22963 增加"回显守卫"（响应含我们的 payload 片段 → probeFailed）。现在 27/27 不再被骗 |
| **置信度靠猜**（本轮） | 扫描列表的"确认命中"是按 `hint` 里有没有"盲打"两个字判断的 | 用文案做逻辑判断，且 XXL-JOB 写的是"无回显"、绕过了判断 → 弱证据显示成"确认命中" | 引入 `ExpVariant.evidence`（strong/weak）显式建模；S2-052、XXL-JOB、WebLogic-10271/14882 标为 weak，列表显示"弱证据·无回显"；`positive_samples` 现在断言证据强度 |
| 扫描结果混排（本轮） | 弱证据和确认命中在同一个列表里，只差一行小字 | 只做了分类没做分层展示 | 结果区分两段："确认命中"（绿）与"弱证据（需人工确认，不代表已拿下）"（黄）；汇总行改为"确认 N · 弱证据 M · 未测通 K" |
| **证据强度靠人标**（本轮） | `ExpEvidence` 是人工写的，没有任何东西保证"标 strong 的变体真的在实靶上跑通过" | 标注与验证脱节 | ① `live_matrix` 现在复用 `confidenceOf()` 并断言"strong 变体必须拿到确认命中"；② 新增 `evidence_coverage` 守卫：strong 变体必须有实靶用例，例外要写原因（当前仅 S2-057 / Zentao 两条）；③ 补齐 5 个用例（S2-005、Spring-22963、ThinkPHP tp2 / tp5022、PHP-CGI），strong 覆盖 21/23|
| 同族互串未验（本轮） | 单模块能打 ≠ 扫描时不串；例如 tp5023 的 captcha 判定会不会把 5.0.20 也报成 5023 | 扫描矩阵只覆盖 7 个靶场 | 扩到 12 个：新增 thinkphp 2.1 / 5.0.20 / php-cgi / spring-1273 / spring-4977，全部**只命中应中的那一个**（5.0.20 只中 tp5022，未误报 tp5023） |
| **Shiro 重构丢功能**（本轮用户指出） | 原 `shiro_exp.dart` 的 11 个输入项里丢了 7 个、5 个动作里丢了 2 个 | 12 页压成薄页时只保留了核心路径，Shiro 恰好是参数最多的家族（其余家族只有 1–2 个字段） | 全量恢复：方法 / 模式(CBC·GCM) / Cookie 名 / Key / Payload(Base64) / 内存马类型(Filter·Valve·Listener) / 冰蝎密码 / Shell 路径 / 详细日志；三个独立动作（爆破 Key / 验证 Key / 发送 Payload）通过 `extraPanelBuilder` 逃生舱接回，与主流程共用同一份字段与日志。实靶验证：默认、自定义密码+路径、Valve、Listener 四种配置均注入成功；GET/POST 均可检测 |
| **流程化重设计**（本轮启动） | 页面是"一堆按钮 + 一个日志"，看不出哪一步做过、结果是什么、缺什么才能做下一步 | 旧页面的步骤关系只存在于代码里（`_currentKey != null` 之类） | 新增步骤模型 `ExpStep` / `StepRunner` / `ExpStepsPanel`：每步有参数、状态、结果、产物；依赖显式（`requires`/`produces`）；失败停留可重试、下游 blocked；Shiro 五步已打通（实靶验证：指纹→爆破→验证→发 payload→注入，产物 key/shellUrl 回写字段） |
| 回显守卫误伤真样本（本轮自查发现） | WebLogic 真靶场的故障页也含 `soapenv:Envelope`，守卫会把真阳性判成回显 | 守卫用了"响应形态"而非"我们 payload 特有片段" | 守卫只认 `java.lang.ProcessBuilder`（payload 独有），真样本恢复命中 |
| Struts2 marker 改造（本轮） | 改 marker 有"修好误报、废掉真阳性"的风险（XXL-JOB 已犯过一次） | — | 改完立即回 S2-005 / S2-032 / S2-045 真靶场复验，均仍命中 |
| Struts2 S2-005 / S2-032（扫描矩阵发现） | 在 **PHP 靶场**上误报命中 | marker 字面量写在请求里（`"55225"`、`echo 54289`），而 PHP 内置服务器的 404 页会**回显请求 URI** → 匹配到自己的输入 | marker 改为服务端计算（`(233*233)`、`expr 233 * 233`），请求里不再出现字面量 |
| Nacos（扫描矩阵发现） | 在 **Shiro 靶场**上误报命中 | 只认 `username` 这个词，而任何登录页都有 `name="username"` | 要求 JSON 结构（`pageItems` / `totalCount`）且响应不是 HTML |
加固手法（本地）：

> 注意：`waf_proxy.dart` 会重新拼装转发的 URL，`%2e%2e` 这类**编码路径会被规范化**，
> 导致 httpd 穿越类变体经过代理后本来就打不穿。这类场景要直连验证，
> 别把"代理改了路径"误判成"WAF 拦住了"。


```bash
# 关键字 WAF（拦 getruntime / processbuilder / system( 等）
dart tool/verify/waf_proxy.dart http://127.0.0.1:18080 18091 --preset=keywords
# 注意：预设用 --preset=，--rules= 是自定义字面规则列表
```

## 10. 验证脚本

```bash
dart tool/verify/ui_guard.dart              # 禁止硬编码色值/字号/字体族
dart tool/verify/spec_bind.dart             # 声明↔模块绑定；没人读的字段直接失败
dart tool/verify/scan_marker_regression.dart # 唯一 marker 的运行时回归
dart tool/verify/false_positive_suite.dart   # 假阳性 + 假阴性回归（SPA / 普通 JSON / 403 拦截）
dart tool/verify/positive_samples.dart       # 正样本对照（收紧判定后仍须命中）
dart tool/verify/robustness_suite.dart       # 畸形目标：27 变体 × 8 种毒饵（含协议层），不许崩/挂/误判
dart tool/verify/evidence_coverage.dart      # 标了 strong 的变体必须在实靶矩阵里有用例
dart tool/verify/step_pilot.dart <shiro-url>  # 流程体系样板：依赖阻塞 + 五步全绿 + 产物回写
dart tool/verify/waf_coverage.dart           # 每个 check 必须判定 WAF 拦截
dart tool/verify/scan_live.dart <url>        # 对真实靶场跑 27 变体扫描
dart tool/verify/scan_matrix.dart --jobs=3   # 扫描矩阵：断言"命中集合完全相等"（12 靶场）
python3 tool/verify/drupal_install.py <url>   # 把 drupal 靶场装起来（镜像默认未安装）
dart tool/verify/live_matrix.dart --jobs=3   # 实靶矩阵：并行起容器→跑真模块→断言→拆容器
                                             # 含 2 个"WAF 后面"的用例（必须报没测通，不是没漏洞）
dart tool/verify/module_smoke.dart --list    # 27 个变体的能力矩阵
```

## 11. 明确不做

- golden 截图测试（暗色 + 字体渲染跨平台不稳）
- l10n（项目无国际化体系，文案内联在 spec）
- 引入 Riverpod / Bloc
- 原地改写旧页面

## 12. 交付清单（2026-11-20 收尾）

**架构**
- 12 个家族页压到 182 行（每页 15–17 行），全部逻辑在 `ExpModulePage` + `lib/exp/ui/`
- 声明层 `lib/exp/specs/`（12 个 ExpSpec / 27 个 ExpVariant，含能力位与证据强度）
- 一键扫描页：流式结果、预算（90 请求 / 90 秒 / 3 次每秒 / 连续 3 次失败熔断）、强/弱证据分段

**判定质量（24 轮实靶驱动的修复，按类型）**
- 载荷失效：S2-007 数组载荷、Spring4Shell 双文件名、ThinkPHP URL 带密码、PHP-CGI 挂载
- 超时未接线：26 个 adapter、Zentao 静态方法、httpd raw client
- 假阳性：marker 串台 8 处、WebLogic/XXL-JOB/Spring-REST 弱判定、Tomcat PUT、回显 7 处
- 假阴性：被拦报"没漏洞"（11 个 check + 2 个内联闭包）、"全超时"报"未检测"
- 崩溃/挂死：Zentao 20 秒挂死（鲁棒性套件发现）

**回归体系（总计约 7.5 分钟）**

| 脚本 | 规模 | 耗时 |
| --- | --- | --- |
| 6 个快速套件（ui/spec/waf/evidence/marker/positive/FP/robustness） | 216 探测 + 27 变体回显 | 183s |
| `live_matrix --jobs=3` | 25 用例（含 2 个 WAF、Drupal 自动安装） | ~2 分钟 |
| `scan_matrix --jobs=3` | 12 靶场，命中断言完全相等 | ~2 分钟 |

**已知边界（未解决，非未发现）**
1. Zentao 零实靶——本地无镜像，整条注入链无运行时证据
2. S2-057 在 2.3.34-showcase 上打不出信号——依赖目标配置，标为未验证变体
3. UI 运行时表现无法自动验证（无 Flutter 运行环境）
4. WebLogic / XXL-JOB 只到 check 与盲执行——架构上缺"执行能力"，非测试缺口
