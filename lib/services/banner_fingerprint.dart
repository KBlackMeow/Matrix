import 'dart:convert';

import '../core/net/net_client.dart';
import 'service_probe_service.dart';

/// Banner 指纹识别引擎（复刻 fscan nmap-service-probes）
///
/// 工作流程（对应 fscan PortFinger.go Identify()）：
///   1. 被动探测：连接后直接读取 banner（FTP/SSH/SMTP 等主动发送 banner）
///   2. HTTP 主动探测：发送 GET 请求（识别 Apache/Nginx/IIS/WebLogic 等）
///   3. 通用主动探测：发送 \r\n（触发部分 TCP 服务响应）
///   4. 特定协议探测：Redis PING、Memcached stats、VNC banner 等
///
/// 规则覆盖服务（~150 条正则）：
///   HTTP 服务器 15+、SSH、FTP、SMTP/POP3/IMAP、
///   MySQL/MariaDB/PostgreSQL/MSSQL/Oracle/Redis/Memcached/MongoDB/Elasticsearch/
///   RabbitMQ/Kafka/ZooKeeper/Cassandra/CouchDB/etcd/MinIO、
///   RDP、VNC、Telnet、LDAP、SMB、
///   Docker/Kubernetes/Consul、Prometheus/Grafana、
///   Jenkins/GitLab/Jira/SonarQube/Nexus/Splunk、
///   Modbus/Industrial
class BannerFingerprintEngine {
  final Duration timeout;
  final NetClient _netClient;

  BannerFingerprintEngine({this.timeout = const Duration(seconds: 3)})
      : _netClient = NetClient(
          connectTimeout: const Duration(milliseconds: 1500),
          readTimeout: const Duration(milliseconds: 1200),
        );

  // ── 主动探测字节 ────────────────────────────────────────────────────────

  // GET / HTTP/1.0\r\n\r\n
  static final _httpProbe = utf8.encode('GET / HTTP/1.0\r\n\r\n');
  // \r\n（触发部分服务）
  static final _genericProbe = utf8.encode('\r\n');
  // Redis PING
  static final _redisProbe = utf8.encode('*1\r\n\$4\r\nPING\r\n');
  // Memcached stats
  static final _memcachedProbe = utf8.encode('stats\r\n');

  // ── 指纹规则 ─────────────────────────────────────────────────────────────

