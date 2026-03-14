import 'dart:convert';
import 'dart:io';

import 'package:mysql1/mysql1.dart';

/// 密码爆破（复刻 fscan）
/// 支持 Redis、FTP、MySQL、SSH
class BruteService {
  final Duration timeout;

  BruteService({this.timeout = const Duration(seconds: 5)});

  /// Redis 爆破：尝试 AUTH
  Future<String?> bruteRedis(String host, int port, List<String> passwords) async {
    for (final pwd in passwords) {
      try {
        final socket = await Socket.connect(host, port, timeout: timeout);
        socket.writeln('AUTH $pwd');
        await socket.flush();
        final data = await socket.map((b) => utf8.decode(b)).first;
        await socket.close();
        if (data.contains('OK') && !data.contains('invalid')) return pwd;
      } catch (_) {}
    }
    return null;
  }

  /// FTP 爆破
  Future<({String user, String pwd})?> bruteFtp(
    String host,
    int port,
    List<({String user, String pwd})> credentials,
  ) async {
    for (final c in credentials) {
      try {
        final socket = await Socket.connect(host, port, timeout: timeout);
        final stream = socket.map((b) => utf8.decode(b)).transform(const LineSplitter());
        await stream.first; // 220
        socket.writeln('USER ${c.user}');
        await socket.flush();
        await stream.first;
        socket.writeln('PASS ${c.pwd}');
        await socket.flush();
        final res = await stream.first;
        await socket.close();
        if (res.startsWith('230')) return c;
      } catch (_) {}
    }
    return null;
  }

  /// MySQL 爆破（使用 mysql1 包）
  Future<({String user, String pwd})?> bruteMysql(
    String host,
    int port,
    List<({String user, String pwd})> credentials,
  ) async {
    for (final c in credentials) {
      try {
        final mysql = await MySqlConnection.connect(
          ConnectionSettings(
            host: host,
            port: port,
            user: c.user,
            password: c.pwd,
            timeout: timeout,
          ),
        );
        await mysql.close();
        return c;
      } catch (_) {}
    }
    return null;
  }

  /// SSH 爆破（依赖 sshpass，需系统已安装）
  Future<({String user, String pwd})?> bruteSsh(
    String host,
    int port,
    List<({String user, String pwd})> credentials,
  ) async {
    for (final c in credentials) {
      try {
        final result = await Process.run(
          'sshpass',
          [
            '-p',
            c.pwd,
            'ssh',
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'ConnectTimeout=${timeout.inSeconds}',
            '-o', 'BatchMode=yes',
            '-p', '$port',
            '$c.user@$host',
            'echo ok',
          ],
          runInShell: true,
        ).timeout(timeout);
        if (result.exitCode == 0 && result.stdout.toString().trim() == 'ok') {
          return c;
        }
      } catch (_) {}
    }
    return null;
  }
}
