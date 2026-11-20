// 正样本对照：收紧判定后，真实特征必须仍然命中。
//
// 上一轮为了消掉假阳性，把 WebLogic / XXL-JOB 的判定从"看状态码"改成"看特征串"。
// 收紧判定有反向风险：**会不会把真漏洞也一起干掉**。
// 本地没有真 WebLogic / XXL-JOB 镜像，所以这里用两条从真实响应形状抄来的样本，
// 保证"特征对得上时仍然命中"。
//
// 用法：dart tool/verify/positive_samples.dart

import 'dart:io';

import '../../lib/exp/core/exp_catalog.dart';
import '../../lib/exp/core/scan_runner.dart';

class _Sample {
  const _Sample(this.name, this.status, this.contentType, this.body, this.mustHit,
      {this.weak = false});

  final String name;
  final int status;
  final String contentType;
  final String body;
  final String mustHit;

  /// true 表示该命中只能算"弱证据"（无回显/端点特征），扫描结果不应显示"确认命中"。
  final bool weak;
}

/// WLS-WSAT 的真实响应形如 SOAP Fault，正文带 `weblogic.wsee` / `xmldecoder` 字样。
const _wlsSoapFault = '''<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
<soapenv:Body><soapenv:Fault>
<faultcode>soapenv:Server</faultcode>
<faultstring>weblogic.wsee.jaxws.framework.exception.WebServiceRuntimeException: xmldecoder</faultstring>
</soapenv:Fault></soapenv:Body></soapenv:Envelope>''';

/// XXL-JOB `/run` 的真实响应：2.2.0 执行器只回 `{"code":200}`（Jackson 省略 null）。
const _xxlRunOk = '{"code":200}';

/// 某些版本会带上 msg/content 字段。
const _xxlRunOkFull = '{"code":200,"msg":null,"content":null}';

const _samples = <_Sample>[
  _Sample('WebLogic WLS-WSAT SOAP Fault', 500, 'text/xml', _wlsSoapFault,
      'weblogic-10271', weak: true),
  _Sample('XXL-JOB /run 成功响应（2.2.0 实测形状）', 200, 'application/json',
      _xxlRunOk, 'xxl-job-unacc', weak: true),
  _Sample('XXL-JOB /run 成功响应（带 msg/content）', 200, 'application/json',
      _xxlRunOkFull, 'xxl-job-unacc', weak: true),
];

Future<void> main() async {
  var failures = 0;
  for (final s in _samples) {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await req.drain<void>();
      req.response
        ..statusCode = s.status
        ..headers.contentType = ContentType.parse(s.contentType)
        ..write(s.body);
      await req.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}';
    stdout.writeln('[*] ${s.name}  ($url)');

    final targets = allVariants
        .where((e) => e.$2.moduleId == s.mustHit)
        .toList(growable: false);
    final runner = ScanRunner(
      maxRequests: 30,
      maxDuration: const Duration(seconds: 20),
      perSecond: 20,
    );

    var hit = false;
    await for (final event in runner.run(
      url: url,
      timeoutSeconds: 5,
      targets: targets,
    )) {
      if (event is ScanHitEvent && event.hit.isHit) {
        hit = true;
        final isWeak = event.hit.confidence == ScanConfidence.noEcho;
        stdout.writeln(
          '    [+] ${event.hit.variant.moduleId} '
          '${event.hit.confidence.label}: ${event.hit.outcome.detail}',
        );
        if (s.weak != isWeak) {
          stdout.writeln(
            '[!] 证据强度不符：期望${s.weak ? "弱" : "强"}，实际${isWeak ? "弱" : "强"}',
          );
          failures++;
        }
      }
    }
    await server.close(force: true);

    if (hit) {
      stdout.writeln('[+] 通过：真实特征仍然命中');
    } else {
      failures++;
      stdout.writeln('[!] 失败：收紧判定后把真特征也漏掉了');
    }
  }

  if (failures == 0) {
    stdout.writeln('[+] 正样本套件通过');
    exit(0);
  }
  stdout.writeln('[!] 正样本套件失败：$failures 处漏报');
  exit(1);
}
