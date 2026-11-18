# 统一漏洞利用控制台（模块化 + 单 UI 模板）

- 日期：2026-11-19
- 目标：把"每个 CVE 一套页面/逻辑"收敛为 **模块（检测 / 命令执行 / 获取 WebShell）+ 一套 UI 模板**
- 入口：Exploits 页第一个卡片 **Universal Exploit Console**

## 1. 架构

```
lib/exp/core/
  exploit_module.dart   # ExploitModule 接口、ExploitTarget、ExploitOutcome、ShellSession
  shell_deployer.dart   # 通用 WebShell 落盘器（任意可执行模块 → 拿 shell）
  module_registry.dart  # 27 个模块的适配与注册
lib/pages/exp/
  universal_exploit_page.dart  # 唯一 UI 模板
```

新增一个 CVE 只需要在 `module_registry.dart` 加一条 `SimpleExploitModule`，
UI 自动获得检测/执行/取 shell 按钮（按能力显示）。

## 2. 模块能力矩阵（27 个）

| 模块 | 分类 | 检测 | 命令执行 | WebShell |
| --- | --- | --- | --- | --- |
| struts2-s2005 / s2007 / s2032 / s2045 / s2053 / s2057 / s2059 | Struts2 | ✅ | ✅ | 通用 JSP 落盘 |
| struts2-s2052 | Struts2 | ✅ | ✅（盲打） | 盲打落盘 + HTTP 验证 |
| spring-22963 / 22965 / 1273 / 8046 / 4977 | Spring | ✅ | ✅ | 通用 JSP 落盘 |
| php-backdoor / php-cgi-2012-1823 | PHP | ✅ | ✅ | 通用 PHP 落盘 |
| tomcat-2017-12615 | Tomcat | ✅ | ✅ | 原生 PUT 写 JSP |
| weblogic-10271 / 14882 | WebLogic | ✅ | ✅ | 通用 JSP 落盘 |
| drupal-2018-7600 | Drupal | ✅ | ✅ | 通用 PHP 落盘 |
| httpd-2021-41773 | Apache | ✅ | ✅ | —（无 Web 目录写入口） |
| nacos-2021-29441 | Nacos | ✅ | — | —（可作 Derby RCE 前置） |
| xxl-job-unacc | XXL-JOB | ✅ | ✅（无回显） | —（执行器无 Web 目录） |
| thinkphp-tp5023 / tp5022 / tp2 | ThinkPHP | ✅ | ✅ | 原生写马 |
| shiro-2016-4437 | Shiro | ✅ | —（注入后可用 Behinder 执行） | 原生内存马（Filter） |
| zentao-2024-24216 | Zentao | ✅ | — | 原生 Repo 写马 |

## 3. WebShell 获取策略

1. **原生**：Tomcat（PUT）、ThinkPHP（写 `php_behinder.php`）、Shiro（rememberMe 内存马）、Zentao（Repo 写马）。
2. **通用落盘**（`ShellDeployer`）：任何能执行命令的模块
   - `find` 探测真实 web 根：`webapp / webapps / ROOT / htdocs / www / public_html`；
   - base64 写 PHP/JSP/ASPX/ASP 小马；
   - 用唯一标记 HTTP 回显验证，成功才返回 `ShellSession`。
3. **盲打模式**：S2-052 这类无回显链路，跳过"写成功"判断，只依赖 HTTP 验证。

## 4. 本轮实测（vulhub 靶场）

| 模块 | 目标 | 结果 |
| --- | --- | --- |
| struts2-s2045 | Jetty (s2-045) | check ✅ / exec `MX_MOD_OK` / shell 写入 `src/main/webapp`，`?c=id` → `uid=0(root)` |
| php-backdoor | PHP 8.1.0-dev | check ✅ / exec `MX_PHP_OK` / shell 写入 `/var/www/html`，`?c=id` → `uid=0(root)` |
| tomcat-2017-12615 | Tomcat 8.5 | check ✅ / exec `uid=0` / 原生 shell `mAtrix_t_shell.jsp` |
| thinkphp-tp5023 | ThinkPHP 5.0.23 | check ✅ / exec `MX_TP_OK` / 原生 `php_behinder.php`，`?c=id` → `uid=33` |

## 5. 已知缺口

- **Nacos / XXL-JOB / httpd**：无 WebShell 落点（执行器/CGI 场景没有可写 Web 目录或需额外载荷）。
- **Shiro**：模块内未直接提供 `exec`；拿到内存马后可作为 `jsp_behinder` WebShell 连接执行。
- **S2-052**：XStream 链本身无回显，执行结果不可读。
- 旧的按 CVE 独立页面仍保留（作为高级选项：Shiro 密钥爆破参数、ThinkPHP 模块选择等），统一控制台是默认入口。

## 6. 验证工具

```bash
# 列出模块与能力
dart tool/verify/module_smoke.dart --list

# 单模块冒烟：检测 + 执行 + 取 shell
dart tool/verify/module_smoke.dart struts2-s2045 http://127.0.0.1:8080 'id' --shell
```
