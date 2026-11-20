import 'package:flutter/material.dart';

import '../../exp/specs/php_spec.dart';
import '../../exp/ui/exp_module_page.dart';

/// PHP 家族页：全部逻辑在 [ExpModulePage]，这里只绑定声明。
class PhpPage extends StatelessWidget {
  const PhpPage({super.key, this.initialTargetUrl});

  final String? initialTargetUrl;

  @override
  Widget build(BuildContext context) =>
      ExpModulePage(spec: phpSpec, initialUrl: initialTargetUrl);
}
