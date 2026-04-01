# Matrix 项目重构方案

> 当前版本：94 个 Dart 文件，34,415 行代码  
> 重构目标：消除冗余、拆分巨型文件、提升可维护性

---

## 一、重构前代码结构

### 1.1 目录总览

```
lib/
├── main.dart                          (1,971 行) ← 过大，包含路由+初始化+导航
├── connectors/                        (3,345 行，13 个文件)
│   ├── shell_connector.dart           (108)  抽象基类
│   ├── connector_factory.dart         (109)  工厂类
│   ├── php_eval_connector.dart        (366)
│   ├── php_behinder_connector.dart    (473)  ← AES key 逻辑与 jsp 重复
│   ├── php_passthru_connector.dart    (66)
│   ├── php_b64rot13_connector.dart    (48)
│   ├── php_probe_connector.dart       (105)
│   ├── jsp_classloader_connector.dart (545)
│   ├── jsp_behinder_connector.dart    (689)  ← AES key 逻辑与 php 重复
│   ├── jsp_runtime_connector.dart     (136)
│   ├── shell_exec_connector.dart      (300)
│   ├── asp_wscript_connector.dart     (240)
│   └── aspx_cmd_connector.dart        (160)
├── database/                          (1,880 行，7 个文件)
│   ├── database_helper.dart           (232)
│   ├── database_helper_io.dart        (1,079) ← 所有 CRUD 堆在一起
│   ├── database_helper_web.dart       (265)
│   ├── database_helper_stub.dart      (214)
│   ├── database_init.dart             (5)
│   ├── database_init_io.dart          (11)
│   └── database_init_stub.dart        (4)
├── models/                            (514 行，6 个文件)
│   ├── project.dart                   (59)
│   ├── webshell.dart                  (98)
│   ├── payload.dart                   (85)
│   ├── dictionary.dart                (95)
│   ├── frp_profile.dart               (78)
│   └── file_entry.dart                (25)
├── services/                          (14,000+ 行，22 个文件)
│   ├── webshell_service.dart          (85)
│   ├── port_scan_service.dart         (223)
│   ├── port_scan_background_service.dart (273)
│   ├── brute_service.dart             (672)
│   ├── dirsearch_service.dart         (1,082)
│   ├── dirscan_background_service.dart (389)
│   ├── service_probe_service.dart     (613)
│   ├── banner_fingerprint.dart        (339)
│   ├── fscan_service.dart             (157)
│   ├── web_poc_service.dart           (216)
│   ├── poc_yaml_engine.dart           (1,024)
│   ├── web_title_service.dart         (90)
│   ├── icmp_service.dart              (79)
│   ├── netbios_service.dart           (291)
│   ├── ms17010_service.dart           (396)
│   ├── redis_exploit_service.dart     (75)
│   ├── ssh_exec_service.dart          (45)
│   ├── reverse_shell_service.dart     (210)
│   ├── frp_client_service.dart        (1,072)
│   ├── scan_session_service.dart      (119)
│   ├── seed_service.dart              (377)
│   └── vulnerability_scan_background_service.dart (136)
├── exp/                               (3,117 行)
│   ├── vulhub/
│   │   ├── misc_http_exp_service.dart (933)  ← 多个服务堆在一个文件
│   │   ├── spring_exp_service.dart    (180)
│   │   └── struts2_exp_service.dart   (160)
│   ├── thinkphp/
│   │   └── thinkphp_exp_service.dart  (886)  ← 多个版本逻辑混杂
│   ├── shiro/
│   │   ├── shiro_exp_service.dart     (341)
│   │   ├── shiro_mem_shell_service.dart (189)
│   │   ├── shiro_crypto.dart          (80)
│   │   └── shiro_payload_repo.dart    (87)
│   └── zentao/
│       └── zentao_exp_service.dart    (261)
├── pages/                             (14,418 行，35+ 个文件)
│   ├── webshell_interactive_page.dart (3,930) ← 最大，4 个 tab 全堆一起
│   ├── webshell_management_page.dart  (1,230)
│   ├── project_management_page.dart   (533)
│   ├── info_collection_page.dart      (787)
│   ├── payload_management_page.dart   (792)
│   ├── dictionary_management_page.dart (932)
│   ├── thinkphp_exp_page.dart         (883)  ← 混有 UI + 业务逻辑
│   ├── zentao_exp_page.dart           (639)
│   ├── frp_tunnel_page.dart           (1,167)
│   ├── reverse_shell_dashboard_page.dart (335)
│   ├── reverse_shell_terminal_page.dart  (294)
│   ├── project_scoped_page.dart       (213)
│   └── vulhub/                        (19 个文件)
│       ├── _vulhub_page_helpers.dart  (244)
│       ├── druid_exp_page.dart        (96)   ← 15 个页面 copy-paste 同一模式
│       ├── spring_exp_page.dart       (306)
│       ├── struts2_exp_page.dart      (398)
│       └── ...(12 more, 96-140 行，结构几乎相同)
├── widgets/
│   ├── port_scan_card.dart            (600)
│   └── dirsearch_card.dart            (646)
├── theme/
│   └── app_theme.dart                 (71)
└── utils/
    ├── encoding_utils.dart            (20)
    └── matrix_console_log.dart        (14)
```

