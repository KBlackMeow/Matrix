import 'package:http/http.dart' as http;

import 'thinkphp_exp_service.dart';

class ThinkphpV6ExpService {
  final Uri baseUri;
  final Duration timeout;

  ThinkphpV6ExpService({
    required this.baseUri,
    required this.timeout,
  });

  static const String _tp5LogErr = '[ error ]';
  static const String _tp6LogCheck = 'RunTime';

  Future<ThinkphpResult> checkTp6Log() async {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final suffix = '$y$m/$d.log';
    final bases = [
      '/runtime/log/',
      '/runtime/log/Home/',
      '/runtime/log/Common/',
      '/runtime/log/Admin/',
    ];
    for (final base in bases) {
      try {
        final u = '${baseUri}$base$suffix'.replaceAll('//', '/');
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        if (res.body.contains(_tp6LogCheck) || res.body.contains(_tp5LogErr)) {
          return ThinkphpResult(true, 'ThinkPHP 6.x 日志泄露', u);
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 6.x 日志泄露', '');
  }
}
