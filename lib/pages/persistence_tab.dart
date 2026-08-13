import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/webshell_service.dart';
import '../theme/app_theme.dart';
import 'persistence_engine.dart';
import 'persistence_methods.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Main tab
// ═══════════════════════════════════════════════════════════════════════════════

class PersistenceTab extends StatefulWidget {
  final WebshellService service;
  const PersistenceTab({super.key, required this.service});

  @override
  State<PersistenceTab> createState() => _PersistenceTabState();
}

class _PersistenceTabState extends State<PersistenceTab>
    with AutomaticKeepAliveClientMixin {
  final Map<String, DetectionResult?> _detectionResults = {};
  final Map<String, _DeployOutcome> _deployOutcomes = {};
  final Map<String, bool> _running = {};
  bool _runningAll = false;

  // Stealth defaults (seed the per-deploy dialog toggles).
  bool _stealthHide = true;
  bool _stealthTimestamp = true;
  bool _stealthCleanHistory = true;

  // Hide methods whose check reports they can't be deployed here.
  bool _hideBlocked = true;

  late final List<PersistGroup> _groups;

  @override
  void initState() {
    super.initState();
    _groups = filterPersistGroups(widget.service.isWindowsTarget);
  }

  @override
  bool get wantKeepAlive => true;

  String _ckey(String methodId) => 'check/$methodId';
  String _dkey(String methodId) => 'deploy/$methodId';

  // ── Check ──────────────────────────────────────────────────────────────────

  Future<void> _runCheck(PersistMethod method) async {
    final key = _ckey(method.id);
    setState(() => _running[key] = true);
    try {
      final out = await widget.service.executeCommand(method.checkCommand);
      if (mounted) {
        final result = parseDetection(method.id, out);
        setState(() {
          _detectionResults[key] = result;
          _running[key] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _detectionResults[key] = DetectionResult.error('[Error] $e');
          _running[key] = false;
        });
      }
    }
  }

  Future<void> _runAllChecks() async {
    setState(() => _runningAll = true);
    for (final g in _groups) {
      for (final m in g.methods) {
        await _runCheck(m);
      }
    }
    if (mounted) setState(() => _runningAll = false);
  }

  void _clearAll() => setState(() {
        _detectionResults.clear();
        _deployOutcomes.clear();
        _running.clear();
      });

  // ── Deploy ─────────────────────────────────────────────────────────────────

  Future<void> _onDeployPressed(PersistMethod method) async {
    final outcome = await showDialog<_DeployOutcome>(
      context: context,
      builder: (_) => _PersistDeployDialog(
        service: widget.service,
        method: method,
        stealthHide: _stealthHide,
        stealthTimestamp: _stealthTimestamp,
        stealthCleanHistory: _stealthCleanHistory,
      ),
    );
    if (outcome != null && mounted) {
      setState(() => _deployOutcomes[_dkey(method.id)] = outcome);
    }
  }

  /// `true` = checked and deployable (usable), `false` = checked but blocked /
  /// errored (unusable), `null` = not checked yet.
  bool? _isUsable(PersistMethod m) {
    final r = _detectionResults[_ckey(m.id)];
    if (r == null) return null;
    if (r.verdict == DetectionVerdict.error) return false;
    return r.exploitability?.isDeployable ?? false;
  }

  List<PersistGroup> get _visibleGroups {
    final visible = <PersistGroup>[];
    for (final g in _groups) {
      final methods = <PersistMethod>[];
      for (final m in g.methods) {
        final usable = _isUsable(m);
        // Hidden mode: only confirmed-usable methods are shown.
        if (_hideBlocked && usable != true) continue;
        methods.add(m);
      }
      if (!_hideBlocked) {
        // Sorted mode: usable first, unchecked next, unusable at the bottom.
        int rank(PersistMethod m) => switch (_isUsable(m)) {
          true => 0,
          null => 1,
          false => 2,
        };
        methods.sort((a, b) => rank(a).compareTo(rank(b)));
      }
      if (methods.isEmpty) continue;
      visible.add(PersistGroup(
        id: g.id,
        title: g.title,
        icon: g.icon,
        color: g.color,
        methods: methods,
      ));
    }
    return visible;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    var checkDone = 0;
    var checkTotal = 0;
    for (final g in _groups) {
      checkTotal += g.methods.length;
      for (final m in g.methods) {
        if (_detectionResults[_ckey(m.id)] != null) checkDone++;
      }
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.bgElevated,
          child: Row(
            children: [
              const Icon(Icons.link, color: AppColors.amber, size: 16),
              const SizedBox(width: 8),
              Text(
                'Persistence Mechanisms',
                style: AppTextStyles.heading(size: 14, color: AppColors.amber),
              ),
              if (checkDone > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$checkDone/$checkTotal',
                    style: AppTextStyles.caption(size: 11, color: AppColors.amber),
                  ),
                ),
              ],
              const Spacer(),
              // Hide methods that can't be deployed here (blocked / errored).
              FilterChip(
                selected: _hideBlocked,
                onSelected: (v) => setState(() => _hideBlocked = v),
                label: const Text('Hide Blocked'),
                labelStyle: AppTextStyles.caption(
                  size: 11,
                  color: _hideBlocked
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
              // Stealth defaults (Linux targets only).
              if (!widget.service.isWindowsTarget)
                PopupMenuButton<String>(
                  icon: Icon(Icons.visibility_off_outlined,
                      size: 16, color: AppColors.textSecondary),
                  tooltip: 'Stealth Defaults',
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  onSelected: (v) => setState(() {
                    switch (v) {
                      case 'hide':
                        _stealthHide = !_stealthHide;
                        break;
                      case 'ts':
                        _stealthTimestamp = !_stealthTimestamp;
                        break;
                      case 'hist':
                        _stealthCleanHistory = !_stealthCleanHistory;
                        break;
                    }
                  }),
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(
                      value: 'hide',
                      checked: _stealthHide,
                      child: const Text('Hide Files'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'ts',
                      checked: _stealthTimestamp,
                      child: const Text('Clone Timestamp'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'hist',
                      checked: _stealthCleanHistory,
                      child: const Text('Clean History'),
                    ),
                  ],
                ),
              if (checkDone > 0)
                TextButton.icon(
                  onPressed: _runningAll ? null : _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _runningAll ? null : _runAllChecks,
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
                label: Text(_runningAll ? 'Scanning All…' : 'Scan All'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDeep,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  textStyle: AppTextStyles.body(size: 13),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              if (_visibleGroups.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text(
                      checkDone == 0
                          ? 'Run "Scan all" to see which methods are usable on this target.'
                          : 'No deployable methods found on this target.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ..._visibleGroups.map(
                (group) => _PersistGroupWidget(
                  group: group,
                  detectionResults: _detectionResults,
                  deployOutcomes: _deployOutcomes,
                  running: _running,
                  ckey: _ckey,
                  dkey: _dkey,
                  onCheck: _runCheck,
                  onDeploy: _onDeployPressed,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Outcome of a deploy (returned from the dialog, stored for card status).
// ═══════════════════════════════════════════════════════════════════════════════

class _DeployOutcome {
  final bool deployOk;
  final bool verified;
  final String? rollbackCommand;
  const _DeployOutcome({
    required this.deployOk,
    required this.verified,
    this.rollbackCommand,
  });
}

class _PreflightResult {
  final bool ok;
  final String message;
  final bool isInfo;
  const _PreflightResult({
    required this.ok,
    required this.message,
    this.isInfo = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// Group widget
// ═══════════════════════════════════════════════════════════════════════════════

class _PersistGroupWidget extends StatelessWidget {
  final PersistGroup group;
  final Map<String, DetectionResult?> detectionResults;
  final Map<String, _DeployOutcome> deployOutcomes;
  final Map<String, bool> running;
  final String Function(String) ckey;
  final String Function(String) dkey;
  final void Function(PersistMethod) onCheck;
  final void Function(PersistMethod) onDeploy;

  const _PersistGroupWidget({
    required this.group,
    required this.detectionResults,
    required this.deployOutcomes,
    required this.running,
    required this.ckey,
    required this.dkey,
    required this.onCheck,
    required this.onDeploy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(group.icon, size: 14, color: group.color),
                const SizedBox(width: 6),
                Text(
                  group.title,
                  style:
                      AppTextStyles.heading(size: 13, color: group.color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Divider(
                    color: group.color.withValues(alpha: 0.25),
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          ...group.methods.map((method) => _PersistMethodWidget(
                method: method,
                color: group.color,
                detectionResult: detectionResults[ckey(method.id)],
                deployOutcome: deployOutcomes[dkey(method.id)],
                isRunning: running[ckey(method.id)] == true,
                onCheck: () => onCheck(method),
                onDeploy: () => onDeploy(method),
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Method card
// ═══════════════════════════════════════════════════════════════════════════════

class _PersistMethodWidget extends StatelessWidget {
  final PersistMethod method;
  final Color color;
  final DetectionResult? detectionResult;
  final _DeployOutcome? deployOutcome;
  final bool isRunning;
  final VoidCallback onCheck;
  final VoidCallback onDeploy;

  const _PersistMethodWidget({
    required this.method,
    required this.color,
    required this.detectionResult,
    required this.deployOutcome,
    required this.isRunning,
    required this.onCheck,
    required this.onDeploy,
  });

  @override
  Widget build(BuildContext context) {
    final hasDetection = detectionResult != null;
    final isBlocked = detectionResult?.exploitability != null &&
        !detectionResult!.exploitability!.isDeployable;
    final blockedReasons = isBlocked
        ? detectionResult!.exploitability!.blocked
        : <String>[];
    final statusChip = _statusChip(isBlocked, blockedReasons);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accentColor(isBlocked)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + description + check button.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.name,
                      style: AppTextStyles.body(size: 13).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      method.description,
                      style: AppTextStyles.caption(
                          size: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 74,
                height: 28,
                child: isRunning
                    ? Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: color,
                          ),
                        ),
                      )
                    : OutlinedButton(
                        onPressed: onCheck,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: color,
                          side: BorderSide(color: color.withValues(alpha: 0.6)),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(
                          hasDetection ? 'Re-scan' : 'Scan',
                          style: AppTextStyles.caption(size: 10, color: color),
                        ),
                      ),
              ),
            ],
          ),
          if (statusChip != null) ...[
            const SizedBox(height: 10),
            statusChip,
          ],
          if (hasDetection) ...[
            const SizedBox(height: 6),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: Text('View Detection Details',
                    style: AppTextStyles.caption(size: 11)),
                children: [
                  _DetailBlock(
                      label: 'Scan Command', value: method.checkCommand),
                  if (detectionResult?.rawOutput != null)
                    _DetailBlock(
                        label: 'Scan Output',
                        value: detectionResult!.rawOutput!),
                ],
              ),
            ),
          ],
          if (deployOutcome?.rollbackCommand != null) ...[
            const SizedBox(height: 8),
            _RollbackRow(command: deployOutcome!.rollbackCommand!),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: isBlocked ? null : onDeploy,
              icon: const Icon(Icons.rocket_launch_outlined, size: 16),
              label: const Text('Deploy'),
              style: FilledButton.styleFrom(
                backgroundColor: isBlocked
                    ? AppColors.textMuted.withValues(alpha: 0.5)
                    : AppColors.primaryDeep,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _accentColor(bool isBlocked) {
    if (deployOutcome != null) {
      if (deployOutcome!.deployOk) {
        return deployOutcome!.verified ? AppColors.primary : AppColors.amber;
      }
      return AppColors.red;
    }
    if (isBlocked) return AppColors.red;
    if (detectionResult != null &&
        detectionResult!.verdict == DetectionVerdict.error) {
      return AppColors.red;
    }
    if (detectionResult != null) return AppColors.primary;
    return AppColors.border;
  }

  Widget? _statusChip(bool isBlocked, List<String> blockedReasons) {
    if (deployOutcome != null) {
      if (deployOutcome!.deployOk && deployOutcome!.verified) {
        return _StatusChip(
          label: 'Deployed & Verified',
          color: AppColors.primary,
          icon: Icons.check_circle_outline,
        );
      }
      if (deployOutcome!.deployOk) {
        return _StatusChip(
          label: 'Deployed — Verify Pending',
          color: AppColors.amber,
          icon: Icons.info_outline,
        );
      }
      return _StatusChip(
        label: 'Deploy Failed',
        color: AppColors.red,
        icon: Icons.cancel_outlined,
      );
    }
    if (isBlocked) {
      return _StatusChip(
        label: 'Blocked',
        color: AppColors.red,
        icon: Icons.lock_outline,
        tooltip: blockedReasons.join('; '),
      );
    }
    if (detectionResult != null &&
        detectionResult!.verdict == DetectionVerdict.error) {
      return _StatusChip(
        label: 'Scan Failed',
        color: AppColors.red,
        icon: Icons.error_outline,
      );
    }
    if (detectionResult != null) {
      return _StatusChip(
        label: 'Ready to Deploy',
        color: AppColors.primary,
        icon: Icons.check_circle_outline,
      );
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Deploy dialog (single-step, self-contained)
// ═══════════════════════════════════════════════════════════════════════════════

class _PersistDeployDialog extends StatefulWidget {
  final WebshellService service;
  final PersistMethod method;
  final bool stealthHide;
  final bool stealthTimestamp;
  final bool stealthCleanHistory;

  const _PersistDeployDialog({
    required this.service,
    required this.method,
    required this.stealthHide,
    required this.stealthTimestamp,
    required this.stealthCleanHistory,
  });

  @override
  State<_PersistDeployDialog> createState() => _PersistDeployDialogState();
}

class _PersistDeployDialogState extends State<_PersistDeployDialog> {
  late final Map<String, TextEditingController> _controllers;
  late bool _stealthHide;
  late bool _stealthTimestamp;
  late bool _stealthCleanHistory;
  bool _executing = false;
  _DeployOutcome? _outcome;
  List<_PreflightResult> _preflight = const [];
  String _deployOutput = '';
  String _verifyOutput = '';

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final p in widget.method.params)
        p.id: TextEditingController(text: p.defaultValue),
    };
    _stealthHide = widget.stealthHide && widget.method.stealth.canDotPrefix;
    _stealthTimestamp =
        widget.stealthTimestamp && widget.method.stealth.canTimestampClone;
    _stealthCleanHistory =
        widget.stealthCleanHistory && widget.method.stealth.canHistoryClean;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _collectParams() {
    final params = <String, String>{};
    for (final p in widget.method.params) {
      var val = _controllers[p.id]!.text;
      if (p.isFilePath && _stealthHide) {
        val = toDotPath(val);
      }
      params[p.id] = val;
    }
    return params;
  }

  String _sub(String template) {
    var s = template;
    for (final e in _collectParams().entries) {
      s = s.replaceAll('{${e.key}}', e.value);
    }
    return s;
  }

  String get _deployCmd {
    var cmd = _sub(widget.method.deployTemplate);
    if (_stealthCleanHistory && widget.method.stealth.canHistoryClean) {
      cmd = 'unset HISTFILE; $cmd';
    }
    return cmd;
  }

  String get _verifyCmd => _sub(widget.method.verifyTemplate);

  String? get _rollbackCmd => widget.method.rollbackTemplate == null
      ? null
      : _sub(widget.method.rollbackTemplate!);

  Future<void> _execute() async {
    setState(() => _executing = true);

    // Preflight.
    final preflight = <_PreflightResult>[];
    for (final cmd in widget.method.preflightCommands) {
      try {
        final out = await widget.service.executeCommand(cmd);
        final t = out.trim();
        if (t.startsWith('OK:')) {
          preflight.add(_PreflightResult(ok: true, message: t.substring(3)));
        } else if (t.startsWith('FAIL:')) {
          preflight.add(_PreflightResult(ok: false, message: t.substring(5)));
        } else if (t.startsWith('INFO:')) {
          preflight.add(_PreflightResult(
              ok: true, isInfo: true, message: t.substring(5)));
        } else {
          preflight.add(_PreflightResult(ok: true, message: t));
        }
      } catch (e) {
        preflight.add(_PreflightResult(ok: false, message: '[Error] $e'));
      }
    }

    // Deploy.
    String deployOutput = '';
    var deployOk = false;
    try {
      deployOutput = await widget.service.executeCommand(_deployCmd);
      deployOk = parseDeploySuccess(deployOutput);
    } catch (e) {
      deployOutput = '[Error] $e';
    }

    // Auto-verify.
    String verifyOutput = '';
    var verified = false;
    if (deployOk) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        verifyOutput = await widget.service.executeCommand(_verifyCmd);
        verified = parseVerifySuccess(verifyOutput);
      } catch (e) {
        verifyOutput = '[Error] $e';
      }
    }

    final outcome = _DeployOutcome(
      deployOk: deployOk,
      verified: verified,
      rollbackCommand: deployOk ? _rollbackCmd : null,
    );

    if (mounted) {
      setState(() {
        _executing = false;
        _outcome = outcome;
        _preflight = preflight;
        _deployOutput = deployOutput;
        _verifyOutput = verifyOutput;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.method;
    final hasStealth = m.stealth.canDotPrefix ||
        m.stealth.canTimestampClone ||
        m.stealth.canHistoryClean;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.link, color: AppColors.amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(m.name, style: AppTextStyles.heading(size: 15)),
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
              _WarningBox(text: m.warningText),
              const SizedBox(height: 12),
              for (final p in m.params)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _controllers[p.id],
                    enabled: !_executing,
                    maxLines: p.multiline ? 5 : 1,
                    minLines: p.multiline ? 3 : 1,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontFamily: 'Monaco',
                      fontFamilyFallback: ['Courier New', 'monospace'],
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: p.label,
                      hintText: p.hint,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              if (hasStealth) ...[
                const SizedBox(height: 4),
                Text('Stealth Options',
                    style: AppTextStyles.caption(
                        size: 11, color: AppColors.textMuted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (m.stealth.canDotPrefix)
                      _DeployStealthToggle(
                        label: 'Dot-Prefix Paths',
                        value: _stealthHide,
                        onChanged: (v) => setState(() => _stealthHide = v),
                      ),
                    if (m.stealth.canTimestampClone)
                      _DeployStealthToggle(
                        label: 'Clone Timestamp',
                        value: _stealthTimestamp,
                        onChanged: (v) => setState(() => _stealthTimestamp = v),
                      ),
                    if (m.stealth.canHistoryClean)
                      _DeployStealthToggle(
                        label: 'Clean History',
                        value: _stealthCleanHistory,
                        onChanged: (v) =>
                            setState(() => _stealthCleanHistory = v),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              _CommandPreview(label: 'Deploy Command', command: _deployCmd),
              const SizedBox(height: 8),
              _CommandPreview(label: 'Verify Command', command: _verifyCmd),
              if (_outcome != null) ...[
                const SizedBox(height: 12),
                _DeployResultBlock(
                  outcome: _outcome!,
                  preflight: _preflight,
                  deployOutput: _deployOutput,
                  verifyOutput: _verifyOutput,
                  rollbackCommand: _rollbackCmd,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _executing ? null : () => Navigator.pop(context, _outcome),
          child: Text(
            _outcome == null ? 'Cancel' : 'Done',
            style: AppTextStyles.caption(size: 13),
          ),
        ),
        FilledButton.icon(
          onPressed: (_executing || _outcome != null) ? null : _execute,
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
          label: Text(
            _executing ? 'Deploying…' : 'Deploy & Verify',
            style: AppTextStyles.body(size: 13, color: Colors.white),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDeep,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.caption(size: 12, color: AppColors.red),
              ),
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
          Text(label,
              style: AppTextStyles.caption(size: 11, color: AppColors.textMuted)),
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

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppTextStyles.caption(size: 10, color: AppColors.textMuted)),
            const SizedBox(height: 3),
            SelectableText(
              value,
              style: AppTextStyles.terminal(
                  size: 10.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.icon,
    this.tooltip,
  });

  final String label;
  final Color color;
  final IconData icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: AppTextStyles.caption(size: 11, color: color)),
        ],
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}

class _RollbackRow extends StatelessWidget {
  const _RollbackRow({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.undo, size: 13, color: AppColors.amber),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                command,
                style: const TextStyle(
                  fontFamily: 'Monaco',
                  fontFamilyFallback: ['Courier New', 'monospace'],
                  fontSize: 10,
                  color: AppColors.amber,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: command));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Rollback Command Copied'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.copy_outlined, size: 14),
              style: IconButton.styleFrom(
                foregroundColor: AppColors.amber,
                padding: const EdgeInsets.all(2),
                minimumSize: const Size(24, 24),
              ),
              tooltip: 'Copy Rollback',
            ),
          ],
        ),
      );
}

// ── Stealth toggle within deploy dialog ──────────────────────────────────────

class _DeployStealthToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DeployStealthToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: value
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.bgDark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: value
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank,
              size: 14,
              color: value ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(label,
                style: AppTextStyles.caption(
                    size: 11,
                    color: value ? AppColors.primary : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Deploy result block (shown inline in the dialog)
// ═══════════════════════════════════════════════════════════════════════════════

class _DeployResultBlock extends StatelessWidget {
  const _DeployResultBlock({
    required this.outcome,
    required this.preflight,
    required this.deployOutput,
    required this.verifyOutput,
    this.rollbackCommand,
  });

  final _DeployOutcome outcome;
  final List<_PreflightResult> preflight;
  final String deployOutput;
  final String verifyOutput;
  final String? rollbackCommand;

  @override
  Widget build(BuildContext context) {
    final color = outcome.verified ? AppColors.primary : AppColors.red;
    final title = outcome.verified
        ? '✓ Deployed & Verified'
        : (outcome.deployOk ? '✓ Deployed — Verification Failed' : '✗ Deploy Failed');

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
          if (preflight.isNotEmpty) ...[
            Text('Pre-flight',
                style: AppTextStyles.caption(size: 10, color: AppColors.textMuted)),
            const SizedBox(height: 3),
            for (final r in preflight)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Icon(
                      r.ok
                          ? (r.isInfo
                              ? Icons.info_outline
                              : Icons.check_circle_outline)
                          : Icons.cancel_outlined,
                      size: 13,
                      color: r.ok
                          ? (r.isInfo ? AppColors.textMuted : AppColors.primary)
                          : AppColors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        r.message,
                        style: AppTextStyles.caption(
                          size: 11,
                          color: r.ok ? AppColors.textSecondary : AppColors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
          ],
          Text('Deploy Output',
              style: AppTextStyles.caption(size: 10, color: AppColors.textMuted)),
          SelectableText(
            deployOutput.isEmpty ? '(empty)' : deployOutput,
            style: AppTextStyles.terminal(
                size: 10.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text('Verify Output',
              style: AppTextStyles.caption(size: 10, color: AppColors.textMuted)),
          SelectableText(
            verifyOutput.isEmpty ? '(empty)' : verifyOutput,
            style: AppTextStyles.terminal(
                size: 10.5, color: AppColors.textSecondary),
          ),
          if (rollbackCommand != null) ...[
            const SizedBox(height: 8),
            _RollbackRow(command: rollbackCommand!),
          ],
        ],
      ),
    );
  }
}
