# exp × vulhub 全量测试矩阵

- 日期：2026-11-19
- 分支：dev20261118
- 范围：`lib/exp/**` 全部检测与命令执行能力 × 对应 vulhub 靶场
- 工具：`tool/verify/exp_live.dart`（单点调用）+ `tool/verify/lab_matrix.py`（自动起停靶场）

## 1. 检测矩阵（26 个靶场）

| # | 靶场 | exp 用例 | 结果 | 证据 |
| --- | --- | --- | --- | --- |
| 1 | struts2/s2-005 | s2005-check | ✅ VULN | README POST 回显 54289 |
| 2 | struts2/s2-007 | s2007-check | ✅ VULN | `user.action` + `age` 注入 54289 |
| 3 | struts2/s2-032 | s2032-check | ✅ VULN | DMI OGNL 54289 |
| 4 | struts2/s2-045 | s2045-check | ✅ VULN | Content-Type OGNL 54289 |
| 5 | struts2/s2-052 | s2052-check | ✅ VULN | XStream `CannotResolveClassException` |
| 6 | struts2/s2-053 | s2053-check | ✅ VULN | Freemarker 54289 |
| 7 | struts2/s2-057 | s2057-check | ✅ VULN | Location 回显 54289 |
| 8 | struts2/s2-059 | s2059-check | ✅ VULN | 标签属性 54289 |
| 9 | spring/CVE-2016-4977 | spring-4977 | ✅ VULN | SpEL 54289 |
| 10 | spring/CVE-2017-8046 | spring-8046 | ✅ VULN | PATCH SpEL 异常特征 |
| 11 | spring/CVE-2018-1273 | spring-1273 | ✅ VULN | `Invalid property 'username'` |
| 12 | spring/CVE-2022-22963 | spring-22963 | ✅ VULN | 时间侧信道 ~3s |
| 13 | spring/CVE-2022-22965 | spring-22965 | ✅ VULN | 写入并回显 JSP |
| 14 | php/8.1-backdoor | php-check | ✅ VULN | User-Agentt 回显 |
| 15 | php/CVE-2012-1823 | phpcgi-check | ✅ VULN | 参数注入回显 |
| 16 | tomcat/CVE-2017-12615 | tomcat-check | ✅ VULN | PUT 写 JSP 并执行 |
| 17 | httpd/CVE-2021-41773 | httpd-check | ✅ VULN | 读取 /etc/passwd |
| 18 | drupal/CVE-2018-7600 | drupal-check | ⚠️ SKIP | 靶场未安装（见 §4） |
| 19 | nacos/CVE-2021-29441 | nacos-check | ✅ VULN | 未授权用户列表 |
| 20 | xxl-job/unacc | xxljob-check | ✅ VULN | 执行器 `/run` code=200 |
| 21 | shiro/CVE-2016-4437 | shiro-check | ✅ VULN | `rememberMe=deleteMe` |
| 22 | thinkphp/5.0.23-rce | thinkphp-check | ✅ VULN | tp5023 |
| 23 | thinkphp/5-rce | thinkphp-check | ✅ VULN | tp5022_5129 |
| 24 | thinkphp/2-rce | thinkphp-check | ✅ VULN | tp2 |
| 25 | weblogic/CVE-2020-14882 | weblogic-14882 | ✅ VULN | Location 路径绕过 302 |
| 26 | weblogic/CVE-2017-10271 | weblogic-10271 | ✅ VULN | `/wls-wsat` XMLDecoder 端点 500 |

统计：**25 VULN / 1 SKIP / 0 漏报**（SKIP 为靶场未安装，不是 exp 缺陷）。

## 2. 命令执行链矩阵

