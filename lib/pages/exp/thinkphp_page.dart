import 'package:flutter/material.dart';

import '../../exp/specs/thinkphp_spec.dart';
import '../../exp/ui/exp_module_page.dart';

/// ThinkPHP 家族页：全部逻辑在 [ExpModulePage]，这里只绑定声明。
class ThinkphpPage extends StatelessWidget {
  const ThinkphpPage({super.key, this.initialTargetUrl});

  final String? initialTargetUrl;

  @override
  Widget build(BuildContext context) =>
      ExpModulePage(spec: thinkphpSpec, initialUrl: initialTargetUrl);
}
