# nginx2root 两个 CVE 的 Docker 验证记录

- 日期：2026-11-19
- 对象：CVE-2026-123007、CVE-2026-123633（F5 NGINX，2026-11-18 披露，俗称 nginx2root）
- 环境：Docker Desktop（aarch64 宿主，`--platform linux/amd64` 模拟）、nginx 官方镜像 1.31.8 / 1.31.9

## 1. 漏洞事实（来自 F5 / MITRE 记录）

| CVE | 类型 | 受影响版本 | 修复 | 前置条件 | 评分 |
| --- | --- | --- | --- | --- | --- |
| CVE-2026-123007 | CWE-191 整数下溢 + CWE-787 越界写 | 1.9.5 – 1.31.8 | 1.31.9 / 1.30.7 | HTTP/2 开启 | 8.1 (v3.1) / 9.2 (v4.0) |
| CVE-2026-123633 | CWE-416 释放后重用 | 1.19.7 – 1.31.8 | 1.31.9 / 1.30.7 | HTTP/2 + 反向代理到 upstream | 8.1 (v3.1) / 9.2 (v4.0) |

两者都只影响数据面；RCE 需要 ASLR 关闭或可绕过，崩溃（DoS）是更现实的直接影响。

## 2. CVE-2026-123007：已复现（官方差分）

使用 Censys Research 公开的 compact h2c 差分脚本（`github.com/Censys-Research/nginx2root`）：

```bash
python3 -I h2c_flow_control_test.py --docker \
  --output /tmp/nginx2root-compact-evidence.json \
  --command-timeout 120 --client-timeout 120 \
  --acknowledge-local-lab I-AUTHORIZE-LOCAL-LAB
```

结果：

```
PASS: vulnerable h2c accepted over-credit; patched control rejected it
```

证据（`/tmp/nginx2root-compact-evidence.json`）：

- nginx:1.31.8：`result=passed`、`expected_exit=0`、`actual_exit=0`
  —— 8 MB 响应排队后，连接窗口被超额补充，1 字节 `WINDOW_UPDATE` 被接受，`PING` 得到 ACK，连接在窗口超过上限的情况下仍然存活。
- nginx:1.31.9：`result=passed`、`expected_exit=1`、`actual_exit=1`
  —— 提前拒绝 4 MiB 的 `WINDOW_UPDATE`，连接以 TCP FIN 结束。

说明：该脚本验证的是 **流控记账错误**，不是 RCE。Censys 的完整 RCE 证据（119 GiB 流量、ASLR 解析、cleanup 回调执行）需要 Rapid7 的完整链，本次未复现。

## 3. CVE-2026-123633：版本与补丁已确认，崩溃未复现

### 3.1 修复点确认（源码级）

- 修复 commit：`0c87dd1db413e440a4e3ef7ee8acc518509e8809`
  "HTTP/2: reset reusable connection status on stream creation"
- 1.31.8 源码：`ngx_http_v2_create_stream()` 中没有
  `ngx_reusable_connection(h2c->connection, 0);`（0 处）
- 1.31.9 源码：该语句存在（1 处）

即：不完整 HEADERS 让连接被标记 reusable 后，补全 HEADERS 创建 stream 时旧版本不清除 reusable，
后续 `ngx_drain_connections()` 可能把仍在处理请求的连接关闭；若 GOAWAY 帧分配失败
（每连接帧数达 10000 上限），错误路径会直接释放连接内存，形成 UAF。

### 3.2 Docker 环境尝试

1. nginx 1.31.8 + 慢后端 + h2c/TLS，worker_connections=24/16/4，测试：
   - 公开 PoC（`github.com/LLCForge/CVE-2026-123633`）：10/25 波 RST 洪泛，worker 未崩溃；
   - 自建触发：不完整 HEADERS → 补全 → 上游挂起，`worker_connections` 耗尽触发
     `ngx_drain_connections`，并构造 10000+ 队列帧让 GOAWAY 分配失败。
2. 结果：nginx 日志出现 `worker_connections are not enough, reusing connections`（drain 已触发），
   但 1.31.8 与 1.31.9 均未出现 `signal 11` / `segfault`，行为差分未显现。

### 3.3 结论

- 受影响/修复版本与补丁代码已确认（1.31.8 无修复、1.31.9 有修复）。
- **未能在本环境复现 worker 崩溃**：该漏洞需要精确的“连接池耗尽 + reusable 状态 + GOAWAY 分配失败 +
  upstream 请求在途”竞态；公开资料没有可直接运行的可靠 PoC（Censys 也只给出结论，未发布 123633 适配器；
  ThreatCluster 报道称当时无公开 PoC）。
- 因此本次只能确认“版本受影响 + 补丁存在”，不能声称已复现 UAF/DoS。

## 4. 复现命令汇总

```bash
# 123007 官方差分
git clone --depth 1 https://github.com/Censys-Research/nginx2root
python3 -I nginx2root/h2c_flow_control_test.py --docker \
  --acknowledge-local-lab I-AUTHORIZE-LOCAL-LAB

# 123633 环境（自建）
#   nginx:1.31.8 / 1.31.9 + 慢后端 + http2 on + worker_connections 4~24
#   客户端：不完整 HEADERS → 补全 → 触发 drain
```

## 5. 来源

- MITRE CVE 记录：CVE-2026-123633 / CVE-2026-123007
- F5 公告：K000163928（123633）、K000163926（123007）
- Censys：<https://censys.com/blog/nginx2root-simple-test/>
- Xint：<https://xint.io/blog/nginx2root-remote-code-execution>
