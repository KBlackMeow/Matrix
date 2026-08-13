import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/webshell_service.dart';
import '../theme/app_theme.dart';
import 'priv_esc_engine.dart';
import 'priv_esc_landing.dart';
import 'priv_esc_risk.dart';
import 'priv_esc_risk_list.dart';
import 'priv_esc_vectors.dart';

class PrivEscTab extends StatefulWidget {
  final WebshellService service;
  const PrivEscTab({super.key, required this.service});

  @override
  State<PrivEscTab> createState() => _PrivEscTabState();
}

class _PrivEscTabState extends State<PrivEscTab>
    with AutomaticKeepAliveClientMixin {
  List<PrivEscRisk> _confirmedRisks = const [];
  bool _runningAll = false;
  bool _scanHasRun = false;
  bool _scanIncomplete = false;
  int _completedChecks = 0;
  String _currentUser = '';

  /// When on (default), only risks with an executable chain (`candidate != null`)
  /// are shown; informational leads are hidden. When off, they reappear below
  /// the executable risks (the level grouping already sorts them last).
  bool _hideUnusable = true;

  List<PrivEscRisk> get _displayRisks {
    if (!_hideUnusable) return _confirmedRisks;
    return _confirmedRisks
        .where((r) => r.candidate != null)
        .toList(growable: false);
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _runAll() async {
    setState(() {
      _runningAll = true;
      _completedChecks = 0;
      _scanIncomplete = false;
    });

    final scanner = PrivEscScanner(widget.service);
    final result = await scanner.scan(
      onProgress: (done, total) {
        if (mounted) setState(() => _completedChecks = done);
      },
    );

    if (mounted) {
      setState(() {
        _confirmedRisks = result.risks;
        _runningAll = false;
        _scanHasRun = true;
        _scanIncomplete = result.incomplete;
        _currentUser = result.currentUser;
      });
    }
  }

  void _clearAll() => setState(() {
    _confirmedRisks = const [];
    _scanHasRun = false;
    _scanIncomplete = false;
    _completedChecks = 0;
    _currentUser = '';
  });

  Future<void> _onExecutePressed(PrivEscRisk risk) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PrivEscExecuteDialog(
        service: widget.service,
        risk: risk,
        currentUser: _currentUser,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final totalCount = vectors.length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.bgElevated,
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, color: AppColors.amber, size: 16),
              const SizedBox(width: 8),
              Text(
                'Privilege Escalation Scan',
                style: AppTextStyles.heading(size: 14, color: AppColors.amber),
              ),
              if (_runningAll || _scanHasRun) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _runningAll
                        ? 'Scanning $_completedChecks / $totalCount'
                        : '${_confirmedRisks.length} risks confirmed',
                    style: AppTextStyles.caption(
                      size: 11,
                      color: AppColors.amber,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              FilterChip(
                selected: _hideUnusable,
                onSelected: (v) => setState(() => _hideUnusable = v),
                label: const Text('Hide Unusable'),
                labelStyle: AppTextStyles.caption(
                  size: 11,
                  color: _hideUnusable
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                checkmarkColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              const SizedBox(width: 4),
              if (_confirmedRisks.isNotEmpty)
                TextButton.icon(
                  onPressed: _runningAll ? null : _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                  label: const Text('Clear Results'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _runningAll ? null : _runAll,
                icon: _runningAll
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 15),
                label: Text(
                  _runningAll ? 'Scanning…' : (_scanHasRun ? 'Re-scan' : 'Start Scan'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDeep,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  textStyle: AppTextStyles.body(size: 13),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              PrivEscRiskList(
                risks: _displayRisks,
                scanIncomplete: _scanIncomplete,
                hasScanned: _scanHasRun,
                hidingUnusable: _hideUnusable && _confirmedRisks.isNotEmpty,
                onCopy: (cmd) {
                  Clipboard.setData(ClipboardData(text: cmd));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Copied to clipboard'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                onExecute: _onExecutePressed,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dialog that lets the user pick a landing method, fill params, preview the
/// generated chain, then execute it and show the result.
class _PrivEscExecuteDialog extends StatefulWidget {
  const _PrivEscExecuteDialog({
    required this.service,
    required this.risk,
    required this.currentUser,
  });

  final WebshellService service;
  final PrivEscRisk risk;
  final String currentUser;

  @override
  State<_PrivEscExecuteDialog> createState() => _PrivEscExecuteDialogState();
}

class _PrivEscExecuteDialogState extends State<_PrivEscExecuteDialog> {
  late final LandingMethod? _fixedLanding;
  late LandingMethod _selected;
  late final Map<String, TextEditingController> _controllers;
  bool _executing = false;
  PrivEscChainResult? _result;

  PrivEscCandidate get _candidate => widget.risk.candidate!;

  @override
  void initState() {
    super.initState();
    _fixedLanding = _resolveFixedLanding();
    _selected = _fixedLanding ?? landingMethods.first;
    _controllers = {
      for (final p in _selected.params)
        p.id: TextEditingController(text: p.defaultValue),
    };
  }

  LandingMethod? _resolveFixedLanding() {
    if (_candidate.gtfo != null) return null; // primitive — landing selectable
    for (final v in vectors) {
      if (v.id == _candidate.vectorId) return v.directLanding;
    }
    return null;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _collectParams() {
    final params = <String, String>{
      for (final e in _controllers.entries) e.key: e.value.text,
    };
    // sudoers landing: default the target user to the scanned current user.
    if (_selected.id == 'sudoers_nopasswd' && (params['user'] ?? '').isEmpty) {
      params['user'] = widget.currentUser.isEmpty ? 'REPLACE_USER' : widget.currentUser;
    }
    return params;
  }

  PrivEscChain _buildChain() => buildChain(
    candidate: _candidate,
    landing: _selected,
    params: _collectParams(),
  );

  Future<void> _execute() async {
    setState(() => _executing = true);
    final chain = _buildChain();
    final result = await executeChain(widget.service, chain);
    if (mounted) {
      setState(() {
        _executing = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chain = _buildChain();
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.admin_panel_settings_outlined,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Execute Escalation Chain',
              style: AppTextStyles.heading(size: 15),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.risk.evidence,
                style: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),

              // Landing selection (fixed for fused vectors).
              if (_fixedLanding != null)
                _LandingTile(landing: _fixedLanding)
              else
                for (final lm in landingMethods)
                  RadioListTile<LandingMethod>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(lm.name,
                        style: AppTextStyles.body(size: 13)),
                    subtitle: Text(lm.description,
                        style: AppTextStyles.caption(size: 11)),
                    value: lm,
                    groupValue: _selected,
                    onChanged: _executing
                        ? null
                        : (v) {
                            setState(() {
                              _selected = v!;
                              for (final c in _controllers.values) {
                                c.dispose();
                              }
                              _controllers
                                ..clear()
                                ..addAll({
                                  for (final p in _selected.params)
                                    p.id: TextEditingController(
                                        text: p.defaultValue),
                                });
                            });
                          },
                  ),

              const SizedBox(height: 8),
              for (final p in _selected.params)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _controllers[p.id],
                    enabled: !_executing,
                    decoration: InputDecoration(
                      labelText: p.label,
                      hintText: p.hint,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),

              const SizedBox(height: 8),
              _CommandPreview(
                label: 'Execute Command (Escalation + Backdoor)',
                command: chain.deployCommand,
              ),
              const SizedBox(height: 8),
              _CommandPreview(
                label: 'Verify Command',
                command: chain.verifyCommand,
              ),

              if (_result != null) ...[
                const SizedBox(height: 12),
                _ResultBlock(result: _result!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _executing ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _executing ? null : _execute,
          icon: _executing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.rocket_launch_outlined, size: 16),
          label: Text(_executing ? 'Executing…' : 'Confirm & Execute'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDeep,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _LandingTile extends StatelessWidget {
  const _LandingTile({required this.landing});

  final LandingMethod landing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Landing: ${landing.name}',
          style: AppTextStyles.body(size: 13).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          landing.description,
          style: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
        ),
      ],
    ),
  );
}

class _CommandPreview extends StatelessWidget {
  const _CommandPreview({required this.label, required this.command});

  final String label;
  final String command;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTextStyles.caption(size: 11, color: AppColors.textMuted)),
      const SizedBox(height: 3),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(maxHeight: 120),
        decoration: BoxDecoration(
          color: AppColors.bgDark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.border),
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            command,
            style: AppTextStyles.terminal(size: 11, color: AppColors.cyan),
          ),
        ),
      ),
    ],
  );
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({required this.result});

  final PrivEscChainResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.fullyVerified ? AppColors.primary : AppColors.red;
    final title = result.fullyVerified
        ? '✓ Escalation succeeded — root established'
        : (result.deployOk ? '✗ Landing succeeded but verification failed' : '✗ Execution failed');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.body(size: 13).copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text('Execution Output', style: AppTextStyles.caption(size: 10, color: AppColors.textMuted)),
          SelectableText(
            result.deployOutput.isEmpty ? '(empty)' : result.deployOutput,
            style: AppTextStyles.terminal(
                size: 10.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text('Verification Output', style: AppTextStyles.caption(size: 10, color: AppColors.textMuted)),
          SelectableText(
            result.verifyOutput.isEmpty ? '(empty)' : result.verifyOutput,
            style: AppTextStyles.terminal(
                size: 10.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
