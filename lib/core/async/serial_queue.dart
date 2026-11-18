import 'dart:async';

/// 串行执行队列：同一队列内的任务严格按提交顺序、互不重叠地执行。
///
/// 背景：Behinder / JSP Session 型 WebShell 依赖 `Set-Cookie` 中的会话
/// （PHP `session_start` 文件锁、`JSESSIONID`、ASP.NET Session）。并发请求
/// 会互相覆盖会话、串号，甚至返回 200 + 空 body。
///
/// 用法：
/// ```dart
/// final queue = SerialQueue.forKey(webshell.url);
/// final response = await queue.run(() => client.post(uri, body: body));
/// ```
///
/// 约定：
/// - 任务抛出异常不会阻塞后续任务（队列尾始终完成）；
/// - 不要在 [run] 的任务内部再次调用同一个 [SerialQueue]（会自锁）。
class SerialQueue {
  SerialQueue();

  /// 按 key（通常是 WebShell URL）共享队列，让 UI 与 MCP 等不同入口也串行。
  static final Map<String, SerialQueue> _registry = <String, SerialQueue>{};

  static SerialQueue forKey(String key) =>
      _registry.putIfAbsent(key, SerialQueue.new);

  Future<void> _tail = Future<void>.value();

  /// 当前排队 + 执行中的任务数，仅供诊断/测试使用。
  int get pending => _pending;
  int _pending = 0;

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    _pending++;
    return previous
        .then((_) => action())
        .whenComplete(() {
          _pending--;
          if (!gate.isCompleted) gate.complete();
        });
  }
}
