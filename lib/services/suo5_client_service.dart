import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

enum Suo5Status { idle, connecting, running, error }

class Suo5Config {
  const Suo5Config({
    required this.targetUrl,
    this.listenHost = '127.0.0.1',
    this.listenPort = 1080,
  });

  final String targetUrl;
  final String listenHost;
  final int listenPort;
}

/// 单条 suo5 隧道的运行时（独立 SOCKS 监听 / 心跳 / 流量统计 / 日志）
///
/// 历史上 [Suo5ClientService] 自身就是单条隧道，整个 App 同时只能跑一条；
/// 现在把这部分实现抽到 [Suo5Session]，由 [Suo5ClientService] 做多会话管理。
class Suo5Session {
  Suo5Session({this.label = ''});

  String label;

  Suo5Status _status = Suo5Status.idle;
  Suo5Status get status => _status;

  String _mode = 'classic';
  String get mode => _mode;
  int _modeByte = 0x03;
  int _activeConnections = 0;
  int get activeConnections => _activeConnections;
  int _uploadBytes = 0;
  int get uploadBytes => _uploadBytes;
  int _downloadBytes = 0;
  int get downloadBytes => _downloadBytes;

  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);

  ServerSocket? _server;
  final http.Client _http = http.Client();
  final Set<_Suo5Tunnel> _tunnels = {};
  String _sessionId = '';
  final Map<String, String> _cookies = {};
  Suo5Config? _currentConfig;
  Suo5Config? get currentConfig => _currentConfig;
  Timer? _heartbeatTimer;

  /// UI 监听：状态/日志/流量发生变化时触发
  void Function()? onChanged;

  /// 由 [Suo5ClientService] 注入：单条日志生成时上抛 (时间, 原始消息)
  void Function(DateTime when, String message)? onLog;

  Future<void> start(Suo5Config config) async {
    if (_status == Suo5Status.connecting || _status == Suo5Status.running) return;
    _setStatus(Suo5Status.connecting);
    _logs.clear();
    _currentConfig = config;
    _sessionId = '';
    _cookies.clear();
    _uploadBytes = 0;
    _downloadBytes = 0;
    _activeConnections = 0;
    try {
      await _handshake(config);
      _server = await ServerSocket.bind(config.listenHost, config.listenPort);
      _server!.listen(_handleSocksClientRaw, onError: (Object e, StackTrace st) {
        _log('SOCKS5 服务错误: $e');
      });
      _log('SOCKS5 已启动 ${config.listenHost}:${config.listenPort}');
      _setStatus(Suo5Status.running);
    } catch (e) {
      _log('启动失败: $e');
      await stop();
      _setStatus(Suo5Status.error);
    }
  }

  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    for (final t in _tunnels.toList()) {
      await t.close(sendDelete: true);
    }
    _tunnels.clear();
    await _server?.close();
    _server = null;
    _sessionId = '';
    _cookies.clear();
    _currentConfig = null;
    _activeConnections = 0;
    if (_status != Suo5Status.error) {
      _setStatus(Suo5Status.idle);
    }
  }

  void clearLogs() {
    _logs.clear();
    onChanged?.call();
  }

  /// 探测：只跑一次握手，不启动心跳，便于在 UI 上做"测试连通"按钮
  Future<void> probe(Suo5Config config) => _handshake(config, keepAlive: false);

  Future<void> _handshake(Suo5Config config, {bool keepAlive = true}) async {
    final lowerUrl = config.targetUrl.toLowerCase();
    // payload 模式兼容性：
    //   PHP   → 只支持 half/classic，classic 受 nginx 缓冲拦截，强制用 half
    //   ASPX  → 只支持 half/classic，但 classic 用线程池即时返回，推荐 classic
    //   JSP   → 支持 full/half/classic，保留自动探测
    final isPhp = lowerUrl.contains('.php');
    final isAspx = lowerUrl.contains('.aspx');
    final startedAt = DateTime.now();
    final marker = _randomString(24 + Random.secure().nextInt(64));
    // a=0x00 → 经典探测（PHP 立即返回两帧，不 sleep），a=0x01 → 流式探测（PHP sleep 2s）
    final payload = _buildBody(
      {
        'ac': Uint8List.fromList([0x01]),
        'id': utf8.encode(_randomString(8)),
        'dt': utf8.encode(marker),
        'a': Uint8List.fromList([0x00]),
      },
      modeByteOverride: 0x00,
      includeSid: false,
    );
    final bytes = await _post(config.targetUrl, payload);
    final frames = _parseFrames(bytes);
    if (frames.length < 2) {
      throw Exception('握手响应不完整');
    }
    final echo = frames[0]['dt'] ?? Uint8List(0);
    if (utf8.decode(echo, allowMalformed: true) != marker) {
      throw Exception('握手校验失败');
    }
    final sid = utf8.decode(frames[1]['dt'] ?? Uint8List(0), allowMalformed: true);
    if (sid.isEmpty) {
      throw Exception('服务端未返回 sid');
    }
    _sessionId = sid;
    final ms = DateTime.now().difference(startedAt).inMilliseconds;
    final detected = ms < 3000 ? 'full' : (ms < 5000 ? 'half' : 'classic');
    if (isPhp) {
      // PHP 强制 half 模式：X-Accel-Buffering: no 保证响应不被 nginx 缓冲
      _mode = 'half';
      _modeByte = 0x02;
      _log('检测到 PHP payload，使用 half 模式');
    } else if (isAspx) {
      // ASPX 强制 classic 模式：IIS 线程池让响应即时返回，无 nginx 缓冲问题；
      // ASPX 不实现 mode=0x01(full)，避免自动探测误判
      _mode = 'classic';
      _modeByte = 0x03;
      _log('检测到 ASPX payload，使用 classic 模式');
    } else if (detected == 'classic') {
      _mode = 'classic';
      _modeByte = 0x03;
    } else if (detected == 'full') {
      _mode = 'full';
      _modeByte = 0x01;
    } else {
      _mode = 'half';
      _modeByte = 0x02;
    }
    _log('握手成功 sid=$_sessionId detected=$detected latency=${ms}ms');
    if (keepAlive) _startHeartbeat();
  }

  void _handleSocksClientRaw(Socket socket) {
    unawaited(_handleSocketSession(socket));
  }

  Future<void> _handleSocketSession(Socket socket) async {
    final reader = _SocketReader(socket);
    try {
      final hs = await reader.read(2);
      if (hs[0] != 0x05) {
        throw Exception('仅支持 SOCKS5');
      }
      final methods = await reader.read(hs[1]);
      if (!methods.contains(0x00)) {
        socket.add([0x05, 0xFF]);
        await socket.flush();
        return;
      }
      socket.add([0x05, 0x00]);
      await socket.flush();

      final reqHead = await reader.read(4);
      if (reqHead[0] != 0x05 || reqHead[1] != 0x01) {
        socket.add([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
        return;
      }
      final atyp = reqHead[3];
      String host;
      if (atyp == 0x01) {
        final ip = await reader.read(4);
        host = InternetAddress.fromRawAddress(ip).address;
      } else if (atyp == 0x03) {
        final len = (await reader.read(1))[0];
        host = utf8.decode(await reader.read(len), allowMalformed: true);
      } else {
        socket.add([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
        return;
      }
      final p = await reader.read(2);
      final port = (p[0] << 8) | p[1];
      final target = '$host:$port';

      final cfg = _currentConfig;
      if (cfg == null || _sessionId.isEmpty) {
        throw Exception('suo5 未就绪');
      }
      final tunnel = _Suo5Tunnel(
        targetUrl: cfg.targetUrl,
        sessionId: _sessionId,
        modeByte: _modeByte,
        socket: socket,
        post: _post,
        openReceiveStream: _openReceiveStream,
        openFullDuplexChannel: _openFullDuplexChannel,
        buildBody: _buildBody,
        parseFrames: _parseFrames,
        onLog: _log,
        onTraffic: (up, down) {
          _uploadBytes += up;
          _downloadBytes += down;
          onChanged?.call();
        },
      );
      _tunnels.add(tunnel);
      final ok = await tunnel.connect(target);
      if (!ok) {
        socket.add([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
        await tunnel.close(sendDelete: true);
        _tunnels.remove(tunnel);
        return;
      }
      _activeConnections = _tunnels.length;
      onChanged?.call();
      socket.add([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      await socket.flush();
      reader.bind(
        onData: (data) {
          tunnel.feedClientData(data);
        },
        onDone: () async {
          await tunnel.close(sendDelete: true);
        },
        onError: (_) async {
          await tunnel.close(sendDelete: true);
        },
      );
      await tunnel.bridge();
      _tunnels.remove(tunnel);
      _activeConnections = _tunnels.length;
      onChanged?.call();
    } catch (e) {
      _log('SOCKS 会话异常: $e');
    } finally {
      await reader.dispose();
      await socket.close();
    }
  }

  Future<List<int>> _post(String url, List<int> body) async {
    Object? lastErr;
    for (var i = 0; i < 3; i++) {
      try {
        final headers = <String, String>{
          'Content-Type': 'application/octet-stream',
          if (_cookies.isNotEmpty) 'Cookie': _cookieHeader,
        };
        final resp = await _http
            .post(
              Uri.parse(url),
              headers: headers,
              body: body,
            )
            .timeout(const Duration(seconds: 15));
        final setCookie = resp.headers['set-cookie'];
        if (setCookie != null && setCookie.isNotEmpty) {
          _captureCookiesFromSetCookie(setCookie);
        }
        if (resp.statusCode != 200) {
          throw Exception('远端状态码异常 ${resp.statusCode}');
        }
        return resp.bodyBytes;
      } catch (e) {
        lastErr = e;
        if (i < 2) {
          await Future<void>.delayed(Duration(milliseconds: 200 * (i + 1)));
        }
      }
    }
    throw Exception('请求失败(重试3次): $lastErr');
  }

  Future<HttpClientResponse> _openReceiveStream(
    String url,
    List<int> body, {
    void Function(HttpClient)? onClient,
  }) async {
    final uri = Uri.parse(url);
    final client = HttpClient()..badCertificateCallback = (cert, host, port) => true;
    onClient?.call(client);
    final req = await client.postUrl(uri).timeout(const Duration(seconds: 15));
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream');
    req.headers.set('X-Accel-Buffering', 'no');
    if (_cookies.isNotEmpty) {
      req.headers.set(HttpHeaders.cookieHeader, _cookieHeader);
    }
    req.add(body);
    final resp = await req.close();
    for (final c in resp.cookies) {
      if (c.value.isEmpty) continue;
      _cookies[c.name] = c.value;
    }
    if (resp.statusCode != 200) {
      client.close(force: true);
      throw Exception('远端状态码异常 ${resp.statusCode}');
    }
    return resp;
  }

  Future<_FullDuplexChannel> _openFullDuplexChannel(String url, List<int> firstBody) {
    return _FullDuplexChannel.open(
      url,
      firstBody,
      cookieHeader: _cookies.isEmpty ? null : _cookieHeader,
    );
  }

  String get _cookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  void _captureCookiesFromSetCookie(String setCookieHeader) {
    final matches = RegExp(r'(^|,\s*)([^=;,\s]+)=([^;,\s]+)', caseSensitive: false)
        .allMatches(setCookieHeader);
    for (final m in matches) {
      final key = m.group(2);
      final value = m.group(3);
      if (key == null || key.isEmpty || value == null || value.isEmpty) continue;
      _cookies[key] = value;
    }
  }

  List<Map<String, Uint8List>> _parseFrames(List<int> bytes) {
    final out = <Map<String, Uint8List>>[];
    var offset = 0;
    while (offset + 8 <= bytes.length) {
      final headB64 = ascii.decode(bytes.sublist(offset, offset + 8));
      offset += 8;
      final head = base64Url.decode(base64Url.normalize(headB64));
      if (head.length != 6) break;
      final obs0 = head[0];
      final obs1 = head[1];
      final l0 = head[2] ^ obs0;
      final l1 = head[3] ^ obs1;
      final l2 = head[4] ^ obs0;
      final l3 = head[5] ^ obs1;
      final encLen = (l0 << 24) | (l1 << 16) | (l2 << 8) | l3;
      if (encLen < 0 || offset + encLen > bytes.length) break;
      final encData = ascii.decode(bytes.sublist(offset, offset + encLen));
      offset += encLen;
      final raw = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(encData)),
      );
      for (var i = 0; i < raw.length; i++) {
        raw[i] = raw[i] ^ (i.isEven ? obs0 : obs1);
      }
      out.add(_unmarshal(raw));
    }
    return out;
  }

  List<int> _buildBody(
    Map<String, List<int>> data, {
    int? modeByteOverride,
    bool includeSid = true,
  }) {
    final m = <String, List<int>>{
      ...data,
      'm': [modeByteOverride ?? _modeByte],
      '_': _randBytes(8 + Random.secure().nextInt(24)),
    };
    if (includeSid && _sessionId.isNotEmpty) {
      m['sid'] = utf8.encode(_sessionId);
    }
    final payload = _marshal(m);
    final obs = _randBytes(2);
    final xoredData = Uint8List.fromList(payload);
    for (var i = 0; i < xoredData.length; i++) {
      xoredData[i] ^= obs[i % 2];
    }
    final dataB64 = ascii.encode(base64UrlEncode(xoredData).replaceAll('=', ''));
    final lenBytes = ByteData(4)..setUint32(0, dataB64.length, Endian.big);
    final xoredLen = Uint8List(4);
    for (var i = 0; i < 4; i++) {
      xoredLen[i] = lenBytes.getUint8(i) ^ obs[i % 2];
    }
    final header = Uint8List.fromList([...obs, ...xoredLen]);
    final headerB64 = ascii.encode(
      base64UrlEncode(header).replaceAll('=', ''),
    );
    return [...headerB64, ...dataB64];
  }

  Uint8List _marshal(Map<String, List<int>> m) {
    final out = BytesBuilder(copy: false);
    m.forEach((k, v) {
      out.add([k.length]);
      out.add(utf8.encode(k));
      final len = ByteData(4)..setUint32(0, v.length, Endian.big);
      out.add(len.buffer.asUint8List());
      out.add(v);
    });
    return out.toBytes();
  }

  Map<String, Uint8List> _unmarshal(Uint8List bytes) {
    final out = <String, Uint8List>{};
    var i = 0;
    while (i + 1 < bytes.length) {
      final kLen = bytes[i];
      i += 1;
      if (i + kLen + 4 > bytes.length) break;
      final key = utf8.decode(bytes.sublist(i, i + kLen), allowMalformed: true);
      i += kLen;
      final vLen = ByteData.sublistView(bytes, i, i + 4).getUint32(0, Endian.big);
      i += 4;
      if (i + vLen > bytes.length) break;
      out[key] = Uint8List.fromList(bytes.sublist(i, i + vLen));
      i += vLen;
    }
    return out;
  }

  List<int> _randBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  String _randomString(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  void _setStatus(Suo5Status s) {
    _status = s;
    onChanged?.call();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    if (_sessionId.isEmpty) return;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_status != Suo5Status.running || _sessionId.isEmpty) return;
      final cfg = _currentConfig;
      if (cfg == null) return;
      try {
        await _post(
          cfg.targetUrl,
          _buildBody({
            'ac': [0x10],
            'id': utf8.encode(_randomString(8)),
          }),
        );
      } catch (_) {
        // best effort
      }
    });
  }

  void _log(String msg) {
    final t = DateTime.now();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    _logs.add('[$hh:$mm:$ss] $msg');
    if (_logs.length > 500) _logs.removeRange(0, _logs.length - 500);
    onLog?.call(t, msg);
    onChanged?.call();
  }

  /// 关闭并释放 http 客户端；用于会话被从管理器中移除时
  Future<void> dispose() async {
    await stop();
    _http.close();
  }
}

// ─── 多会话管理器（替代旧的单例隧道） ─────────────────────────────────────────

class _Suo5AggLog {
  const _Suo5AggLog(this.when, this.label, this.message);
  final DateTime when;
  final String label;
  final String message;

  String format() {
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    final ss = when.second.toString().padLeft(2, '0');
    if (label.isEmpty) return '[$hh:$mm:$ss] $message';
    return '[$hh:$mm:$ss] [$label] $message';
  }
}

/// 多会话管理：按 profileId 维护若干 [Suo5Session]，可同时启动多条 suo5 隧道
class Suo5ClientService {
  Suo5ClientService._internal();
  static final Suo5ClientService _instance = Suo5ClientService._internal();
  factory Suo5ClientService() => _instance;

  final Map<int, Suo5Session> _sessions = {};
  final List<_Suo5AggLog> _aggLog = [];

  /// 任一会话状态/流量/日志变化时触发
  void Function()? onChanged;

  /// 当前注册过的所有会话；只读视图
  Map<int, Suo5Session> get sessions => Map.unmodifiable(_sessions);

  /// 按 profile 取出（不存在则不创建）
  Suo5Session? sessionFor(int profileId) => _sessions[profileId];

  Suo5Session _ensureSession(int profileId, {String label = ''}) {
    final existing = _sessions[profileId];
    if (existing != null) {
      if (label.isNotEmpty && existing.label != label) existing.label = label;
      return existing;
    }
    final s = Suo5Session(label: label)
      ..onChanged = _emit
      ..onLog = (when, msg) => _appendAggLog(when, label, msg);
    _sessions[profileId] = s;
    // 标签后续可能改变，确保 onLog 拿到最新 label
    s.onLog = (when, msg) => _appendAggLog(when, s.label, msg);
    return s;
  }

  /// 启动指定 profile 的隧道；若已有同 id 会话先停旧的（避免重复绑定本地端口）
  Future<void> startProfile(
    int profileId,
    Suo5Config config, {
    String label = '',
  }) async {
    final s = _ensureSession(profileId, label: label);
    if (s.status == Suo5Status.running || s.status == Suo5Status.connecting) {
      await s.stop();
    }
    await s.start(config);
  }

  Future<void> stopProfile(int profileId) async {
    final s = _sessions[profileId];
    if (s == null) return;
    await s.stop();
    _emit();
  }

  /// 探测：使用临时 session，不污染管理器，也不会启动心跳
  Future<void> probe(Suo5Config config, {String label = ''}) async {
    final temp = Suo5Session(label: label);
    temp.onLog = (when, msg) => _appendAggLog(when, label, msg);
    // 与常驻会话一致：[_log] 末尾会调 onChanged；临时会话若不接 _emit，聚合日志已写入但 UI 不刷新
    temp.onChanged = _emit;
    try {
      await temp.probe(config);
    } finally {
      await temp.dispose();
    }
  }

  /// 移除某条 profile 的会话（先停止再丢弃），用于删除 profile 时清理
  Future<void> removeProfile(int profileId) async {
    final s = _sessions.remove(profileId);
    if (s == null) return;
    await s.dispose();
    _emit();
  }

  bool isRunning(int profileId) {
    final s = _sessions[profileId];
    return s != null &&
        (s.status == Suo5Status.running || s.status == Suo5Status.connecting);
  }

  int get runningCount => _sessions.values
      .where((s) => s.status == Suo5Status.running)
      .length;
  int get connectingCount => _sessions.values
      .where((s) => s.status == Suo5Status.connecting)
      .length;
  int get totalActiveConnections =>
      _sessions.values.fold(0, (a, s) => a + s.activeConnections);
  int get totalUploadBytes =>
      _sessions.values.fold(0, (a, s) => a + s.uploadBytes);
  int get totalDownloadBytes =>
      _sessions.values.fold(0, (a, s) => a + s.downloadBytes);

  List<String> get aggregatedLogs =>
      _aggLog.map((e) => e.format()).toList(growable: false);

  void clearAllLogs() {
    _aggLog.clear();
    for (final s in _sessions.values) {
      s._logs.clear();
    }
    _emit();
  }

  void _appendAggLog(DateTime when, String label, String msg) {
    _aggLog.add(_Suo5AggLog(when, label, msg));
    if (_aggLog.length > 1000) {
      _aggLog.removeRange(0, _aggLog.length - 1000);
    }
  }

  void _emit() => onChanged?.call();
}

class _SocketReader {
  _SocketReader(this.socket) {
    _sub = socket.listen((chunk) {
      if (_onData != null) {
        _onData!(Uint8List.fromList(chunk));
      } else {
        _buffer.addAll(chunk);
        _waiter?.complete();
        _waiter = null;
      }
    }, onError: (Object e) {
      if (_onError != null) {
        unawaited(_onError!(e));
      }
      _error = e;
      _waiter?.complete();
      _waiter = null;
    }, onDone: () {
      if (_onDone != null) {
        unawaited(_onDone!());
      }
      _done = true;
      _waiter?.complete();
      _waiter = null;
    }, cancelOnError: true);
  }

  final Socket socket;
  late final StreamSubscription<List<int>> _sub;
  final List<int> _buffer = [];
  bool _done = false;
  Object? _error;
  Completer<void>? _waiter;
  void Function(Uint8List data)? _onData;
  Future<void> Function()? _onDone;
  Future<void> Function(Object err)? _onError;

  Future<Uint8List> read(int n) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (_buffer.length < n) {
      if (_error != null) throw _error!;
      if (_done) throw Exception('socket closed');
      final now = DateTime.now();
      if (now.isAfter(deadline)) {
        throw TimeoutException('socket read timeout');
      }
      _waiter ??= Completer<void>();
      final remain = deadline.difference(now);
      await _waiter!.future.timeout(remain);
    }
    final out = Uint8List.fromList(_buffer.sublist(0, n));
    _buffer.removeRange(0, n);
    return out;
  }

  Future<void> dispose() async {
    await _sub.cancel();
  }

  void bind({
    required void Function(Uint8List data) onData,
    required Future<void> Function() onDone,
    required Future<void> Function(Object err) onError,
  }) {
    _onData = onData;
    _onDone = onDone;
    _onError = onError;
    if (_buffer.isNotEmpty) {
      final pending = Uint8List.fromList(_buffer);
      _buffer.clear();
      _onData!(pending);
    }
  }
}

class _FrameStreamParser {
  final List<int> _buf = [];

  List<Map<String, Uint8List>> feed(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <Map<String, Uint8List>>[];
    while (_buf.length >= 8) {
      final headB64 = ascii.decode(_buf.sublist(0, 8), allowInvalid: true);
      Uint8List head;
      try {
        head = Uint8List.fromList(base64Url.decode(base64Url.normalize(headB64)));
      } catch (_) {
        break;
      }
      if (head.length != 6) break;
      final obs0 = head[0];
      final obs1 = head[1];
      final l0 = head[2] ^ obs0;
      final l1 = head[3] ^ obs1;
      final l2 = head[4] ^ obs0;
      final l3 = head[5] ^ obs1;
      final encLen = (l0 << 24) | (l1 << 16) | (l2 << 8) | l3;
      if (_buf.length < 8 + encLen) break;
      final encData = ascii.decode(
        _buf.sublist(8, 8 + encLen),
        allowInvalid: true,
      );
      Uint8List raw;
      try {
        raw = Uint8List.fromList(base64Url.decode(base64Url.normalize(encData)));
      } catch (_) {
        break;
      }
      for (var i = 0; i < raw.length; i++) {
        raw[i] = raw[i] ^ (i.isEven ? obs0 : obs1);
      }
      out.add(_unmarshalLocal(raw));
      _buf.removeRange(0, 8 + encLen);
    }
    return out;
  }

  Map<String, Uint8List> _unmarshalLocal(Uint8List bytes) {
    final out = <String, Uint8List>{};
    var i = 0;
    while (i + 1 < bytes.length) {
      final kLen = bytes[i];
      i += 1;
      if (i + kLen + 4 > bytes.length) break;
      final key = utf8.decode(bytes.sublist(i, i + kLen), allowMalformed: true);
      i += kLen;
      final vLen = ByteData.sublistView(bytes, i, i + 4).getUint32(0, Endian.big);
      i += 4;
      if (i + vLen > bytes.length) break;
      out[key] = Uint8List.fromList(bytes.sublist(i, i + vLen));
      i += vLen;
    }
    return out;
  }
}

class _FullDuplexChannel {
  _FullDuplexChannel._(this._socket, this._bodyStreamController);

  final Socket _socket;
  final StreamController<List<int>> _bodyStreamController;
  final List<int> _headerBuf = [];
  final _ChunkedBodyDecoder _chunkedDecoder = _ChunkedBodyDecoder();
  StreamSubscription<List<int>>? _sub;
  Future<void> _writeQueue = Future<void>.value();
  bool _headerDone = false;
  bool _isChunked = true;
  bool _closed = false;

  Stream<List<int>> get bodyStream => _bodyStreamController.stream;

  static Future<_FullDuplexChannel> open(
    String url,
    List<int> firstBody, {
    String? cookieHeader,
  }) async {
    final uri = Uri.parse(url);
    final host = uri.host;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final path = uri.path.isEmpty ? '/' : uri.path;
    final fullPath = uri.hasQuery ? '$path?${uri.query}' : path;

    late Socket socket;
    if (uri.scheme == 'https') {
      socket = await SecureSocket.connect(
        host,
        port,
        onBadCertificate: (_) => true,
        timeout: const Duration(seconds: 15),
      );
    } else {
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 15));
    }
    socket.setOption(SocketOption.tcpNoDelay, true);

    final bodyCtrl = StreamController<List<int>>.broadcast();
    final ch = _FullDuplexChannel._(socket, bodyCtrl);
    ch._sub = socket.listen(
      ch._onData,
      onDone: () {
        if (!bodyCtrl.isClosed) bodyCtrl.close();
      },
      onError: (Object _) {
        if (!bodyCtrl.isClosed) bodyCtrl.close();
      },
      cancelOnError: true,
    );

    final headers = StringBuffer()
      ..write('POST $fullPath HTTP/1.1\r\n')
      ..write('Host: $host:$port\r\n')
      ..write('User-Agent: DartSuo5/1.0\r\n')
      ..write('Accept: */*\r\n')
      ..write('Connection: keep-alive\r\n')
      ..write('Content-Type: application/octet-stream\r\n')
      ..write(cookieHeader != null ? 'Cookie: $cookieHeader\r\n' : '')
      ..write('Transfer-Encoding: chunked\r\n')
      ..write('\r\n');
    socket.add(ascii.encode(headers.toString()));
    await socket.flush();
    await ch.send(firstBody);
    return ch;
  }

  void _onData(List<int> chunk) {
    if (_closed) return;
    if (!_headerDone) {
      _headerBuf.addAll(chunk);
      final idx = _findHeaderEnd(_headerBuf);
      if (idx < 0) return;
      final headerRaw = ascii.decode(_headerBuf.sublist(0, idx), allowInvalid: true);
      final lines = headerRaw.split('\r\n');
      if (lines.isNotEmpty && !lines.first.contains(' 200 ')) {
        if (!_bodyStreamController.isClosed) _bodyStreamController.close();
        _closed = true;
        return;
      }
      _isChunked = headerRaw.toLowerCase().contains('transfer-encoding: chunked');
      _headerDone = true;
      final rest = _headerBuf.sublist(idx + 4);
      _headerBuf.clear();
      if (rest.isNotEmpty) {
        _feedBody(rest);
      }
      return;
    }
    _feedBody(chunk);
  }

  void _feedBody(List<int> chunk) {
    if (_isChunked) {
      final outs = _chunkedDecoder.feed(chunk);
      for (final o in outs) {
        _bodyStreamController.add(o);
      }
    } else {
      _bodyStreamController.add(chunk);
    }
  }

  Future<void> send(List<int> body) {
    if (_closed) return Future.value();
    _writeQueue = _writeQueue.then((_) async {
      if (_closed) return;
      final line = '${body.length.toRadixString(16)}\r\n';
      _socket.add(ascii.encode(line));
      _socket.add(body);
      _socket.add(const [13, 10]); // \r\n
      await _socket.flush();
    });
    return _writeQueue;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _socket.add(ascii.encode('0\r\n\r\n'));
      await _socket.flush();
    } catch (_) {}
    await _sub?.cancel();
    await _socket.close();
    await _bodyStreamController.close();
  }

  static int _findHeaderEnd(List<int> b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }
}

