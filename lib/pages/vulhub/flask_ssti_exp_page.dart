import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class FlaskSstiExpPage extends BaseVulhubExpPage {
  const FlaskSstiExpPage({super.key});

  @override
  State<FlaskSstiExpPage> createState() => _FlaskSstiPageState();
}

class _FlaskSstiPageState extends BaseVulhubExpPageState<FlaskSstiExpPage> {
  @override
  IconData get pageIcon => Icons.code;
  @override
  String get appBarTitle => 'Flask / Jinja2 SSTI 服务端模板注入 RCE';
  @override
  String get cardTitle => 'Flask / Jinja2 SSTI';
  @override
  String get cardSubtitle => '服务端 Jinja2 模板注入，通过 URL 参数执行任意 Python 代码';

  final _urlCtrl = TextEditingController();
  final _paramCtrl = TextEditingController(text: 'name');
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();
  final _headersCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  SstiInjectMode _mode = SstiInjectMode.get;

  Map<String, String> _parseHeaders() {
    final result = <String, String>{};
    for (final line in _headersCtrl.text.trim().split('\n')) {
      final idx = line.indexOf(':');
      if (idx > 0) {
        result[line.substring(0, idx).trim()] =
            line.substring(idx + 1).trim();
      }
    }
    return result;
  }

  FlaskSstiExpService _svc() => FlaskSstiExpService(
        baseUrl: _urlCtrl.text.trim(),
        paramName:
            _paramCtrl.text.trim().isEmpty ? 'name' : _paramCtrl.text.trim(),
        injectMode: _mode,
        extraHeaders: _parseHeaders(),
        rawBody: _bodyCtrl.text,
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 Jinja2 SSTI（233×233=54289）...');
    try {
      final r = await _svc().check();
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 SSTI');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] SSTI RCE 执行: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(
          out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出或执行失败');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _paramCtrl.dispose();
    _cmdCtrl.dispose();
    _timeoutCtrl.dispose();
    _headersCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }


  String get _bodyHint => switch (_mode) {
        SstiInjectMode.post =>
          'form: param=value&inject={{INJECT}}\n'
          'json: {"key":"{{INJECT}}"}',
        _ => '仅 POST 模式生效',
      };

  Widget _multiTf(
    TextEditingController c,
    String label,
    String hint, {
    int minLines = 3,
    bool enabled = true,
  }) =>
      TextField(
        controller: c,
        enabled: enabled,
        minLines: minLines,
        maxLines: null,
        style: AppTextStyles.terminal(
            size: 11,
            color: enabled ? AppColors.textPrimary : AppColors.textMuted),
        decoration: vInputDec(label, hint),
      );

  @override
  Widget buildLeftPanel(BuildContext context) {
    final isPost = _mode == SstiInjectMode.post;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          vSecTitle('目标配置'),
          vTf(_urlCtrl, '目标 URL', 'http://localhost:8080'),
          const SizedBox(height: 8),
          SegmentedButton<SstiInjectMode>(
            segments: const [
              ButtonSegment(value: SstiInjectMode.get, label: Text('GET')),
              ButtonSegment(value: SstiInjectMode.post, label: Text('POST')),
              ButtonSegment(
                  value: SstiInjectMode.header, label: Text('Header')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
            style: ButtonStyle(
              textStyle:
                  WidgetStateProperty.all(const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 8),
          vTf(_paramCtrl, '注入参数名 (GET)', 'name',
              enabled: _mode == SstiInjectMode.get),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            '超时(s)',
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 12),
          vSecTitle('请求头'),
          _multiTf(
            _headersCtrl,
            '自定义 Headers',
            'Authorization: Bearer token\nX-Forwarded-For: 127.0.0.1',
          ),
          const SizedBox(height: 12),
          vSecTitle('请求体'),
          _multiTf(
            _bodyCtrl,
            isPost ? '请求体（{{INJECT}} 为注入点）' : '请求体（POST 模式生效）',
            _bodyHint,
            minLines: 4,
            enabled: isPost,
          ),
          const SizedBox(height: 8),
          vBtn('检测 SSTI', running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle('命令执行'),
          vTf(_cmdCtrl, '命令', 'id'),
          const SizedBox(height: 8),
          vBtn('执行命令', running ? null : _exec),
        ],
      ),
    );
  }
}
