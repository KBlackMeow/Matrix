/// 一键扫描页。
///
/// 迁移前是 691 行的"模块列表 + 参数面板 + 手动按钮"控制台；
/// 现在只做一件事：**把 27 个变体全跑一遍，把结果分级列给用户选**。
/// 精细操作交给各家族页（结果行提供深链）。
library;

import 'package:flutter/material.dart';

import '../../exp/core/exploit_module.dart';
import '../../exp/core/exploit_session.dart';
import '../../exp/core/exp_catalog.dart';
import '../../exp/core/exp_spec.dart';
import '../../exp/core/log_line.dart';
import '../../exp/core/scan_runner.dart';
import '../../exp/ui/exp_fields.dart';
import '../../exp/ui/exp_icons.dart';
import '../../exp/ui/exp_scaffold.dart';
import '../../exp/ui/exp_tokens.dart';
import '../../exp/ui/shell_handoff.dart';
import '../../theme/app_theme.dart';
import 'drupal_page.dart';
import 'httpd_page.dart';
import 'nacos_page.dart';
import 'php_page.dart';
import 'shiro_page.dart';
import 'spring_page.dart';
import 'struts2_page.dart';
import 'thinkphp_page.dart';
import 'tomcat_page.dart';
import 'weblogic_page.dart';
import 'xxljob_page.dart';
import 'zentao_page.dart';

class UniversalScanPage extends StatefulWidget {
  const UniversalScanPage({super.key, this.initialTargetUrl});

  final String? initialTargetUrl;

  @override
  State<UniversalScanPage> createState() => _UniversalScanPageState();
}

class _UniversalScanPageState extends State<UniversalScanPage> {
  late final TextEditingController _url = TextEditingController(
    text: widget.initialTargetUrl ?? '',
  );
  late final TextEditingController _timeout = TextEditingController(text: '10');