| 靶场 | 用例 | 命令 | 结果 |
| --- | --- | --- | --- |
| s2-005 | s2005-exec | `id` | 盲打（官方 PoC 设计为无回显），返回提示文案 |
| s2-032 | s2032-exec | `echo MATRIX_EXP_OK` | `MATRIX_EXP_OK` |
| s2-045 | s2045-exec | 同上 | `MATRIX_EXP_OK` |
| s2-053 | s2053-exec | 同上 | `MATRIX_EXP_OK` |
| s2-057 | s2057-exec | `id` | `uid=0(root)` |
| s2-059 | s2059-exec | `id` | `uid=0(root)` |
| spring-22963 | spring-exec | `touch "/tmp/matrix exec"` | 目标文件生成 |
| spring-22965 | spring-22965 | 写 JSP | 标记回显 |
| php backdoor | php-exec | `echo $HOME` | `/root` |
| php-cgi | phpcgi-exec | `id` | `uid=33(www-data)` |
| tomcat | tomcat-getshell | — | 返回 shell URL |
| httpd | httpd-exec | `id` | `uid=1(daemon)` |
| xxl-job | xxljob-exec | — | 执行器 `{"code":200}`（无回显） |
| thinkphp 5.0.23 | thinkphp-exec | `echo MATRIX_EXP_OK` / `id` | 标记 / `uid=33(www-data)` |

未测执行链：S2-052（XStream 盲打）、Drupal（未安装）、Nacos（Derby RCE 需额外载荷）、Shiro（需密钥爆破 + 内存马注入）。

## 3. 本轮修复（靶场驱动）

| 问题 | 修复 |
| --- | --- |
| S2-007 打错路径/字段 | 候选 `user.action`/`login.action`/`index.action` + 两套字段名 |
| Spring4Shell 时机太早 | 先发预热请求，再轮询最多 ~20s |
| Spring Data Commons 只认 Whitelabel 500 | 请求 JSON 错误页，只认 `Invalid property username` / SpEL 特征 |
| Drupal 未安装被当成"不存在" | 识别安装向导 → `probeFailed("未安装")`；并用唯一标记验证执行 |
| XXL-JOB 只匹配响应里的 "200" | 解析 JSON 且要求 `code==200`；按执行器端口测试 |
| ThinkPHP 2.x/3.x 未编码 `${...}` | `Uri.encodeComponent`，并补齐 harness 的 tp2 等用例 |
| ThinkPHP exec 截断到 `</html>` | 命令用标记包裹 + 按标记提取；payload 直接作为 raw body 提交 |
| S2-052 只要端点可达就算漏洞 | 要求 XStream 反序列化特征 |
| Apache CGI 输出乱码/为空 | CGI 前置 `Content-Type` 行；RawHttpClient 解码 chunked 响应 |
| 矩阵复用容器导致"打错靶场" | 每个靶场独立 compose 项目名，按项目清理与取端口 |

## 4. 环境限制与后续

1. **Drupal CVE-2018-7600**：vulhub 靶场要求手动完成安装（标准 profile + SQLite）。
   容器化自动安装未成功（installer 多步表单 + batch token），因此检测只能验证到
   "未安装 → probeFailed"。已改用唯一标记检测，安装后即可直接验证。
2. **XXL-JOB**：检测/执行要打**执行器**端口（9999），不是 admin（8080）；矩阵已按此配置。
3. **WebLogic**：镜像需要 `--platform linux/amd64`；两个 CVE 已单独验证。
4. **Shiro 密钥爆破/内存马**：需要密钥字典与目标端载荷，未纳入本轮矩阵。
5. 本轮仅覆盖 `lib/exp` 的检测与主要 RCE 链；`zentao`、`misc_http` 等无对应 vulhub 目录的模块未纳入。

## 5. 复现方式

```bash
# 单点
dart tool/verify/exp_live.dart s2059-check http://127.0.0.1:8080

# 全量（自动起停靶场，需本地 vulhub 仓库）
VULHUB_DIR=/path/to/vulhub DART_BIN=$(which dart) \
  python3 tool/verify/lab_matrix.py
```