  static final _rules = <_Rule>[
    // ══ HTTP 服务器 ════════════════════════════════════════════════════════
    _Rule('Apache httpd',   r'Server: Apache/(\S+)',              vg: 1),
    _Rule('Apache httpd',   r'Apache/(\S+) \(',                   vg: 1),
    _Rule('Nginx',          r'Server: nginx/(\S+)',               vg: 1),
    _Rule('Nginx',          r'Server: nginx\b'),
    _Rule('OpenResty',      r'Server: openresty/(\S+)',           vg: 1),
    _Rule('Tengine',        r'Server: Tengine/(\S+)',             vg: 1),
    _Rule('Microsoft IIS',  r'Server: Microsoft-IIS/(\S+)',       vg: 1),
    _Rule('WebLogic',       r'Server: WebLogic Server[/ ](\S+)', vg: 1),
    _Rule('WebLogic',       r'BEA-WebLogic|WebLogic Server'),
    _Rule('JBoss',          r'JBoss[- ](\S+)',                    vg: 1),
    _Rule('WildFly',        r'WildFly[/ ](\S+)',                  vg: 1),
    _Rule('Tomcat',         r'Apache-Coyote|Apache Tomcat/(\S+)', vg: 1),
    _Rule('Jetty',          r'Server: Jetty\(([^)]+)\)',          vg: 1),
    _Rule('Gunicorn',       r'Server: gunicorn/(\S+)',            vg: 1),
    _Rule('Caddy',          r'Server: Caddy'),
    _Rule('HAProxy',        r'Server: haproxy'),
    _Rule('Lighttpd',       r'Server: lighttpd/(\S+)',            vg: 1),
    _Rule('Kestrel',        r'Server: Kestrel'),
    _Rule('Cowboy',         r'Server: cowboy'),
    _Rule('Werkzeug',       r'Server: Werkzeug/(\S+)',            vg: 1),
    _Rule('Spring Boot',    r'X-Application-Context:|spring'),
    _Rule('HTTP',           r'^HTTP/\d'),

    // ══ SSH ════════════════════════════════════════════════════════════════
    _Rule('OpenSSH',        r'SSH-2\.0-OpenSSH[_-](\S+)',        vg: 1),
    _Rule('Dropbear SSH',   r'SSH-2\.0-dropbear[_-](\S+)',       vg: 1),
    _Rule('libssh',         r'SSH-2\.0-libssh[_-](\S+)',         vg: 1),
    _Rule('SSH',            r'SSH-2\.0-(\S+)',                    vg: 1),
    _Rule('SSH',            r'SSH-1\.99-(\S+)',                   vg: 1),

    // ══ FTP ════════════════════════════════════════════════════════════════
    _Rule('vsftpd',         r'220.*vsftpd (\S+)',                 vg: 1),
    _Rule('ProFTPD',        r'220.*ProFTPD (\S+)',                vg: 1),
    _Rule('FileZilla',      r'220.*FileZilla Server (\S+)',       vg: 1),
    _Rule('Pure-FTPd',      r'220.*Pure-FTPd'),
    _Rule('WU-FTPD',        r'220.*wu-(\S+)',                     vg: 1),
    _Rule('Microsoft FTP',  r'220.*Microsoft FTP Service'),
    _Rule('FTP',            r'^220 '),

    // ══ SMTP ═══════════════════════════════════════════════════════════════
    _Rule('Postfix',        r'220.*Postfix'),
    _Rule('Sendmail',       r'220.*Sendmail'),
    _Rule('Exchange',       r'220.*Microsoft ESMTP'),
    _Rule('Exim',           r'220.*Exim (\S+)',                   vg: 1),
    _Rule('qmail',          r'220.*qmail'),
    _Rule('SMTP',           r'^220 '),

    // ══ POP3 ═══════════════════════════════════════════════════════════════
    _Rule('Dovecot POP3',   r'\+OK.*Dovecot'),
    _Rule('POP3',           r'^\+OK'),

    // ══ IMAP ═══════════════════════════════════════════════════════════════
    _Rule('Dovecot IMAP',   r'\* OK.*Dovecot'),
    _Rule('IMAP',           r'^\* OK'),

    // ══ MySQL / MariaDB ════════════════════════════════════════════════════
    _Rule('MariaDB',        r'(\d+\.\d+\.\d+[^\x00]*MariaDB[^\x00]*)',  vg: 1),
    _Rule('MySQL',          r'(\d+\.\d+\.\d+[^\x00]{1,40})',            vg: 1),

    // ══ Redis ══════════════════════════════════════════════════════════════
    _Rule('Redis',          r'redis_version:(\S+)',               vg: 1),
    _Rule('Redis',          r'^\+PONG'),
    _Rule('Redis',          r'^-ERR|^-NOAUTH|^-WRONGPASS'),

    // ══ Memcached ══════════════════════════════════════════════════════════
    _Rule('Memcached',      r'^STAT version (\S+)',               vg: 1),
    _Rule('Memcached',      r'^STAT '),
    _Rule('Memcached',      r'^ERROR\r?\n'),

    // ══ MongoDB ════════════════════════════════════════════════════════════
    _Rule('MongoDB',        r'ismaster|isMaster|MongoDB'),

    // ══ Elasticsearch ══════════════════════════════════════════════════════
    _Rule('Elasticsearch',  r'"number"\s*:\s*"(\d[^"]+)".*elastic',     vg: 1),
    _Rule('Elasticsearch',  r'elasticsearch'),

    // ══ PostgreSQL ═════════════════════════════════════════════════════════
    _Rule('PostgreSQL',     r'PostgreSQL (\S+)',                  vg: 1),
    _Rule('PostgreSQL',     r'pg_hba\.conf|PostgreSQL'),

    // ══ MSSQL ══════════════════════════════════════════════════════════════
    _Rule('MSSQL',          r'Microsoft SQL Server (\d+)',        vg: 1),
    _Rule('MSSQL',          r'Microsoft SQL Server'),

    // ══ Oracle ═════════════════════════════════════════════════════════════
    _Rule('Oracle TNS',     r'CONNECT_DATA|TNS|Oracle'),

    // ══ RabbitMQ / AMQP ════════════════════════════════════════════════════
    _Rule('RabbitMQ',       r'RabbitMQ (\S+)',                    vg: 1),
    _Rule('AMQP',           r'^AMQP'),

    // ══ Kafka ══════════════════════════════════════════════════════════════
    _Rule('Kafka',          r'kafka\.common|apache\.kafka'),

    // ══ ZooKeeper ══════════════════════════════════════════════════════════
    _Rule('ZooKeeper',      r'Zookeeper version: (\S+)',          vg: 1),
    _Rule('ZooKeeper',      r'zxid=|Zookeeper'),

    // ══ Cassandra ══════════════════════════════════════════════════════════
    _Rule('Cassandra',      r'apache\.cassandra|Cassandra'),

    // ══ CouchDB ════════════════════════════════════════════════════════════
    _Rule('CouchDB',        r'Apache CouchDB/(\S+)',              vg: 1),
    _Rule('CouchDB',        r'couchdb'),

    // ══ etcd ═══════════════════════════════════════════════════════════════
    _Rule('etcd',           r'etcdserver|etcdcluster'),

    // ══ MinIO ══════════════════════════════════════════════════════════════
    _Rule('MinIO',          r'x-minio-deployment-id|MinIO'),

    // ══ VNC ════════════════════════════════════════════════════════════════
    _Rule('VNC',            r'^RFB (\d{3}\.\d{3})',              vg: 1),

    // ══ RDP ════════════════════════════════════════════════════════════════
    // RDP negotiation response: 0x03 0x00 (TPKT header)
    _Rule('RDP',            r'\x03\x00'),

    // ══ Telnet ═════════════════════════════════════════════════════════════
    _Rule('Telnet',         r'\xff[\xfb-\xfe]'),   // IAC DO/DONT/WILL/WONT

    // ══ LDAP ═══════════════════════════════════════════════════════════════
    _Rule('LDAP',           r'OpenLDAP|Active Directory|slapd'),

    // ══ SMB ════════════════════════════════════════════════════════════════
    _Rule('SMB',            r'\xffSMB|\xfeSMB'),

    // ══ Docker API ═════════════════════════════════════════════════════════
    _Rule('Docker API',     r'"ServerVersion"|"DockerRootDir"'),

    // ══ Kubernetes API ═════════════════════════════════════════════════════
    _Rule('Kubernetes API', r'"kind"\s*:\s*"Status"'),
    _Rule('Kubernetes API', r'kubernetes'),

    // ══ Consul ═════════════════════════════════════════════════════════════
    _Rule('Consul',         r'consul_'),

    // ══ Prometheus ═════════════════════════════════════════════════════════
    _Rule('Prometheus',     r'prometheus_build_info|go_gc_duration_seconds'),

    // ══ Grafana ════════════════════════════════════════════════════════════
    _Rule('Grafana',        r'x-grafana-id|grafana\.com'),

    // ══ Jenkins ════════════════════════════════════════════════════════════
    _Rule('Jenkins',        r'X-Jenkins: (\S+)',                  vg: 1),
    _Rule('Jenkins',        r'X-Jenkins|Jenkins'),

    // ══ GitLab ═════════════════════════════════════════════════════════════
    _Rule('GitLab',         r'X-GitLab-Meta|gitlab\.com'),

    // ══ Jira ═══════════════════════════════════════════════════════════════
    _Rule('Jira',           r'X-ASEN:|Atlassian|Jira'),

    // ══ SonarQube ══════════════════════════════════════════════════════════
    _Rule('SonarQube',      r'SonarQube'),

    // ══ Nexus ══════════════════════════════════════════════════════════════
    _Rule('Nexus',          r'Nexus Repository Manager'),

    // ══ Splunk ═════════════════════════════════════════════════════════════
    _Rule('Splunk',         r'splunkd|Splunk'),

    // ══ Industrial / Modbus ════════════════════════════════════════════════
    // Port 502: Modbus TCP response header (transaction ID + protocol ID 0x0000)
    _Rule('Modbus',         r'^\x00..\x00\x00'),
  ];