  final List<LogLine> _log = [];
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);
  /// 强证据：命中即证明代码执行。
  final List<ScanHit> _hits = [];

  /// 弱证据：只证明"载荷被接受"（盲打/后台任务/端点特征），需人工确认。
  final List<ScanHit> _weak = [];
  final List<ScanHit> _blocked = [];
  ScanRunner? _runner;
  bool _running = false;
  String? _summary;
  int _progress = 0;

  @override
  void dispose() {
    _url.dispose();
    _timeout.dispose();
    _tick.dispose();
    super.dispose();
  }

  String get _target => _url.text.trim();

  Future<void> _start() async {
    if (_running) return;
    if (!_isUrl(_target)) {
      setState(() => _log.add(const LogLine(LogLevel.error, '请先填写 http(s):// 开头的目标 URL')));
      return;
    }
    final timeout = int.tryParse(_timeout.text.trim()) ?? 10;
    final runner = ScanRunner();
    setState(() {
      _running = true;
      _hits.clear();
      _weak.clear();
      _blocked.clear();
      _log.clear();
      _summary = null;
      _progress = 0;
      _runner = runner;
    });
    setState(() {
      _log.add(
        LogLine(
          LogLevel.action,
          '开始扫描 ${allVariants.length} 个变体（预算 90 次请求 / 90 秒 / 3 次每秒）',
        ),
      );
    });

    await for (final event in runner.run(
      url: _target,
      timeoutSeconds: timeout,
    )) {
      if (!mounted) return;
      final line = event.toLogLine();
      setState(() {
        if (event is ScanStarted) {
          _progress = event.index + 1;
          _tick.value = _progress;
        }
        if (line != null) _log.add(line);
        if (event is ScanHitEvent) {
          if (event.hit.confidence == ScanConfidence.confirmed) {
            _hits.add(event.hit);
          } else if (event.hit.confidence == ScanConfidence.noEcho) {
            _weak.add(event.hit);
          } else if (event.hit.confidence == ScanConfidence.failed) {
            // 被拦/超时 ≠ 没有漏洞：必须让用户看见"这几个没测通"。
            _blocked.add(event.hit);
          }
        }
        if (event is ScanFinished) {
          _running = false;
          _summary =
              '确认命中 ${_hits.length} 条 · 弱证据 ${_weak.length} 条 · '
              '未测通 ${_blocked.length} 个 · 约 ${event.requests} 次请求 · '
              '${event.skipped} 个未扫 · 结束原因 ${event.reason}';
        }
      });
    }
    if (mounted) setState(() => _running = false);
  }

  void _stop() {
    _runner?.cancel();
    setState(() => _log.add(const LogLine(LogLevel.action, '用户中止扫描')));
  }

  @override
  Widget build(BuildContext context) {
    return ExpScaffold(
      icon: Icons.radar,
      title: '一键扫描利用',
      subtitle: '对全部变体做一遍检测，按置信度列出结果；选中后再利用',
      notes: const [
        '包含会修改目标状态的探测（Tomcat 写文件、Spring4Shell 改配置、XXL-JOB 建任务）',
        '命中后不会自动利用：列表里选中一条，再决定下一步',
      ],
      listenable: _tick,
      state: () => ExpWorkspaceState(
        lines: _log,
        running: _running,
        onClear: () => setState(_log.clear),
        statusLabel: _running ? 'Scanning $_progress/${allVariants.length}' : null,
      ),
      form: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _url,
            enabled: !_running,
            style: AppTextStyles.body(size: ExpText.body, color: ExpColors.text),
            decoration: expInputDecoration('目标 URL', 'http://target:8080'),
          ),
          ExpSpace.vMd,
          SizedBox(
            width: 96,
            child: TextField(
              controller: _timeout,
              enabled: !_running,
              keyboardType: TextInputType.number,
              style: AppTextStyles.body(
                size: ExpText.body,
                color: ExpColors.text,
              ),
              decoration: expInputDecoration('超时(秒)'),
            ),
          ),
          ExpSpace.vLg,
          Row(
            children: [
              FilledButton(
                onPressed: _running ? null : _start,
                style: ExpButton.primary(),
                child: Text(_running ? '扫描中…' : '开始扫描'),
              ),
              ExpSpace.hSm,
              OutlinedButton(
                onPressed: _running ? _stop : null,
                style: ExpButton.secondary(),
                child: const Text('停止'),
              ),
            ],
          ),
          if (_summary != null) ...[
            ExpSpace.vMd,
            Text(
              _summary!,
              style: AppTextStyles.caption(
                size: ExpText.caption,
                color: ExpColors.textSecondary,
              ),
            ),
          ],
          if (_blocked.isNotEmpty) ...[
            ExpSpace.vSm,
            Container(
              padding: ExpSpace.control,
              decoration: BoxDecoration(
                color: ExpColors.fill(ExpColors.warn, 0.10),
                borderRadius: ExpRadius.controlBorder,
                border: Border.all(color: ExpColors.fill(ExpColors.warn, 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 14, color: ExpColors.warn),
                  ExpSpace.hSm,
                  Expanded(
                    child: Text(
                      '${_blocked.length} 个变体没测通（被 WAF 拦或超时），'
                      '不代表没有漏洞：${_blocked.map((h) => h.variant.id).join('、')}',
                      style: AppTextStyles.caption(
                        size: ExpText.caption,
                        color: ExpColors.warn,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          ExpSpace.vLg,
          if (_hits.isEmpty && _weak.isEmpty)
            Text(
              _running ? '扫描中，结果会逐条出现…' : '尚无命中',
              style: AppTextStyles.caption(
                size: ExpText.caption,
                color: ExpColors.muted,
              ),
            ),
          if (_hits.isNotEmpty) ...[
            _sectionLabel('确认命中', ExpColors.ok),
            for (final hit in _hits) ...[
              _HitRow(
                hit: hit,
                onOpenPage: () => _openPage(hit),
                onExploit: () => _exploit(hit),
              ),
              ExpSpace.vSm,
            ],
          ],
          if (_weak.isNotEmpty) ...[
            ExpSpace.vSm,
            _sectionLabel('弱证据（需人工确认，不代表已拿下）', ExpColors.warn),
            for (final hit in _weak) ...[
              _HitRow(
                hit: hit,
                onOpenPage: () => _openPage(hit),
                onExploit: () => _exploit(hit),
              ),
              ExpSpace.vSm,
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _openPage(ScanHit hit) async {
    final page = _pageForSpec(hit.spec, _target);
    if (page == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _exploit(ScanHit hit) async {
    final module = moduleById(hit.variant.moduleId);
    if (module == null) return;
    final session = ExploitSessionController(module: module, initialUrl: _target);
    if (module.supports(ExploitCapability.getShell)) {
      await session.deployShell();
      final shell = session.shell;
      if (shell != null && mounted) {
        await ShellHandoff.open(
          context,
          shell,
          name: '${hit.spec.family} Shell',
        );
      }
      session.dispose();
      return;
    }
    if (module.supports(ExploitCapability.exec)) {
      await session.execute('id');
      final out = session.execOutput;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(out?.trim() ?? '无回显')),
        );
      }
      session.dispose();
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该变体没有可直接执行的利用动作，请进模块页操作')),
      );
    }
    session.dispose();
  }

  Widget? _pageForSpec(ExpSpec spec, String url) => switch (spec.id) {
    'struts2' => Struts2Page(initialTargetUrl: url),
    'spring' => SpringPage(initialTargetUrl: url),
    'thinkphp' => ThinkphpPage(initialTargetUrl: url),
    'drupal' => DrupalPage(initialTargetUrl: url),
    'php' => PhpPage(initialTargetUrl: url),
    'tomcat' => TomcatPage(initialTargetUrl: url),
    'weblogic' => WeblogicPage(initialTargetUrl: url),
    'httpd' => HttpdPage(initialTargetUrl: url),
    'nacos' => NacosPage(initialTargetUrl: url),
    'xxljob' => XxljobPage(initialTargetUrl: url),
    'shiro' => ShiroPage(initialTargetUrl: url),
    'zentao' => ZentaoPage(initialTargetUrl: url),
    _ => null,
  };

  static bool _isUrl(String v) {
    final uri = Uri.tryParse(v);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }
}

Widget _sectionLabel(String text, Color color) => Padding(
  padding: const EdgeInsets.only(bottom: ExpSpace.sm),
  child: Row(
    children: [
      Container(
        width: 3,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      ExpSpace.hSm,
      Text(
        text,
        style: AppTextStyles.heading(size: ExpText.section, color: color),
      ),
    ],
  ),
);

class _HitRow extends StatelessWidget {
  const _HitRow({
    required this.hit,
    required this.onOpenPage,
    required this.onExploit,
  });

  final ScanHit hit;
  final VoidCallback onOpenPage;
  final VoidCallback onExploit;

  @override
  Widget build(BuildContext context) {
    final color = switch (hit.confidence) {
      ScanConfidence.confirmed => ExpColors.ok,
      ScanConfidence.noEcho => ExpColors.warn,
      ScanConfidence.failed => ExpColors.muted,
      ScanConfidence.miss => ExpColors.muted,
    };
    return Container(
      padding: ExpSpace.control,
      decoration: BoxDecoration(
        color: ExpColors.fill(color, 0.08),
        borderRadius: ExpRadius.controlBorder,
        border: Border.all(color: ExpColors.fill(color, 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(hit.spec.icon.data, size: 14, color: color),
              ExpSpace.hSm,
              Expanded(
                child: Text(
                  '${hit.spec.family} · ${hit.variant.label}',
                  style: AppTextStyles.heading(
                    size: ExpText.body,
                    color: ExpColors.text,
                  ),
                ),
              ),
              Text(
                hit.confidence.label,
                style: AppTextStyles.caption(
                  size: ExpText.caption,
                  color: color,
                ),
              ),
            ],
          ),
          if (hit.outcome.detail.trim().isNotEmpty) ...[
            ExpSpace.vXs,
            Text(
              hit.outcome.detail,
              style: AppTextStyles.caption(
                size: ExpText.caption,
                color: ExpColors.textSecondary,
              ),
            ),
          ],
          ExpSpace.vSm,
          Wrap(
            spacing: ExpSpace.sm,
            children: [
              FilledButton(
                onPressed: onExploit,
                style: ExpButton.primary(),
                child: const Text('利用'),
              ),
              OutlinedButton(
                onPressed: onOpenPage,
                style: ExpButton.secondary(),
                child: const Text('打开模块页'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
