import 'dart:convert';
import 'dart:io';

import 'banner_fingerprint.dart';

class _Fp {
  final String name;
  final RegExp pattern;
  const _Fp(this.name, this.pattern);
}

/// 服务探测结果：服务名、指纹、漏洞
class ServiceProbeResult {
  final String service;
  final String? version;
  final String fingerprint;
  final List<String> vulnerabilities;

  ServiceProbeResult({
    required this.service,
    this.version,
    required this.fingerprint,
    this.vulnerabilities = const [],
  });
}

/// 服务探测：识别开放端口上的服务、指纹、默认口令漏洞
class ServiceProbeService {
  final Duration timeout;

  ServiceProbeService({this.timeout = const Duration(seconds: 5)});

  /// 根据端口推测服务类型（常见端口映射）
  static String _guessServiceByPort(int port) {
    const map = {
      21: 'FTP',
      22: 'SSH',
      23: 'Telnet',
      25: 'SMTP',
      53: 'DNS',
      80: 'HTTP',
      81: 'HTTP',
      88: 'Kerberos',
      110: 'POP3',
      135: 'MSRPC',
      139: 'NetBIOS',
      143: 'IMAP',
      443: 'HTTPS',
      445: 'SMB',
      993: 'IMAPS',
      995: 'POP3S',
      1433: 'MSSQL',
      1521: 'Oracle',
      3000: 'HTTP',
      3306: 'MySQL',
      4000: 'HTTP',
      5000: 'HTTP',
      5432: 'PostgreSQL',
      5672: 'RabbitMQ',
      6379: 'Redis',
      7000: 'HTTP',
      7001: 'WebLogic',
      8000: 'HTTP',
      8080: 'HTTP',
      8081: 'HTTP',
      8082: 'HTTP',
      8083: 'HTTP',
      8084: 'HTTP',
      8085: 'HTTP',
      8086: 'HTTP',
      8087: 'HTTP',
      8088: 'HTTP',
      888: 'HTTP',
      8089: 'Splunk',
      8090: 'HTTP',
      8443: 'HTTPS',
      8888: 'HTTP',
      9000: 'HTTP',
      9443: 'HTTPS',
      9090: 'Prometheus',
      9100: 'Prometheus',
      9200: 'Elasticsearch',
      11211: 'Memcached',
      27017: 'MongoDB',
    };
    return map[port] ?? 'TCP';
  }

  /// 探测服务：返回服务名、指纹、漏洞
  Future<ServiceProbeResult> probe(String host, int port) async {
    final guessed = _guessServiceByPort(port);

    try {
      // HTTP/HTTPS（常见 Web 端口）
      if (port == 80 || port == 81 || port == 443 || port == 888 || port == 3000 || port == 4000 ||
          port == 5000 || port == 7000 || port == 8000 || port == 8080 || port == 8081 ||
          port == 8082 || port == 8083 || port == 8084 || port == 8085 || port == 8086 ||
          port == 8087 || port == 8088 || port == 8089 || port == 8090 || port == 8443 ||
          port == 8888 || port == 9000 || port == 9090 || port == 9100 || port == 9443) {
        return await _probeHttp(host, port);
      }
      // Redis
      if (port == 6379) return await _probeRedis(host, port);
      // FTP
      if (port == 21) return await _probeFtp(host, port);
      // MySQL
      if (port == 3306) return await _probeMysql(host, port);
      // SSH
      if (port == 22) return await _probeSsh(host, port);
      // Memcached
      if (port == 11211) return await _probeMemcached(host, port);
      // MongoDB
      if (port == 27017) return await _probeMongodb(host, port);
      // Elasticsearch
      if (port == 9200) return await _probeElasticsearch(host, port);
      // PostgreSQL
      if (port == 5432) return await _probePostgres(host, port);
      // MSSQL
      if (port == 1433) return await _probeMssql(host, port);

      // 通用 banner 抓取
      return await _probeBanner(host, port, guessed);
    } catch (_) {
      return ServiceProbeResult(
        service: guessed,
        fingerprint: '(探测超时或失败)',
        vulnerabilities: [],
      );
    }
  }

  // HTTPS 端口集合（非 80 的 TLS 端口）
  static const _httpsPorts = {443, 8443, 9443};