class _ChunkedBodyDecoder {
  final List<int> _buf = [];
  int? _need;
  bool _done = false;

  List<Uint8List> feed(List<int> data) {
    if (_done) return const [];
    _buf.addAll(data);
    final out = <Uint8List>[];
    while (true) {
      if (_need == null) {
        final lineEnd = _findCrlf(_buf, 0);
        if (lineEnd < 0) break;
        final line = ascii.decode(_buf.sublist(0, lineEnd), allowInvalid: true);
        final hex = line.split(';').first.trim();
        final n = int.tryParse(hex, radix: 16);
        if (n == null) break;
        _buf.removeRange(0, lineEnd + 2);
        _need = n;
        if (n == 0) {
          _done = true;
          break;
        }
      }
      final n = _need!;
      if (_buf.length < n + 2) break;
      out.add(Uint8List.fromList(_buf.sublist(0, n)));
      _buf.removeRange(0, n + 2); // data + \r\n
      _need = null;
    }
    return out;
  }

  static int _findCrlf(List<int> b, int start) {
    for (var i = start; i + 1 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10) return i;
    }
    return -1;
  }
}

class _Suo5Tunnel {
  _Suo5Tunnel({
    required this.targetUrl,
    required this.sessionId,
    required this.modeByte,
    required this.socket,
    required this.post,
    required this.openReceiveStream,
    required this.openFullDuplexChannel,
    required this.buildBody,
    required this.parseFrames,
    required this.onLog,
    required this.onTraffic,
  });

