import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// ─── Status ──────────────────────────────────────────────────────────────────

enum Suo6Status { idle, connecting, running, error }

class Suo6Config {
  const Suo6Config({
    required this.targetUrl,
    this.listenHost = '127.0.0.1',
    this.listenPort = 1080,
  });
  final String targetUrl;
  final String listenHost;
  final int listenPort;
}

// ─── Protocol constants ───────────────────────────────────────────────────────

const _tOpen    = 0x01;
const _tOpenAck = 0x02;
const _tData    = 0x03;
const _tFin     = 0x04;
const _tPing    = 0x05;

const _magic = [0x53, 0x36, 0x00, 0x01];

final _suo6Http200 = RegExp(r'HTTP/\d\.\d\s+200\b');

/// 上游 HTTP 响应体的传输方式（反代可能把 chunked 转成 Content-Length）。
enum _Suo6InboundTransport { chunked, contentLength, raw }

class _Suo6InboundParse {
  const _Suo6InboundParse({
    required this.transport,
    this.contentLengthRemaining = 0,
    this.unsupportedContentEncoding = false,
  });
  final _Suo6InboundTransport transport;
  final int contentLengthRemaining;
  final bool unsupportedContentEncoding;

  static _Suo6InboundParse fromHeaders(String headerRaw) {
    var teChunked = false;
    var badEnc = false;
    int? cl;
    for (final line in headerRaw.split('\r\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final name = line.substring(0, colon).trim().toLowerCase();
      final val = line.substring(colon + 1).trim();
      if (name == 'transfer-encoding') {
        for (final p in val.split(',')) {
          if (p.trim().toLowerCase() == 'chunked') teChunked = true;
        }
      } else if (name == 'content-length') {
        cl ??= int.tryParse(val.split(';').first.split(',').first.trim());
      } else if (name == 'content-encoding') {
        final v = val.toLowerCase();
        if (v != 'identity' &&
            v.isNotEmpty &&
            (v.contains('gzip') || v.contains('deflate') || v.contains('compress'))) {
          badEnc = true;
        }
      }
    }
    if (badEnc) {
      return const _Suo6InboundParse(
        transport: _Suo6InboundTransport.raw,
        unsupportedContentEncoding: true,
      );
    }
    if (teChunked) {
      return const _Suo6InboundParse(transport: _Suo6InboundTransport.chunked);
    }
    if (cl != null && cl >= 0) {
      return _Suo6InboundParse(
        transport: _Suo6InboundTransport.contentLength,
        contentLengthRemaining: cl,
      );
    }
    return const _Suo6InboundParse(transport: _Suo6InboundTransport.raw);
  }
}

/// 与 [zema1/suo5](https://github.com/zema1/suo5) 默认行为对齐：显式禁用压缩，避免反代对
/// `application/octet-stream` 仍做 gzip，导致 chunked 体不是原始二进制协议流。
/// UA 使用常见桌面 Chrome，降低 WAF/网关对「脚本客户端」的拦截概率。
const _kSuo6UserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

String _suo6HostHeaderValue(String host, int port, String scheme) {
  if (scheme == 'https' && port == 443) return host;
  if (scheme == 'http' && port == 80) return host;
  return '$host:$port';
}

// ─── Suo6Session ─────────────────────────────────────────────────────────────

/// One suo6 session: one persistent HTTP connection carrying all SOCKS streams.
class Suo6Session {
  Suo6Session({this.label = ''});

  String label;

  Suo6Status _status = Suo6Status.idle;
  Suo6Status get status => _status;

  int _activeConnections = 0;
  int get activeConnections => _activeConnections;
  int _uploadBytes   = 0;
  int get uploadBytes   => _uploadBytes;
  int _downloadBytes = 0;
  int get downloadBytes => _downloadBytes;

  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);

  void Function()? onChanged;
  void Function(DateTime, String)? onLog;

  ServerSocket? _server;
  Suo6Config?   _config;
  Suo6Config?   get currentConfig => _config;

  // ── Multiplexed channel state ─────────────────────────────────────────────
  _Suo6Channel? _channel;
  final _rng = Random.secure();
  Timer? _uiThrottle;
  Timer? _pingTimer;

  // ── Start / stop ──────────────────────────────────────────────────────────

