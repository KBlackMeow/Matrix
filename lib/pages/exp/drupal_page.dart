import 'package:flutter/material.dart';

import '../../exp/specs/drupal_spec.dart';
import '../../exp/ui/exp_module_page.dart';

/// Drupal 家族页：全部逻辑在 [ExpModulePage]，这里只绑定声明。
class DrupalPage extends StatelessWidget {
  const DrupalPage({super.key, this.initialTargetUrl});

  final String? initialTargetUrl;

  @override
  Widget build(BuildContext context) =>
      ExpModulePage(spec: drupalSpec, initialUrl: initialTargetUrl);
}