  final String targetUrl;
  final String sessionId;
  final int modeByte;
  final Socket socket;
  final Future<List<int>> Function(String url, List<int> body) post;
  final Future<HttpClientResponse> Function(
          String url, List<int> body, {void Function(HttpClient)? onClient})
      openReceiveStream;
  final Future<_FullDuplexChannel> Function(String url, List<int> firstBody)
      openFullDuplexChannel;
  final List<int> Function(Map<String, List<int>> body) buildBody;
  final List<Map<String, Uint8List>> Function(List<int> bytes) parseFrames;
  final void Function(String msg) onLog;
  final void Function(int up, int down) onTraffic;

  final String id = _shortId();
  bool _closed = false;
  Timer? _pollTimer;
  Future<void> _queue = Future<void>.value();
  StreamSubscription<List<int>>? _recvSub;
  HttpClient? _recvHttpClient;
  final _frameParser = _FrameStreamParser();
  _FullDuplexChannel? _fullChannel;

  Future<bool> connect(String address) async {
    final pos = address.lastIndexOf(':');
    if (pos <= 0) return false;
    final host = address.substring(0, pos);
    final port = int.tryParse(address.substring(pos + 1)) ?? 0;
    if (port <= 0 || port > 65535) return false;
    final body = buildBody({
      'ac': [0x00],
      'id': utf8.encode(id),
      'h': utf8.encode(host),
      'p': utf8.encode(port.toString()),
    });
    try {
      if (modeByte == 0x03) {
        final resp = await post(targetUrl, body);
        final frames = parseFrames(resp);
        for (final f in frames) {
          final ac = f['ac'];
          if (ac != null && ac.isNotEmpty && ac[0] == 0x03) {
            final s = f['s'];
            if (s != null && s.isNotEmpty && s[0] == 0x00) {
              if (_closed) return false;
              onLog('隧道建立成功 id=$id -> $address');
              return true;
            }
          }
        }
        return false;
      }

      if (modeByte == 0x01) {
        final ch = await openFullDuplexChannel(targetUrl, body);
        _fullChannel = ch;
        final ready = Completer<bool>();
        _recvSub = ch.bodyStream.listen((chunk) {
          final frames = _frameParser.feed(chunk);
          for (final f in frames) {
            final ac = f['ac'];
            if (ac != null && ac.isNotEmpty && ac[0] == 0x03 && !ready.isCompleted) {
              final s = f['s'];
              ready.complete(s != null && s.isNotEmpty && s[0] == 0x00);
              continue;
            }
            _handleFrame(f);
          }
        }, onDone: () async {
          if (!ready.isCompleted) ready.complete(false);
          await close(sendDelete: false);
        }, onError: (_) async {
          if (!ready.isCompleted) ready.complete(false);
          await close(sendDelete: true);
        }, cancelOnError: true);
        final connected = await ready.future.timeout(const Duration(seconds: 15));
        if (!connected || _closed) return false;
        onLog('隧道建立成功 id=$id -> $address');
        return true;
      }

      final resp = await openReceiveStream(targetUrl, body, onClient: (c) => _recvHttpClient = c);
      final ready = Completer<bool>();
      _recvSub = resp.listen((chunk) {
        final frames = _frameParser.feed(chunk);
        for (final f in frames) {
          final ac = f['ac'];
          if (ac != null && ac.isNotEmpty && ac[0] == 0x03 && !ready.isCompleted) {
            final s = f['s'];
            ready.complete(s != null && s.isNotEmpty && s[0] == 0x00);
            continue;
          }
          _handleFrame(f);
        }
      }, onDone: () async {
        if (!ready.isCompleted) ready.complete(false);
        await close(sendDelete: false);
      }, onError: (_) async {
        if (!ready.isCompleted) ready.complete(false);
        await close(sendDelete: true);
      }, cancelOnError: true);
      final connected = await ready.future.timeout(const Duration(seconds: 15));
      if (!connected || _closed) return false;
      onLog('隧道建立成功 id=$id -> $address');
      return true;
    } catch (e) {
      onLog('隧道建立失败 id=$id err=$e');
    }
    return false;
  }