  Future<void> start(Suo6Config config) async {
    if (_status == Suo6Status.connecting || _status == Suo6Status.running) return;
    _setStatus(Suo6Status.connecting);
    _logs.clear();
    _config = config;
    _uploadBytes = _downloadBytes = _activeConnections = 0;
    try {
      await _openChannel(config);
      _server = await ServerSocket.bind(config.listenHost, config.listenPort);
      _server!.listen(_handleSocksClientRaw, onError: (Object e, _) {
        _log('SOCKS5 服务错误: $e');
      });
      _log('SOCKS5 已启动 ${config.listenHost}:${config.listenPort}');
      _setStatus(Suo6Status.running);
    } catch (e) {
      _log('启动失败: $e');
      await stop();
      _setStatus(Suo6Status.error);
    }
  }

  Future<void> stop() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    _uiThrottle?.cancel();
    _uiThrottle = null;
    await _channel?.close();
    _channel = null;
    await _server?.close();
    _server = null;
    _config = null;
    _activeConnections = 0;
    if (_status != Suo6Status.error) _setStatus(Suo6Status.idle);
  }

  void clearLogs() {
    _logs.clear();
    onChanged?.call();
  }

  // ── Channel open + handshake ──────────────────────────────────────────────

  /// 仅完成 HTTP 体握手（密钥协商），不启 SOCKS、不启 ping；用于「测试握手」。
  Future<void> probe(Suo6Config config) async {
    try {
      await _openChannel(config, keepAlive: false);
    } finally {
      await stop();
    }
  }

  Future<void> _openChannel(Suo6Config config, {bool keepAlive = true}) async {
    final channelOpenStarted = DateTime.now();
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
      }
      final clientSeed = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        clientSeed[i] = _rng.nextInt(256);
      }
      final firstBody = Uint8List(20);
      firstBody.setRange(0, 4, _magic);
      firstBody.setRange(4, 20, clientSeed);

      _Suo6Channel? ch;
      try {
        ch = await _Suo6Channel.open(config.targetUrl, firstBody);
        final ack = await ch.readExact(20);
        if (ack[0] != 0x53 ||
            ack[1] != 0x36 ||
            ack[2] != 0x00 ||
            ack[3] != 0x01) {
          throw Exception('suo6 bad handshake magic');
        }
        final serverSeed = ack.sublist(4, 20);
        final key = Uint8List(16);
        for (var i = 0; i < 16; i++) {
          key[i] = clientSeed[i] ^ serverSeed[i];
        }
        ch.setKey(key);
        _channel = ch;
        ch = null;

        if (keepAlive) {
          _pingTimer?.cancel();
          _pingTimer = Timer.periodic(const Duration(seconds: 12), (_) {
            _channel?.sendFrame(0, _tPing, const []);
          });
          _channel!.onFrame = _handleServerFrame;
        }

        _channel!.onClose = () {
          _log('通道已关闭');
          if (_status == Suo6Status.running) {
            _setStatus(Suo6Status.error);
          }
        };

        final openMs =
            DateTime.now().difference(channelOpenStarted).inMilliseconds;
        _log(keepAlive
            ? 'suo6 通道已建立 latency=${openMs}ms'
            : '握手成功 latency=${openMs}ms');
        return;
      } catch (e, st) {
        if (ch != null) {
          try {
            await ch.close();
          } catch (_) {}
        }
        if (attempt == 2) {
          _log('suo6 建立通道失败（已重试 3 次）: $e');
          Error.throwWithStackTrace(e, st);
        } else {
          _log('suo6 建立通道重试 ${attempt + 1}/3: $e');
        }
      }
    }
  }

  // ── SOCKS5 acceptance ─────────────────────────────────────────────────────

  void _handleSocksClientRaw(Socket socket) {
    unawaited(_handleSocksSession(socket));
  }

  Future<void> _handleSocksSession(Socket socket) async {
    final reader = _SockReader(socket);
    String? target;
    int? streamId;
    _Suo6Channel? ch;
    try {
      final hs = await reader.read(2);
      if (hs[0] != 0x05) throw Exception('SOCKS5 only');
      await reader.read(hs[1]); // skip auth methods — we always reply "no auth"
      socket.add([0x05, 0x00]);
      await socket.flush();

      final req = await reader.read(4);
      if (req[0] != 0x05 || req[1] != 0x01) {
        socket.add([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
        return;
      }

      final atyp = req[3];
      String host;
      if (atyp == 0x01) {
        final ip = await reader.read(4);
        host = InternetAddress.fromRawAddress(ip).address;
      } else if (atyp == 0x03) {
        final len = (await reader.read(1))[0];
        host = utf8.decode(await reader.read(len));
      } else if (atyp == 0x04) {
        final ip = await reader.read(16);
        host = '[${InternetAddress.fromRawAddress(ip, type: InternetAddressType.IPv6).address}]';
      } else {
        socket.add([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
        return;
      }
      final p = await reader.read(2);
      final port = (p[0] << 8) | p[1];
      target = '$host:$port';

      ch = _channel;
      if (ch == null || ch.isClosed) {
        _log('SOCKS 通道不可用，拒绝 $target');
        socket.add([0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
        return;
      }

      // Open stream
      streamId = ch.allocateStreamId();
      final stream = _Suo6Stream(streamId, socket, ch);
      ch.registerStream(streamId, stream);
      _log('隧道建立中 id=$streamId -> $target');

      // OPEN frame: port(2B) + host(utf8)
      final hostBytes = utf8.encode(host);
      final openPayload = Uint8List(2 + hostBytes.length);
      openPayload[0] = (port >> 8) & 0xff;
      openPayload[1] = port & 0xff;
      openPayload.setRange(2, openPayload.length, hostBytes);
      ch.sendFrame(streamId, _tOpen, openPayload);

      // Wait for OPEN_ACK (15 s timeout → false)
      final ok = await stream.waitForAck;
      if (!ok) {
        _log('隧道建立失败 id=$streamId -> $target（超时或失败）');
        socket.add([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
        return;
      }
      _log('隧道建立成功 id=$streamId -> $target');

      socket.add([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      await socket.flush();
      _activeConnections++;
      _scheduleUiUpdate();

      // Pipe: socket -> channel
      reader.bind(
        onData: (data) {
          _uploadBytes += data.length;
          _scheduleUiUpdate();
          ch!.sendFrame(streamId!, _tData, data);
        },
        onDone: () async {
          ch!.sendFrame(streamId!, _tFin, const []);
          stream.deliverFin(); // completes _doneCompleter, unblocks await below
        },
        onError: (_) async {
          ch!.sendFrame(streamId!, _tFin, const []);
          stream.deliverFin(); // completes _doneCompleter, unblocks await below
        },
      );

      await stream.done;
    } catch (e) {
      if (!_isBenignSocksClose(e)) {
        _log(target == null ? 'SOCKS 会话异常: $e' : 'SOCKS 会话异常 $target: $e');
      }
    } finally {
      _activeConnections = (_activeConnections - 1).clamp(0, 1 << 30);
      _scheduleUiUpdate();
      // 确保 stream 从 channel 中移除（deliverFin 也会移除，双重调用无害）。
      if (streamId != null) ch?.unregisterStream(streamId);
      // 先取消 socket 上的 StreamSubscription，再 close 才不会抛
      // "StreamSink is bound to a stream"。
      try { await reader.dispose(); } catch (_) {}
      try { await socket.close(); } catch (_) {}
    }
  }

  bool _isBenignSocksClose(Object e) {
    if (e is TimeoutException) return true;
    final msg = e.toString().toLowerCase();
    return msg.contains('socket closed') ||
        msg.contains('broken pipe') ||
        msg.contains('connection reset') ||
        msg.contains('connection aborted');
  }

  // ── Incoming frame routing ────────────────────────────────────────────────

  void _handleServerFrame(int streamId, int typ, Uint8List payload) {
    if (typ == _tPing) return; // keepalive, no reply needed
    final stream = _channel?.getStream(streamId);
    if (stream == null) return;
    switch (typ) {
      case _tOpenAck:
        stream.deliverAck(payload.isNotEmpty && payload[0] == 0x00);
        break;
      case _tData:
        _downloadBytes += payload.length;
        _scheduleUiUpdate();
        stream.deliverData(payload);
        break;
      case _tFin:
        stream.deliverFin();
        break;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _scheduleUiUpdate() {
    _uiThrottle ??= Timer(const Duration(milliseconds: 16), () {
      _uiThrottle = null;
      onChanged?.call();
    });
  }

  void _setStatus(Suo6Status s) {
    _status = s;
    onChanged?.call();
  }

  void _log(String msg) {
    final t = DateTime.now();
    final ts = '${t.hour.toString().padLeft(2,'0')}:'
               '${t.minute.toString().padLeft(2,'0')}:'
               '${t.second.toString().padLeft(2,'0')}';
    _logs.add('[$ts] $msg');
    if (_logs.length > 500) _logs.removeRange(0, _logs.length - 500);
    onLog?.call(t, msg);
    onChanged?.call();
  }

  Future<void> dispose() async => stop();
}

// ─── Per-stream state ─────────────────────────────────────────────────────────

class _Suo6Stream {
  _Suo6Stream(this.streamId, this.socket, this._ch);

  final int          streamId;
  final Socket       socket;
  final _Suo6Channel _ch;
  bool _closed = false;

  final _ackCompleter  = Completer<bool>();
  final _doneCompleter = Completer<void>();

  Future<bool>  get waitForAck => _ackCompleter.future
      .timeout(const Duration(seconds: 15), onTimeout: () => false);
  Future<void>  get done => _doneCompleter.future;

  void deliverAck(bool ok) {
    if (!_ackCompleter.isCompleted) _ackCompleter.complete(ok);
    if (!ok && !_doneCompleter.isCompleted) _doneCompleter.complete();
  }

  void deliverData(Uint8List data) {
    if (_closed) return;
    try {
      socket.add(data);
    } catch (_) {
      deliverFin();
    }
  }

  void deliverFin() {
    if (_closed) return;
    _closed = true;
    _ch.unregisterStream(streamId);
    if (!_ackCompleter.isCompleted) _ackCompleter.complete(false);
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
    // 不在此处关闭 socket：socket 由 _handleSocksSession 的 finally 块
    // 在 reader.dispose() 取消订阅后统一做优雅关闭，避免 "StreamSink is
    // bound to a stream" 以及 TCP RST 导致浏览器收不到残余数据。
  }
}

// ─── Multiplexed HTTP channel ─────────────────────────────────────────────────

class _Suo6Channel {
  _Suo6Channel._(this._socket, this._bodyCtrl);

  final Socket _socket;
  final StreamController<List<int>> _bodyCtrl;
  final _ChunkedBodyDecoder _chunkedDec = _ChunkedBodyDecoder();

  Uint8List? _key;
  int  _c2sPos = 0; // client→server XOR counter
  int  _s2cPos = 0; // server→client XOR counter
  bool _headerDone = false;
  bool _closed = false;
  final List<int> _headerBuf = [];
  final _Buf _frameBuf = _Buf();

  _Suo6InboundTransport _inTransport = _Suo6InboundTransport.chunked;
  int _inClRemaining = 0;

  // Stream ID allocator (1–65534, wraps)
  int _nextStreamId = 1;
  final _streams = <int, _Suo6Stream>{};

  StreamSubscription<List<int>>? _sub;

  /// FIFO queue of encoded frames (each becomes one HTTP chunk body).
  final Queue<Uint8List> _pendingChunks = Queue<Uint8List>();
  static const int _batchWireBudget = 32 * 1024;
  Future<void> _writeTail = Future<void>.value();
  /// True while [close] is draining; [sendFrame] becomes a no-op.
  bool _inClose = false;

  void Function(int streamId, int typ, Uint8List payload)? onFrame;
  void Function()? onClose;

  bool get isClosed => _closed;

  static Future<_Suo6Channel> open(String url, List<int> firstBody) async {
    final uri  = Uri.parse(url);
    final host = uri.host;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final path = uri.path.isEmpty ? '/' : uri.path;
    final fullPath = uri.hasQuery ? '$path?${uri.query}' : path;

    late Socket socket;
    if (uri.scheme == 'https') {
      socket = await SecureSocket.connect(host, port,
          onBadCertificate: (_) => true,
          timeout: const Duration(seconds: 15));
    } else {
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 15));
    }
    socket.setOption(SocketOption.tcpNoDelay, true);

    final bodyCtrl = StreamController<List<int>>.broadcast();
    final ch = _Suo6Channel._(socket, bodyCtrl);
    ch._sub = socket.listen(ch._onRawData,
        onDone: () { if (!bodyCtrl.isClosed) bodyCtrl.close(); ch.onClose?.call(); },
        onError: (_) { if (!bodyCtrl.isClosed) bodyCtrl.close(); ch.onClose?.call(); },
        cancelOnError: true);

    final hostHdr = _suo6HostHeaderValue(host, port, uri.scheme);

    final hdrs = StringBuffer()
      ..write('POST $fullPath HTTP/1.1\r\n')
      ..write('Host: $hostHdr\r\n')
      ..write('User-Agent: $_kSuo6UserAgent\r\n')
      ..write('Accept: */*\r\n')
      ..write('Accept-Language: en-US,en;q=0.9\r\n')
      ..write('Accept-Encoding: identity\r\n')
      ..write('Connection: keep-alive\r\n')
      ..write('Cache-Control: no-cache\r\n')
      ..write('Pragma: no-cache\r\n')
      // 与 suo5 流式 POST / 服务端 jsp 一致：减轻 nginx 等对上游 chunked 的缓冲。
      ..write('X-Accel-Buffering: no\r\n')
      ..write('Content-Type: application/octet-stream\r\n')
      ..write('Transfer-Encoding: chunked\r\n')
      ..write('\r\n');
    socket.add(ascii.encode(hdrs.toString()));
    await socket.flush();

    // Send first body (handshake) as initial chunk
    await ch._sendHandshakeChunk(firstBody);
    return ch;
  }

  void setKey(Uint8List key) { _key = key; }

  // ── Allocate stream IDs ───────────────────────────────────────────────────

  int allocateStreamId() {
    final id = _nextStreamId;
    _nextStreamId = (_nextStreamId % 65534) + 1;
    return id;
  }

  void registerStream(int id, _Suo6Stream s) => _streams[id] = s;
  void unregisterStream(int id) => _streams.remove(id);
  _Suo6Stream? getStream(int id) => _streams[id];

  // ── Send a frame ──────────────────────────────────────────────────────────

  void sendFrame(int streamId, int typ, List<int> payload) {
    if (_closed || _inClose || _key == null) return;
    final frame = Uint8List(5 + payload.length);
    frame[0] = (streamId >> 8) & 0xff;
    frame[1] = streamId & 0xff;
    frame[2] = typ;
    frame[3] = (payload.length >> 8) & 0xff;
    frame[4] = payload.length & 0xff;
    for (var i = 0; i < payload.length; i++) {
      frame[5 + i] = payload[i];
    }
    final k = _key!;
    for (var i = 0; i < frame.length; i++) {
      frame[i] ^= k[_c2sPos++ & 15];
    }
    _pendingChunks.add(frame);
    _writeTail = _writeTail.then((_) => _drainOutboundBatches()).catchError((Object e) {
      if (!_closed && !_inClose) {
        _failChannel(e);
      }
    });
  }

  Future<void> _sendHandshakeChunk(List<int> data) async {
    if (_closed) return;
    final line = '${data.length.toRadixString(16)}\r\n';
    _socket.add(ascii.encode(line));
    _socket.add(data);
    _socket.add(const [13, 10]);
    await _socket.flush();
  }

  /// Sends as few TCP writes as possible: multiple HTTP/1.1 chunks per flush.
  Future<void> _drainOutboundBatches() async {
    while (_pendingChunks.isNotEmpty && !_closed) {
      final bb = BytesBuilder(copy: false);
      var budget = _batchWireBudget;
      while (_pendingChunks.isNotEmpty) {
        final f = _pendingChunks.first;
        final overhead = f.length + 24;
        if (bb.isNotEmpty && overhead > budget) break;
        _pendingChunks.removeFirst();
        bb.add(ascii.encode('${f.length.toRadixString(16)}\r\n'));
        bb.add(f);
        bb.add(const [13, 10]);
        budget -= overhead;
        if (budget <= 0 && bb.isNotEmpty) break;
      }
      if (bb.isEmpty) break;
      try {
        _socket.add(bb.takeBytes());
        await _socket.flush();
      } catch (e) {
        _failChannel(e);
        return;
      }
    }
  }

  void _failChannel(Object _) {
    if (_closed) return;
    _closed = true;
    _pendingChunks.clear();
    // 唤醒所有挂起的 stream，让对应的 SOCKS session 能正常退出。
    _closeAllStreams();
    onClose?.call();
    unawaited(_sub?.cancel());
    try {
      _socket.destroy();
    } catch (_) {}
  }

  void _closeAllStreams() {
    if (_streams.isEmpty) return;
    final copy = _streams.values.toList();
    _streams.clear();
    for (final s in copy) {
      try { s.deliverFin(); } catch (_) {}
    }
  }

  // ── Handshake: read exactly n raw decoded bytes ───────────────────────────

  // Used only during handshake (before key is set), so no XOR yet.
  final _Buf _ackBuf = _Buf(64);
  Completer<void>? _ackWaiter;

  Future<Uint8List> readExact(int n) async {
    while (true) {
      if (_ackBuf.length >= n) {
        final out = Uint8List.fromList(_ackBuf.view(0, n));
        _ackBuf.consume(n);
        return out;
      }
      if (_closed) throw Exception('channel closed during handshake read');
      _ackWaiter = Completer<void>();
      await _ackWaiter!.future.timeout(const Duration(seconds: 15));
    }
  }

  // ── Raw socket data → HTTP decode → frame parse ───────────────────────────

  void _onRawData(List<int> chunk) {
    if (_closed) return;
    if (!_headerDone) {
      _headerBuf.addAll(chunk);
      final idx = _findHeaderEnd(_headerBuf);
      if (idx < 0) return;
      final headerRaw = String.fromCharCodes(_headerBuf.sublist(0, idx));
      final firstLine = headerRaw.split('\r\n').first;
      if (!_suo6Http200.hasMatch(firstLine)) {
        _closed = true;
        _closeAllStreams();
        unawaited(_sub?.cancel());
        try { _socket.destroy(); } catch (_) {}
        onClose?.call();
        return;
      }
      final inbound = _Suo6InboundParse.fromHeaders(headerRaw);
      if (inbound.unsupportedContentEncoding) {
        _closed = true;
        _closeAllStreams();
        unawaited(_sub?.cancel());
        try { _socket.destroy(); } catch (_) {}
        onClose?.call();
        return;
      }
      _inTransport = inbound.transport;
      _inClRemaining = inbound.contentLengthRemaining;
      _chunkedDec.reset();
      _headerDone = true;
      final rest = _headerBuf.sublist(idx + 4);
      _headerBuf.clear();
      if (rest.isNotEmpty) _feedBody(rest);
      return;
    }
    _feedBody(chunk);
  }

  void _feedBody(List<int> chunk) {
    if (chunk.isEmpty) return;
    switch (_inTransport) {
      case _Suo6InboundTransport.chunked:
        final decoded = _chunkedDec.feed(chunk);
        for (final block in decoded) {
          _applyInboundBlock(block);
        }
        break;
      case _Suo6InboundTransport.contentLength:
        _feedBodyContentLength(chunk);
        break;
      case _Suo6InboundTransport.raw:
        _applyInboundBlock(
          chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
        );
        break;
    }
  }

  void _feedBodyContentLength(List<int> chunk) {
    var buf = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    var off = 0;
    while (off < buf.length) {
      if (_inClRemaining <= 0) {
        _inTransport = _Suo6InboundTransport.raw;
        if (off < buf.length) {
          _feedBody(Uint8List.sublistView(buf, off));
        }
        return;
      }
      final take = min(buf.length - off, _inClRemaining);
      _applyInboundBlock(Uint8List.sublistView(buf, off, off + take));
      off += take;
      _inClRemaining -= take;
    }
  }

  void _applyInboundBlock(Uint8List block) {
    if (block.isEmpty) return;
    if (_key == null) {
      _ackBuf.add(block);
      _ackWaiter?.complete();
      _ackWaiter = null;
      return;
    }
    final k = _key!;
    final dec = Uint8List.fromList(block);
    for (var i = 0; i < dec.length; i++) {
      dec[i] ^= k[_s2cPos++ & 15];
    }
    _frameBuf.add(dec);
    _parseFrames();
  }

  void _parseFrames() {
    while (_frameBuf.length >= 5) {
      final hdr = _frameBuf.view(0, 5);
      final streamId = ((hdr[0] & 0xff) << 8) | (hdr[1] & 0xff);
      final typ      = hdr[2] & 0xff;
      final len      = ((hdr[3] & 0xff) << 8) | (hdr[4] & 0xff);
      if (_frameBuf.length < 5 + len) break;
      final payload = Uint8List.fromList(_frameBuf.view(5, 5 + len));
      _frameBuf.consume(5 + len);
      onFrame?.call(streamId, typ, payload);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _inClose = true;
    try {
      await _writeTail;
      while (_pendingChunks.isNotEmpty) {
        await _drainOutboundBatches();
      }
    } catch (_) {}
    _closed = true;
    _inClose = false;
    // 唤醒所有挂起的 stream，以便 SOCKS session 能正常退出 finally 块。
    _closeAllStreams();
    try {
      _socket.add(ascii.encode('0\r\n\r\n'));
      await _socket.flush();
    } catch (_) {}
    await _sub?.cancel();
    try {
      await _socket.close();
    } catch (_) {}
    await _bodyCtrl.close();
  }

  static int _findHeaderEnd(List<int> b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i+1] == 10 && b[i+2] == 13 && b[i+3] == 10) return i;
    }
    return -1;
  }
}

// ─── SOCKS5 socket reader (same as suo5) ─────────────────────────────────────

class _SockReader {
  _SockReader(this.socket) {
    _sub = socket.listen((chunk) {
      if (_onData != null) {
        _onData!(Uint8List.fromList(chunk));
      } else {
        _buffer.addAll(chunk);
        _waiter?.complete(); _waiter = null;
      }
    }, onError: (Object e) {
      if (_onError != null) { unawaited(_onError!(e)); }
      _error = e; _waiter?.complete(); _waiter = null;
    }, onDone: () {
      if (_onDone != null) { unawaited(_onDone!()); }
      _done = true; _waiter?.complete(); _waiter = null;
    }, cancelOnError: true);
  }

  final Socket socket;
  late final StreamSubscription<List<int>> _sub;
  final List<int> _buffer = [];
  bool _done = false;
  Object? _error;
  Completer<void>? _waiter;
  void Function(Uint8List)? _onData;
  Future<void> Function()? _onDone;
  Future<void> Function(Object)? _onError;

  Future<Uint8List> read(int n) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (_buffer.length < n) {
      if (_error != null) throw _error!;
      if (_done) throw Exception('socket closed');
      final now = DateTime.now();
      if (now.isAfter(deadline)) throw TimeoutException('read timeout');
      _waiter ??= Completer<void>();
      await _waiter!.future.timeout(deadline.difference(now));
    }
    final out = Uint8List.fromList(_buffer.sublist(0, n));
    _buffer.removeRange(0, n);
    return out;
  }

  Future<void> dispose() => _sub.cancel();

  void bind({
    required void Function(Uint8List) onData,
    required Future<void> Function() onDone,
    required Future<void> Function(Object) onError,
  }) {
    _onData = onData; _onDone = onDone; _onError = onError;
    if (_buffer.isNotEmpty) {
      final pending = Uint8List.fromList(_buffer); _buffer.clear();
      _onData!(pending);
    }
    // Socket 可能在 bind() 调用前已关闭/出错，立即触发对应回调，
    // 避免 await stream.done 永久挂起。
    if (_error != null) {
      unawaited(_onError!(_error!));
    } else if (_done) {
      unawaited(_onDone!());
    }
  }
}

// ─── Efficient byte buffer (O(1) consume) ─────────────────────────────────────

class _Buf {
  static const _minCap = 4096;
  Uint8List _data;
  int _start = 0;
  int _end   = 0;

  _Buf([int cap = _minCap]) : _data = Uint8List(cap < _minCap ? _minCap : cap);

  int get length => _end - _start;
  int operator [](int i) => _data[_start + i];

  void add(List<int> chunk) {
    _reserve(chunk.length);
    if (chunk is Uint8List) {
      _data.setRange(_end, _end + chunk.length, chunk);
    } else {
      for (var i = 0; i < chunk.length; i++) { _data[_end + i] = chunk[i]; }
    }
    _end += chunk.length;
  }

  void consume(int n) {
    _start += n;
    if (_start > _minCap && _start * 2 > _data.length) _compact();
  }

  void clear() {
    _start = 0;
    _end = 0;
  }

  Uint8List view(int from, int to) =>
      Uint8List.sublistView(_data, _start + from, _start + to);

  void _compact() {
    final len = _end - _start;
    _data.setRange(0, len, _data, _start);
    _start = 0; _end = len;
  }

  void _reserve(int extra) {
    final needed = _end + extra;
    if (needed <= _data.length) return;
    if (_end - _start + extra <= _data.length) { _compact(); return; }
    var cap = _data.length;
    while (cap < _end - _start + extra) { cap <<= 1; }
    final next = Uint8List(cap);
    next.setRange(0, _end - _start, _data, _start);
    _data = next; _end -= _start; _start = 0;
  }
}

// ─── Chunked HTTP body decoder ────────────────────────────────────────────────

class _ChunkedBodyDecoder {
  final _Buf _buf = _Buf();
  int? _need;
  bool _done = false;

  void reset() {
    _buf.clear();
    _need = null;
    _done = false;
  }

  List<Uint8List> feed(List<int> data) {
    if (_done) return const [];
    _buf.add(data);
    final out = <Uint8List>[];
    while (true) {
      if (_need == null) {
        final lineEnd = _findCrlf();
        if (lineEnd < 0) break;
        final line = String.fromCharCodes(_buf.view(0, lineEnd));
        final n = int.tryParse(line.split(';').first.trim(), radix: 16);
        if (n == null) break;
        _buf.consume(lineEnd + 2);
        _need = n;
        if (n == 0) { _done = true; break; }
      }
      final n = _need!;
      if (_buf.length < n + 2) break;
      out.add(Uint8List.fromList(_buf.view(0, n)));
      _buf.consume(n + 2);
      _need = null;
    }
    return out;
  }

  int _findCrlf() {
    for (var i = 0; i + 1 < _buf.length; i++) {
      if (_buf[i] == 13 && _buf[i + 1] == 10) return i;
    }
    return -1;
  }
}

// ─── Multi-session manager ────────────────────────────────────────────────────

class _Suo6AggLog {
  const _Suo6AggLog(this.when, this.label, this.message);
  final DateTime when;
  final String   label;
  final String   message;

  String format() {
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    final ss = when.second.toString().padLeft(2, '0');
    return label.isEmpty ? '[$hh:$mm:$ss] $message' : '[$hh:$mm:$ss] [$label] $message';
  }
}

class Suo6ClientService {
  Suo6ClientService._internal();
  static final Suo6ClientService _instance = Suo6ClientService._internal();
  factory Suo6ClientService() => _instance;

  final Map<int, Suo6Session> _sessions = {};
  final List<_Suo6AggLog>     _aggLog   = [];

  void Function()? onChanged;

  Map<int, Suo6Session> get sessions => Map.unmodifiable(_sessions);
  Suo6Session? sessionFor(int id) => _sessions[id];

  Suo6Session _ensureSession(int profileId, {String label = ''}) {
    final existing = _sessions[profileId];
    if (existing != null) {
      if (label.isNotEmpty && existing.label != label) existing.label = label;
      return existing;
    }
    final s = Suo6Session(label: label)
      ..onChanged = _emit
      ..onLog     = (when, msg) => _appendLog(when, label, msg);
    _sessions[profileId] = s;
    s.onLog = (when, msg) => _appendLog(when, s.label, msg);
    return s;
  }

  Future<void> startProfile(int profileId, Suo6Config config, {String label = ''}) async {
    final s = _ensureSession(profileId, label: label);
    if (s.status == Suo6Status.running || s.status == Suo6Status.connecting) await s.stop();
    await s.start(config);
  }

  /// 探测：临时会话只跑握手，不监听 SOCKS、不启 ping，与 [Suo5ClientService.probe] 对齐。
  Future<void> probe(Suo6Config config, {String label = ''}) async {
    final temp = Suo6Session(label: label);
    temp.onLog = (when, msg) => _appendLog(when, label, msg);
    temp.onChanged = _emit;
    try {
      await temp.probe(config);
    } finally {
      await temp.dispose();
    }
  }

  Future<void> stopProfile(int profileId) async {
    final s = _sessions[profileId];
    if (s == null) return;
    await s.stop();
    _emit();
  }

  Future<void> removeProfile(int profileId) async {
    final s = _sessions.remove(profileId);
    if (s == null) return;
    await s.dispose();
    _emit();
  }

  bool isRunning(int profileId) {
    final s = _sessions[profileId];
    return s != null && (s.status == Suo6Status.running || s.status == Suo6Status.connecting);
  }

  int get runningCount    => _sessions.values.where((s) => s.status == Suo6Status.running).length;
  int get totalActiveConn => _sessions.values.fold(0, (a, s) => a + s.activeConnections);
  int get totalUpload     => _sessions.values.fold(0, (a, s) => a + s.uploadBytes);
  int get totalDownload   => _sessions.values.fold(0, (a, s) => a + s.downloadBytes);

  List<String> get aggregatedLogs => _aggLog.map((e) => e.format()).toList(growable: false);

  /// 与 [Suo5ClientService.aggregatedLogEvents] 成对使用：按 [when] 合并为一条时间线。
  List<({DateTime when, String line})> get aggregatedLogEvents => [
        for (final e in _aggLog) (when: e.when, line: '[suo6] ${e.format()}'),
      ];

  void clearAllLogs() {
    _aggLog.clear();
    for (final s in _sessions.values) { s._logs.clear(); }
    _emit();
  }

  void _appendLog(DateTime when, String label, String msg) {
    _aggLog.add(_Suo6AggLog(when, label, msg));
    if (_aggLog.length > 1000) _aggLog.removeRange(0, _aggLog.length - 1000);
  }

  void _emit() => onChanged?.call();
}
