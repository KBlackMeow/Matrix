import 'package:flutter/material.dart';

import '../../exp/specs/struts2_spec.dart';
import '../../exp/ui/exp_module_page.dart';

/// Struts2 家族页：全部逻辑在 [ExpModulePage]，这里只绑定声明。
///
/// 迁移前 453 行，迁移后 15 行。
class Struts2Page extends StatelessWidget {
  const Struts2Page({super.key, this.initialTargetUrl});

  final String? initialTargetUrl;

  @override
  Widget build(BuildContext context) =>
      ExpModulePage(spec: struts2Spec, initialUrl: initialTargetUrl);
}
