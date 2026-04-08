# Matrix

> 新一代个性化 Webshell 管理工具，基于 Flutter 构建，支持 macOS / Windows / Linux 全平台。

Matrix 将 Webshell 管理、漏洞利用、内网穿透与后渗透能力整合为一体，提供流畅的图形化操作体验，专为实战渗透测试场景设计。

---

## 核心特性

### Webshell 管理

多协议连接器支持，覆盖主流 Webshell 类型：

| 类型 | 连接方式 |
|------|----------|
| PHP  | 原生 eval、passthru、base64+rot13 混淆、冰蝎 3.0（AES 加密） |
| JSP  | 冰蝎 3.0、Runtime exec、ClassLoader 字节码加载 |
| ASP  | WScript.Shell 命令执行 |
| ASPX | cmd 管道执行 |

交互功能：
- 终端命令执行（支持交互式终端）
- 可视化文件管理器（上传 / 下载 / 删除 / 重命名）
- 系统信息采集（OS、权限、网络、进程）
- 提权向量自动检测（SUID、sudo 免密、内核版本匹配）
- 反弹 Shell 一键生成与管理

### 漏洞利用模块（EXP）

**Apache Shiro**
- 默认密钥爆破 + 反序列化 RCE
- 内存马注入（冰蝎协议）

**ThinkPHP**
- ThinkPHP 5.x RCE（CVE-2018-20062、CVE-2019-9082）
- ThinkPHP 6.x 反序列化

**Struts2**
- S2-001（CVE-2010-1870）
- S2-045（CVE-2017-5638）
- S2-048（CVE-2017-9791）
- S2-052（CVE-2017-9805）
- S2-057（CVE-2018-11776）
- S2-059 / S2-061（CVE-2019-0230）

**Spring**
- Spring4Shell（CVE-2022-22965）
- Spring Cloud Function SPEL RCE（CVE-2022-22963）
- Spring Data REST（CVE-2017-8046）
- Spring OAuth2（CVE-2016-4977）
- Spring AMQP（CVE-2018-1273）

**WebLogic**
- CVE-2017-10271（XMLDecoder 反序列化）
- CVE-2020-14882（未授权 RCE）

**Tomcat**
- CVE-2017-12615（PUT 文件上传）

**Apache HTTPD**
- CVE-2021-41773（路径穿越 / RCE）

**Drupal**
- CVE-2018-7600（Drupalgeddon2）

**Elasticsearch**
- CVE-2015-1427（Groovy 沙箱逃逸 RCE）

**SaltStack**
- CVE-2020-16846 / CVE-2020-25592（未授权 RCE）

**Nacos**
- CVE-2021-29441（未授权访问 / 用户创建）

**XXL-Job**
- 未授权 Executor RCE

**Supervisor**
- CVE-2017-11610（XML-RPC RCE）

**Aria2**
- 未授权 RPC 任意文件写入

**Solr**
- CVE-2017-12629（XXE / RCE）

**Flask / SSTI**
- Jinja2 SSTI RCE

**PHP**
- CVE-2012-1823（CGI 模式参数注入 RCE）

**Shellshock**
- CVE-2014-6271（Bash 环境变量注入 RCE）

**OFBiz**
- CVE-2023-51467 / CVE-2024-38856（未授权 RCE）

**Zentao（禅道）**
- 多版本未授权 RCE

**Druid**
- 未授权访问信息泄露

### 内网穿透

内置 FRP 客户端，支持图形化配置与管理：
- TCP / UDP 隧道
- 多 Server 配置管理
- 控制通道 AES-128-CFB 加密

### 其他功能

- 项目管理：按目标归档 Webshell 与利用记录
- Payload 管理：自定义 Webshell 模板库
- 字典管理：内置常用密码与路径字典
- 信息收集：目标基础信息探测

---

## 快速开始

```bash
flutter pub get
flutter run -d macos    # 或 windows / linux
```

---

## 免责声明

本工具仅供授权渗透测试与安全研究使用，严禁用于未经授权的系统。使用者需自行承担一切法律责任。