  Future<ServiceProbeResult> _probeHttp(String host, int port) async {
    final scheme = _httpsPorts.contains(port) ? 'https' : 'http';
    final base = '$scheme://$host:$port';
    final uri = Uri.parse('$base/');
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = timeout
        ..badCertificateCallback = (_, __, _) => true;
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'Mozilla/5.0 (compatible; MatrixScanner/1.0)');
      final res = await req.close().timeout(timeout);
      final body = await res.transform(utf8.decoder).join();
      final server = res.headers.value('server') ?? '';
      final poweredBy = res.headers.value('x-powered-by') ?? '';
      final titleMatch = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(body);
      final title = titleMatch?.group(1)?.trim().replaceAll(RegExp(r'\s+'), ' ').substring(0, 50) ?? '';

      // 使用最终落地 URL（跟随重定向后）进行 CMS 识别，避免根路径无特征的问题
      final finalUrl = res.redirects.isNotEmpty
          ? res.redirects.last.location.toString()
          : uri.toString();
      String? cms = _detectCms(body, res.headers, finalUrl);

      // 根路径未识别出 CMS 时，探测常见子路径（如禅道安装在 /zentaopms/www/）
      String? zentaoBase;
      if (cms == null) {
        const zentaoPaths = [
          '/zentaopms/www',
          '/zentao',
          '/zentaopms',
        ];
        for (final p in zentaoPaths) {
          try {
            final subUri = Uri.parse('$base$p/index.php?m=user&f=login');
            final req2 = await client.getUrl(subUri);
            req2.headers.set('User-Agent', 'Mozilla/5.0 (compatible; MatrixScanner/1.0)');
            final res2 = await req2.close().timeout(timeout);
            final body2 = await res2.transform(utf8.decoder).join();
            if (_detectCms(body2, res2.headers, subUri.toString()) == 'Zentao') {
              cms = 'Zentao';
              zentaoBase = '$base$p';
              break;
            }
          } catch (_) {}
        }
      }

      final parts = <String>[];
      if (server.isNotEmpty) parts.add('Server: $server');
      if (poweredBy.isNotEmpty) parts.add('X-Powered-By: $poweredBy');
      if (cms != null) parts.add('CMS: $cms');
      if (zentaoBase != null) parts.add('ZentaoBase: $zentaoBase');
      if (title.isNotEmpty) parts.add('Title: $title');
      parts.add('Status: ${res.statusCode}');