  // ── 主入口 ────────────────────────────────────────────────────────────────

  /// 对未知端口执行多轮探测，返回识别结果
  Future<ServiceProbeResult> identify(String host, int port, String guessed) async {
    // 1. 被动 banner（等待服务主动发送，适用 FTP/SSH/SMTP/Redis 等）
    final passive = await _readBanner(host, port);
    if (passive != null) {
      final r = _match(passive);
      if (r != null) return r;
    }

    // 2. HTTP 主动探测（Nginx/Apache/WebLogic 等需要请求才响应）
    final httpBanner = await _probeSend(host, port, _httpProbe);
    if (httpBanner != null) {
      final r = _match(httpBanner);
      if (r != null) return r;
    }

    // 3. Redis PING（Redis 不主动发 banner，需要命令触发）
    final redisBanner = await _probeSend(host, port, _redisProbe);
    if (redisBanner != null) {
      final r = _match(redisBanner);
      if (r != null) return r;
    }

    // 4. Memcached stats
    final memBanner = await _probeSend(host, port, _memcachedProbe);
    if (memBanner != null) {
      final r = _match(memBanner);
      if (r != null) return r;
    }

    // 5. Generic \r\n（部分服务需要换行触发）
    final genericBanner = await _probeSend(host, port, _genericProbe);
    if (genericBanner != null) {
      final r = _match(genericBanner);
      if (r != null) return r;
    }

    // 未识别：返回 banner 原文或猜测名称
    final raw = passive ?? httpBanner ?? '';
    final printable = raw
        .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'), '')
        .trim();
    return ServiceProbeResult(
      service: guessed,
      fingerprint: printable.isEmpty
          ? '(端口开放，无可识别 banner)'
          : printable.substring(0, printable.length.clamp(0, 120)),
      vulnerabilities: [],
    );
  }

