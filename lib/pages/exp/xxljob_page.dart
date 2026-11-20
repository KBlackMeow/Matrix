import 'package:flutter/material.dart';

import '../../exp/specs/xxljob_spec.dart';
import '../../exp/ui/exp_module_page.dart';

/// XXL-JOB 家族页：全部逻辑在 [ExpModulePage]，这里只绑定声明。
class XxljobPage extends StatelessWidget {
  const XxljobPage({super.key, this.initialTargetUrl});

  final String? initialTargetUrl;

  @override
  Widget build(BuildContext context) =>
      ExpModulePage(spec: xxljobSpec, initialUrl: initialTargetUrl);
}
