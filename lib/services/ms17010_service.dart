import 'dart:io';
import 'dart:typed_data';

/// MS17-010 永恒之蓝漏洞检测（复刻 fscan）
/// 完整 SMB1 协议：Negotiate → SessionSetup → TreeConnect → TransNamedPipe
/// 检测 STATUS_INSUFF_SERVER_RESOURCES (0xC0000205) 响应 → 确认漏洞
/// 额外检测 DOUBLEPULSAR 后门 (reply[34] == 0x51)
class Ms17010Service {
  final Duration timeout;

  Ms17010Service({this.timeout = const Duration(seconds: 5)});

  /// 检测结果
  Future<Ms17010Result> check(String host, {int port = 445}) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);

      try {
        return await _scan(socket, host);
      } finally {
        socket.destroy();
      }
    } catch (_) {
      return Ms17010Result(host: host);
    }
  }

  Future<Ms17010Result> _scan(Socket socket, String host) async {
    // ── Step 1: SMB1 Negotiate ──────────────────────────────────────────
    socket.add(_negotiateRequest());
    await socket.flush();

    final negResp = await _read(socket, 36);
    if (negResp == null) return Ms17010Result(host: host);

    // NT Status at bytes 9–12 must be 0
    final negStatus = _uint32le(negResp, 9);
    if (negStatus != 0) return Ms17010Result(host: host);

    // ── Step 2: SMB1 SessionSetup (anonymous NTLMSSP) ───────────────────
    socket.add(_sessionSetupRequest());
    await socket.flush();

    final sessResp = await _read(socket, 36);
    if (sessResp == null) return Ms17010Result(host: host);

    final sessStatus = _uint32le(sessResp, 9);
    if (sessStatus != 0) return Ms17010Result(host: host);

    // Extract OS version string from SessionSetup response
    final osName = _extractOs(sessResp);

    // Extract UserID (bytes 32–33) for subsequent requests
    final uid0 = sessResp[32];
    final uid1 = sessResp[33];

    // ── Step 3: TreeConnect to \\*\IPC$ ─────────────────────────────────
    final treeReq = _treeConnectRequest(uid0, uid1);
    socket.add(treeReq);
    await socket.flush();

    final treeResp = await _read(socket, 36);
    if (treeResp == null) return Ms17010Result(host: host, os: osName);

    // Extract TreeID (bytes 28–29)
    final tid0 = treeResp[28];
    final tid1 = treeResp[29];

    // ── Step 4: TransNamedPipe ──────────────────────────────────────────
    final pipeReq = _transNamedPipeRequest(tid0, tid1, uid0, uid1);
    socket.add(pipeReq);
    await socket.flush();

    final pipeResp = await _read(socket, 36);
    if (pipeResp == null) return Ms17010Result(host: host, os: osName);

    // Vulnerable: NT Status == STATUS_INSUFF_SERVER_RESOURCES (0xC0000205)
    // In little-endian at bytes 9–12: 05 02 00 C0
    final isVulnerable = pipeResp[9] == 0x05 &&
        pipeResp[10] == 0x02 &&
        pipeResp[11] == 0x00 &&
        pipeResp[12] == 0xC0;

    if (!isVulnerable) {
      return Ms17010Result(host: host, os: osName);
    }

    // ── Step 5: DOUBLEPULSAR backdoor check ─────────────────────────────
    final trans2Req = _trans2SessionSetupRequest(tid0, tid1, uid0, uid1);
    socket.add(trans2Req);
    await socket.flush();

    final dpResp = await _read(socket, 36);
    final hasDoublePulsar = dpResp != null && dpResp.length > 34 && dpResp[34] == 0x51;

    return Ms17010Result(
      host: host,
      os: osName,
      isVulnerable: true,
      hasDoublePulsar: hasDoublePulsar,
    );
  }

  // ── SMB packet builders ──────────────────────────────────────────────────

  /// SMB1 Negotiate Protocol Request
  List<int> _negotiateRequest() => [
    // NetBIOS session header
    0x00, 0x00, 0x00, 0x54,
    // SMB header
    0xFF, 0x53, 0x4D, 0x42, // \xffSMB magic
    0x72,                   // SMB_COM_NEGOTIATE
    0x00, 0x00, 0x00, 0x00, // NT Status: 0
    0x18,                   // Flags
    0x01, 0x28,             // Flags2
    0x00, 0x00,             // PID High
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Sig
    0x00, 0x00,             // Reserved
    0xFF, 0xFF,             // TID
    0xFE, 0xFF,             // PID
    0x00, 0x00,             // UID
    0x40, 0x00,             // MID
    // Parameters
    0x00,                   // Word count: 0
    // Data
    0x31, 0x00,             // Byte count: 49
    // Dialects
    0x02, 0x4C, 0x41, 0x4E, 0x4D, 0x41, 0x4E, 0x31, 0x2E, 0x30, 0x00, // LANMAN1.0
    0x02, 0x4C, 0x4D, 0x31, 0x32, 0x58, 0x30, 0x30, 0x32, 0x00,       // LM1.2X002
    0x02, 0x4E, 0x54, 0x20, 0x4C, 0x41, 0x4E, 0x4D, 0x41, 0x4E,
          0x20, 0x31, 0x2E, 0x30, 0x00,                                 // NT LANMAN 1.0
    0x02, 0x4E, 0x54, 0x20, 0x4C, 0x4D, 0x20, 0x30, 0x2E, 0x31,
          0x32, 0x00,                                                    // NT LM 0.12
  ];

  /// SMB1 Session Setup AndX (anonymous, NTLMSSP negotiate blob)
  List<int> _sessionSetupRequest() {
    // NTLMSSP NEGOTIATE message (type 1), wrapped in GSSAPI/SPNEGO
    const ntlmBlob = <int>[
      0x60, 0x48, 0x06, 0x06, 0x2B, 0x06, 0x01, 0x05,
      0x05, 0x02, 0xA0, 0x3E, 0x30, 0x3C, 0xA0, 0x0E,
      0x30, 0x0C, 0x06, 0x0A, 0x2B, 0x06, 0x01, 0x04,
      0x01, 0x82, 0x37, 0x02, 0x02, 0x0A, 0xA2, 0x2A,
      0x04, 0x28, 0x4E, 0x54, 0x4C, 0x4D, 0x53, 0x53,
      0x50, 0x00, 0x01, 0x00, 0x00, 0x00, 0xB7, 0x82,
      0x08, 0xE2, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x06, 0x01, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x0F,
    ]; // 74 bytes

    // Native OS (Unicode): "Windows 7 Professional 7601\x00"
    const nativeOs = <int>[
      0x57, 0x00, 0x69, 0x00, 0x6E, 0x00, 0x64, 0x00,
      0x6F, 0x00, 0x77, 0x00, 0x73, 0x00, 0x20, 0x00,
      0x37, 0x00, 0x20, 0x00, 0x50, 0x00, 0x72, 0x00,
      0x6F, 0x00, 0x66, 0x00, 0x65, 0x00, 0x73, 0x00,
      0x73, 0x00, 0x69, 0x00, 0x6F, 0x00, 0x6E, 0x00,
      0x61, 0x00, 0x6C, 0x00, 0x20, 0x00, 0x37, 0x00,
      0x36, 0x00, 0x30, 0x00, 0x31, 0x00, 0x00, 0x00,
    ]; // 56 bytes

    // ntlmBlob.length=74, nativeOs.length=56, byteCount=130
    const blobLen = 74;
    const byteCount = 130;
    const params = <int>[
      13,                     // Word count
      0xFF, 0x00, 0x00, 0x00, // AndX cmd=0xFF, reserved, offset=0
      0xDF, 0xFF,             // MaxBufferSize
      0x02, 0x00,             // MaxMpxCount
      0x00, 0x00,             // VcNumber
      0x00, 0x00, 0x00, 0x00, // SessionKey
      blobLen & 0xFF, (blobLen >> 8) & 0xFF, // BlobLen=74
      0x00, 0x00, 0x00, 0x00, // Reserved
      0x74, 0x00, 0x00, 0x80, // Capabilities
    ];
    const dataHeader = <int>[
      byteCount & 0xFF, (byteCount >> 8) & 0xFF,
    ];

    final body = <int>[...params, ...dataHeader, ...ntlmBlob, ...nativeOs];
    final payloadLen = 32 + body.length; // SMB header(32) + body
    final netbiosLen = payloadLen;

    return [
      0x00, 0x00,
      (netbiosLen >> 8) & 0xFF, netbiosLen & 0xFF,
      // SMB header
      0xFF, 0x53, 0x4D, 0x42, // \xffSMB
      0x73,                   // SMB_COM_SESSION_SETUP_ANDX
      0x00, 0x00, 0x00, 0x00, // NT Status: 0
      0x18,                   // Flags
      0x07, 0xC0,             // Flags2
      0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Signature
      0x00, 0x00,             // Reserved
      0xFF, 0xFF,             // TID
      0xFE, 0xFF,             // PID
      0x00, 0x00,             // UID (0 for initial)
      0x40, 0x00,             // MID
      ...body,
    ];
  }

  /// SMB1 Tree Connect to \\*\IPC$
  List<int> _treeConnectRequest(int uid0, int uid1) {
    // Path: "\\*\IPC$\0" in Unicode
    const path = <int>[
      0x5C, 0x00, 0x5C, 0x00, // \\
      0x2A, 0x00,             // *
      0x5C, 0x00,             // \
      0x49, 0x00, 0x50, 0x00, 0x43, 0x00, 0x24, 0x00, // IPC$
      0x00, 0x00,             // null terminator
    ];
    const service = <int>[0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x00]; // "?????\0"

    const params = <int>[
      4,                      // Word count
      0xFF, 0x00, 0x00, 0x00, // AndX
      0x00, 0x00,             // Flags
      0x01, 0x00,             // PasswordLength (1 for null)
    ];
    final byteCount = 1 + path.length + service.length; // 1(null pwd) + path + service
    final dataHeader = <int>[byteCount & 0xFF, (byteCount >> 8) & 0xFF];

    final body = <int>[...params, ...dataHeader, 0x00, ...path, ...service];
    final payloadLen = 32 + body.length;

    return [
      0x00, 0x00,
      (payloadLen >> 8) & 0xFF, payloadLen & 0xFF,
      0xFF, 0x53, 0x4D, 0x42, // SMB magic
      0x75,                   // SMB_COM_TREE_CONNECT_ANDX
      0x00, 0x00, 0x00, 0x00,
      0x18, 0x01, 0x20,
      0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00,
      0xFF, 0xFF,             // TID
      0xFE, 0xFF,             // PID
      uid0, uid1,             // UID
      0x40, 0x00,             // MID
      ...body,
    ];
  }

  /// SMB1 Trans - peek named pipe (triggers vulnerability check)
  List<int> _transNamedPipeRequest(int tid0, int tid1, int uid0, int uid1) {
    // SMB_COM_TRANSACTION targeting \PIPE\
    const setup = <int>[0x00, 0x23, 0x00, 0x00]; // 2 setup words: subcommand=0x0023 (PeekNamedPipe)
    const pipeName = <int>[0x5C, 0x50, 0x49, 0x50, 0x45, 0x5C, 0x00]; // \PIPE\
    const params = <int>[
      10,                     // Word count
      0x00, 0x00,             // Total param count
      0x00, 0x00,             // Total data count
      0xFF, 0xFF,             // Max param count
      0x00, 0x00,             // Max data count
      0x00,                   // Max setup count
      0x00,                   // Reserved
      0x00, 0x00,             // Flags
      0x00, 0x00, 0x00, 0x00, // Timeout
      0x00, 0x00,             // Reserved
      0x00, 0x00,             // Param count
      0x00, 0x00,             // Param offset (filled below)
      0x00, 0x00,             // Data count
      0x00, 0x00,             // Data offset
      0x02,                   // Setup count
      0x00,                   // Reserved
    ];
    final byteCount = pipeName.length + setup.length;
    final dataHeader = <int>[byteCount & 0xFF, (byteCount >> 8) & 0xFF];
    final body = <int>[...params, ...dataHeader, ...pipeName, ...setup];
    final payloadLen = 32 + body.length;

    return [
      0x00, 0x00,
      (payloadLen >> 8) & 0xFF, payloadLen & 0xFF,
      0xFF, 0x53, 0x4D, 0x42,
      0x25,                   // SMB_COM_TRANSACTION
      0x00, 0x00, 0x00, 0x00,
      0x18, 0x01, 0x28,
      0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00,
      tid0, tid1,             // TID
      0xFE, 0xFF,             // PID
      uid0, uid1,             // UID
      0x40, 0x00,
      ...body,
    ];
  }

  /// SMB1 Trans2 SessionSetup (for DOUBLEPULSAR detection)
  List<int> _trans2SessionSetupRequest(int tid0, int tid1, int uid0, int uid1) {
    const setup = <int>[0x00, 0x0E, 0x00, 0x00]; // Trans2 subcommand=14 (SESSION_SETUP)
    const params = <int>[
      15,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x01, 0x00, 0x00, 0x00, 0x00,
    ];
    const byteCount = <int>[0x04, 0x00];
    final body = <int>[...params, ...byteCount, ...setup];
    final payloadLen = 32 + body.length;

    return [
      0x00, 0x00,
      (payloadLen >> 8) & 0xFF, payloadLen & 0xFF,
      0xFF, 0x53, 0x4D, 0x42,
      0x32,                   // SMB_COM_TRANSACTION2
      0x00, 0x00, 0x00, 0x00,
      0x18, 0x07, 0xC0,
      0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00,
      tid0, tid1,
      0xFE, 0xFF,
      uid0, uid1,
      0x41, 0x00,
      ...body,
    ];
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<Uint8List?> _read(Socket socket, int minLen) async {
    try {
      final data = await socket.first.timeout(timeout);
      if (data.length < minLen) return null;
      final buf = Uint8List(data.length);
      buf.setRange(0, data.length, data);
      return buf;
    } catch (_) {
      return null;
    }
  }

  int _uint32le(Uint8List buf, int offset) =>
      buf[offset] |
      (buf[offset + 1] << 8) |
      (buf[offset + 2] << 16) |
      (buf[offset + 3] << 24);

  /// Extract OS version from SessionSetup response (Unicode strings after word params)
  String? _extractOs(Uint8List resp) {
    try {
      // SessionSetup response: SMB header(32) + word count(1) + words + byte count(2) + data
      if (resp.length < 45) return null;
      final wordCount = resp[36];
      if (wordCount == 0) return null;
      final dataStart = 37 + wordCount * 2 + 2; // skip words + byte count
      if (dataStart >= resp.length) return null;

      // Native OS is the first Unicode null-terminated string in data
      final sb = StringBuffer();
      for (var i = dataStart; i + 1 < resp.length; i += 2) {
        final lo = resp[i];
        final hi = resp[i + 1];
        if (lo == 0 && hi == 0) break;
        sb.writeCharCode((hi << 8) | lo);
      }
      final s = sb.toString().trim();
      return s.isNotEmpty ? s : null;
    } catch (_) {
      return null;
    }
  }
}

class Ms17010Result {
  final String host;
  final String? os;
  final bool isVulnerable;
  final bool hasDoublePulsar;

  Ms17010Result({
    required this.host,
    this.os,
    this.isVulnerable = false,
    this.hasDoublePulsar = false,
  });

  @override
  String toString() {
    if (isVulnerable) {
      final parts = ['MS17-010 漏洞'];
      if (os != null) parts.add(os!);
      if (hasDoublePulsar) parts.add('DOUBLEPULSAR 后门');
      return '$host [${parts.join(', ')}]';
    }
    if (os != null) return '$host [系统: $os]';
    return '$host [未检测到 MS17-010]';
  }
}
