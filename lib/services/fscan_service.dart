import 'dart:io';

import 'icmp_service.dart';
import 'ms17010_service.dart';
import 'netbios_service.dart';
import 'port_scan_service.dart';
import 'service_probe_service.dart';
import 'web_poc_service.dart';
import 'web_title_service.dart';

/// fscan 全功能编排：ICMP、端口扫描、服务探测、webtitle、webpoc、爆破、NetBIOS、MS17-010、结果导出
class FscanService {
  final Duration timeout;
  final int threads;
  final bool skipPing;
  final bool enableProbe;
  final bool enableNetbios;
  final bool enableMs17010;
  final bool enableWebTitle;
  final bool enableWebPoc;

  FscanService({
    this.timeout = const Duration(seconds: 3),
    this.threads = 200,
    this.skipPing = false,
    this.enableProbe = true,
    this.enableNetbios = false,
    this.enableMs17010 = false,
    this.enableWebTitle = true,
    this.enableWebPoc = true,
  });

  /// 执行完整扫描
  Future<FscanResult> run({
    required List<String> hosts,
    required List<int> ports,
    required bool Function() isCancelled,
    void Function(String)? onLog,
    void Function(String host, int port)? onOpen,
    void Function(String host, int port, dynamic probeResult)? onProbe,
  }) async {
    final result = FscanResult();

    var targets = hosts;
    if (!skipPing && hosts.length > 1) {
      onLog?.call('[*] ICMP 存活探测...');
      final icmp = IcmpService(timeout: timeout);
      targets = await icmp.filterAlive(
        hosts,
        isCancelled: isCancelled,
        onProgress: (d, t) => onLog?.call('[*] 存活探测 $d/$t'),
      );
      onLog?.call('[*] 存活主机: ${targets.length}');
    }

    final webUrls = <String>[];
    void Function(String host, int port, dynamic probeResult)? wrappedProbe;
    if (onProbe != null) {
      wrappedProbe = (host, port, probeResult) {
        onProbe(host, port, probeResult);
        if (probeResult is ServiceProbeResult &&
            (probeResult.service == 'HTTP' || probeResult.service == 'HTTPS')) {
          final scheme = port == 443 ? 'https' : 'http';
          webUrls.add('$scheme://$host:$port');
        }
      };
    }

    final portSvc = PortScanService(
      timeout: timeout,
      threads: threads,
      enableServiceProbe: enableProbe,
    );

    await portSvc.scan(
      hosts: targets,
      ports: ports,
      isCancelled: isCancelled,
      onLog: onLog,
      onOpen: onOpen,
      onProbe: wrappedProbe ?? onProbe,
    );

    // Web 标题 + POC 漏洞扫描（仅对 HTTP 服务）
    if ((enableWebTitle || enableWebPoc) && webUrls.isNotEmpty && !isCancelled()) {
      onLog?.call('[INFO] 开始漏洞扫描');
      onLog?.call('[INFO] 加载的插件: webpoc, webtitle');
      final webTimeout = Duration(seconds: timeout.inSeconds.clamp(5, 15));
      for (final url in webUrls) {
        if (isCancelled()) break;
        try {
          if (enableWebTitle) {
            final titleSvc = WebTitleService(timeout: webTimeout);
            final r = await titleSvc.probe(url);
            onLog?.call(WebTitleService.formatResult(r));
          }
          if (enableWebPoc) {
            final pocSvc = WebPocService(timeout: webTimeout);
            final pocResults = await pocSvc.scan(url);
            for (final line in WebPocService.formatResults(pocResults)) {
              onLog?.call(line);
            }
          }
        } catch (_) {}
      }
      onLog?.call('[INFO] 扫描已完成: ${webUrls.length}/${webUrls.length}');
    }

    // NetBIOS (139)
    if (enableNetbios && ports.contains(139) && !isCancelled()) {
      for (final h in targets) {
        if (isCancelled()) break;
        try {
          final nb = NetbiosService(timeout: timeout);
          final r = await nb.probe(h);
          if (r != null) {
            onLog?.call('[+] NetBIOS $h ${r.name}${r.isDomainController ? " [DC]" : ""}');
            result.netbios.add(r);
          }
        } catch (_) {}
      }
    }

    // MS17-010 (445)
    if (enableMs17010 && ports.contains(445) && !isCancelled()) {
      for (final h in targets) {
        if (isCancelled()) break;
        try {
          final ms = Ms17010Service(timeout: timeout);
          final r = await ms.check(h);
          if (r.isVulnerable) {
            final msg = r.hasDoublePulsar
                ? '[!] MS17-010+DOUBLEPULSAR: $h${r.os != null ? " [${r.os}]" : ""}'
                : '[!] MS17-010: $h${r.os != null ? " [${r.os}]" : ""}';
            onLog?.call(msg);
            result.ms17010.add('$h:445');
          } else if (r.os != null) {
            onLog?.call('[*] SMB 系统信息: $h [${r.os}]');
          }
        } catch (_) {}
      }
    }

    return result;
  }

  /// 导出结果到文件
  static Future<void> exportToFile(String path, String content) async {
    await File(path).writeAsString(content, flush: true);
  }
}

class FscanResult {
  final List<NetbiosResult> netbios = [];
  final List<String> ms17010 = [];
}
