# Matrix

> 新一代个性化 Webshell 管理工具，基于 Flutter 构建，支持 macOS / Windows / Linux 全平台。

---

## 核心特性

### Webshell 管理

多协议连接器，覆盖主流 Webshell 类型：

| 类型 | 连接方式 |
|------|----------|
| PHP  | eval、passthru、base64+rot13 混淆、冰蝎 3.0（AES） |
| JSP  | 冰蝎 3.0、Runtime exec、ClassLoader 字节码加载 |
| ASP  | WScript.Shell |
| ASPX | .NET Process |

交互功能：
- 交互式终端
- 可视化文件管理器（上传 / 下载 / 删除 / 重命名）
- 系统信息采集（OS、权限、网络、进程）
- 提权向量检测（SUID、sudo 免密、内核版本）
- 反弹 Shell 生成

### 漏洞利用（EXP）

| 框架 / 组件 | CVE / 漏洞 |
|------------|-----------|
| Apache Shiro | 默认密钥爆破 + 反序列化 RCE，内存马注入 |
| ThinkPHP | 5.x RCE（CVE-2018-20062、CVE-2019-9082），6.x 反序列化 |
| Struts2 | S2-001 / 045 / 048 / 052 / 057 / 059 / 061 |
| Spring | Spring4Shell、Cloud Function SPEL、Data REST、OAuth2、AMQP |
| WebLogic | CVE-2017-10271、CVE-2020-14882 |
| Tomcat | CVE-2017-12615 |
| Apache HTTPD | CVE-2021-41773 |
| Drupal | CVE-2018-7600 |
| Elasticsearch | CVE-2015-1427 |
| SaltStack | CVE-2020-16846 / CVE-2020-25592 |
| Nacos | CVE-2021-29441 |
| XXL-Job | 未授权 Executor RCE |
| Supervisor | CVE-2017-11610 |
| Aria2 | 未授权 RPC 任意文件写入 |
| Solr | CVE-2017-12629 |
| Flask / SSTI | Jinja2 SSTI RCE |
| PHP CGI | CVE-2012-1823 |
| Shellshock | CVE-2014-6271 |
| OFBiz | CVE-2023-51467 / CVE-2024-38856 |
| Zentao（禅道） | 多版本未授权 RCE |
| Druid | 未授权访问信息泄露 |

### 内网穿透

内置 FRP 客户端：
- TCP / UDP 隧道
- 多 Server 配置管理
- 控制通道 AES-128-CFB 加密

### 项目与 Payload 管理

- 按目标归档 Webshell 与利用记录
- 内置 Payload 模板库（可自定义）

---

## 快速开始

```bash
flutter pub get
flutter run -d macos    # 或 windows / linux
```

---

## 免责声明

本工具仅供授权渗透测试与安全研究使用，严禁用于未经授权的系统。使用者需自行承担一切法律责任。
