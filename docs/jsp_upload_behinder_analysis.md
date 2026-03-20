# JSP 上传加速：对照 Behinder 源码的结论与 Matrix 方案

## 1. 外部代码在做什么（Behinder）

### `FileService.java`

- `UPLOAD_BLOCK_SIZE = 30720`（约 **30KB** 一块）
- 固定线程池 **`THREAD_NUM = 10`**
- 对本地文件用 `FileChannel`，按块 `position(finalI * UPLOAD_BLOCK_SIZE)` 读数据
- 每块调用 `uploadFilePart(remotePath, bytes, blockIndex, blockSize)`，**多线程并发**提交

### `FileOperation.java` → `updateFile()`

- 从 **`HttpSession`** 里按 **`path`** 取 `FileChannel`；没有则 `new FileOutputStream(path)` 并放进 Session
- **`synchronized(ch)`** 后：`ch.position(blockIndex * blockSize)`，再写入 **Base64 解码后的 `content`**
- 要点：**块可乱序到达**，靠 **固定 blockSize** 与 **blockIndex** 定位；**同一文件共用同一 Session 里的 Channel**

因此 Behinder 能快的原因可以概括为：

1. **大块**（30KB）减少往返次数  
2. **多线程并行** HTTP 请求  
3. **数据在加密 Body 里**，不受 Tomcat **请求头 8KB 级别**限制  

---

## 2. Matrix 冰蝎协议（`jsp_behinder`）的硬约束

- 客户端每次 POST：**Body = 一整行 AES( M.class )**；**命令与数据主要在 HTTP Header**（`X-Path`、`X-Path-B64`、`X-Data`、`X-V`…）
- **`X-Data` 不能随意放大**：需落在 **`maxHttpHeaderSize`（常见 8KB）** 内，还要扣掉 Cookie、UA 等
- **无法**在不大改 JSP/协议的前提下做到 Behinder 那种 **30KB/块**；只能 **按头预算算安全块大小**（通常 **几百字节～几 KB 原始数据** 量级）
- **中文 / 非 ASCII 路径**：HTTP 头值须为可传输的 ASCII。客户端对路径做 **UTF-8 → Base64**，放在 **`X-Path-B64`**；`M.java` 优先解码该头再作为 `File` 路径。仍用明文的 **`X-Path`** 仅适合纯 ASCII 路径。若 Base64 后路径头过长（约 **>6000 字符**，视容器 `maxHttpHeaderSize` 而定），客户端回退 **`exec`**（路径经 shell base64 解码）。

---

## 3. 推荐方案（已实现思路）

### 服务端 `M.java`

- 增加与 Behinder **`updateFile` 同模型** 的指令（如 **`wpart` / `wclose`**）：
  - Session 里保存 `FileChannel` + `FileOutputStream`
  - `position = blockIndex * blockSize`，写入解码后的块  
- **必须依赖 `HttpSession`**：与 Behinder 一样，无 Session 则不可用  
- **响应写入**：避免 `OutputStream.close()` 失败后又 `getWriter()` 触发 `IllegalStateException` 被吞掉 → **空响应、ping 失败**

### 客户端 `jsp_behinder_connector.dart`

- **小文件**：若整文件 Base64 后仍能塞进 `X-Data` 预算 → 单次 **`write`**（与 Behinder GUI 小文件行为一致）
- **大文件**：  
  1. 先发一次 **`ping`**（拿到 `JSESSIONID`，避免**首批并行请求各自新建 Session**）  
  2. **块 0 必须串行** 完成，再对 **块 1…N 并行**（批大小参考 Behinder 的 10，Matrix 可用 8）  
  3. 结束后 **`wclose`**；任一步失败 → **回退** 到现有 **`exec` + base64 重定向** 分块（**不改变**原慢路径语义）

### `jsp_classloader` 连接器

- 每次请求表单里都带 **整段 agent Base64**，体积巨大；**并行多块 = 每块重复传 agent**，带宽反而更差。  
- **上传加速应以 `jsp_behinder` 为主**；ClassLoader 马仍以 **`exec` 分块** 为主（可适当调大 `_kChunkSize`，受 `maxPostSize` 限制）。  
- 内置 **`jsp_classloader_b64.jsp`**（隐蔽默认）与 **`jsp_classloader_b64_debug.jsp`**（明文 `MATRIX_JSP_ERR:*`，仅排错）均使用参数名 **`mAtrix_911`**；连接器在「密码」为空时默认参数名必须是 **`mAtrix_911`**，否则会 **完全无响应**（与 M 无关）。

---

## 4. 风险与回退

| 风险 | 缓解 |
|------|------|
| 旧 agent 无 `wpart` | 返回非 `1`，客户端 **自动走 exec** |
| Session 粘连 | `wclose` + 失败同样 `wclose` |
| 头仍超限 | 动态缩小块或只走 exec |
| 中文路径 | 优先 **`X-Path-B64`** + 原生 `ls`/`write`/`wpart`/`rm`；头过长则 **exec** |

---

## 5. 文件对应关系

| 组件 | 路径 |
|------|------|
| 分析对象（外部） | `workstation/BehinderClientSource/.../FileService.java`、`FileOperation.java` |
| Matrix agent | `tools/jsp_agent/M.java` → `data/jsp_agent_M.b64` |
| 冰蝎连接器 | `lib/connectors/jsp_behinder_connector.dart` |
| ClassLoader 连接器 | `lib/connectors/jsp_classloader_connector.dart` |
| 内置 ClassLoader JSP（默认 / 排错） | `jsp_classloader_b64.jsp` / `jsp_classloader_b64_debug.jsp` |

编译 agent：`tools/jsp_agent/build_agent.sh`（改完 `M.java` 后执行，并 **`flutter clean` 后完整运行**）。
