import 'dart:async';
import 'dart:convert';

import 'brute_service.dart';
import 'fscan_service.dart';
import 'port_scan_service.dart';
import 'scan_session_service.dart';
import 'service_probe_service.dart';

/// 端口扫描后台服务：扫描与 UI 解耦，离开页面后继续运行
class PortScanBackgroundService {
  static final PortScanBackgroundService _instance = PortScanBackgroundService._internal();
  factory PortScanBackgroundService() => _instance;
  PortScanBackgroundService._internal();

  final _scanSession = ScanSessionService();

  final _cancelFlags = <int, bool>{};
  final _logController = StreamController<PortScanLogEvent>.broadcast();
  Stream<PortScanLogEvent> get logEvents => _logController.stream;

  String _ts() => '[${DateTime.now().toString().substring(0, 19)}]';

  String _serviceTag(String service) {
    if (service.isEmpty) return '';
    final lower = service.toLowerCase();
    if (lower == 'http') return '[http]';
    if (lower == 'https') return '[https]';
    return '[$lower]';
  }

  void _appendServicePocs(
    String host,
    int port,
    ServiceProbeResult r,
    void Function(String) log,
  ) {
    if (r.vulnerabilities.any((v) => v.contains('Redis 未授权'))) {
      log('${_ts()} [SUCCESS] 目标: $host:$port');
      log('  漏洞类型: poc-yaml-redis-unauth');
      log('  详细信息:');
      log('        Redis 未授权访问${r.vulnerabilities.any((v) => v.contains('可写')) ? '，可写公钥/计划任务' : ''}');
    }
    if (r.vulnerabilities.any((v) => v.contains('FTP 匿名'))) {
      log('${_ts()} [SUCCESS] 目标: $host:$port');
      log('  漏洞类型: poc-yaml-ftp-anonymous');
      log('  详细信息:');
      log('        params:[{user anonymous} {password anonymous@}]');
    }
    if (r.vulnerabilities.any((v) => v.contains('Elasticsearch 未授权'))) {
      log('${_ts()} [SUCCESS] 目标: $host:$port');
      log('  漏洞类型: poc-yaml-elasticsearch-unauth');
      log('  详细信息:');
      log('        Elasticsearch 未授权访问');
    }
    if (r.vulnerabilities.any((v) => v.contains('Memcached 未授权'))) {
      log('${_ts()} [SUCCESS] 目标: $host:$port');
      log('  漏洞类型: poc-yaml-memcached-unauth');
      log('  详细信息:');
      log('        Memcached 未授权访问');
    }
    if (r.vulnerabilities.any((v) => v.contains('MongoDB'))) {
      log('${_ts()} [SUCCESS] 目标: $host:$port');
      log('  漏洞类型: poc-yaml-mongodb-unauth');
      log('  详细信息:');
      log('        MongoDB 默认无认证');
    }
  }

  Future<void> _runBrute(
    String host,
    int port,
    ServiceProbeResult r,
    void Function(String) log,
  ) async {
    final brute = BruteService(timeout: const Duration(seconds: 5));
    if (r.service == 'Redis') {
      final pwd = await brute.bruteRedis(host, port, ['', 'redis', '123456', 'root', 'password']);
      if (pwd != null) {
        log('${_ts()} [SUCCESS] [$host:$port] Redis 爆破成功: ${pwd.isEmpty ? "(空)" : pwd}');
        log('${_ts()} [SUCCESS] 目标: $host:$port');
        log('  漏洞类型: poc-yaml-redis-weak-password');
        log('  详细信息:');
        log('        params:[{password ${pwd.isEmpty ? "(空)" : pwd}}]');
      }
    } else if (r.service == 'SSH') {
      final creds = [
        (user: 'root', pwd: 'root'),
        (user: 'root', pwd: '123456'),
        (user: 'root', pwd: ''),
        (user: 'admin', pwd: 'admin'),
        (user: 'root', pwd: 'password'),
      ];
      final c = await brute.bruteSsh(host, port, creds);
      if (c != null) {
        log('${_ts()} [SUCCESS] [$host:$port] SSH 爆破成功: ${c.user}/${c.pwd.isEmpty ? "(空)" : c.pwd}');
        log('${_ts()} [SUCCESS] 目标: $host:$port');
        log('  漏洞类型: poc-yaml-ssh-weak-password');
        log('  详细信息:');
        log('        params:[{user ${c.user}} {password ${c.pwd.isEmpty ? "(空)" : c.pwd}}]');
      }
    } else if (r.service == 'FTP') {
      final creds = [
        (user: 'anonymous', pwd: 'anonymous@'),
        (user: 'ftp', pwd: 'ftp'),
        (user: 'admin', pwd: 'admin'),
        (user: 'root', pwd: 'root'),
      ];
      final c = await brute.bruteFtp(host, port, creds);
      if (c != null) {
        log('${_ts()} [SUCCESS] [$host:$port] FTP 爆破成功: ${c.user}/${c.pwd}');
        log('${_ts()} [SUCCESS] 目标: $host:$port');
        log('  漏洞类型: poc-yaml-ftp-weak-password');
        log('  详细信息:');
        log('        params:[{user ${c.user}} {password ${c.pwd}}]');
      }
    } else if (r.service == 'MySQL') {
      final creds = [
        (user: 'root', pwd: 'root'),
        (user: 'root', pwd: '123456'),
        (user: 'root', pwd: ''),
        (user: 'root', pwd: 'password'),
      ];
      final c = await brute.bruteMysql(host, port, creds);
      if (c != null) {
        log('${_ts()} [SUCCESS] [$host:$port] MySQL 爆破成功: ${c.user}/${c.pwd.isEmpty ? "(空)" : c.pwd}');
        log('${_ts()} [SUCCESS] 目标: $host:$port');
        log('  漏洞类型: poc-yaml-mysql-weak-password');
        log('  详细信息:');
        log('        params:[{user ${c.user}} {password ${c.pwd.isEmpty ? "(空)" : c.pwd}}]');
      }
    }
  }