### 1.2 主要问题清单

| # | 问题 | 涉及文件 | 严重度 |
|---|------|---------|--------|
| P1 | `webshell_interactive_page.dart` 3930 行，4 个 Tab 全混一起 | pages/ | 高 |
| P2 | 15 个 Vulhub 页面 copy-paste 相同的 log/state 模式 | pages/vulhub/ | 高 |
| P3 | AES key 推导逻辑在 php/jsp Behinder connector 中重复 | connectors/ | 高 |
| P4 | `misc_http_exp_service.dart` 933 行，10+ 个服务堆一起 | exp/vulhub/ | 高 |
| P5 | HTTP 请求样板代码在 20+ 个 service 中各自复制 | services/, exp/ | 中 |
| P6 | 模型 toMap/fromMap/copyWith 5 次重复模式 | models/ | 中 |
| P7 | `database_helper_io.dart` 1079 行，所有表的 CRUD 堆在一起 | database/ | 中 |
| P8 | `main.dart` 1971 行，路由、导航、初始化全混一起 | main.dart | 中 |
| P9 | 默认密码 `mAtrix_911`、Buffer 500 行等魔法值散落各处 | 多处 | 低 |
| P10 | 无依赖注入，页面直接 new Service | pages/ | 低 |

---

## 二、重构后代码结构

### 2.1 目录总览