      return ServiceProbeResult(
        service: 'HTTP',
        version: server.isNotEmpty ? _extractVersion(server) : null,
        fingerprint: parts.join(' | '),
        vulnerabilities: [],
      );
    } catch (_) {
      return ServiceProbeResult(service: 'HTTP', fingerprint: '(连接失败)', vulnerabilities: []);
    } finally {
      client?.close(force: true);
    }
  }

  String? _extractVersion(String s) {
    final m = RegExp(r'[\d.]+').firstMatch(s);
    return m?.group(0);
  }

  /// Web 指纹识别：CMS、OA 框架
  String? _detectCms(String body, HttpHeaders headers, String url) {
    final lower = body.toLowerCase();
    final headerStr = headers.toString().toLowerCase();
    final combined = '$lower $headerStr $url';

    final fingerprints = [
      // ThinkPHP：匹配明显的框架特征，避免单纯因 /index.php 误报
      _Fp('ThinkPHP', RegExp(
        r'thinkphp|think-php|tp3\.0|tp5\.0|tp6\.0|/thinkphp|index\.php\?s=/',
        caseSensitive: false,
      )),
      // Zentao：多维度识别（中文名、路径、Cookie、JS 变量）
      _Fp('Zentao', RegExp(
        r'zentaosid=|zentaopms|禅道|window\.zentao|/zentao/',
        caseSensitive: false,
      )),
      _Fp('Drupal', RegExp(r'drupal|sites/all|sites/default')),
      _Fp('WordPress', RegExp(r'wp-content|wp-includes|wordpress')),
      _Fp('Joomla', RegExp(r'joomla|/media/jui/')),
      _Fp('Discuz', RegExp(r'discuz|uc_server|static/image')),
      _Fp('Dedecms', RegExp(r'dedecms|powered by dedecms')),
      _Fp('PhpMyAdmin', RegExp(r'phpmyadmin|pma_')),
      _Fp('Shiro', RegExp(r'rememberme=deleteMe|shiro')),
      _Fp('Struts2', RegExp(r'struts|ognl')),
      _Fp('WebLogic', RegExp(r'weblogic|bea-weblogic')),
      _Fp('Tomcat', RegExp(r'tomcat|apache-coyote')),
      _Fp('致远OA', RegExp(r'seeyon|致远|A6')),
      _Fp('泛微OA', RegExp(r'weaver|泛微|e-cology')),
      _Fp('通达OA', RegExp(r'tongda|通达|office anywhere')),
      _Fp('用友', RegExp(r'yonyou|用友|ufida')),
      _Fp('蓝凌', RegExp(r'landray|蓝凌')),
      _Fp('帆软', RegExp(r'finereport|帆软')),
      _Fp('Spring', RegExp(r'spring|springframework')),
      _Fp('Laravel', RegExp(r'laravel|laravel_session')),
    ];

    for (final fp in fingerprints) {
      if (fp.pattern.hasMatch(combined)) return fp.name;
    }
    return null;
  }

  Future<ServiceProbeResult> _probeRedis(String host, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.write('INFO\r\n');
      await socket.flush();
      final data = await socket.map((b) => utf8.decode(b)).join();
      await socket.close();

      String? version;
      final versionMatch = RegExp(r'redis_version:([^\r\n]+)').firstMatch(data);
      if (versionMatch != null) version = versionMatch.group(1)?.trim();

      // Redis 无 auth 时 INFO 直接返回数据
      final hasAuth = data.contains('NOAUTH') || data.contains('invalid password');
      final vulns = <String>[];
      if (!hasAuth && data.contains('redis_version')) {
        vulns.add('Redis 未授权访问');
        if (await _redisCanWrite(host, port)) {
          vulns.add('Redis 可写公钥/计划任务');
        }
      }

      return ServiceProbeResult(
        service: 'Redis',
        version: version,
        fingerprint: version != null ? 'Redis $version' : 'Redis',
        vulnerabilities: vulns,
      );
    } catch (_) {
      return ServiceProbeResult(service: 'Redis', fingerprint: '(探测失败)', vulnerabilities: []);
    } finally {
      await socket?.close();
    }
  }

  static String _resp(String cmd) {
    final parts = cmd.split(' ');
    var s = '*${parts.length}\r\n';
    for (final p in parts) {
      s += '\$${p.length}\r\n$p\r\n';
    }
    return s;
  }

  Future<bool> _redisCanWrite(String host, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.write(_resp('CONFIG SET dir /tmp/'));
      await socket.flush();
      final r = await socket.map((b) => utf8.decode(b)).first;
      await socket.close();
      return !r.contains('ERR');
    } catch (_) {
      return false;
    } finally {
      await socket?.close();
    }
  }

  Future<ServiceProbeResult> _probeFtp(String host, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      final banner = await socket.map((b) => utf8.decode(b)).first;
      await socket.close();

      final version = _extractVersion(banner);
      final vulns = <String>[];

      // 尝试匿名登录
      socket = await Socket.connect(host, port, timeout: timeout);
      final stream = socket.map((b) => utf8.decode(b)).transform(const LineSplitter());
      final first = await stream.first;
      if (!first.startsWith('220')) {
        await socket.close();
        return ServiceProbeResult(
          service: 'FTP',
          version: version,
          fingerprint: banner.trim().substring(0, banner.length.clamp(0, 80)),
          vulnerabilities: vulns,
        );
      }
      socket.writeln('USER anonymous');
      await socket.flush();
      await stream.first;
      socket.writeln('PASS anonymous@');
      await socket.flush();
      final passRes = await stream.first;
      await socket.close();

      if (passRes.startsWith('230')) {
        vulns.add('FTP 匿名登录 (anonymous/anonymous)');
      }

      return ServiceProbeResult(
        service: 'FTP',
        version: version,
        fingerprint: banner.trim().substring(0, banner.length.clamp(0, 80)),
        vulnerabilities: vulns,
      );
    } catch (_) {
      return ServiceProbeResult(service: 'FTP', fingerprint: '(探测失败)', vulnerabilities: []);
    } finally {
      await socket?.close();
    }
  }

  Future<ServiceProbeResult> _probeMysql(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      final bytes = await socket.first as List<int>;
      await socket.close();

      if (bytes.length < 10) {
        return ServiceProbeResult(service: 'MySQL', fingerprint: '(数据过短)', vulnerabilities: []);
      }
      // MySQL greeting: 3B len, 1B seq, 1B proto, then version string until NUL
      final versionStart = 5;
      final nulIdx = bytes.indexOf(0, versionStart);
      final version = nulIdx > versionStart
          ? String.fromCharCodes(bytes.sublist(versionStart, nulIdx))
          : null;

      return ServiceProbeResult(
        service: 'MySQL',
        version: version,
        fingerprint: version != null ? 'MySQL $version' : 'MySQL',
        vulnerabilities: [], // 仅爆破成功时报告
      );
    } catch (_) {
      return ServiceProbeResult(service: 'MySQL', fingerprint: '(探测失败)', vulnerabilities: []);
    }
  }

  Future<ServiceProbeResult> _probeSsh(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      final banner = await socket.map((b) => utf8.decode(b)).transform(const LineSplitter()).first;
      await socket.close();

      // SSH-2.0-OpenSSH_8.2
      final m = RegExp(r'SSH-2\.0-([^\s\r\n]+)').firstMatch(banner);
      final version = m?.group(1);

      return ServiceProbeResult(
        service: 'SSH',
        version: version,
        fingerprint: banner.trim().substring(0, banner.length.clamp(0, 80)),
        vulnerabilities: [], // 仅爆破成功时报告，不预填「风险」误报
      );
    } catch (_) {
      return ServiceProbeResult(service: 'SSH', fingerprint: '(探测失败)', vulnerabilities: []);
    }
  }

  Future<ServiceProbeResult> _probeMemcached(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.write('stats\r\n');
      await socket.flush();
      final data = await socket.map((b) => utf8.decode(b)).first;
      await socket.close();

      final vulns = <String>[];
      if (data.contains('STAT') && !data.contains('ERROR')) {
        vulns.add('Memcached 未授权访问');
      }

      return ServiceProbeResult(
        service: 'Memcached',
        fingerprint: 'Memcached (stats 可读)',
        vulnerabilities: vulns,
      );
    } catch (_) {
      return ServiceProbeResult(service: 'Memcached', fingerprint: '(探测失败)', vulnerabilities: []);
    }
  }

  Future<ServiceProbeResult> _probeMongodb(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      // MongoDB wire protocol: first message is client request
      // We can send isMaster and parse response, or just read banner
      final _ = await socket.first;
      await socket.close();

      return ServiceProbeResult(
        service: 'MongoDB',
        fingerprint: 'MongoDB',
        vulnerabilities: [], // MongoDB 需实际尝试命令才能确认未授权
      );
    } catch (_) {
      return ServiceProbeResult(service: 'MongoDB', fingerprint: '(探测失败)', vulnerabilities: []);
    }
  }

  Future<ServiceProbeResult> _probeElasticsearch(String host, int port) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = timeout
        ..badCertificateCallback = (_, __, _) => true;
      final uri = Uri.parse('http://$host:$port/');
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(timeout);
      final body = await res.transform(utf8.decoder).join();

      String? version;
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final ver = json['version']?['number'];
        if (ver != null) version = ver.toString();
      } catch (_) {}

      final vulns = <String>[];
      if (res.statusCode == 200) {
        try {
          final j = jsonDecode(body) as Map<String, dynamic>;
          if (j.containsKey('cluster_name') || j.containsKey('version')) {
            vulns.add('Elasticsearch 未授权访问');
          }
        } catch (_) {}
      }

      return ServiceProbeResult(
        service: 'Elasticsearch',
        version: version,
        fingerprint: version != null ? 'Elasticsearch $version' : 'Elasticsearch',
        vulnerabilities: vulns,
      );
    } catch (_) {
      return ServiceProbeResult(service: 'Elasticsearch', fingerprint: '(探测失败)', vulnerabilities: []);
    } finally {
      client?.close(force: true);
    }
  }

  Future<ServiceProbeResult> _probePostgres(String host, int port) async {
    // PostgreSQL startup message: length(4) + protocol(4=196608) + "user\0postgres\0database\0postgres\0\0"
    // Server responds with 'R'=auth required or 'E'=error
    final user = 'postgres';
    final userBytes = [...user.codeUnits, 0];
    final db = 'postgres';
    final dbBytes = [...db.codeUnits, 0];
    final payload = <int>[
      0x00, 0x03, 0x00, 0x00, // protocol 3.0
      ...utf8.encode('user'), 0x00, ...userBytes,
      ...utf8.encode('database'), 0x00, ...dbBytes,
      0x00, // terminator
    ];
    final len = payload.length + 4;
    final startup = <int>[
      (len >> 24) & 0xFF, (len >> 16) & 0xFF,
      (len >> 8) & 0xFF, len & 0xFF,
      ...payload,
    ];
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(startup);
      await socket.flush();
      List<int> bytes = [];
      try {
        bytes = await socket.first.timeout(const Duration(milliseconds: 1500)) as List<int>;
      } catch (_) {}
      await socket.close();

      // Response: 'R'=AuthRequest (any auth type = confirmed PostgreSQL)
      //           'E'=Error (also confirmed)
      //           'N'=NoData
      if (bytes.isNotEmpty) {
        final first = bytes[0];
        if (first == 0x52 /* 'R' */ || first == 0x45 /* 'E' */ || first == 0x4E /* 'N' */) {
          return ServiceProbeResult(
            service: 'PostgreSQL',
            fingerprint: 'PostgreSQL',
            vulnerabilities: [],
          );
        }
      }
      return ServiceProbeResult(
        service: 'PostgreSQL',
        fingerprint: bytes.isNotEmpty ? 'PostgreSQL' : 'PostgreSQL (仅端口开放)',
        vulnerabilities: [],
      );
    } catch (_) {
      return ServiceProbeResult(service: 'PostgreSQL', fingerprint: '(探测失败)', vulnerabilities: []);
    }
  }

  Future<ServiceProbeResult> _probeMssql(String host, int port) async {
    // TDS 7.0 PRELOGIN 包：触发 SQL Server 响应版本信息
    // header: type=0x12(prelogin) status=0x01 length=0x002F call_id=0x0000 window=0x0000
    // options: VERSION(0) ENCRYPTION(1) INSTOPT(2) THREADID(3) MARS(4) TERMINATOR
    final prelogin = <int>[
      0x12, 0x01, 0x00, 0x2F, 0x00, 0x00, 0x01, 0x00, // TDS header
      0x00, 0x00, 0x1A, 0x00, 0x06, // VERSION offset=0x001A, len=6
      0x01, 0x00, 0x20, 0x00, 0x01, // ENCRYPTION offset=0x0020, len=1
      0x02, 0x00, 0x21, 0x00, 0x01, // INSTOPT offset=0x0021, len=1
      0x03, 0x00, 0x22, 0x00, 0x04, // THREADID offset=0x0022, len=4
      0x04, 0x00, 0x26, 0x00, 0x01, // MARS offset=0x0026, len=1
      0xFF,                          // TERMINATOR
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // VERSION (0.0.0.0 sub=0)
      0x02,                          // ENCRYPTION = NOT_SUP
      0x00,                          // INSTOPT = empty
      0x00, 0x00, 0x00, 0x00,        // THREADID
      0x00,                          // MARS = OFF
    ];
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(prelogin);
      await socket.flush();
      List<int> bytes = [];
      try {
        bytes = await socket.first.timeout(const Duration(milliseconds: 1500)) as List<int>;
      } catch (_) {}
      await socket.close();

      // TDS prelogin response: header 8 bytes, then version at offset indicated by option
      // Simple approach: scan for version-like byte sequence (major.minor.build.sub)
      String? version;
      if (bytes.length >= 14) {
        // Skip 8-byte TDS header; look for 6-byte VERSION field in prelogin response
        // Response options list has same structure; version is first option value
        // Simpler: just scan for 4-byte version block (major, minor, build-hi, build-lo)
        for (var i = 8; i + 5 < bytes.length; i++) {
          final major = bytes[i];
          final minor = bytes[i + 1];
          final buildHi = bytes[i + 2];
          final buildLo = bytes[i + 3];
          if (major >= 9 && major <= 16 && minor == 0) {
            final build = (buildHi << 8) | buildLo;
            version = '$major.$minor.$build';
            break;
          }
        }
      }
      // Fallback: printable string scan
      if (version == null && bytes.isNotEmpty) {
        final str = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
        final m = RegExp(r'Microsoft SQL Server').firstMatch(str);
        if (m != null) version = 'MSSQL';
      }
      return ServiceProbeResult(
        service: 'MSSQL',
        version: version,
        fingerprint: version != null ? 'MSSQL $version' : (bytes.isNotEmpty ? 'MSSQL' : 'MSSQL (仅端口开放)'),
        vulnerabilities: [],
      );
    } catch (_) {
      return ServiceProbeResult(service: 'MSSQL', fingerprint: '(探测失败)', vulnerabilities: []);
    }
  }

  Future<ServiceProbeResult> _probeBanner(String host, int port, String guessed) async {
    // 使用 BannerFingerprintEngine 进行多轮主动/被动探测
    // 覆盖 150+ 条服务规则，对应 fscan nmap-service-probes 行为
    final engine = BannerFingerprintEngine(timeout: timeout);
    return engine.identify(host, port, guessed);
  }
}
