import 'package:flutter/material.dart';

import '../../exp/specs/zentao_spec.dart';
import '../../exp/ui/exp_module_page.dart';

/// Zentao 家族页：全部逻辑在 [ExpModulePage]，这里只绑定声明。
class ZentaoPage extends StatelessWidget {
  const ZentaoPage({super.key, this.initialTargetUrl});

  final String? initialTargetUrl;

  @override
  Widget build(BuildContext context) =>
      ExpModulePage(spec: zentaoSpec, initialUrl: initialTargetUrl);
}
