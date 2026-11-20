/// 通用模块页：一个家族 = 一个 [ExpSpec] 的渲染结果。
///
/// 迁移后的页面基本只是它的薄包装（20–40 行），需要特化时用 [extraPanel]
/// 插一块自定义 UI——逃生舱，而不是退回手写整页。
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../core/exp_catalog.dart';
import '../core/exp_spec.dart';
import '../core/exploit_module.dart';
import '../core/exploit_session.dart';
import 'exp_actions.dart';
import 'exp_fields.dart';
import 'exp_steps_panel.dart';
import 'exp_icons.dart';
import 'exp_scaffold.dart';
import 'exp_target_fields.dart';
import 'exp_tokens.dart';
import 'exp_variant_picker.dart';

class ExpModulePage extends StatefulWidget {
  const ExpModulePage({
    super.key,
    required this.spec,
    this.initialUrl,
    this.extraPanel,
    this.extraPanelBuilder,
  });

  final ExpSpec spec;
  final String? initialUrl;

  /// 逃生舱：标准表单之下的自定义区块（静态）。
  final Widget? extraPanel;

  /// 逃生舱（需要访问会话时用）：能拿到 controller 才能复用日志/忙闲/URL 校验。
  final Widget Function(BuildContext, ExploitSessionController)?
      extraPanelBuilder;

  @override
  State<ExpModulePage> createState() => _ExpModulePageState();
}

class _ExpModulePageState extends State<ExpModulePage> {
  late ExpVariant _variant;
  late final ExploitSessionController _session;

  @override
  void initState() {
    super.initState();
    _variant = widget.spec.defaultVariant;
    final module = moduleOf(widget.spec, _variant);
    _session = ExploitSessionController(
      module: module ?? _missingModule(widget.spec, _variant),
      initialUrl: widget.initialUrl ?? '',
    );
    _session.setFields(widget.spec.defaultValuesFor(_variant));
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _selectVariant(ExpVariant variant) {
    final module = moduleOf(widget.spec, variant);
    if (module == null) return;
    setState(() {
      _variant = variant;
      _session
        ..selectModule(module)
        ..setFields(widget.spec.defaultValuesFor(variant));
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return ExpScaffold(
      icon: spec.icon.data,
      title: spec.title,
      subtitle: spec.subtitle,
      notes: spec.notes,
      listenable: _session,
      state: () => ExpWorkspaceState(
        lines: _session.log,
        running: _session.running,
        onClear: _session.clearLog,
      ),
      form: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpTargetFields(session: _session, enabled: !_session.running),
          ExpSpace.vLg,
          if (spec.variants.length > 1) ...[
            ExpVariantPicker(
              spec: spec,
              selected: _variant,
              enabled: !_session.running,
              onChanged: _selectVariant,
            ),
            ExpSpace.vLg,
          ],
          ExpFields(
            key: ValueKey(_variant.id),
            fields: spec.fieldsFor(_variant),
            values: _session.fieldValues,
            enabled: !_session.running,
            onChanged: _session.setField,
          ),
          if (spec.steps.isNotEmpty)
            // 声明了流程的家族走步骤面板；能力接口只在步骤内部被调用。
            ExpStepsPanel(spec: spec, session: _session)
          else
            ExpSessionPanel(
              session: _session,
              capabilities: _variant.capabilities,
              shellName: '${spec.family} Shell',
            ),
          if (widget.extraPanel != null) ...[
            ExpSpace.vLg,
            widget.extraPanel!,
          ],
          if (widget.extraPanelBuilder != null) ...[
            ExpSpace.vLg,
            widget.extraPanelBuilder!(context, _session),
          ],
        ],
      ),
    );
  }
}

/// spec 声明的模块不存在时的替身：让页面仍能打开并说明原因，
/// 而不是在 `build` 里抛空指针。`tool/verify/spec_bind.dart` 会在 CI 里拦住这种情况。
ExploitModule _missingModule(ExpSpec spec, ExpVariant variant) =>
    _MissingModule(spec: spec, variant: variant);

class _MissingModule extends ExploitModule {
  _MissingModule({required this.spec, required this.variant});

  final ExpSpec spec;
  final ExpVariant variant;

  @override
  String get id => variant.moduleId;

  @override
  String get name => variant.label;

  @override
  String get category => spec.category;

  @override
  String get cve => variant.id;

  @override
  String get description => '模块 ${variant.moduleId} 未注册';

  @override
  Set<ExploitCapability> get capabilities => const {};

  @override
  Future<ExploitOutcome> check(ExploitTarget target) async =>
      ExploitOutcome.probeFailed('模块缺失', '${variant.moduleId} 未在 module_registry 中注册');
}

/// 供页面复用的提示条样式（未迁移完成的家族会显示它）。
class ExpNotice extends StatelessWidget {
  const ExpNotice({super.key, required this.text, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: ExpSpace.control,
      decoration: BoxDecoration(
        color: ExpColors.fill(ExpColors.info, 0.10),
        borderRadius: ExpRadius.controlBorder,
        border: Border.all(color: ExpColors.fill(ExpColors.info, 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: ExpColors.info),
          ExpSpace.hSm,
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption(
                size: ExpText.caption,
                color: ExpColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
