# CVE-2026-123633 真实 Docker 靶场

在 x86_64 主机（ja30）上验证通过：nginx 官方镜像 1.31.8 / 1.31.9，
HTTP/2 (h2c)，`worker_connections 4`，上游被 iptables DROP（connect 挂起）。

## 启动

```bash
BASE=nginx:1.31.8 PORT=18090 docker compose -p n633d8 up -d --build
BASE=nginx:1.31.9 PORT=18091 docker compose -p n633d9 up -d --build
```

## 攻击（客户端容器）

```bash
docker run --rm --network host -v $PWD:/w -w /w python:3.12-slim \
  python client2.py 127.0.0.1 18090
```

## 实测结果（2026-11-19, ja30）

- 1.31.8：`4 worker_connections are not enough, reusing connections`（drain 持续触发），
  客户端完成 RST+drain 序列，但**没有** `signal 11/segfault`。
- 1.31.9：同样只出现 drain 日志，无崩溃。

配合插桩构建（见上级目录 README）已确认：1.31.8 在 `create_stream` 时
`reusable=1`（bug 状态），1.31.9 修复后为 `0`；1.31.8 的 drain 会选中该连接。

未复现崩溃的原因：还需要 GOAWAY 发送失败（`h2c->frames` 达到 10000 或
socket 在精确窗口内被 RST），或 Rapid7 那种 60–119 GiB 的流量编排。
