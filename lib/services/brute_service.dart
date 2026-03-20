import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mysql1/mysql1.dart';

/// 密码爆破（复刻 fscan）
/// 并发执行，支持 Redis、FTP、MySQL、MSSQL、PostgreSQL、Telnet
/// 账号锁定检测：识别 MSSQL 18470/18486、PostgreSQL 28000、MySQL ER_SIGNAL 等错误
/// 对应 fscan SMB.go concurrentSmbScan 中的 lockedUsers map 机制
class BruteService {
  final Duration timeout;

  /// 同时并发的凭据数量
  final int concurrency;

  BruteService({
    this.timeout = const Duration(seconds: 5),
    this.concurrency = 5,
  });

  // ── 账号锁定异常 ──────────────────────────────────────────────────────────

  // 爆破尝试结果（细粒度错误分类，对应 fscan SMB.go STATUS_* 错误码处理）
  static const _kLocked   = 'locked';    // 账号被锁定（继续尝试无意义，立即跳过该用户）
  static const _kDisabled = 'disabled';  // 账号已禁用（密码可能正确，但无法登录）
  static const _kExpired  = 'expired';   // 密码已过期（密码正确，需变更）

  // ── 并发执行助手 ──────────────────────────────────────────────────────────

  /// 并发尝试凭据列表，返回首个成功的凭据；全部失败返回 null
  /// [getUser] 可选：提取凭据中的用户名，用于跳过已锁定账号
  /// [onAccountStatus] 可选：报告账号状态（locked/disabled/expired）
  Future<T?> _runConcurrent<T>(
    List<T> credentials,
    Future<String?> Function(T) tryFn, // returns null=fail, 'ok'=success, _kLocked/etc
    {String Function(T)? getUser,
    void Function(T cred, String status)? onAccountStatus}
  ) async {
    final lockedUsers = <String>{};

    for (var i = 0; i < credentials.length; i += concurrency) {
      final end = (i + concurrency).clamp(0, credentials.length);
      final allBatch = credentials.sublist(i, end);
      // 跳过已知锁定用户（对应 fscan lockedUsers map）
      final batch = getUser == null
          ? allBatch
          : allBatch.where((c) => !lockedUsers.contains(getUser(c))).toList();
      if (batch.isEmpty) continue;

      T? found;
      await Future.wait(batch.map((cred) async {
        if (found != null) return;
        try {
          final result = await tryFn(cred);
          if (result == 'ok') {
            found = cred;
          } else if (result == _kLocked || result == _kDisabled || result == _kExpired) {
            if (getUser != null) lockedUsers.add(getUser(cred));
            onAccountStatus?.call(cred, result!);
          }
        } catch (_) {}
      }));

      if (found != null) return found;
    }
    return null;
  }

  // ── Redis ─────────────────────────────────────────────────────────────────

  Future<String?> bruteRedis(
    String host,
    int port,
    List<String> passwords,
  ) async {
    return _runConcurrent<String>(
      passwords,
      (pwd) async => (await _tryRedis(host, port, pwd)) ? 'ok' : null,
    );
  }

