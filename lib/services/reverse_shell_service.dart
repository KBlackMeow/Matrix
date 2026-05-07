import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../database/database_helper.dart';

/// 反弹 Shell 会话
class ReverseShellSession {
  ReverseShellSession(this.id, this._socket) {
    _bytesController = StreamController<List<int>>.broadcast();
    _historyRaw = <List<int>>[];
    _subscription = _socket.listen(
      (data) {
        // 记录历史字节数据，便于之后重新打开终端页面时回放
        _historyRaw.add(List<int>.from(data));
        // 原始字节流（供终端控件使用）
        _bytesController.add(data);
        // 兼容旧的字符串输出（如简单日志查看）
        _controller.add(utf8.decode(data, allowMalformed: true));
      },
      onError: (e, st) {
        _alive = false;
        if (!_controller.isClosed) _controller.addError(e, st);
        if (!_bytesController.isClosed) _bytesController.addError(e, st);
      },
      onDone: () {
        _alive = false;
        if (!_controller.isClosed) _controller.close();
        if (!_bytesController.isClosed) _bytesController.close();
      },
      cancelOnError: true,
    );
  }

  final String id;
  final Socket _socket;

  /// 可选的来源标签，例如 Webshell 名称，便于在 UI 中展示
  String? label;

  /// 上次发送给远端的 stty cols/rows，用于避免重复进入终端页面时重复发送
  int? lastSttyCols;
  int? lastSttyRows;

  bool _alive = true;

  /// Socket 是否仍然存活（远端未断开）
  bool get isAlive => _alive;

  final _controller = StreamController<String>.broadcast();
  late final StreamController<List<int>> _bytesController;
  late final List<List<int>> _historyRaw;
  late final StreamSubscription<List<int>> _subscription;

  /// 远端输出（UTF‑8 解码后的文本流）
  Stream<String> get output => _controller.stream;

  /// 原始字节流（供终端模拟器解析 ANSI 控制序列）
  Stream<List<int>> get rawStream => _bytesController.stream;

  /// 历史原始字节数据快照（按接收顺序拼接），用于重新打开终端页面时回放。
  ///
  /// 返回只读视图，避免外部修改内部缓存。
  List<List<int>> get historyRaw => List.unmodifiable(_historyRaw);

  /// 发送原始命令/按键数据到远端（不会自动追加换行，请在调用方自行控制）
  Future<void> send(String data) async {
    if (!_alive) throw StateError('连接已断开');
    try {
      _socket.add(utf8.encode(data));
      await _socket.flush();
    } catch (e) {
      _alive = false;
      rethrow;
    }
  }

  /// 发送原始字节（用于大块数据传输，避免中间字符串拼接）
  Future<void> sendBytes(List<int> data) async {
    if (!_alive) throw StateError('连接已断开');
    try {
      _socket.add(data);
      await _socket.flush();
    } catch (e) {
      _alive = false;
      rethrow;
    }
  }

  Future<void> close() async {
    _alive = false;
    await _subscription.cancel();
    await _socket.close();
    if (!_controller.isClosed) await _controller.close();
    if (!_bytesController.isClosed) await _bytesController.close();
  }
}

/// 本地反弹 Shell 监听服务（单例）
class ReverseShellService {
  ReverseShellService._internal();

  static final ReverseShellService _instance = ReverseShellService._internal();

  factory ReverseShellService() => _instance;

  ServerSocket? _server;
  final _sessions = <String, ReverseShellSession>{};
  final _changes = StreamController<void>.broadcast();

  // 当前监听绑定的地址与端口（用于避免在同一地址/端口上重复重启监听）
  String? _bindAddress;
  int? _bindPort;
  bool _portOccupied = false;

  String lhost = '127.0.0.1';
  int lport = 4444;

  static const _kLhostKey = 'reverse_shell_lhost';
  static const _kLportKey = 'reverse_shell_lport';

