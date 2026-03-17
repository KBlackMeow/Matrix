import '../exp/shiro/shiro_crypto.dart';
import '../exp/shiro/shiro_exp_service.dart';
import '../exp/shiro/shiro_payload_repo.dart';
import '../exp/thinkphp/thinkphp_exp_service.dart';
import '../exp/zentao/zentao_exp_service.dart';

/// Web POC 漏洞扫描（webpoc）：ThinkPHP RCE、Shiro Key 等
/// 输出格式对齐 fscan
class WebPocService {
  final Duration timeout;
  final ShiroPayloadRepo _shiroRepo;

  WebPocService({
    this.timeout = const Duration(seconds: 10),
    ShiroPayloadRepo? shiroRepo,
  }) : _shiroRepo = shiroRepo ?? const ShiroPayloadRepo();

  /// 对单个 URL 执行 POC 扫描
  Future<List<WebPocResult>> scan(String url) async {
    final results = <WebPocResult>[];
    final baseUrl = url.trim().startsWith('http') ? url : 'http://$url';
    final baseUri = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';

    // 1. ThinkPHP 检测（先指纹确认，避免非 ThinkPHP 站点误报）
    try {
      final tpSvc = ThinkphpExpService(url: baseUri, timeout: timeout);
      final hasFingerprint = await tpSvc.isThinkPHP();
      final hasRce = await _quickThinkphpRceCheck(tpSvc);
      if (!hasFingerprint && !hasRce) {
        // 非 ThinkPHP，跳过
      } else {
        final tpResults = await tpSvc.checkAll();
        for (final r in tpResults) {
          if (r.vulnerable) {
            final pocName = _thinkphpToPocName(r.vulnName);
            results.add(WebPocResult(
              target: baseUri,
              pocType: pocName,
              pocName: r.vulnName,
              detail: r.detail,
              params: null,
            ));
          }
        }
      }
    } catch (_) {}

    // 2. Shiro Key 检测
    try {
      final shiroSvc = ShiroExpService(url: baseUri, timeout: timeout);
      final isShiro = await shiroSvc.checkIsShiro();
      if (isShiro) {
        final keys = await _shiroRepo.loadKeys();
        if (keys.isNotEmpty) {
          final payload = await _shiroRepo.loadPayload('shiro_payload_principal.b64');
          if (payload.isNotEmpty) {
            // 先尝试 CBC
            final keyCbc = await shiroSvc.bruteForceKey(
              candidateKeysBase64: keys,
              serializedPayload: payload,
              mode: ShiroEncryptionMode.cbc,
            );
            if (keyCbc != null) {
              results.add(WebPocResult(
                target: baseUri,
                pocType: 'poc-yaml-shiro-key',
                pocName: '',
                detail: '',
                params: {'key': keyCbc, 'mode': 'cbc'},
              ));
              return results; // 找到即返回
            }
            // 再尝试 GCM
            final keyGcm = await shiroSvc.bruteForceKey(
              candidateKeysBase64: keys,
              serializedPayload: payload,
              mode: ShiroEncryptionMode.gcm,
            );
            if (keyGcm != null) {
              results.add(WebPocResult(
                target: baseUri,
                pocType: 'poc-yaml-shiro-key',
                pocName: '',
                detail: '',
                params: {'key': keyGcm, 'mode': 'gcm'},
              ));
            }
          }
        }
      }
    } catch (_) {}

    // 3. 禅道 Repo RCE 检测
    try {
      final zentaoBase = await ZentaoExpService.detectZentaoBase(
        baseUri,
        timeout: timeout,
      );
      if (zentaoBase != null) {
        results.add(WebPocResult(
          target: baseUri,
          pocType: 'poc-yaml-zentao-repo-rce',
          pocName: '禅道 Repo 配置 RCE (CVE-2022-40978)',
          detail: '',
          params: {'zentaoBase': zentaoBase},
        ));
      }
    } catch (_) {}

    return results;
  }

  /// 快速 RCE 检测（根路径 403 时，指纹可能缺失，用 RCE 确认）
  Future<bool> _quickThinkphpRceCheck(ThinkphpExpService svc) async {
    try {
      final r = await svc.checkTp5022_5129();
      return r.vulnerable;
    } catch (_) {
      return false;
    }
  }

  /// 映射 ThinkPHP 漏洞名到 fscan/xray 风格 POC 类型
  String _thinkphpToPocName(String vulnName) {
    if (vulnName.contains('5.0 RCE') || vulnName.contains('5.0.10') ||
        vulnName.contains('5.0.22') || vulnName.contains('5.0.23') ||
        vulnName.contains('5.0.24') || vulnName.contains('5.1') ||
        vulnName.contains('5 View') || vulnName.contains('5.x _method') ||
        vulnName.contains('5.x Lang')) {
      return 'poc-yaml-thinkphp5-controller-rce';
    }
    if (vulnName.contains('5.0.22 config')) return 'poc-yaml-thinkphp5-config-leak';
    if (vulnName.contains('5.x 数据库')) return 'poc-yaml-thinkphp5-db-leak';
    if (vulnName.contains('5.x 日志')) return 'poc-yaml-thinkphp5-log-leak';
    if (vulnName.contains('3.x RCE') || vulnName.contains('3.x Module') ||
        vulnName.contains('3.x module') || vulnName.contains('3.x Log RCE')) {
      return 'poc-yaml-thinkphp3-rce';
    }
    if (vulnName.contains('3.x 日志')) return 'poc-yaml-thinkphp3-log-leak';
    if (vulnName.contains('6.x 日志')) return 'poc-yaml-thinkphp6-log-leak';
    return 'poc-yaml-thinkphp5-controller-rce';
  }

  /// 格式化为 fscan 风格输出
  static List<String> formatResults(List<WebPocResult> results) {
    final lines = <String>[];
    for (final r in results) {
      lines.add('[SUCCESS] 目标: ${r.target}');
      lines.add('  漏洞类型: ${r.pocType}');
      if (r.pocName.isNotEmpty) lines.add('  漏洞名称: ${r.pocName}');
      lines.add('  详细信息:');
      if (r.params != null && r.params!.isNotEmpty) {
        final paramStr = r.params!.entries.map((e) => '{${e.key} ${e.value}}').join(' ');
        lines.add('        params:[$paramStr]');
      }
      if (r.detail.isNotEmpty) {
        for (final line in r.detail.split('\n')) {
          lines.add('        $line');
        }
      }
      if (r.detail.isEmpty && (r.params == null || r.params!.isEmpty)) {
        if (r.pocType.startsWith('poc-yaml-thinkphp5')) {
          lines.add('        links:https://github.com/vulhub/vulhub/tree/master/thinkphp/5-rce');
        } else if (r.pocType.startsWith('poc-yaml-thinkphp3')) {
          lines.add('        links:https://github.com/vulhub/vulhub/tree/master/thinkphp/3-rce');
        } else if (r.pocType.startsWith('poc-yaml-thinkphp6')) {
          lines.add('        links:https://github.com/vulhub/vulhub/tree/master/thinkphp/6-rce');
        }
      }
    }
    return lines;
  }
}

class WebPocResult {
  final String target;
  final String pocType;
  final String pocName;
  final String detail;
  final Map<String, String>? params;

  WebPocResult({
    required this.target,
    required this.pocType,
    required this.pocName,
    required this.detail,
    this.params,
  });
}
