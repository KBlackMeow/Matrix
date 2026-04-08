# Matrix

基于 Flutter 构建的跨平台渗透测试框架，支持 macOS、Windows、Linux。

## 项目介绍

Matrix 是一个基于 Flutter 的跨平台安全测试工具，支持 macOS、Windows、Linux。当前版本聚焦于 Web 漏洞利用与 Webshell 管理，提供从漏洞验证到命令执行的实战化流程。

## 支持的功能

- Webshell 管理与交互式命令执行
- 多类型 Webshell 连接器支持（PHP / JSP / ASP / ASPX）
- Vulhub 系列漏洞利用模块
- ThinkPHP、Shiro、Zentao 等常见漏洞利用能力
- 快速验证与批量化利用流程支持

## 支持的 EXP 类型

- Vulhub RCE 系列 EXP
- Struts2 系列 EXP（S2）
- Spring 系列 EXP
- ThinkPHP 系列 EXP
- Shiro 系列 EXP
- Zentao EXP
- 其他常见中间件与组件漏洞 EXP（如 Tomcat、WebLogic、Nacos、Drupal、Elasticsearch、Shellshock 等）

## 快速开始

```bash
flutter pub get
flutter run -d macos   # 或 windows / linux
```

## 免责声明

本工具仅供授权渗透测试与安全研究使用，请勿用于未经授权的系统。