  /// 启动后台扫描，返回 sessionId
  Future<int> startScan({
    required int projectId,
    required String target,
    String portsStr = '1-10000',
    int timeoutSec = 3,
    int threads = 200,
    bool skipPing = true,
    bool enableProbe = true,
    bool enableNetbios = false,
    bool enableMs17010 = false,
    bool enableBrute = false,
  }) async {
    final config = jsonEncode({
      'ports': portsStr,
      'timeout': timeoutSec.toString(),
      'threads': threads.toString(),
    });
    final sessionId = await _scanSession.createSession(
      projectId: projectId,
      scanType: 'port_scan',
      target: target,
      configJson: config,
    );
    _cancelFlags[sessionId] = false;
    unawaited(_runScan(
      sessionId: sessionId,
      target: target,
      portsStr: portsStr,
      timeoutSec: timeoutSec,
      threads: threads,
      skipPing: skipPing,
      enableProbe: enableProbe,
      enableNetbios: enableNetbios,
      enableMs17010: enableMs17010,
      enableBrute: enableBrute,
    ));
    return sessionId;
  }

  Future<void> _runScan({
    required int sessionId,
    required String target,
    required String portsStr,
    required int timeoutSec,
    required int threads,
    required bool skipPing,
    required bool enableProbe,
    required bool enableNetbios,
    required bool enableMs17010,
    required bool enableBrute,
  }) async {
    void log(String line) {
      _scanSession.appendLog(sessionId, line);
      if (!_logController.isClosed) _logController.add(PortScanLogEvent(sessionId: sessionId, line: line));
    }

    try {
      log('Fscan Version: 2.0.0');
      log('');
      log('${_ts()} [INFO] 暴力破解线程数: 1');
      log('${_ts()} [INFO] 开始信息扫描');

      final hosts = await PortScanService.parseTargets(target);
      if (hosts.isEmpty) {
        log('${_ts()} [!] 无法解析目标');
        return;
      }
      log('${_ts()} [INFO] 最终有效主机数量: ${hosts.length}');
      log('${_ts()} [INFO] 开始主机扫描');

      final ports = PortScanService.parsePorts(portsStr);
      log('${_ts()} [INFO] 有效端口数量: ${ports.length}');

      final svc = FscanService(
        timeout: Duration(seconds: timeoutSec.clamp(1, 30)),
        threads: threads.clamp(10, 1000),
        skipPing: skipPing,
        enableProbe: enableProbe,
        enableNetbios: enableNetbios,
        enableMs17010: enableMs17010,
        enableWebTitle: true,
        enableWebPoc: true,
      );

      var openCount = 0;
      await svc.run(
        hosts: hosts,
        ports: ports,
        isCancelled: () => _cancelFlags[sessionId] ?? false,
        onLog: (line) => log('${_ts()} $line'),
        onOpen: (host, port) => openCount++,
        onProbe: (host, port, result) {
          if (result is ServiceProbeResult) {
            final r = result;
            final svcTag = _serviceTag(r.service);
            // Include fingerprint detail (version, title, etc.) if available
            final fp = r.fingerprint;
            final fpSuffix = fp.isNotEmpty && !fp.startsWith('(')
                ? ' | $fp'
                : '';
            log('${_ts()} [SUCCESS] 服务识别 $host:$port => $svcTag$fpSuffix');
            for (final v in r.vulnerabilities) {
              log('${_ts()} [!] [$host:$port] $v');
            }
            _appendServicePocs(host, port, r, log);
            if (enableBrute) unawaited(_runBrute(host, port, r, log));
          }
        },
      );

      log('${_ts()} [INFO] 存活端口数量: $openCount');
    } catch (e) {
      log('[!] 异常: $e');
    } finally {
      final cancelled = _cancelFlags[sessionId] == true;
      _cancelFlags.remove(sessionId);
      await _scanSession.finishSession(
        sessionId,
        status: cancelled ? 'cancelled' : 'completed',
      );
    }
  }

  void cancelSession(int sessionId) {
    _cancelFlags[sessionId] = true;
  }

  void dispose() {
    _logController.close();
  }
}

class PortScanLogEvent {
  final int sessionId;
  final String line;

  PortScanLogEvent({required this.sessionId, required this.line});
}
