import 'package:flutter/material.dart';

import '../../exp/specs/spring_spec.dart';
import '../../exp/ui/exp_module_page.dart';

/// Spring 家族页：全部逻辑在 [ExpModulePage]，这里只绑定声明。
class SpringPage extends StatelessWidget {
  const SpringPage({super.key, this.initialTargetUrl});

  final String? initialTargetUrl;

  @override
  Widget build(BuildContext context) =>
      ExpModulePage(spec: springSpec, initialUrl: initialTargetUrl);
}