```
lib/
├── main.dart                          (≤ 80 行)  仅启动入口
├── app/
│   ├── app.dart                       App Widget + MaterialApp
│   ├── router.dart                    所有路由定义
│   └── constants.dart                 全局常量（魔法值统一在此）
│
├── core/                              ← 新增：跨模块公共能力
│   ├── http/
│   │   ├── http_client.dart           统一 HTTP 请求封装（timeout/error）
│   │   └── http_result.dart           Result<T> 类型（Ok/Err）
│   ├── crypto/
│   │   ├── behinder_crypto.dart       ← 合并 php/jsp 重复的 AES key 逻辑
│   │   ├── shiro_crypto.dart          (从 exp/shiro/ 移入)
│   │   └── aes_cfb_stream.dart        (从 frp_client_service 提取)
│   ├── log/
│   │   ├── log_buffer.dart            通用有界 log 缓冲区（替换散落的 _log_()）
│   │   └── matrix_console_log.dart    (保留)
│   └── utils/
│       └── encoding_utils.dart        (保留)
│
├── connectors/                        (结构保持，内部精简)
│   ├── shell_connector.dart           (不变)
│   ├── connector_factory.dart         (不变)
│   ├── behinder/
│   │   ├── php_behinder_connector.dart  (AES key 改用 core/crypto/behinder_crypto)
│   │   └── jsp_behinder_connector.dart  (同上，去重后各减约 60 行)
│   ├── php/
│   │   ├── php_eval_connector.dart
│   │   ├── php_passthru_connector.dart
│   │   ├── php_b64rot13_connector.dart
│   │   └── php_probe_connector.dart
│   ├── jsp/
│   │   ├── jsp_classloader_connector.dart
│   │   └── jsp_runtime_connector.dart
│   ├── asp/
│   │   ├── asp_wscript_connector.dart
│   │   └── aspx_cmd_connector.dart
│   └── shell_exec_connector.dart
│
├── models/                            (结构保持不变)
│   ├── project.dart
│   ├── webshell.dart
│   ├── payload.dart
│   ├── dictionary.dart
│   ├── frp_profile.dart
│   └── file_entry.dart
│
├── database/                          ← 拆分 IO 层
│   ├── database_helper.dart           (接口层，不变)
│   ├── database_helper_web.dart       (不变)
│   ├── database_helper_stub.dart      (不变)
│   ├── database_init.dart             (不变)
│   ├── io/                            ← 原 database_helper_io.dart 按表拆分
│   │   ├── database_io_base.dart      共享 db 实例 + schema 版本管理
│   │   ├── project_dao.dart           projects 表 CRUD
│   │   ├── webshell_dao.dart          webshells 表 CRUD
│   │   ├── payload_dao.dart           payloads 表 CRUD
│   │   ├── dictionary_dao.dart        dictionaries 表 CRUD
│   │   ├── scan_session_dao.dart      scan_sessions 表 CRUD
│   │   └── frp_profile_dao.dart       frp_profiles 表 CRUD
│   └── database_helper_io.dart        (薄包装层，组合各 DAO)
│
├── services/                          ← 按功能分组
│   ├── webshell/
│   │   ├── webshell_service.dart
│   │   └── reverse_shell_service.dart
│   ├── scan/
│   │   ├── port_scan_service.dart
│   │   ├── port_scan_background_service.dart
│   │   ├── dirsearch_service.dart
│   │   ├── dirscan_background_service.dart
│   │   ├── fscan_service.dart
│   │   ├── icmp_service.dart
│   │   ├── netbios_service.dart
│   │   └── scan_session_service.dart
│   ├── fingerprint/
│   │   ├── service_probe_service.dart
│   │   ├── banner_fingerprint.dart
│   │   └── web_title_service.dart
│   ├── brute/
│   │   └── brute_service.dart
│   ├── poc/
│   │   ├── web_poc_service.dart
│   │   └── poc_yaml_engine.dart
│   ├── tunnel/
│   │   └── frp_client_service.dart
│   ├── exploit/
│   │   ├── ms17010_service.dart
│   │   ├── redis_exploit_service.dart
│   │   └── ssh_exec_service.dart
│   └── seed_service.dart
│
├── exp/                               ← 拆分 misc_http_exp_service
│   ├── base_exp_service.dart          ← 新增：抽象基类（统一 HTTP 请求+error）
│   ├── vulhub/
│   │   ├── apache/
│   │   │   ├── apache_httpd_exp_service.dart   (从 misc_http 拆出)
│   │   │   └── apache_tomcat_exp_service.dart
│   │   ├── druid/
│   │   │   └── druid_exp_service.dart
│   │   ├── solr/
│   │   │   └── solr_exp_service.dart
│   │   ├── elasticsearch/
│   │   │   └── elasticsearch_exp_service.dart
│   │   ├── confluence/
│   │   │   └── confluence_exp_service.dart
│   │   ├── weblogic/
│   │   │   └── weblogic_exp_service.dart
│   │   ├── spring/
│   │   │   └── spring_exp_service.dart          (不变)
│   │   └── struts2/
│   │       └── struts2_exp_service.dart         (不变)
│   ├── thinkphp/
│   │   ├── thinkphp_exp_service.dart            (接口层)
│   │   ├── thinkphp_v5_exp.dart                 ← 按版本拆分
│   │   └── thinkphp_v6_exp.dart
│   ├── shiro/
│   │   ├── shiro_exp_service.dart
│   │   ├── shiro_mem_shell_service.dart
│   │   └── shiro_payload_repo.dart
│   └── zentao/
│       └── zentao_exp_service.dart
│
├── pages/                             ← 最大改动：拆分巨型页面
│   ├── project/
│   │   └── project_management_page.dart
│   ├── webshell/
│   │   ├── webshell_management_page.dart
│   │   └── interactive/
│   │       ├── webshell_interactive_page.dart   (≤ 200 行，仅 Tab 框架)
│   │       ├── command_tab.dart                 ← 从 3930 行拆出
│   │       ├── file_manager_tab.dart            ← 从 3930 行拆出
│   │       ├── shell_terminal_tab.dart          ← 从 3930 行拆出
│   │       └── reverse_shell_tab.dart           ← 从 3930 行拆出
│   ├── scan/
│   │   └── info_collection_page.dart
│   ├── payload/
│   │   └── payload_management_page.dart
│   ├── dictionary/
│   │   └── dictionary_management_page.dart
│   ├── tunnel/
│   │   └── frp_tunnel_page.dart
│   ├── reverse_shell/
│   │   ├── reverse_shell_dashboard_page.dart
│   │   └── reverse_shell_terminal_page.dart
│   ├── exp/
│   │   ├── thinkphp_exp_page.dart
│   │   ├── zentao_exp_page.dart
│   │   └── vulhub/
│   │       ├── base_vulhub_exp_page.dart        ← 新增：抽象基类，消除 15 份 copy-paste
│   │       ├── druid_exp_page.dart              (继承 base，≤ 60 行)
│   │       ├── spring_exp_page.dart             (继承 base，≤ 60 行)
│   │       ├── struts2_exp_page.dart            (继承 base，≤ 60 行)
│   │       └── ...(其余 12 个页面同上)
│   └── shared/
│       └── project_scoped_page.dart
│
├── widgets/
│   ├── port_scan_card.dart
│   ├── dirsearch_card.dart
│   └── common/                        ← 新增：抽取跨页面通用组件
│       ├── log_view.dart              统一的 log 滚动显示组件
│       ├── status_badge.dart
│       └── action_button.dart
│
└── theme/
    └── app_theme.dart
```

