/// 声明式字段渲染器：把 [ExpFieldSpec] 列表画成表单。
///
/// 这是 12 个旧页面重复最多的部分——每页手写 `TextEditingController`、
/// 手写 `DropdownButton`、手写输入装饰。改一处 schema，表单自动跟着变。
library;

import 'package:flutter/material.dart';

import '../core/exp_spec.dart';
import '../../theme/app_theme.dart';
import 'exp_tokens.dart';

class ExpFields extends StatefulWidget {
  const ExpFields({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
    this.enabled = true,
  });

  final List<ExpFieldSpec> fields;

  /// 当前值（key → 字符串）。受控组件：外部改值会同步到输入框。
  final Map<String, String> values;

  final void Function(String key, String value) onChanged;
  final bool enabled;

  @override
  State<ExpFields> createState() => _ExpFieldsState();
}

class _ExpFieldsState extends State<ExpFields> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focus = {};

  TextEditingController _controllerFor(ExpFieldSpec f) => _controllers.putIfAbsent(
    f.key,
    () => TextEditingController(text: widget.values[f.key] ?? f.defaultValue),
  );

  FocusNode _focusFor(ExpFieldSpec f) =>
      _focus.putIfAbsent(f.key, () => FocusNode());

  @override
  void didUpdateWidget(covariant ExpFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final f in widget.fields) {
      final c = _controllers[f.key];
      if (c == null) continue;
      final incoming = widget.values[f.key] ?? f.defaultValue;
      // 只在外部值变化且该框未获得焦点时回写，避免打断输入。
      if (incoming != c.text && !(_focus[f.key]?.hasFocus ?? false)) {
        c.text = incoming;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in widget.fields) ...[
          _field(f),
          ExpSpace.vMd,
        ],
      ],
    );
  }

  Widget _field(ExpFieldSpec f) {
    return switch (f.type) {
      ExpFieldType.select => _select(f),
      ExpFieldType.toggle => _toggle(f),
      ExpFieldType.number => _text(f, keyboard: TextInputType.number),
      ExpFieldType.textarea => _text(f, maxLines: 4),
      ExpFieldType.text => _text(f),
    };
  }

  Widget _text(ExpFieldSpec f, {TextInputType? keyboard, int maxLines = 1}) {
    final c = _controllerFor(f);
    return TextField(
      controller: c,
      focusNode: _focusFor(f),
      enabled: widget.enabled,
      keyboardType: keyboard,
      maxLines: maxLines,
      style: AppTextStyles.body(size: ExpText.body, color: ExpColors.text),
      decoration: expInputDecoration(f.label, f.hint),
      onChanged: (v) => widget.onChanged(f.key, f.normalize(v)),
    );
  }

  Widget _select(ExpFieldSpec f) {
    final current = widget.values[f.key] ?? f.defaultValue;
    final hasOption = f.options.any((o) => o.value == current);
    return DropdownButtonFormField<String>(
      initialValue: hasOption
          ? current
          : (f.options.isEmpty ? null : f.options.first.value),
      // 选项文案可能很长，同 exp_variant_picker：必须展开 + 省略号，
      // 否则按钮内部的 Row 会 RenderFlex overflow。
      isExpanded: true,
      isDense: true,
      dropdownColor: ExpColors.surfaceRaised,
      style: AppTextStyles.body(size: ExpText.body, color: ExpColors.text),
      decoration: expInputDecoration(f.label, f.hint),
      items: [
        for (final o in f.options)
          DropdownMenuItem(
            value: o.value,
            child: Text(
              o.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(
                size: ExpText.body,
                color: ExpColors.text,
              ),
            ),
          ),
      ],
      onChanged: widget.enabled
          ? (v) {
              if (v != null) widget.onChanged(f.key, v);
            }
          : null,
    );
  }

  Widget _toggle(ExpFieldSpec f) {
    final on = (widget.values[f.key] ?? f.defaultValue) == 'true';
    return Row(
      children: [
        Expanded(
          child: Text(
            f.label,
            style: AppTextStyles.caption(
              size: ExpText.label,
              color: ExpColors.textSecondary,
            ),
          ),
        ),
        Switch(
          value: on,
          activeThumbColor: ExpColors.ok,
          onChanged: widget.enabled
              ? (v) => widget.onChanged(f.key, v ? 'true' : 'false')
              : null,
        ),
      ],
    );
  }
}

/// 全项目统一的输入装饰。
InputDecoration expInputDecoration(String label, [String hint = '']) =>
    InputDecoration(
      labelText: label,
      hintText: hint.isEmpty ? null : hint,
      hintStyle: AppTextStyles.caption(
        size: ExpText.caption,
        color: ExpColors.muted,
      ),
      labelStyle: AppTextStyles.caption(
        size: ExpText.caption,
        color: ExpColors.textSecondary,
      ),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      isDense: true,
      contentPadding: ExpSpace.control,
      border: OutlineInputBorder(borderRadius: ExpRadius.controlBorder),
      enabledBorder: OutlineInputBorder(
        borderRadius: ExpRadius.controlBorder,
        borderSide: const BorderSide(color: ExpColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: ExpRadius.controlBorder,
        borderSide: BorderSide(color: ExpColors.fill(ExpColors.ok, 0.6)),
      ),
    );
