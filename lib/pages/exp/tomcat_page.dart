import 'package:flutter/material.dart';

import '../../exp/specs/tomcat_spec.dart';
import '../../exp/ui/exp_module_page.dart';

/// Tomcat 家族页：全部逻辑在 [ExpModulePage]，这里只绑定声明。
class TomcatPage extends StatelessWidget {
  const TomcatPage({super.key, this.initialTargetUrl});

  final String? initialTargetUrl;

  @override
  Widget build(BuildContext context) =>
      ExpModulePage(spec: tomcatSpec, initialUrl: initialTargetUrl);
}
