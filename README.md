# Matrix

> 新一代个性化 Webshell 管理工具，基于 Flutter 构建，支持 macOS / Windows / Linux 全平台。

---

## 核心特性

### Webshell 管理

多协议连接器，覆盖主流 Webshell 类型：


| 类型   | 连接方式                                      |
| ---- | ----------------------------------------- |
| PHP  | eval、passthru、base64+rot13 混淆、冰蝎 3.0（AES） |
| JSP  | 冰蝎 3.0、Runtime exec、ClassLoader 字节码加载     |
| ASP  | WScript.Shell                             |
| ASPX | .NET Process                              |


交互功能：

- 交互式终端
- 可视化文件管理器（上传 / 下载 / 删除 / 重命名）
- 支持从 Payload 库选择文件并上传到当前远程目录
- 系统信息采集（OS、权限、网络、进程）
- 提权向量检测（SUID、sudo 免密、内核版本）
- 反弹 Shell 生成

### Payload 管理

- 内置 PHP / JSP / ASP / ASPX 常用 payload
- 支持从本地文件导入 payload，并在详情页复制、下载或转 Base64
- 支持二进制 payload 的 Base64 存储与下载
- Webshell 文件管理器可直接选择 Payload 库中的文件上传到目标目录

### 漏洞利用（EXP）


| 框架 / 组件             | 漏洞编号                                                            |
| ------------------- | --------------------------------------------------------------- |
| Apache Shiro        | CVE-2016-4437                                                   |
| ThinkPHP            | CVE-2018-20062 / CVE-2019-9082 / CNVD-2022-86535                |
| Zentao（禅道）          | CVE-2024-24216                                                  |
| Apache Struts2      | S2-032 / S2-045 / S2-053 / S2-057 / S2-059                      |
| Spring Framework    | CVE-2022-22963 / CVE-2022-22965 / CVE-2018-1273 / CVE-2017-8046 |
| Apache HTTP Server  | CVE-2021-41773                                                  |
| Apache Druid        | CVE-2021-25646                                                  |
| Apache OFBiz        | CVE-2023-51467 / CVE-2024-38856                                 |
| Apache Solr         | CVE-2017-12629                                                  |
| Drupal              | CVE-2018-7600                                                   |
| Elasticsearch       | CVE-2015-1427                                                   |
| Flask / Jinja2 SSTI | SSTI                                                            |
| PHP                 | PHP 8.1.0-dev / CVE-2012-1823                                   |
| Apache Tomcat       | CVE-2017-12615                                                  |
| Oracle WebLogic     | CVE-2017-10271 / CVE-2020-14882                                 |
| Supervisor          | CVE-2017-11610                                                  |
| XXL-JOB             | 未授权 Executor RCE                                                |
| Nacos               | CVE-2021-29441                                                  |
| Bash Shellshock     | CVE-2014-6271                                                   |
| SaltStack           | CVE-2020-16846                                                  |
| Aria2               | 未授权 JSON-RPC                                                    |




### 内网穿透

内置 FRP 客户端

---

## 快速开始

```bash
flutter pub get
flutter run -d macos    # 或 windows / linux
```

> 当前主要面向桌面端（macOS / Windows / Linux），不以 Flutter Web 作为支持目标。

---

## 免责声明

本工具仅供授权渗透测试与安全研究使用，严禁用于未经授权的系统。使用者需自行承担一切法律责任。