---

### 2.2 关键重构点详解

#### 重构点 A：拆分 `webshell_interactive_page.dart`（3930 → ≤200 行）

**重构前：**  
一个文件包含 4 个 Tab 的所有 UI + 逻辑，状态混杂，难以独立修改任何一个 Tab。

**重构后：**
```
interactive/
├── webshell_interactive_page.dart   # 只负责 TabBar + TabBarView 框架
├── command_tab.dart                 # 命令执行 Tab（输入框 + 结果展示）
├── file_manager_tab.dart            # 文件管理 Tab（树形列表 + 上传下载）
├── shell_terminal_tab.dart          # Shell 终端 Tab（ANSI 颜色 + 补全）
└── reverse_shell_tab.dart           # 反弹 Shell Tab（session 选择 + 终端）
```

每个 Tab 是独立的 `StatefulWidget`，通过共享 `WebshellService` 实例通信。

---

#### 重构点 B：Vulhub 页面抽象基类（15 份 copy-paste → 1 基类）

**重构前（每个页面重复）：**
```dart
// druid_exp_page.dart, solr_exp_page.dart, confluence_exp_page.dart...
bool _running = false;
final List<String> _log = [];
final _logScroll = ScrollController();

void _log_(String l) {
  setState(() {
    _log.add(l);
    if (_log.length > 500) _log.removeAt(0);
  });
  // 滚动到底部...
}
```

**重构后：**
```dart
// base_vulhub_exp_page.dart
abstract class BaseVulhubExpPage<T> extends StatefulWidget { ... }

abstract class BaseVulhubExpState<T, W extends BaseVulhubExpPage<T>>
    extends State<W> {
  final logBuffer = LogBuffer(maxLines: 500);   // 来自 core/log/
  bool running = false;

  // 子类只需实现：
  String get title;
  Widget buildControls();           // 目标 URL + 参数输入
  Future<void> onRun();             // 实际漏洞利用逻辑

  @override
  Widget build(BuildContext context) => VulhubExpCardShell(
    title: title,
    controls: buildControls(),
    log: LogView(buffer: logBuffer), // 统一展示
  );
}

// druid_exp_page.dart（重构后）
class DruidExpPage extends BaseVulhubExpPage<DruidExpService> {
  @override String get title => 'Apache Druid';
  @override Widget buildControls() => /* 仅 URL 输入框 */;
  @override Future<void> onRun() => service.checkRce(url, log: logBuffer.append);
}
```

---

#### 重构点 C：消除 AES Key 重复（`behinder_crypto.dart`）

**重构前：** `php_behinder_connector.dart` 和 `jsp_behinder_connector.dart` 各自实现：
```dart
String get _aesKey {
  if (_isHex16(password)) return password;
  if (_isHex32(password)) return password.substring(0, 16);
  return md5(password).substring(0, 16);
}
```

**重构后：** 提取到 `core/crypto/behinder_crypto.dart`：
```dart
class BehinderCrypto {
  static String deriveKey(String password) { ... }
  static Uint8List encryptEcb(Uint8List data, String key) { ... }
  static Uint8List decryptEcb(Uint8List data, String key) { ... }
  static Uint8List encryptCbc(Uint8List data, String key, Uint8List iv) { ... }
}
```

两个 connector 直接调用 `BehinderCrypto.deriveKey(password)`。

---

