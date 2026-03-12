import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 反弹 Shell 会话
class ReverseShellSession {
  ReverseShellSession(this.id, this._socket) {
    _bytesController = StreamController<List<int>>.broadcast();
    _subscription = _socket.listen(
      (data) {
        // 原始字节流（供终端控件使用）
        _bytesController.add(data);
        // 兼容旧的字符串输出（如简单日志查看）
        _controller.add(utf8.decode(data, allowMalformed: true));
      },
      onError: (e, st) {
        _controller.addError(e, st);
        _bytesController.addError(e, st);
      },
      onDone: () {
        _controller.close();
        _bytesController.close();
      },
      cancelOnError: true,
    );
  }

  final String id;
  final Socket _socket;

  final _controller = StreamController<String>.broadcast();
  late final StreamController<List<int>> _bytesController;
  late final StreamSubscription<List<int>> _subscription;

  /// 远端输出（UTF‑8 解码后的文本流）
  Stream<String> get output => _controller.stream;

  /// 原始字节流（供终端模拟器解析 ANSI 控制序列）
  Stream<List<int>> get rawStream => _bytesController.stream;

  /// 发送原始命令/按键数据到远端（不会自动追加换行，请在调用方自行控制）
  Future<void> send(String data) async {
    // 终端控件 (xterm) 已经按协议输出了正确的控制序列，这里必须原样转发，
    // 否则会导致回车/换行组合被多次处理，出现光标逐行右移等异常。
    _socket.add(utf8.encode(data));
    await _socket.flush();
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _socket.close();
    await _controller.close();
    await _bytesController.close();
  }
}

/// 本地反弹 Shell 监听服务（单例）
class ReverseShellService {
  ReverseShellService._internal();

  static final ReverseShellService _instance = ReverseShellService._internal();

  factory ReverseShellService() => _instance;

  ServerSocket? _server;
  final _sessions = <String, ReverseShellSession>{};

  /// 新会话建立时的回调（例如用于在 UI 中自动打开终端标签页）
  void Function(ReverseShellSession session)? onSession;

  /// 会话结束时的回调（例如用于刷新会话列表 UI）
  void Function(ReverseShellSession session)? onSessionClosed;

  Map<String, ReverseShellSession> get sessions => Map.unmodifiable(_sessions);

  /// 启动监听。重复调用会先关闭旧监听再重新绑定。
  Future<void> startListening({
    String address = '0.0.0.0',
    required int port,
  }) async {
    await stopListening();
    _server = await ServerSocket.bind(address, port);
    _server!.listen(_handleConnection);
  }

  Future<void> stopListening() async {
    await _server?.close();
    _server = null;
    for (final s in _sessions.values.toList()) {
      await s.close();
    }
    _sessions.clear();
  }

  Future<void> _handleConnection(Socket socket) async {
    final id = '${socket.remoteAddress.address}:${socket.remotePort}';
    final session = ReverseShellSession(id, socket);
    _sessions[id] = session;
    onSession?.call(session);
    // 任一输出流结束即认为会话结束
    await session.output.last.whenComplete(() {
      final removed = _sessions.remove(id);
      if (removed != null) {
        onSessionClosed?.call(removed);
      }
    });
  }
}

