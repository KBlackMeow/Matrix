# Matrix

基于 Flutter 构建的跨平台渗透测试框架，支持 macOS、Windows、Linux、iOS、Android 及 Web。

## 主要功能

- **Webshell 管理**：支持 PHP / JSP / ASP 多种协议，提供交互式终端与文件管理
- **漏洞利用**：内置 Apache Shiro、ThinkPHP、Zentao 利用模块，通用 POC 引擎支持 389 条 YAML 规则
- **网络侦察**：端口扫描、Web 目录枚举、服务指纹识别、ICMP/NetBIOS 探测
- **暴力破解**：支持 MySQL、Redis、FTP、SMB、MSSQL 等常见服务
- **反弹 Shell**：多平台 Shell 生成与交互式监听
- **内网穿透**：集成 FRP，支持 TCP/SOCKS5 隧道

## 快速开始

```bash
flutter pub get
flutter run -d macos   # 或 windows / linux / chrome / android
```

## 免责声明

本工具仅供授权渗透测试与安全研究使用，请勿用于未经授权的系统。
