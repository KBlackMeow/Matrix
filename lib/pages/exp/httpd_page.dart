import 'package:flutter/material.dart';

import '../../exp/specs/httpd_spec.dart';
import '../../exp/ui/exp_module_page.dart';

/// Apache httpd 家族页：全部逻辑在 [ExpModulePage]，这里只绑定声明。
class HttpdPage extends StatelessWidget {
  const HttpdPage({super.key, this.initialTargetUrl});

  final String? initialTargetUrl;

  @override
  Widget build(BuildContext context) =>
      ExpModulePage(spec: httpdSpec, initialUrl: initialTargetUrl);
}