  // ── 内部方法 ──────────────────────────────────────────────────────────────

  /// 被动读取初始 banner（不发送任何数据）
  Future<String?> _readBanner(String host, int port) async {
    SocketConnection? conn;
    try {
      conn = await _netClient.connectTcp(host, port);
      if (conn == null) return null;
      final banner = utf8.decode(await conn.read(maxBytes: 4096), allowMalformed: true);
      return banner.isEmpty ? null : banner;
    } catch (_) {
      return null;
    } finally {
      try {
        await conn?.close();
      } catch (_) {}
    }
  }

  /// 发送探测字节，读取响应
  Future<String?> _probeSend(String host, int port, List<int> probe) async {
    SocketConnection? conn;
    try {
      conn = await _netClient.connectTcp(host, port);
      if (conn == null) return null;
      await conn.write(probe);
      final banner = utf8.decode(await conn.read(maxBytes: 4096), allowMalformed: true);
      return banner.isEmpty ? null : banner;
    } catch (_) {
      return null;
    } finally {
      try {
        await conn?.close();
      } catch (_) {}
    }
  }

  /// 匹配规则，返回结果；无匹配返回 null
  static ServiceProbeResult? _match(String banner) {
    for (final rule in _rules) {
      final m = rule.pattern.firstMatch(banner);
      if (m == null) continue;
      String? version;
      if (rule.versionGroup != null && m.groupCount >= rule.versionGroup!) {
        version = m.group(rule.versionGroup!)?.trim();
        if (version != null && version.isEmpty) version = null;
      }
      return ServiceProbeResult(
        service: rule.service,
        version: version,
        fingerprint: rule.service + (version != null ? ' $version' : ''),
        vulnerabilities: [],
      );
    }
    return null;
  }
}

// ── 规则数据类 ────────────────────────────────────────────────────────────────

class _Rule {
  final String service;
  final RegExp pattern;
  final int? versionGroup;

  _Rule(this.service, String pattern, {int? vg, bool caseSensitive = false})
      : pattern = RegExp(pattern, caseSensitive: caseSensitive),
        versionGroup = vg;
}
