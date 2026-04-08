import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/api.dart';
import '../core/net/net_client.dart';

// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------

/// privilege_key 计算模式
enum FrpAuthMode {
  /// MD5(token + timestamp_str) —— 官方 frp 全版本默认算法
  md5,
  /// HMAC-SHA1(key=token, data=timestamp_str)  —— 部分自定义 frp 版本
  hmacSha1,
  /// HMAC-SHA256(key=token, data=timestamp_str) —— 部分自定义 frp 版本
  hmacSha256,
  /// 直接发送原始 token 字符串，不做任何哈希 —— 极少数修改版
  rawToken,
}

class FrpTunnelConfig {
  final String serverAddr;
  final int serverPort;
  final String token;
  final String proxyName;
  final int remotePort;
  final String localAddr;
  final int localPort;
  /// 声明给服务端的版本号，留空则不携带
  final String version;
  /// 是否使用 yamux 多路复用（frp 默认 true，即 transport.tcpMux = true）
  final bool useTcpMux;
  /// privilege_key 计算算法
  final FrpAuthMode authMode;

  const FrpTunnelConfig({
    required this.serverAddr,
    this.serverPort = 7000,
    this.token = '',
    required this.proxyName,
    required this.remotePort,
    this.localAddr = '127.0.0.1',
    required this.localPort,
    this.version = '',
    this.useTcpMux = true,
    this.authMode = FrpAuthMode.md5,
  });
}

// ---------------------------------------------------------------------------
// 状态
// ---------------------------------------------------------------------------

enum FrpTunnelStatus { idle, connecting, running, error }

// ---------------------------------------------------------------------------
// AES-128-CFB 流密码（与 fatedier/golib crypto 兼容）
//
// 协议：
//   发送端第一次写入时，在密文前先发送 16 字节随机 IV；
//   接收端第一次读取时，先读取 16 字节 IV，然后解密后续数据。
//   密钥派生：PBKDF2(password=token, salt="frp", iter=64, dkLen=16, PRF=HMAC-SHA1)
// ---------------------------------------------------------------------------

class _AesCfbStream {
  final Uint8List _reg;   // 16-byte 反馈寄存器（初始为 IV，后续为上一密文块）
  int _used = 16;         // 当前密钥流块中已消耗字节数（初始=16 触发首次加密）
  final AESEngine _aes = AESEngine();
  final bool _isEncrypt;

  _AesCfbStream({
    required Uint8List key,
    required Uint8List iv,
    required bool encrypt,
  })  : _reg = Uint8List.fromList(iv),
        _used = 16,
        _isEncrypt = encrypt {
    // AES 密钥扩展（CFB 加解密均使用 AES 加密方向生成密钥流）
    _aes.init(true, KeyParameter(key));
  }