#### 重构点 D：拆分 `misc_http_exp_service.dart`（933 行 → 按应用分文件）

**重构前：** 10+ 个不相关服务混在一个文件，任何修改都要阅读 933 行。

**重构后：** 每个应用独立文件，全部继承 `BaseExpService`：
```dart
// base_exp_service.dart
abstract class BaseExpService {
  final String targetUrl;
  final Duration timeout;
  final http.Client _client;

  Future<HttpResult> get(String path, {Map<String, String>? headers});
  Future<HttpResult> post(String path, {dynamic body, ...});
}
```

---

#### 重构点 E：拆分数据库层（`database_helper_io.dart` 1079 行 → 6 个 DAO）

**重构前：** 所有表的 CRUD 方法塞在一个文件，修改 webshell 表要翻阅 project 的代码。

**重构后：** 每张表对应一个 DAO：
```
io/
├── database_io_base.dart    # db 实例 + onCreate/onUpgrade
├── project_dao.dart         # insertProject, getProjects, updateProject, deleteProject
├── webshell_dao.dart
├── payload_dao.dart
├── dictionary_dao.dart
├── scan_session_dao.dart
└── frp_profile_dao.dart
```

`database_helper_io.dart` 变为薄组合层：
```dart
class DatabaseHelperIo implements DatabaseHelper {
  final _projectDao = ProjectDao();
  final _webshellDao = WebshellDao();
  // ...
}
```

---

#### 重构点 F：统一 LogBuffer（`core/log/log_buffer.dart`）

**重构前：** `_log_()` 方法在 15+ 个文件中各自实现有界队列 + setState。

**重构后：**
```dart
// core/log/log_buffer.dart
class LogBuffer extends ChangeNotifier {
  final int maxLines;
  final Queue<String> _lines = Queue();

  void append(String line) {
    _lines.add(line);
    if (_lines.length > maxLines) _lines.removeFirst();
    notifyListeners();
  }

  List<String> get lines => _lines.toList();
}

// widgets/common/log_view.dart
class LogView extends StatelessWidget {
  final LogBuffer buffer;
  // ListenableBuilder + ListView.builder + 自动滚动
}
```

---

#### 重构点 G：统一常量（`app/constants.dart`）

**重构前（散落各处）：**
```dart
// 多个文件中
const defaultPassword = 'mAtrix_911';
const logMaxLines = 500;
const defaultTimeout = Duration(seconds: 10);
```

**重构后：**
```dart
// app/constants.dart
abstract class AppConstants {
  static const defaultShellPassword = 'mAtrix_911';
  static const logBufferSize = 500;
  static const defaultHttpTimeout = Duration(seconds: 10);
  static const defaultScanConcurrency = 200;
  static const maxPort = 65535;
}
```

---

### 2.3 重构后量化对比

| 指标 | 重构前 | 重构后 | 改善 |
|------|--------|--------|------|
| 最大单文件行数 | 3,930 行 | ≤ 400 行 | -90% |
| Vulhub 页面重复代码 | ~1,200 行 | ~100 行（基类）| -90% |
| AES key 推导实现数 | 2 份 | 1 份 | -50% |
| 数据库层单文件 | 1,079 行 | 6 × ≤ 200 行 | 模块化 |
| `misc_http_exp_service` | 933 行 | 8 × ≤ 130 行 | 模块化 |
| 魔法值分散位置 | 20+ 处 | 1 处 | 集中管理 |
| `main.dart` | 1,971 行 | ≤ 80 行 | -96% |

---

## 三、重构优先级与建议顺序

按影响范围从小到大，降低重构风险：

```
阶段 1（零破坏性，可立即执行）
  └── G: 提取 AppConstants（只是移动常量）
  └── C: 提取 BehinderCrypto（只改两个文件）
  └── F: 提取 LogBuffer + LogView（新增文件，逐步替换）

阶段 2（中等影响，分模块执行）
  └── E: 拆分 database_helper_io → DAO 层
  └── D: 拆分 misc_http_exp_service → 按应用独立文件
  └── B: 创建 BaseVulhubExpPage，逐个迁移 Vulhub 页面

阶段 3（最大改动，最后执行）
  └── A: 拆分 webshell_interactive_page 四个 Tab
  └── 整理 main.dart → app/router.dart + app/app.dart
```

> **注意：** 每个阶段完成后应运行完整回归测试，确认功能不退化再进入下一阶段。
