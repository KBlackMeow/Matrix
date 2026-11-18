// ignore_for_file: avoid_print

/// exp 模块的靶场联调脚本（不改动 App，仅直接调用 exp 服务）。
///
/// 用法：
///   dart tool/verify/exp_live.dart php-check  http://127.0.0.1:18090
///   dart tool/verify/exp_live.dart php-exec   http://127.0.0.1:18090 'echo $HOME'
///   dart tool/verify/exp_live.dart spring-check http://127.0.0.1:18093
///   dart tool/verify/exp_live.dart spring-exec  http://127.0.0.1:18093 'echo hi'
///   dart tool/verify/exp_live.dart s2059-check  http://127.0.0.1:18091
///   dart tool/verify/exp_live.dart s2059-exec   http://127.0.0.1:18091 'echo hi'
///   dart tool/verify/exp_live.dart s2057-check  http://127.0.0.1:18092
///   dart tool/verify/exp_live.dart s2057-exec   http://127.0.0.1:18092 'echo hi'
library;

import 'dart:io';

import '../../lib/exp/vulhub/services/runtime_services.dart';
import '../../lib/exp/vulhub/services/exp_result.dart';
import '../../lib/exp/vulhub/spring_exp_service.dart';
import '../../lib/exp/vulhub/struts2_exp_service.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('usage: exp_live <case> <url> [cmd]');
    exitCode = 64;
    return;
  }
  final mode = args[0];
  final url = args[1];
  final cmd = args.length > 2 ? args[2] : 'echo MATRIX_EXP_OK';

  switch (mode) {
    case 'php-check':
      _show(await PhpBackdoorExpService(baseUrl: url).check());
      break;
    case 'php-exec':
      print(await PhpBackdoorExpService(baseUrl: url).execRce(cmd));
      break;
    case 'spring-check':
      _show(await SpringExpService(url: url).checkSpringCloudFunction());
      break;
    case 'spring-exec':
      print(await SpringExpService(url: url).execSpringCloudFunction(cmd));
      break;
    case 's2059-check':
      _show(await Struts2ExpService(url: url).checkS2059());
      break;
    case 's2059-exec':
      print(await Struts2ExpService(url: url).execS2059(cmd));
      break;
    case 's2057-check':
      _show(await Struts2ExpService(url: url).checkS2057());
      break;
    case 's2057-exec':
      print(await Struts2ExpService(url: url).execS2057(cmd));
      break;
    default:
      print('unknown case: $mode');
      exitCode = 64;
  }
}

void _show(ExpResult r) {
  print('vulnerable=${r.vulnerable} failed=${r.failed} '
      'name=${r.vulnName} detail=${r.detail}');
}