  Future<bool> _tryRedis(String host, int port, String pwd) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.write('AUTH $pwd\r\n');
      await socket.flush();
      final data = await socket.map((b) => utf8.decode(b, allowMalformed: true)).first.timeout(timeout);
      await socket.close();
      return data.contains('+OK') && !data.contains('-ERR');
    } catch (_) {
      return false;
    } finally {
      try { socket?.destroy(); } catch (_) {}
    }
  }

  // ── FTP ───────────────────────────────────────────────────────────────────

  Future<({String user, String pwd})?> bruteFtp(
    String host,
    int port,
    List<({String user, String pwd})> credentials,
  ) async {
    return _runConcurrent(
      credentials,
      (c) async => (await _tryFtp(host, port, c.user, c.pwd)) ? 'ok' : null,
    );
  }

  Future<bool> _tryFtp(String host, int port, String user, String pwd) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      final stream = socket.map((b) => utf8.decode(b, allowMalformed: true))
          .transform(const LineSplitter());
      await stream.first.timeout(timeout); // 220 banner
      socket.writeln('USER $user');
      await socket.flush();
      await stream.first.timeout(timeout);
      socket.writeln('PASS $pwd');
      await socket.flush();
      final res = await stream.first.timeout(timeout);
      await socket.close();
      // 421 = service unavailable (account locked); 530 = auth fail
      if (res.startsWith('421')) return false;
      return res.startsWith('230');
    } catch (_) {
      return false;
    } finally {
      try { socket?.destroy(); } catch (_) {}
    }
  }

  // ── MySQL ─────────────────────────────────────────────────────────────────

  Future<({String user, String pwd})?> bruteMysql(
    String host,
    int port,
    List<({String user, String pwd})> credentials,
  ) async {
    return _runConcurrent(
      credentials,
      (c) async => _tryMysqlStatus(host, port, c.user, c.pwd),
      getUser: (c) => c.user,
    );
  }

  /// 返回 'ok' / _kLocked / _kDisabled / null
  Future<String?> _tryMysqlStatus(String host, int port, String user, String pwd) async {
    try {
      final mysql = await MySqlConnection.connect(
        ConnectionSettings(host: host, port: port, user: user, password: pwd, timeout: timeout),
      );
      await mysql.close();
      return 'ok';
    } catch (e) {
      final msg = e.toString().toLowerCase();
      // ER_USER_IS_BLOCKED (1042) / ER_ACCOUNT_HAS_BEEN_LOCKED (3955)
      if (msg.contains('account') && (msg.contains('lock') || msg.contains('block'))) {
        return _kLocked;
      }
      // ERROR 1045: Access denied (password wrong or user disabled)
      return null;
    }
  }

  // ── SSH ───────────────────────────────────────────────────────────────────

  Future<({String user, String pwd})?> bruteSsh(
    String host,
    int port,
    List<({String user, String pwd})> credentials,
  ) async {
    return _runConcurrent(
      credentials,
      (c) async => (await _trySsh(host, port, c.user, c.pwd)) ? 'ok' : null,
    );
  }

  Future<bool> _trySsh(String host, int port, String user, String pwd) async {
    try {
      final result = await Process.run(
        'sshpass',
        [
          '-p', pwd,
          'ssh',
          '-o', 'StrictHostKeyChecking=no',
          '-o', 'ConnectTimeout=${timeout.inSeconds}',
          '-o', 'BatchMode=yes',
          '-p', '$port',
          '$user@$host',
          'echo ok',
        ],
        runInShell: true,
      ).timeout(timeout + const Duration(seconds: 2));
      return result.exitCode == 0 && result.stdout.toString().trim() == 'ok';
    } catch (_) {
      return false;
    }
  }

  // ── MSSQL（TDS 协议）────────────────────────────────────────────────────

  Future<({String user, String pwd})?> bruteMssql(
    String host,
    int port,
    List<({String user, String pwd})> credentials,
  ) async {
    return _runConcurrent(
      credentials,
      (c) => _tryMssqlStatus(host, port, c.user, c.pwd),
      getUser: (c) => c.user,
    );
  }

  /// TDS Login7：返回 'ok' / _kLocked / _kDisabled / _kExpired / null
  /// 对应 fscan SMB.go 中的 STATUS_ACCOUNT_LOCKED_OUT / STATUS_ACCOUNT_DISABLED 处理
  Future<String?> _tryMssqlStatus(String host, int port, String user, String pwd) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);

      socket.add(_tdsPrelogin());
      await socket.flush();

      final preResp = await socket.first.timeout(timeout);
      if (preResp.isEmpty || preResp[0] != 0x04) return null;

      socket.add(_tdsLogin7(host, user, pwd));
      await socket.flush();

      final loginResp = await socket.first.timeout(timeout);
      await socket.close();

      for (var i = 8; i < loginResp.length; i++) {
        if (loginResp[i] == 0xAD) return 'ok'; // LOGINACK = success
        if (loginResp[i] == 0xAA) {
          // ERROR token: parse error number (4 bytes at i+3)
          if (i + 6 < loginResp.length) {
            final errNum = loginResp[i + 3] |
                (loginResp[i + 4] << 8) |
                (loginResp[i + 5] << 16) |
                (loginResp[i + 6] << 24);
            // 18470 = account disabled, 18486 = account locked, 18488 = password expired
            if (errNum == 18486) return _kLocked;
            if (errNum == 18470) return _kDisabled;
            if (errNum == 18488) return _kExpired;
          }
          return null; // login failed, wrong password
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      try { socket?.destroy(); } catch (_) {}
    }
  }

  List<int> _tdsPrelogin() {
    // Body: VERSION(5) + ENCRYPTION(5) + TERMINATOR(1) + data(7) = 18 bytes
    // Offsets relative to body start (after 8-byte TDS header)
    // VERSION: offset=11, len=6; ENCRYPTION: offset=17, len=1
    const body = <int>[
      0x00, 0x00, 0x0B, 0x00, 0x06, // VERSION option: offset=11, len=6
      0x01, 0x00, 0x11, 0x00, 0x01, // ENCRYPTION option: offset=17, len=1
      0xFF,                          // TERMINATOR
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // VERSION data (v0.0.0)
      0x02,                          // ENCRYPTION=NOT_SUP
    ];
    final len = 8 + body.length;
    return [
      0x12, 0x01,
      (len >> 8) & 0xFF, len & 0xFF,
      0x00, 0x00, 0x01, 0x00,
      ...body,
    ];
  }

  List<int> _tdsLogin7(String serverName, String user, String password) {
    // Encode strings as UCS-2LE
    List<int> ucs2(String s) {
      final out = <int>[];
      for (final c in s.codeUnits) {
        out.add(c & 0xFF);
        out.add((c >> 8) & 0xFF);
      }
      return out;
    }

    // Password obfuscation: swap nibbles then XOR 0xA5
    List<int> obfuscatePwd(String s) {
      final raw = ucs2(s);
      return raw.map((b) {
        final swapped = ((b & 0x0F) << 4) | ((b & 0xF0) >> 4);
        return swapped ^ 0xA5;
      }).toList();
    }

    final hostnameBytes = ucs2('MATRIX');
    final usernameBytes = ucs2(user);
    final passwordBytes = obfuscatePwd(password);
    final appnameBytes = ucs2('MatrixScanner');
    final servernameBytes = ucs2(serverName);
    final libraryBytes = ucs2('MatrixScanner');
    final databaseBytes = ucs2('master');

    // Fixed header size: 36 + (13 * 4) + 6 + 4 = 98 bytes
    const fixedSize = 98;
    var dataOffset = fixedSize;

    final hostnameOff = dataOffset;
    dataOffset += hostnameBytes.length;
    final usernameOff = dataOffset;
    dataOffset += usernameBytes.length;
    final passwordOff = dataOffset;
    dataOffset += passwordBytes.length;
    final appnameOff = dataOffset;
    dataOffset += appnameBytes.length;
    final servernameOff = dataOffset;
    dataOffset += servernameBytes.length;
    final libraryOff = dataOffset;
    dataOffset += libraryBytes.length;
    final databaseOff = dataOffset;
    dataOffset += databaseBytes.length;
    final totalPayloadLen = dataOffset;

    final buf = ByteData(totalPayloadLen);
    var pos = 0;

    void writeInt32(int v) {
      buf.setInt32(pos, v, Endian.little);
      pos += 4;
    }

    void writeInt16(int v) {
      buf.setInt16(pos, v, Endian.little);
      pos += 2;
    }

    void writeByte(int v) {
      buf.setUint8(pos, v);
      pos += 1;
    }

    void writeOffLen(int off, int byteLen) {
      writeInt16(off);
      writeInt16(byteLen ~/ 2); // character count
    }

    // Login7 fixed header
    writeInt32(totalPayloadLen);        // length
    writeInt32(0x74000004);             // TDS version 7.4
    writeInt32(4096);                   // packet size
    writeInt32(7);                      // client program version
    writeInt32(0);                      // client PID
    writeInt32(0);                      // connection ID
    writeByte(0xE0);                    // option flags 1: UNICODE | CHAR | FLOAT | DUMPLOAD | USE_DB | DATABASE
    writeByte(0x03);                    // option flags 2: INIT_DB_FATAL | SET_LANG
    writeByte(0x00);                    // type flags
    writeByte(0x00);                    // option flags 3
    writeInt32(0);                      // timezone
    writeInt32(0x0409);                 // LCID en-US

    // Variable data offset/length pairs
    writeOffLen(hostnameOff, hostnameBytes.length);
    writeOffLen(usernameOff, usernameBytes.length);
    writeOffLen(passwordOff, passwordBytes.length);
    writeOffLen(appnameOff, appnameBytes.length);
    writeOffLen(servernameOff, servernameBytes.length);
    writeOffLen(0, 0);                  // extension
    writeOffLen(libraryOff, libraryBytes.length);
    writeOffLen(0, 0);                  // locale
    writeOffLen(databaseOff, databaseBytes.length);

    // Client ID (6 bytes, fake MAC)
    for (var i = 0; i < 6; i++) { writeByte(0x00); }

    writeOffLen(0, 0);                  // SSPI
    writeOffLen(0, 0);                  // attach_db_file
    writeOffLen(0, 0);                  // change_password
    writeInt32(0);                      // sspi_long

    final payload = buf.buffer.asUint8List();

    // Rebuild: fixed header from ByteData, then variable string data appended
    final result = Uint8List(totalPayloadLen);
    result.setRange(0, fixedSize, payload.sublist(0, fixedSize));
    var dPos = fixedSize;
    for (final chunk in [hostnameBytes, usernameBytes, passwordBytes,
                         appnameBytes, servernameBytes, libraryBytes, databaseBytes]) {
      result.setRange(dPos, dPos + chunk.length, chunk);
      dPos += chunk.length;
    }

    final totalLen = 8 + totalPayloadLen;
    return [
      0x10, 0x01,                       // Login7, EOM
      (totalLen >> 8) & 0xFF, totalLen & 0xFF,
      0x00, 0x00, 0x01, 0x00,
      ...result,
    ];
  }

  // ── PostgreSQL（wire protocol）────────────────────────────────────────────

  Future<({String user, String pwd})?> brutePostgres(
    String host,
    int port,
    List<({String user, String pwd})> credentials,
  ) async {
    return _runConcurrent(
      credentials,
      (c) => _tryPostgresStatus(host, port, c.user, c.pwd),
      getUser: (c) => c.user,
    );
  }

  /// PostgreSQL wire protocol 认证：返回 'ok' / _kLocked / _kDisabled / null
  /// SQLSTATE 28000 = invalid_authorization_specification（账号禁用/不存在）
  /// SQLSTATE 28P01 = invalid_password（密码错误）
  Future<String?> _tryPostgresStatus(String host, int port, String user, String pwd) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);

      // Startup message: len(4) + protocol(4) + "user\0" + user + "\0" + "database\0postgres\0\0"
      final userBytes = utf8.encode(user);
      final dbBytes = utf8.encode('postgres');
      final paramUser = [...utf8.encode('user'), 0, ...userBytes, 0];
      final paramDb = [...utf8.encode('database'), 0, ...dbBytes, 0];
      final body = [...paramUser, ...paramDb, 0];
      final msgLen = 4 + 4 + body.length; // length field + protocol + params
      final startup = ByteData(msgLen);
      startup.setInt32(0, msgLen, Endian.big);
      startup.setInt32(4, 196608, Endian.big); // protocol 3.0
      final startupBytes = Uint8List.fromList([
        ...startup.buffer.asUint8List(),
        ...body,
      ]);
      socket.add(startupBytes);
      await socket.flush();

      // Read authentication request
      final data = await socket.first.timeout(timeout);
      if (data.length < 9) return null;

      final msgType = data[0];
      // 'E' = 0x45 → ErrorResponse: check SQLSTATE for lockout
      if (msgType == 0x45) {
        final errStr = String.fromCharCodes(data.sublist(1));
        // SQLSTATE 28000 = invalid_authorization / account disabled
        if (errStr.contains('28000')) return _kDisabled;
        return null;
      }
      if (msgType != 0x52) return null; // Not AuthenticationRequest

      final authType = ByteData.sublistView(
        Uint8List.fromList(data), 5, 9,
      ).getInt32(0, Endian.big);

      if (authType == 0) return 'ok'; // AuthenticationOK (no password needed)

      List<int>? authMsg;

      if (authType == 3) {
        // Cleartext password
        final pwdBytes = utf8.encode(pwd);
        final pktLen = 4 + pwdBytes.length + 1;
        authMsg = [
          0x70,
          (pktLen >> 24) & 0xFF, (pktLen >> 16) & 0xFF,
          (pktLen >> 8) & 0xFF, pktLen & 0xFF,
          ...pwdBytes, 0,
        ];
      } else if (authType == 5) {
        // MD5 password: "md5" + md5(md5(pwd+user)+salt)
        if (data.length < 13) return null;
        final salt = data.sublist(9, 13);
        final inner = md5.convert([...utf8.encode(pwd), ...utf8.encode(user)]).toString();
        final outer = md5.convert([...utf8.encode(inner), ...salt]).toString();
        final hash = utf8.encode('md5$outer');
        final pktLen = 4 + hash.length + 1;
        authMsg = [
          0x70,
          (pktLen >> 24) & 0xFF, (pktLen >> 16) & 0xFF,
          (pktLen >> 8) & 0xFF, pktLen & 0xFF,
          ...hash, 0,
        ];
      } else {
        return null; // Unsupported auth type (e.g. SCRAM)
      }

      socket.add(authMsg);
      await socket.flush();

      final authResp = await socket.first.timeout(timeout);
      await socket.close();

      if (authResp.isEmpty) return null;
      // 'E' = ErrorResponse after password send
      if (authResp[0] == 0x45) {
        final errStr = String.fromCharCodes(authResp.sublist(1));
        if (errStr.contains('28000')) return _kDisabled;
        return null; // 28P01 = wrong password
      }
      // 'R' + authType=0 → AuthenticationOK
      if (authResp[0] == 0x52 &&
          authResp.length >= 9 &&
          ByteData.sublistView(Uint8List.fromList(authResp), 5, 9)
              .getInt32(0, Endian.big) == 0) {
        return 'ok';
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      try { socket?.destroy(); } catch (_) {}
    }
  }

  // ── Telnet ────────────────────────────────────────────────────────────────

  /// Telnet 爆破：支持 username+password 和 only-password 两种模式
  Future<({String user, String pwd})?> bruteTelnet(
    String host,
    int port,
    List<({String user, String pwd})> credentials,
  ) async {
    return _runConcurrent(
      credentials,
      (c) async => (await _tryTelnet(host, port, c.user, c.pwd)) ? 'ok' : null,
    );
  }

  Future<bool> _tryTelnet(String host, int port, String user, String pwd) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      final client = _TelnetSession(socket, timeout: timeout);
      await client.init();

      final type = client.detectType();
      if (type == _TelnetType.noAuth) return true;
      if (type == _TelnetType.closed) return false;

      if (type == _TelnetType.usernamePassword) {
        client.write(user);
        await Future.delayed(const Duration(seconds: 1));
        client.clear();
      }

      client.write(pwd);
      await Future.delayed(const Duration(seconds: 2));
      final resp = client.response;
      return _isTelnetSuccess(resp);
    } catch (_) {
      return false;
    } finally {
      await socket?.close();
    }
  }

  bool _isTelnetSuccess(String resp) {
    if (resp.isEmpty) return false;
    final lower = resp.toLowerCase();
    for (final bad in ['wrong', 'invalid', 'fail', 'incorrect', 'error', 'denied']) {
      if (lower.contains(bad)) return false;
    }
    final lines = resp.split('\n');
    final last = lines.last;
    if (RegExp(r'^[#$>]').hasMatch(last)) return true;
    if (RegExp(r'^<[a-zA-Z0-9_]+>').hasMatch(last)) return true;
    if (lower.contains('last login')) return true;
    return false;
  }
}