  /// 处理任意长度的数据（加密或解密）
  Uint8List process(List<int> input) {
    final out = Uint8List(input.length);
    for (var i = 0; i < input.length; i++) {
      if (_used == 16) {
        // 用当前寄存器（上一密文块或 IV）加密，得到 16 字节密钥流
        final ks = Uint8List(16);
        _aes.processBlock(_reg, 0, ks, 0);
        _reg.setAll(0, ks);
        _used = 0;
      }
      if (_isEncrypt) {
        final c = (input[i] ^ _reg[_used]) & 0xFF;
        _reg[_used] = c; // 反馈 = 密文
        out[i] = c;
      } else {
        final c = input[i] & 0xFF;
        out[i] = (c ^ _reg[_used]) & 0xFF;
        _reg[_used] = c; // 反馈 = 密文（解密时输入即密文）
      }
      _used++;
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// yamux 流
// ---------------------------------------------------------------------------

class _MuxStream {
  _MuxStream(this.id);

  final int id;
  bool closed = false;

  final Completer<void> _established = Completer<void>();
  Future<void> get established => _established.future;

  final StreamController<List<int>> _ctrl =
      StreamController<List<int>>.broadcast();
  Stream<List<int>> get onData => _ctrl.stream;

  void feedData(List<int> data) {
    if (!closed && !_ctrl.isClosed) _ctrl.add(data);
  }

  void markEstablished() {
    if (!_established.isCompleted) _established.complete();
  }

  void close() {
    closed = true;
    if (!_ctrl.isClosed) _ctrl.close();
    if (!_established.isCompleted) {
      _established.completeError(Exception('stream $id closed'));
    }
  }
}

// ---------------------------------------------------------------------------
// 服务（单例）
// ---------------------------------------------------------------------------

/// frp 客户端服务。
///
/// 支持两种传输模式：
///  • tcpMux=true  （默认）：TCP → yamux session → frp 消息流，与官方 frpc 行为一致
///  • tcpMux=false ：TCP 直连，适用于服务端配置了 transport.tcpMux=false 的情况
class FrpClientService {
  FrpClientService._internal();
  static final FrpClientService _instance = FrpClientService._internal();
  factory FrpClientService() => _instance;

  // ---- frp 消息类型 ----
  static const int _tLogin = 0x6F;          // 'o'
  static const int _tLoginResp = 0x31;      // '1'
  static const int _tNewProxy = 0x70;       // 'p'
  static const int _tNewProxyResp = 0x32;   // '2'
  static const int _tNewWorkConn = 0x77;    // 'w'
  static const int _tStartWorkConn = 0x73;  // 's'
  static const int _tReqWorkConn = 0x72;    // 'r'
  static const int _tPing = 0x68;           // 'h'

  // ---- yamux 常量 ----
  // 帧头 12 字节：[version(1)][type(1)][flags(2)][streamId(4)][length(4)]
  static const int _mxVer = 0;
  static const int _mxData = 0;
  static const int _mxWindowUpdate = 1;
  static const int _mxPing = 2;
  static const int _mxGoAway = 3;
  static const int _mxSyn = 0x0001;
  static const int _mxAck = 0x0002;
  static const int _mxFin = 0x0004;
  static const int _mxRst = 0x0008;
  static const int _mxInitWindow = 256 * 1024;

  // ---- 状态 ----
  FrpTunnelStatus _status = FrpTunnelStatus.idle;
  FrpTunnelStatus get status => _status;
  FrpTunnelConfig? currentConfig;

  // ---- TCP ----
  Socket? _tcpSocket;
  final NetClient _netClient = NetClient(
    connectTimeout: const Duration(seconds: 10),
    readTimeout: const Duration(seconds: 10),
  );
  bool _tcpActive = false;
  StreamSubscription<List<int>>? _tcpSub;
  Timer? _pingTimer;

  // ---- yamux ----
  bool _useTcpMux = true;
  final List<int> _yamuxBuf = [];
  final Map<int, _MuxStream> _muxStreams = {};
  int _nextStreamId = 1;

  /// yamux 控制 TCP 上 **add 与 await flush 绝不能交错**（否则会 StateError: StreamSink is bound…）。
  /// 用单协程顺序：排空队列里所有 add → 再 await flush；期间不再启动另一路 microtask 去 add。
  final List<void Function()> _muxOutboundQueue = [];
  bool _muxWriterRunning = false;
  bool _pendingTcpFlush = false;

  // ---- frp 控制通道 ----
  final List<int> _ctrlBuf = [];
  String? _runId;

  // ---- 控制通道加密（LoginResp 之后所有消息均加密） ----
  // 发送端
  Uint8List? _encKey;        // PBKDF2 派生 AES-128 密钥
  Uint8List? _encIV;         // 随机生成的发送端 IV
  bool _encIVSent = false;   // IV 是否已随第一条加密消息发出
  _AesCfbStream? _encCipher; // AES-128-CFB 加密流
  // 接收端
  _AesCfbStream? _decCipher; // AES-128-CFB 解密流
  bool _decNeedIV = false;   // 是否正在等待接收服务端 IV
  final List<int> _decIVBuf = []; // 服务端 IV 收集缓冲

  // ---- 日志 ----
  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);

  void clearLogs() {
    _logs.clear();
    onChanged?.call();
  }

  void Function()? onChanged;

  // ---- 断开后自动重连 ----
  bool _autoReconnect = false;
  bool get autoReconnect => _autoReconnect;
  set autoReconnect(bool v) => _autoReconnect = v;
  Timer? _reconnectTimer;

  // --------------------------------------------------------------------------
  // 公开 API
  // --------------------------------------------------------------------------

  Future<void> start(FrpTunnelConfig config) async {
    if (_status == FrpTunnelStatus.running ||
        _status == FrpTunnelStatus.connecting) {
      return;
    }
    _teardown(); // 确保前一次连接完全清理，避免残留 socket 导致 flush 异常
    currentConfig = config;
    _logs.clear();
    _ctrlBuf.clear();
    _yamuxBuf.clear();
    _muxStreams.clear();
    _nextStreamId = 1;
    _useTcpMux = config.useTcpMux;
    _resetCrypto();
    _setStatus(FrpTunnelStatus.connecting);
    try {
      await _connect(config);
    } catch (e) {
      _log('连接失败：$e');
      _setStatus(FrpTunnelStatus.error);
    }
  }

  Future<void> stop() async => _teardown();

  // --------------------------------------------------------------------------
  // 连接
  // --------------------------------------------------------------------------

  Future<void> _connect(FrpTunnelConfig cfg) async {
    _log('正在连接 ${cfg.serverAddr}:${cfg.serverPort}  tcpMux=${cfg.useTcpMux}');
    _tcpSocket = (await _netClient.connectTcp(cfg.serverAddr, cfg.serverPort))?.rawSocket;
    if (_tcpSocket == null) {
      throw Exception('无法连接 FRP 服务端');
    }
    _tcpSocket!.setOption(SocketOption.tcpNoDelay, true);
    _tcpActive = true;
    _log('TCP 已连接');

    _tcpSub = _tcpSocket!.listen(
      _onTcpData,
      onError: (e) {
        _log('TCP 错误：$e');
        _teardown();
      },
      onDone: () {
        if (_status != FrpTunnelStatus.idle) {
          _log('控制连接已断开（服务端主动关闭）');
          if (_useTcpMux) {
            _log('  提示：若服务端配置了 tcpMux=false，请关闭「TCPMux」选项重试');
          }
          _setStatus(FrpTunnelStatus.error);
          final cfg = currentConfig;
          _teardown();
          if (_autoReconnect && cfg != null) {
            _log('5 秒后自动重连...');
            _reconnectTimer = Timer(const Duration(seconds: 5), () {
              _reconnectTimer = null;
              start(cfg);
            });
          }
        }
      },
    );

    if (_useTcpMux) {
      _log('正在建立 yamux 控制流...');
      final ctrlStream = _muxOpenStream(); // stream id = 1
      await ctrlStream.established.timeout(const Duration(seconds: 10),
          onTimeout: () =>
              throw TimeoutException('yamux 握手超时（10s），服务端未响应 SYN ACK'));
      _log('yamux 流 #1 已建立');
    }

    _sendLogin(cfg);
  }

  // --------------------------------------------------------------------------
  // TCP 数据接收
  // --------------------------------------------------------------------------

  void _onTcpData(List<int> data) {
    if (!_useTcpMux) {
      _logRaw('←', data);
      _feedCtrlBytes(data);
      return;
    }
    _yamuxBuf.addAll(data);
    _drainYamux();
  }

  // --------------------------------------------------------------------------
  // 加密层：LoginResp 之后所有 payload 需加密
  //
  // 关键：yamux 帧头的 length 必须等于实际发送的字节数。
  // 若加密，实际发送 = IV(首次) + 密文，故需先加密再写帧头。
  // --------------------------------------------------------------------------

  /// 返回加密后的字节（含 IV 若首次），供 _muxSendData 使用正确长度
  List<int> _encryptPayload(List<int> data) {
    if (_encCipher == null) return data;
    final result = <int>[];
    if (!_encIVSent) {
      _encIVSent = true;
      result.addAll(_encIV!);
    }
    result.addAll(_encCipher!.process(Uint8List.fromList(data)));
    return result;
  }

  // --------------------------------------------------------------------------
  // yamux 帧处理
  // --------------------------------------------------------------------------

  void _muxOutgoing(void Function() op) {
    _muxOutboundQueue.add(op);
    _ensureMuxWriter();
  }

  void _ensureMuxWriter() {
    if (_muxWriterRunning) return;
    _muxWriterRunning = true;
    unawaited(_runMuxWriterLoop());
  }

  Future<void> _runMuxWriterLoop() async {
    try {
      for (;;) {
        while (_muxOutboundQueue.isNotEmpty) {
          final batch = List<void Function()>.from(_muxOutboundQueue);
          _muxOutboundQueue.clear();
          for (final f in batch) {
            try {
              f();
            } catch (e, st) {
              _log('[yamux] outbound 异常：$e');
              assert(() {
                _log('[yamux] $st');
                return true;
              }());
            }
          }
        }
        if (_pendingTcpFlush) {
          _pendingTcpFlush = false;
          final s = _tcpSocket;
          if (_tcpActive && s != null) {
            try {
              await s.flush();
            } on StateError {
              // socket 已关或与其它操作冲突
            } catch (_) {}
          }
        }
        if (_muxOutboundQueue.isEmpty && !_pendingTcpFlush) break;
      }
    } finally {
      _muxWriterRunning = false;
      if (_muxOutboundQueue.isNotEmpty || _pendingTcpFlush) {
        _ensureMuxWriter();
      }
    }
  }

  void _muxSendFrame(int type, int flags, int streamId, int length) {
    _muxOutgoing(() => _muxSendFrameNow(type, flags, streamId, length));
  }

  void _muxSendFrameNow(int type, int flags, int streamId, int length) {
    if (!_tcpActive) return;
    final sock = _tcpSocket;
    if (sock == null) return;

    final hdr = Uint8List(12);
    final bd = ByteData.view(hdr.buffer);
    bd.setUint8(0, _mxVer);
    bd.setUint8(1, type);
    bd.setUint16(2, flags, Endian.big);
    bd.setUint32(4, streamId, Endian.big);
    bd.setUint32(8, length, Endian.big);

    // yamux 帧头始终明文（与 frps 行为一致）
    try {
      sock.add(hdr);
    } on StateError catch (e) {
      _log('[yamux] send frame failed (StateError): $e');
      _tcpActive = false;
    }
  }

  void _muxSendData(int streamId, List<int> data) {
    if (data.isEmpty || !_tcpActive) return;
    if (_tcpSocket == null) return;
    // 仅控制流（stream 1）加密，工作流（stream 3+）明文（frps handleConnection 直接 ReadMsg）
    final payload = streamId == 1 ? _encryptPayload(data) : data;
    final sid = streamId;
    final pl = List<int>.from(payload);

    _muxOutgoing(() {
      if (!_tcpActive) return;
      final sock = _tcpSocket;
      if (sock == null) return;
      _muxSendFrameNow(_mxData, 0, sid, pl.length);
      try {
        sock.add(pl);
      } on StateError catch (e) {
        _log('[yamux] send data failed (StateError): $e');
        _tcpActive = false;
      }
    });
  }

  _MuxStream _muxOpenStream() {
    final id = _nextStreamId;
    _nextStreamId += 2;
    final stream = _MuxStream(id);
    _muxStreams[id] = stream;
    _muxSendFrame(_mxWindowUpdate, _mxSyn, id, _mxInitWindow);
    _tcpFlush();
    return stream;
  }

  void _tcpFlush() {
    if (!_tcpActive) return;
    if (_tcpSocket == null) return;
    _pendingTcpFlush = true;
    _ensureMuxWriter();
  }

  void _drainYamux() {
    var needFlush = false;
    while (_yamuxBuf.length >= 12) {
      final bd = ByteData.sublistView(Uint8List.fromList(_yamuxBuf), 0, 12);
      final version = bd.getUint8(0);
      final type = bd.getUint8(1);
      final flags = bd.getUint16(2, Endian.big);
      final streamId = bd.getUint32(4, Endian.big);
      final length = bd.getUint32(8, Endian.big);

      if (version != _mxVer && version != 1) {
        _log('yamux 版本字节错误：0x${version.toRadixString(16)}  '
            '→ 请关闭「TCPMux」选项后重试');
        _teardown();
        return;
      }

      if (type == _mxData) {
        if (_yamuxBuf.length < 12 + length) break;
        _yamuxBuf.removeRange(0, 12);
        final payload = List<int>.from(_yamuxBuf.sublist(0, length));
        _yamuxBuf.removeRange(0, length);
        _onMuxData(streamId, flags, payload);
        if (length > 0) {
          _muxSendFrame(_mxWindowUpdate, 0, streamId, length);
          needFlush = true;
        }
      } else {
        _yamuxBuf.removeRange(0, 12);
        _onMuxControl(type, flags, streamId, length);
      }

      if (!_tcpActive) return;
    }
    if (needFlush) _tcpFlush();
  }

  void _onMuxData(int streamId, int flags, List<int> payload) {
    if (streamId == 1) {
      if (payload.isNotEmpty) {
        _logRaw('←', payload);
        _feedCtrlBytes(payload);
      }
    } else {
      // 工作流 payload 明文（frps 仅加密控制连接）
      if (payload.isNotEmpty) {
        _muxStreams[streamId]?.feedData(payload);
      }
    }

    if (flags & (_mxFin | _mxRst) != 0) {
      _log('[yamux] stream $streamId closed by server (flags=0x${flags.toRadixString(16)})');
      _muxStreams[streamId]?.close();
      _muxStreams.remove(streamId);
    }
  }

  void _onMuxControl(int type, int flags, int streamId, int length) {
    switch (type) {
      case _mxWindowUpdate:
        if (flags & _mxAck != 0) {
          _muxStreams[streamId]?.markEstablished();
        }
        if (flags & (_mxFin | _mxRst) != 0) {
          _muxStreams[streamId]?.close();
          _muxStreams.remove(streamId);
          if (streamId == 1) {
            _log('控制流被服务端关闭（FIN/RST）');
            _setStatus(FrpTunnelStatus.error);
            _teardown();
          }
        }
        break;
      case _mxPing:
        if (flags & _mxSyn != 0) {
          _muxSendFrame(_mxPing, _mxAck, 0, length);
          _tcpFlush();
        }
        break;
      case _mxGoAway:
        _log('yamux GoAway errorCode=$length');
        _teardown();
        break;
    }
  }

  // --------------------------------------------------------------------------
  // 控制通道加密管道
  //
  // 协议（与 fatedier/golib crypto 对齐）：
  //   • 发送侧：首次写入时，在密文前先写 16 字节随机 IV
  //   • 接收侧：首次读取时，先读 16 字节 IV，随后均为密文
  //   • LoginResp 之前（含 LoginResp）：明文
  //   • LoginResp 之后：加密
  // --------------------------------------------------------------------------

  /// 将来自服务端的原始字节送入解密管道，最终填充到 _ctrlBuf 并触发解析
  void _feedCtrlBytes(List<int> data) {
    if (!_decNeedIV && _decCipher == null) {
      // 明文阶段（Login / LoginResp）
      _ctrlBuf.addAll(data);
      _drainCtrl();
      return;
    }

    if (_decNeedIV) {
      // 正在收集服务端 IV（16 字节）
      _decIVBuf.addAll(data);
      if (_decIVBuf.length >= 16) {
        final iv = Uint8List.fromList(_decIVBuf.sublist(0, 16));
        _decCipher = _AesCfbStream(key: _encKey!, iv: iv, encrypt: false);
        _decNeedIV = false;
        final remaining = _decIVBuf.sublist(16);
        _decIVBuf.clear();
        if (remaining.isNotEmpty) {
          _ctrlBuf.addAll(_decCipher!.process(remaining));
        }
        _drainCtrl();
      }
      // 若 IV 尚未收齐，等待下一次数据到达
      return;
    }

    // 解密阶段
    _ctrlBuf.addAll(_decCipher!.process(Uint8List.fromList(data)));
    _drainCtrl();
  }

  // --------------------------------------------------------------------------
  // frp 控制消息
  // --------------------------------------------------------------------------

  /// 发送控制消息（加密由 _encryptPayload / _muxSendData 统一处理）
  void _sendCtrl(List<int> data, {bool skipLog = false}) {
    if (!skipLog) _logRaw('→', data);

    if (_useTcpMux) {
      _muxSendData(1, data);
    } else {
      _tcpSocket?.add(_encryptPayload(data));
    }
    _tcpFlush();
  }

  void _sendLogin(FrpTunnelConfig cfg) {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _runId = '';

    final pk = _privilegeKey(cfg.token, ts, cfg.authMode);
    final tokenHex = cfg.token.codeUnits
        .map((c) => c.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    _log('[auth] mode=${cfg.authMode.name}  token(${cfg.token.length}B): $tokenHex');
    _log('[auth] timestamp=$ts  privilege_key=$pk');

    final body = <String, dynamic>{
      'version': cfg.version.isNotEmpty ? cfg.version : '0.67.0',
      'hostname': 'matrix-client',
      'os': Platform.operatingSystem,
      'arch': 'amd64',
      'user': '',
      'privilege_key': pk,
      'timestamp': ts,
      'run_id': _runId,
      'metas': <String, String>{},
      'pool_count': 0,
    };

    // Login 明文发送（服务端在加密初始化之前直接读取）
    final frame = _encodeMsg(_tLogin, body);
    _sendCtrl(frame);
    _log('Login 已发送（明文），等待 LoginResp...');
  }

  void _drainCtrl() {
    while (_ctrlBuf.length >= 9) {
      final type = _ctrlBuf[0];
      final bd = ByteData.sublistView(Uint8List.fromList(_ctrlBuf), 1, 9);
      final len = bd.getUint64(0, Endian.big);

      if (len > 1024 * 1024) {
        _log('frp 消息长度异常 ($len bytes)，可能协议不匹配');
        _teardown();
        return;
      }
      if (_ctrlBuf.length < 9 + len) break;
      final body = _ctrlBuf.sublist(9, 9 + len.toInt());
      _ctrlBuf.removeRange(0, 9 + len.toInt());
      _handleCtrlMsg(type, body);

      // 若 _handleCtrlMsg 刚初始化了加密（处理了 LoginResp），
      // _ctrlBuf 中的残余字节属于加密数据，需要重新走解密管道
      if (_decNeedIV && _ctrlBuf.isNotEmpty) {
        final remaining = List<int>.from(_ctrlBuf);
        _ctrlBuf.clear();
        _feedCtrlBytes(remaining);
        return; // _feedCtrlBytes 内部会再次调用 _drainCtrl
      }
    }
  }

  void _handleCtrlMsg(int type, List<int> raw) {
    _log('[msg] type=0x${type.toRadixString(16)} len=${raw.length}');
    try {
      final body = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      switch (type) {
        case _tLoginResp:
          final err = (body['error'] as String?) ?? '';
          if (err.isNotEmpty) {
            _log('登录失败：$err');
            _setStatus(FrpTunnelStatus.error);
            return;
          }
          final rid = body['run_id'] as String? ?? '';
          if (rid.isNotEmpty) _runId = rid;
          _log('登录成功（run_id=$_runId），初始化加密通道...');

          // 初始化控制通道加密（Login 之后所有消息均加密）
          _initCtrlCrypto(currentConfig!.token);

          _startPing();
          _sendNewProxy(currentConfig!);
          break;

        case _tNewProxyResp:
          final err = (body['error'] as String?) ?? '';
          if (err.isNotEmpty) {
            _log('创建代理失败：$err');
            _setStatus(FrpTunnelStatus.error);
            return;
          }
          final remote = body['remote_addr'] ?? '';
          _log('代理已就绪！远端地址：$remote');
          _log('隧道运行中，等待用户连接 ${currentConfig?.serverAddr}:${currentConfig?.remotePort} ...');
          _setStatus(FrpTunnelStatus.running);
          break;

        case _tReqWorkConn:
          _log('收到 ReqWorkConn，建立工作连接...');
          _openWorkConn(currentConfig!);
          break;

        default:
          break; // Pong 等忽略
      }
    } catch (e) {
      _log('解析消息失败：$e  raw=${utf8.decode(raw, allowMalformed: true)}');
    }
  }

  void _sendNewProxy(FrpTunnelConfig cfg) {
    final frame = _encodeMsg(_tNewProxy, {
      'proxy_name': cfg.proxyName,
      'proxy_type': 'tcp',
      'remote_port': cfg.remotePort,
    });
    _log('[newproxy] ${utf8.decode(frame.sublist(9))}');
    _sendCtrl(frame); // 此时 _encCipher 已初始化，自动加密
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!_tcpActive) return;
      final cfg = currentConfig;
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      String pk = '';
      if (cfg != null && cfg.token.isNotEmpty) {
        pk = _privilegeKey(cfg.token, ts, cfg.authMode);
      }
      _sendCtrl(_encodeMsg(_tPing, {
        if (pk.isNotEmpty) 'privilege_key': pk,
        if (pk.isNotEmpty) 'timestamp': ts,
      }));
    });
  }

