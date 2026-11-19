# nginx2root 状态探针（CVE-2026-123633）

这两个脚本用于在**插桩编译**的 nginx 上确认 CVE-2026-123633 的根因状态，
而不是完整崩溃利用。

## 前置

- nginx 1.31.8 / 1.31.9 源码，编译时在
  `ngx_http_v2_create_stream()` 的 `ngx_reusable_connection(...)` 前后加日志；
- `listen 18090; http2 on;` + `proxy_pass` 到慢后端（示例 `/slow` 3 秒）。

## 用法

```bash
# 1) 只发 1 字节帧头，再补发剩余部分：
#    1.31.8 会打印 create_stream idle=1 reusable=1 processing=1
#    1.31.9 修复语句后为 reusable=0
python3 probe_bug_state.py 127.0.0.1 18090

# 2) 占满 worker_connections，触发 ngx_drain_connections：
#    1.31.8 日志出现 drain pick（选中仍在处理请求的连接）
python3 probe_drain.py 127.0.0.1 18090
```

## 已确认（ja30, x86_64）

- 1.31.8：`create_stream idle=1 reusable=1 processing=1`
- 1.31.9：修复语句执行后 `reusable=0`
- 1.31.8：`drain pick idle=1 reusable=1`（drain 命中 bug 状态连接）

完整 worker 崩溃 / UAF 还需要让 `h2c->frames` 达到 10000 使 GOAWAY 帧分配失败
（Rapid7 用 60–119 GiB 流量实现），当前未复现。