  void _handleFrame(Map<String, Uint8List> f) {
    final ac = f['ac'];
    if (ac == null || ac.isEmpty) return;
    if (ac[0] == 0x01) {
      final data = f['dt'] ?? Uint8List(0);
      if (data.isNotEmpty && !_closed) {
        socket.add(data);
        onTraffic(0, data.length);
      }
    } else if (ac[0] == 0x02) {
      unawaited(close(sendDelete: false));
    }
  }

  Future<void> bridge() async {
    if (modeByte == 0x03) {
      _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        _enqueueSend(Uint8List(0));
      });
    }
    while (!_closed) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  void feedClientData(Uint8List data) {
    _enqueueSend(data);
  }

  Future<void> close({required bool sendDelete}) async {
    if (_closed) return;
    _closed = true;
    _pollTimer?.cancel();
    await _recvSub?.cancel();
    _recvSub = null;
    _recvHttpClient?.close(force: true);
    _recvHttpClient = null;
    final fullCh = _fullChannel;
    if (sendDelete) {
      try {
        final delBody = buildBody({
          'ac': [0x02],
          'id': utf8.encode(id),
        });
        if (modeByte == 0x01 && fullCh != null) {
          await fullCh.send(delBody);
        } else {
          await post(targetUrl, delBody);
        }
      } catch (_) {}
    }
    await _fullChannel?.close();
    _fullChannel = null;
  }

  void _enqueueSend(Uint8List payload) {
    if (_closed) return;
    _queue = _queue.then((_) => _send(payload)).catchError((_) {});
  }

  Future<void> _send(Uint8List payload) async {
    if (_closed) return;
    final body = buildBody({
      'ac': [0x01],
      'id': utf8.encode(id),
      'dt': payload,
    });
    try {
      if (payload.isNotEmpty) {
        onTraffic(payload.length, 0);
      }
      if (modeByte == 0x01) {
        final ch = _fullChannel;
        if (ch == null) throw Exception('full channel not ready');
        await ch.send(body);
      } else {
        final resp = await post(targetUrl, body);
        if (modeByte == 0x03) {
          final frames = parseFrames(resp);
          for (final f in frames) {
            final ac = f['ac'];
            if (ac == null || ac.isEmpty) continue;
            if (ac[0] == 0x01) {
              final data = f['dt'] ?? Uint8List(0);
              if (data.isNotEmpty) {
                socket.add(data);
                await socket.flush();
                onTraffic(0, data.length);
              }
            } else if (ac[0] == 0x02) {
              await close(sendDelete: false);
              break;
            }
          }
        }
      }
    } catch (e) {
      onLog('隧道发送失败 id=$id err=$e');
      await close(sendDelete: true);
    }
  }

  static String _shortId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