  // --------------------------------------------------------------------------
  // 控制通道加密初始化
  // --------------------------------------------------------------------------

  /// 在 LoginResp 处理完成后调用，初始化加密/解密状态
  void _initCtrlCrypto(String token) {
    _encKey = _pbkdf2HmacSha1(
      Uint8List.fromList(utf8.encode(token)),
      Uint8List.fromList(utf8.encode('frp')),
      64,
      16,
    );

    // 发送端：生成随机 IV，初始化加密流
    _encIV = _randomBytes(16);
    _encIVSent = false;
    _encCipher = _AesCfbStream(key: _encKey!, iv: _encIV!, encrypt: true);

    // 接收端：等待服务端 IV（服务端首次写入密文时会先发 16 字节 IV）
    _decNeedIV = true;
    _decIVBuf.clear();
    _decCipher = null;

    // 加密通道已初始化（密钥派生、IV 已生成）
  }

  void _resetCrypto() {
    _encKey = null;
    _encIV = null;
    _encIVSent = false;
    _encCipher = null;
    _decCipher = null;
    _decNeedIV = false;
    _decIVBuf.clear();
  }

  // --------------------------------------------------------------------------
  // 工作连接
  // --------------------------------------------------------------------------

  Future<void> _openWorkConn(FrpTunnelConfig cfg) async {
    Socket? local;
    SocketConnection? localConn;
    StreamSubscription<List<int>>? workSub;
    void Function()? closeWork;
    try {
      final workFrpBuf = <int>[];
      final ready = Completer<void>();
      List<int> postHandshakeBuf = [];
      /// StartWorkConn 已收到但本地 Socket 尚未 connect 前到达的数据（否则 local?.add 会丢）
      final pendingBeforeLocal = <int>[];
      late void Function(List<int>) sendToWork;

      if (_useTcpMux) {
        final workStream = _muxOpenStream();
        // 与官方 frpc 一致：OpenStream 后立即发送 NewWorkConn，不等待 SYN-ACK
        // （服务端 handleConnection 有 10s 读超时，会阻塞直到收到 NewWorkConn）
        workStream.established.ignore();
        final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final body = <String, dynamic>{
          'run_id': _runId ?? '',
        };
        if (cfg.token.isNotEmpty) {
          body['timestamp'] = ts;
          body['privilege_key'] =
              _privilegeKey(cfg.token, ts, cfg.authMode);
        }
        final workMsg = _encodeMsg(_tNewWorkConn, body);
        _logRaw('→ (work stream ${workStream.id})', workMsg);

        // 工作流明文发送（frps 仅加密控制流，handleConnection 直接 ReadMsg）
        _muxSendData(workStream.id, workMsg);
        _tcpFlush();

        workSub = workStream.onData.listen((data) {
          if (ready.isCompleted) {
            final loc = local;
            if (loc != null) {
              loc.add(data);
            } else {
              pendingBeforeLocal.addAll(data);
            }
            return;
          }
          workFrpBuf.addAll(data);
          _tryConsumeStartWorkConn(workFrpBuf, ready, (remaining) {
            postHandshakeBuf = remaining;
          });
        },
            onError: (e) {
              if (!ready.isCompleted) ready.completeError(e);
            },
            onDone: () {
              if (!ready.isCompleted) {
                ready.completeError(Exception('工作流关闭'));
              }
            });

        sendToWork = (d) {
          _muxSendData(workStream.id, d);
          _tcpFlush();
        };
        closeWork = () {
          _muxSendFrame(_mxWindowUpdate, _mxFin, workStream.id, 0);
          _tcpFlush();
          workStream.close();
          _muxStreams.remove(workStream.id);
        };
      } else {
        // ---- 非 tcpMux 模式：新 TCP 连接 ----
        final workConn = await _netClient.connectTcp(cfg.serverAddr, cfg.serverPort);
        if (workConn == null) {
          throw Exception('无法建立 FRP 工作连接');
        }
        final workSocket = workConn.rawSocket;
        final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final body = <String, dynamic>{
          'run_id': _runId ?? '',
        };
        if (cfg.token.isNotEmpty) {
          body['timestamp'] = ts;
          body['privilege_key'] =
              _privilegeKey(cfg.token, ts, cfg.authMode);
        }
        final workMsg = _encodeMsg(_tNewWorkConn, body);
        _logRaw('→ (work conn)', workMsg);

        // 工作连接消息明文发送（服务端通过 msg.ReadMsg 以明文读取）
        workSocket.add(workMsg);
        await workSocket.flush();

        workSub = workSocket.listen((data) {
          if (ready.isCompleted) {
            final loc = local;
            if (loc != null) {
              loc.add(data);
            } else {
              pendingBeforeLocal.addAll(data);
            }
            return;
          }
          workFrpBuf.addAll(data);
          _tryConsumeStartWorkConn(workFrpBuf, ready, (remaining) {
            postHandshakeBuf = remaining;
          });
        },
            onError: (e) {
              if (!ready.isCompleted) ready.completeError(e);
            },
            onDone: () {
              if (!ready.isCompleted) {
                ready.completeError(Exception('工作连接在握手前关闭'));
              }
            });

        sendToWork = (d) {
          workSocket.add(d);
          workSocket.flush();
        };
        closeWork = workSocket.destroy;
      }

      await ready.future.timeout(const Duration(hours: 24),
          onTimeout: () => throw TimeoutException('等待 StartWorkConn 超时（24h）'));

      localConn = await _netClient.connectTcp(cfg.localAddr, cfg.localPort);
      if (localConn == null) {
        throw Exception('无法连接本地服务 ${cfg.localAddr}:${cfg.localPort}');
      }
      local = localConn.rawSocket;
      _log('桥接成功：frps ↔ ${cfg.localAddr}:${cfg.localPort}');

      if (postHandshakeBuf.isNotEmpty) local.add(postHandshakeBuf);
      if (pendingBeforeLocal.isNotEmpty) {
        local.add(pendingBeforeLocal);
        pendingBeforeLocal.clear();
      }

      workSub.onData((d) => local?.add(d));
      workSub.onDone(() => local?.destroy());
      workSub.onError((_) => local?.destroy());

      local.listen(
        sendToWork,
        onDone: () => closeWork?.call(),
        onError: (_) => closeWork?.call(),
        cancelOnError: true,
      );
    } catch (e) {
      _log('工作连接失败：$e');
      local?.destroy();
      await localConn?.close();
      await workSub?.cancel();
      closeWork?.call(); // 发送 yamux FIN、关闭流并从 _muxStreams 移除，避免影响后续连接
    }
  }