  Future<void> loadConfig() async {
    try {
      final db = DatabaseHelper();
      final savedHost = await db.getMetaValue(_kLhostKey);
      final savedPortStr = await db.getMetaValue(_kLportKey);
      final savedPort = int.tryParse(savedPortStr ?? '');
      if (savedHost != null && savedHost.isNotEmpty) {
        lhost = savedHost;
      }
      if (savedPort != null && savedPort > 0 && savedPort < 65536) {
        lport = savedPort;
      }
    } catch (_) {
      // 读取配置失败时静默回退到默认值
    }
  }

  Future<void> saveConfig() async {
    try {
      final db = DatabaseHelper();
      await db.setMetaValue(_kLhostKey, lhost);
      await db.setMetaValue(_kLportKey, lport.toString());
    } catch (_) {
      // 持久化失败时忽略，不影响当前会话使用
    }
  }

  /// 新会话建立时的回调（例如用于在 UI 中自动打开终端标签页）
  void Function(ReverseShellSession session)? onSession;

  /// 会话结束时的回调（例如用于刷新会话列表 UI）
  void Function(ReverseShellSession session)? onSessionClosed;

  /// 服务状态变化流（监听状态/会话列表变化时触发）
  Stream<void> get changes => _changes.stream;

  Map<String, ReverseShellSession> get sessions => Map.unmodifiable(_sessions);

  /// 当前是否有监听 Socket 存活（可能与配置的 LHOST/LPORT 不同）
  bool get isListening => _server != null;

  /// 实际监听绑定的地址（可能为 null，表示尚未绑定）
  String? get bindAddress => _bindAddress;

  /// 实际监听绑定的端口（可能为 null，表示尚未绑定）
  int? get bindPort => _bindPort;
  bool get isPortOccupied => _portOccupied;

  /// 启动监听。重复调用会先关闭旧监听再重新绑定。
  Future<void> startListening({
    String address = '0.0.0.0',
    required int port,
  }) async {
    // 如果已经在相同的地址和端口上监听，则复用当前监听，避免清空现有会话。
    if (_server != null && _bindAddress == address && _bindPort == port) {
      return;
    }

    await stopListening();
    _server = await ServerSocket.bind(address, port);
    _bindAddress = address;
    _bindPort = port;
    _portOccupied = false;
    _server!.listen(_handleConnection);
    _notifyChanged();
  }

  Future<void> stopListening() async {
    await _server?.close();
    _server = null;
    _bindAddress = null;
    _bindPort = null;
    _portOccupied = false;
    for (final s in _sessions.values.toList()) {
      await s.close();
    }
    _sessions.clear();
    _notifyChanged();
  }

  /// 刷新监听状态（用于 UI 与真实端口占用状态对齐）。
  ///
  /// 当服务自身未持有 server 句柄时，会通过尝试 bind 探测端口是否被占用。
  Future<void> refreshListeningState({
    String address = '0.0.0.0',
    int? port,
  }) async {
    if (_server != null) {
      if (_portOccupied) {
        _portOccupied = false;
        _notifyChanged();
      }
      return;
    }
    final targetPort = port ?? lport;
    try {
      final probe = await ServerSocket.bind(address, targetPort);
      await probe.close();
      if (_portOccupied) {
        _portOccupied = false;
        _notifyChanged();
      }
    } catch (_) {
      _portOccupied = true;
      _bindAddress = address;
      _bindPort = targetPort;
      _notifyChanged();
    }
  }

  Future<void> _handleConnection(Socket socket) async {
    final id = '${socket.remoteAddress.address}:${socket.remotePort}';
    final session = ReverseShellSession(id, socket);
    _sessions[id] = session;
    onSession?.call(session);
    _notifyChanged();
    // 等待会话结束（含无数据即断开的情况）
    try {
      await session.output.last;
    } catch (_) {
      // 连接未发送任何数据即关闭时属于正常情况，忽略 StateError
    } finally {
      final removed = _sessions.remove(id);
      if (removed != null) {
        onSessionClosed?.call(removed);
        _notifyChanged();
      }
    }
  }

  void _notifyChanged() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }
}

