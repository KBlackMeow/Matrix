import 'package:flutter/material.dart';

import '../../exp/specs/weblogic_spec.dart';
import '../../exp/ui/exp_module_page.dart';

/// WebLogic 家族页：全部逻辑在 [ExpModulePage]，这里只绑定声明。
class WeblogicPage extends StatelessWidget {
  const WeblogicPage({super.key, this.initialTargetUrl});

  final String? initialTargetUrl;

  @override
  Widget build(BuildContext context) =>
      ExpModulePage(spec: weblogicSpec, initialUrl: initialTargetUrl);
}