  void _tryConsumeStartWorkConn(
    List<int> buf,
    Completer<void> ready,
    void Function(List<int>) onRemaining,
  ) {
    while (buf.length >= 9) {
      final bd = ByteData.sublistView(Uint8List.fromList(buf), 1, 9);
      final msgLen = bd.getUint64(0, Endian.big);

      if (buf.length < 9 + msgLen) return;
      final t = buf[0];
      buf.removeRange(0, 9 + msgLen.toInt());
      if (t == _tStartWorkConn) {
        if (!ready.isCompleted) {
          onRemaining(List<int>.from(buf));
          ready.complete();
        }
        return;
      }
    }
  }

  // --------------------------------------------------------------------------
  // 清理
  // --------------------------------------------------------------------------

  void _teardown() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _muxOutboundQueue.clear();
    _muxWriterRunning = false;
    _pendingTcpFlush = false;
    _tcpActive = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    _tcpSub?.cancel();
    _tcpSub = null;
    for (final s in _muxStreams.values) {
      s.close();
    }
    _muxStreams.clear();
    _tcpSocket?.destroy();
    _tcpSocket = null;
    _ctrlBuf.clear();
    _yamuxBuf.clear();
    _nextStreamId = 1;
    _runId = null;
    _resetCrypto();
    if (_status != FrpTunnelStatus.idle) _setStatus(FrpTunnelStatus.idle);
  }

  // --------------------------------------------------------------------------
  // 工具方法
  // --------------------------------------------------------------------------

  void _setStatus(FrpTunnelStatus s) {
    _status = s;
    onChanged?.call();
  }

  void _log(String msg) {
    final ts = DateTime.now().toLocal();
    final hms =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
    _logs.add('[$hms] $msg');
    if (_logs.length > 500) _logs.removeRange(0, _logs.length - 500);
    onChanged?.call();
  }

  void _logRaw(String dir, List<int> data) {
    final hex = data
        .take(32)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    _log('[raw $dir${data.length}B] $hex');
  }

  /// frp 消息编码：[type(1)][big-endian int64 len(8)][json body(N)]
  Uint8List _encodeMsg(int type, Map<String, dynamic> body) {
    final jsonBytes = utf8.encode(jsonEncode(body));
    final out = Uint8List(9 + jsonBytes.length);
    out[0] = type;
    final bd = ByteData.view(out.buffer);
    bd.setUint64(1, jsonBytes.length, Endian.big);
    out.setRange(9, out.length, jsonBytes);
    return out;
  }

  /// privilege_key 计算
  String _privilegeKey(String token, int timestamp, FrpAuthMode mode) {
    final tsStr = timestamp.toString();
    switch (mode) {
      case FrpAuthMode.md5:
        return md5.convert(utf8.encode(token + tsStr)).toString();
      case FrpAuthMode.hmacSha1:
        return Hmac(sha1, utf8.encode(token))
            .convert(utf8.encode(tsStr))
            .toString();
      case FrpAuthMode.hmacSha256:
        return Hmac(sha256, utf8.encode(token))
            .convert(utf8.encode(tsStr))
            .toString();
      case FrpAuthMode.rawToken:
        return token;
    }
  }

  /// 生成密钥：PBKDF2(password=token, salt="frp", iter=64, dkLen=16, PRF=HMAC-SHA1)
  /// 与 fatedier/golib v0.5.1 crypto 包行为完全一致（DefaultSalt="frp"）
  Uint8List _pbkdf2HmacSha1(
      Uint8List password, Uint8List salt, int iterations, int dkLen) {
    // 单块推导（dkLen=16 ≤ SHA1 输出长度 20，仅需 block index=1）
    final hmac = Hmac(sha1, password);

    // U1 = HMAC(password, salt || INT(1))
    final saltBlock = Uint8List(salt.length + 4)
      ..setRange(0, salt.length, salt)
      ..[salt.length + 3] = 1; // big-endian 0x00000001

    List<int> u = hmac.convert(saltBlock).bytes;
    final result = List<int>.from(u);

    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return Uint8List.fromList(result.sublist(0, dkLen));
  }

  /// 生成密码学安全的随机字节
  Uint8List _randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(n, (_) => rng.nextInt(256)));
  }
}
