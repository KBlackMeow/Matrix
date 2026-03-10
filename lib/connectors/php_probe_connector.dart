import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/file_entry.dart';
import 'shell_connector.dart';

/// `php_probe_info.php`：`phpinfo()`
///
/// 只读探测型，无命令执行能力。
/// getSystemInfo 通过正则解析 phpinfo HTML 输出。
class PhpProbeConnector extends ShellConnector {
  PhpProbeConnector(super.webshell);

  @override
  Set<ConnectorCapability> get capabilities =>
      const {ConnectorCapability.probeOnly};

  Future<String> _fetch() async {
    try {
      final uri = Uri.parse(webshell.url);
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return response.body;
      return '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<bool> ping() async {
    try {
      final body = await _fetch();
      return body.toLowerCase().contains('phpinfo') ||
          body.toLowerCase().contains('php version');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, String>> getSystemInfo() async {
    final body = await _fetch();
    if (body.isEmpty) return {};
    final map = <String, String>{};

    String? _extract(String pattern) =>
        RegExp(pattern, caseSensitive: false).firstMatch(body)?.group(1)?.trim();

    final phpVer = _extract(r'PHP Version\s*</td>\s*<td[^>]*>([^<]+)') ??
        _extract(r'<h1 class="p">PHP Version ([^<]+)</h1>');
    if (phpVer != null && phpVer.isNotEmpty) map['PHP版本'] = phpVer;

    final system = _extract(r'System\s*</td>\s*<td[^>]*>([^<]+)');
    if (system != null && system.isNotEmpty) map['OS'] = system;

    final api = _extract(r'Server API\s*</td>\s*<td[^>]*>([^<]+)');
    if (api != null && api.isNotEmpty) map['服务器API'] = api;

    final df = _extract(r'disable_functions\s*</td>\s*<td[^>]*>([^<]*)');
    if (df != null) map['禁用函数'] = df.isEmpty ? '无' : df;

    final dr = _extract(r'DOCUMENT_ROOT\s*</td>\s*<td[^>]*>([^<]+)');
    if (dr != null && dr.isNotEmpty) map['文档根目录'] = dr;

    map['探测模式'] = 'phpinfo() 解析（只读）';
    return map;
  }

  // ── 不支持的操作 ──────────────────────────────────────────────────────────

  @override
  Future<String> executeCommand(String cmd, {String workingDir = ''}) async =>
      '[probe 模式：不支持命令执行]';

  @override
  Future<String> getCurrentDir() async => currentDir;

  @override
  Future<List<FileEntry>> listDirectory(String path) async => [];

  @override
  Future<String> readFile(String path) async => '[probe 模式：不支持文件读取]';

  @override
  Future<bool> writeFile(String path, String content) async => false;

  @override
  Future<bool> deleteFile(String path) async => false;

  @override
  Future<List<({String name, bool isDir})>> listNamesForCompletion(
          String path) async =>
      [];

  @override
  Future<String> getHomeDir() async => '';

  @override
  Future<List<String>> listEnvVarNames() async => [];
}