// ── Telnet session helper ────────────────────────────────────────────────────

enum _TelnetType { closed, noAuth, onlyPassword, usernamePassword }

class _TelnetSession {
  final Socket socket;
  final Duration timeout;
  String response = '';

  static const iac = 0xFF;
  static const dont = 0xFE;
  static const doCmd = 0xFD;
  static const wont = 0xFC;
  static const will = 0xFB;
  static const sb = 0xFA;
  static const se = 0xF0;
  static const echo = 0x01;
  static const sga = 0x03;

  _TelnetSession(this.socket, {required this.timeout});

  Future<void> init() async {
    socket.listen((data) {
      final processed = _process(data);
      response += String.fromCharCodes(
        processed.where((b) => b >= 0x20 || b == 0x0A || b == 0x0D),
      );
    }, onError: (_) {});
    await Future.delayed(const Duration(seconds: 2));
  }

  List<int> _process(List<int> raw) {
    final display = <int>[];
    final reply = <int>[];

    for (var i = 0; i < raw.length; i++) {
      if (raw[i] != iac || i + 1 >= raw.length) {
        display.add(raw[i]);
        continue;
      }
      i++;
      final verb = raw[i];
      if (verb == iac) { display.add(iac); continue; }
      if (verb == sb) {
        while (i < raw.length && raw[i] != se) { i++; }
        continue;
      }
      if (i + 1 >= raw.length) break;
      i++;
      final opt = raw[i];
      if (opt == echo || opt == sga) {
        switch (verb) {
          case doCmd: { reply.addAll([iac, will, opt]); }
          case dont:  { reply.addAll([iac, wont, opt]); }
          case will:  { reply.addAll([iac, doCmd, opt]); }
          case wont:  { reply.addAll([iac, dont, opt]); }
        }
      } else {
        switch (verb) {
          case doCmd:
          case dont:  { reply.addAll([iac, wont, opt]); }
          case will:
          case wont:  { reply.addAll([iac, dont, opt]); }
        }
      }
    }

    if (reply.isNotEmpty) socket.add(reply);
    return display;
  }

  _TelnetType detectType() {
    if (response.isEmpty) return _TelnetType.closed;
    final lines = response.split('\n');
    final last = lines.last.toLowerCase().trim();

    if (RegExp(r'(user|name|login|account)').hasMatch(last)) {
      return _TelnetType.usernamePassword;
    }
    if (last.contains('pass')) return _TelnetType.onlyPassword;
    if (RegExp(r'^[#$>]|^<[a-z]').hasMatch(last)) return _TelnetType.noAuth;
    return _TelnetType.closed;
  }

  void write(String s) {
    socket.add([...utf8.encode(s), 0x0D, 0x00]);
  }

  void clear() => response = '';
}
