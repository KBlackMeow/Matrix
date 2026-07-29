import '../models/webshell.dart';
import '../services/webshell_service.dart';

/// WebShell 连接池，按 shell_id 缓存 [WebshellService] 实例。
///
/// 连接器内部维护了 currentDir、Behinder 密钥协商状态等上下文，
/// 复用已有实例可以避免重复握手。
class SessionPool {
  final Future<Webshell?> Function(int id) _lookup;
  final Map<int, WebshellService> _sessions = {};

  /// 默认 shell_id，由 shell_use 设置后，后续工具可省略 shell_id 参数。
  int? defaultShellId;

  SessionPool(this._lookup);

  /// 解析 shell_id：优先用显式传入的，否则用 [defaultShellId]。
  Future<WebshellService> resolve(int? shellId) async {
    final id = shellId ?? defaultShellId;
    if (id == null) {
      throw Exception('未指定 shell_id 且没有设置默认 shell（请先调用 shell_use）');
    }
    return get(id);
  }

  /// 获取或创建 shell_id 对应的 [WebshellService]。
  ///
  /// 首次调用时从数据库读取 WebShell 配置并实例化连接器；
  /// 后续调用复用已缓存的实例。
  Future<WebshellService> get(int shellId) async {
    if (_sessions.containsKey(shellId)) return _sessions[shellId]!;

    final ws = await _lookup(shellId);
    if (ws == null) throw Exception('WebShell $shellId 不存在');
    final svc = WebshellService(ws);
    _sessions[shellId] = svc;
    return svc;
  }

  /// 移除并关闭指定 session（可选用于清理连接）。
  void evict(int shellId) {
    _sessions.remove(shellId);
  }

  /// 当前缓存的 session 数量。
  int get size => _sessions.length;

  /// 清除所有缓存的 session。
  void clear() {
    _sessions.clear();
  }
}
