import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../connectors/connector_factory.dart';
import '../database/database_helper.dart';
import '../models/project.dart';
import '../models/webshell.dart';
import '../theme/app_theme.dart';
import '../app/localization.dart';
import 'webshell_interactive_page.dart';

/// Webshell 管理页面：创建、编辑、删除
class WebshellManagementPage extends StatefulWidget {
  final Project project;
  final VoidCallback onSwitchProject;

  const WebshellManagementPage({
    super.key,
    required this.project,
    required this.onSwitchProject,
  });

  @override
  State<WebshellManagementPage> createState() => _WebshellManagementPageState();
}

class _WebshellManagementPageState extends State<WebshellManagementPage> {
  final DatabaseHelper _db = DatabaseHelper();
  List<Webshell> _webshells = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWebshells();
  }

  @override
  void didUpdateWidget(WebshellManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id) {
      _loadWebshells();
    }
  }

  Future<void> _loadWebshells() async {
    setState(() => _loading = true);
    final list = await _db.getWebshellsByProject(widget.project.id);
    setState(() {
      _webshells = list;
      _loading = false;
    });
  }

  Future<void> _showCreateDialog() async {
    final urlController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController();
    String selectedMethod = 'POST';
    String selectedConnectorType = 'php_eval';
    bool obscurePassword = true;
    bool detecting = false;
    List<_DetectResult>? detectResults;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> runDetect() async {
            final url = urlController.text.trim();
            final pass = passwordController.text;
            if (url.isEmpty || pass.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(S.snackFillUrlAndPassword),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
              return;
            }
            setDialogState(() {
              detecting = true;
              detectResults = null;
            });
            final results = await _autoDetect(
              url: url,
              password: pass,
              method: selectedMethod,
            );
            final first = results.firstWhere(
              (r) => r.ok,
              orElse: () => results.first,
            );
            setDialogState(() {
              detecting = false;
              detectResults = results;
              if (first.ok) selectedConnectorType = first.type;
            });
          }

          return AlertDialog(
            backgroundColor: AppColors.bgCard,
            title: Text(
              S.actionAddWebshell,
              style: AppTextStyles.heading(color: AppColors.primary),
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildField(
                      controller: urlController,
                      label: S.fieldWebshellUrl,
                      hint: S.hintWebshellUrl,
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    _PasswordParamField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      connectorType: selectedConnectorType,
                      onToggleObscure: () => setDialogState(
                        () => obscurePassword = !obscurePassword,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: nameController,
                      label: S.fieldWebshellName,
                      hint: S.hintWebshellName,
                    ),
                    const SizedBox(height: 16),
                    _ConnectorRow(
                      value: selectedConnectorType,
                      detecting: detecting,
                      onChanged: (v) => setDialogState(() {
                        selectedConnectorType = v;
                        final fixed = ConnectorFactory.fixedMethod(v);
                        if (fixed != null) selectedMethod = fixed;
                        // 切换类型时，若参数名为空则自动回填默认值
                        if (passwordController.text.isEmpty) {
                          final def = ConnectorFactory.defaultParam(v);
                          if (def.isNotEmpty) passwordController.text = def;
                        }
                      }),
                      onDetect: runDetect,
                    ),
                    if (detectResults != null)
                      _DetectResultPanel(results: detectResults!),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          S.labelRequestMethod,
                          style: AppTextStyles.body(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _MethodToggle(
                          value: selectedMethod,
                          lockedMethod: ConnectorFactory.fixedMethod(
                            selectedConnectorType,
                          ),
                          onChanged: (v) =>
                              setDialogState(() => selectedMethod = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  S.btnCancel,
                  style: AppTextStyles.body(color: AppColors.textSecondary),
                ),
              ),
              FilledButton(
                onPressed: () {
                  if (urlController.text.trim().isEmpty ||
                      passwordController.text.isEmpty) {
                    return;
                  }
                  Navigator.pop(context, true);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: Text(
                  S.btnAdd,
                  style: AppTextStyles.body(color: AppColors.bgDark),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (result == true &&
        urlController.text.trim().isNotEmpty &&
        passwordController.text.isNotEmpty) {
      final url = urlController.text.trim();
      final name = nameController.text.trim().isEmpty
          ? _deriveNameFromUrl(url)
          : nameController.text.trim();
      await _db.createWebshell(
        widget.project.id,
        name: name,
        url: url,
        password: passwordController.text,
        method: selectedMethod,
        type: ConnectorFactory.typeLabel(selectedConnectorType),
        connectorType: selectedConnectorType,
      );
      _loadWebshells();
    }
  }

  Future<void> _showEditDialog(Webshell ws) async {
    final urlController = TextEditingController(text: ws.url);
    final passwordController = TextEditingController(text: ws.password ?? '');
    final nameController = TextEditingController(text: ws.name);
    String selectedMethod = ws.method;
    String selectedConnectorType = ws.connectorType;
    bool obscurePassword = true;
    bool detecting = false;
    List<_DetectResult>? detectResults;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> runDetect() async {
            final url = urlController.text.trim();
            final pass = passwordController.text;
            if (url.isEmpty || pass.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(S.snackFillUrlAndPassword),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
              return;
            }
            setDialogState(() {
              detecting = true;
              detectResults = null;
            });
            final results = await _autoDetect(
              url: url,
              password: pass,
              method: selectedMethod,
            );
            final first = results.firstWhere(
              (r) => r.ok,
              orElse: () => results.first,
            );
            setDialogState(() {
              detecting = false;
              detectResults = results;
              if (first.ok) selectedConnectorType = first.type;
            });
          }

          return AlertDialog(
            backgroundColor: AppColors.bgCard,
            title: Text(
              S.titleEditWebshell,
              style: AppTextStyles.heading(color: AppColors.primary),
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildField(
                      controller: urlController,
                      label: S.fieldWebshellUrl,
                      hint: S.hintWebshellUrl,
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    _PasswordParamField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      connectorType: selectedConnectorType,
                      onToggleObscure: () => setDialogState(
                        () => obscurePassword = !obscurePassword,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: nameController,
                      label: S.fieldWebshellName,
                      hint: S.hintWebshellName,
                    ),
                    const SizedBox(height: 16),
                    _ConnectorRow(
                      value: selectedConnectorType,
                      detecting: detecting,
                      onChanged: (v) => setDialogState(() {
                        selectedConnectorType = v;
                        final fixed = ConnectorFactory.fixedMethod(v);
                        if (fixed != null) selectedMethod = fixed;
                      }),
                      onDetect: runDetect,
                    ),
                    if (detectResults != null)
                      _DetectResultPanel(results: detectResults!),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          S.labelRequestMethod,
                          style: AppTextStyles.body(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _MethodToggle(
                          value: selectedMethod,
                          lockedMethod: ConnectorFactory.fixedMethod(
                            selectedConnectorType,
                          ),
                          onChanged: (v) =>
                              setDialogState(() => selectedMethod = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  S.btnCancel,
                  style: AppTextStyles.body(color: AppColors.textSecondary),
                ),
              ),
              FilledButton(
                onPressed: () {
                  if (urlController.text.trim().isEmpty ||
                      passwordController.text.isEmpty) {
                    return;
                  }
                  Navigator.pop(context, true);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: Text(
                  S.btnSave,
                  style: AppTextStyles.body(color: AppColors.bgDark),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (result == true &&
        urlController.text.trim().isNotEmpty &&
        passwordController.text.isNotEmpty) {
      final url = urlController.text.trim();
      final name = nameController.text.trim().isEmpty
          ? _deriveNameFromUrl(url)
          : nameController.text.trim();
      await _db.updateWebshell(
        ws.copyWith(
          name: name,
          url: url,
          password: passwordController.text,
          type: ConnectorFactory.typeLabel(selectedConnectorType),
          method: selectedMethod,
          connectorType: selectedConnectorType,
        ),
      );
      _loadWebshells();
    }
  }

  Future<void> _showDeleteConfirm(Webshell ws) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(S.btnDelete, style: const TextStyle(color: AppColors.red)),
        content: Text(
          S.confirmDeleteWebshell(ws.name),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              S.btnCancel,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text(
              S.btnDelete,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      await _db.deleteWebshell(ws.id);
      _loadWebshells();
    }
  }

  String _deriveNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) return segments.last;
      return uri.host.isNotEmpty ? uri.host : url;
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 项目信息栏
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: const Icon(
                  Icons.terminal,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.webshellManagementTitle(widget.project.name),
                      style: AppTextStyles.heading(
                        size: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      widget.project.domain,
                      style: AppTextStyles.caption(
                        size: 13,
                        color: AppColors.cyan,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: widget.onSwitchProject,
                icon: const Icon(
                  Icons.swap_horiz,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                label: Text(
                  S.btnSwitchProject,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 工具栏
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _showCreateDialog,
              icon: const Icon(Icons.add, size: 18),
              label: Text(S.actionAddWebshell),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.bgDark,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: _loading ? null : _loadWebshells,
              icon: const Icon(Icons.refresh),
              color: AppColors.textSecondary,
              tooltip: S.actionRefresh,
            ),
            const Spacer(),
            if (!_loading)
              Text(
                S.webshellCount(_webshells.length),
                style: AppTextStyles.caption(color: AppColors.textMuted),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // 列表
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : _webshells.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.terminal_outlined,
                        size: 64,
                        color: AppColors.textSecondary.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        S.webshellEmptyHint(S.actionAddWebshell),
                        style: AppTextStyles.body(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _webshells.length,
                  itemBuilder: (context, index) {
                    final ws = _webshells[index];
                    return _WebshellCard(
                      webshell: ws,
                      onEnter: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WebshellInteractivePage(webshell: ws),
                        ),
                      ),
                      onEdit: () => _showEditDialog(ws),
                      onDelete: () => _showDeleteConfirm(ws),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool autofocus = false,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'monospace',
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}

// ─── Webshell 卡片 ────────────────────────────────────────────────────────────

class _WebshellCard extends StatefulWidget {
  final Webshell webshell;
  final VoidCallback onEnter;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _WebshellCard({
    required this.webshell,
    required this.onEnter,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_WebshellCard> createState() => _WebshellCardState();
}

class _WebshellCardState extends State<_WebshellCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isOnline = widget.webshell.status == 1;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onEnter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.bgElevated : AppColors.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : AppColors.border,
              width: _hovered ? 1.2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(
                  alpha: _hovered ? 0.14 : 0.0,
                ),
                blurRadius: 14,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              // 状态指示点
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isOnline ? AppColors.primary : AppColors.textMuted,
                  shape: BoxShape.circle,
                  boxShadow: isOnline
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 14),
              // 图标
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.terminal,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.webshell.name,
                            style: AppTextStyles.body(
                              size: 14,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _Tag(
                          label: ConnectorFactory.shortLabel(
                            widget.webshell.connectorType,
                          ),
                          color: widget.webshell.connectorType.startsWith('jsp')
                              ? AppColors.amber
                              : widget.webshell.connectorType.startsWith('asp')
                              ? Colors.purple.shade300
                              : AppColors.cyan,
                        ),
                        const SizedBox(width: 6),
                        _Tag(
                          label: widget.webshell.method,
                          color: widget.webshell.method == 'POST'
                              ? AppColors.cyan
                              : AppColors.amber,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.webshell.url,
                            style: AppTextStyles.caption(
                              size: 12,
                              color: AppColors.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: widget.webshell.url),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(S.snackCopied),
                                backgroundColor: AppColors.bgCard,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: const Icon(
                            Icons.copy_outlined,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    if (widget.webshell.password != null &&
                        widget.webshell.password!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${S.webshellPasswordLabel}: ${'•' * widget.webshell.password!.length.clamp(1, 12)}',
                        style: AppTextStyles.caption(
                          size: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // 操作按钮
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final screenW = MediaQuery.of(ctx).size.width;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (screenW > 680) ...[
                        Text(
                          _formatDate(widget.webshell.createdAt),
                          style: AppTextStyles.caption(
                            size: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        color: AppColors.cyan,
                        tooltip: S.tooltipEdit,
                        splashRadius: 18,
                      ),
                      IconButton(
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: AppColors.red,
                        tooltip: S.tooltipDelete,
                        splashRadius: 18,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ─── GET/POST 切换按钮 ────────────────────────────────────────────────────────

class _MethodToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  /// 非 null 时表示该连接器固定使用此方法，切换按钮置灰并展示说明
  final String? lockedMethod;

  const _MethodToggle({
    required this.value,
    required this.onChanged,
    this.lockedMethod,
  });

  @override
  Widget build(BuildContext context) {
    final locked = lockedMethod != null;
    return Row(
      children: [
        ...['GET', 'POST'].map((method) {
          final selected = value == method;
          return GestureDetector(
            onTap: locked ? null : () => onChanged(method),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: locked
                    ? (selected
                          ? AppColors.textMuted.withValues(alpha: 0.15)
                          : AppColors.bgElevated.withValues(alpha: 0.5))
                    : (selected
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : AppColors.bgElevated),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: locked
                      ? AppColors.border.withValues(alpha: 0.5)
                      : (selected ? AppColors.primary : AppColors.border),
                ),
              ),
              child: Text(
                method,
                style: AppTextStyles.caption(
                  size: 13,
                  color: locked
                      ? (selected
                            ? AppColors.textSecondary
                            : AppColors.textMuted.withValues(alpha: 0.5))
                      : (selected
                            ? AppColors.primary
                            : AppColors.textSecondary),
                ),
              ),
            ),
          );
        }),
        if (locked)
          Row(
            children: [
              const Icon(
                Icons.lock_outline,
                size: 13,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                S.connectorMethodFixed,
                style: AppTextStyles.caption(
                  size: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ─── 标签 ─────────────────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String label;
  final Color color;

  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: AppTextStyles.caption(size: 11, color: color)),
    );
  }
}

// ─── Connector 类型下拉选择器 ────────────────────────────────────────────────

class _ConnectorTypeDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _ConnectorTypeDropdown({required this.value, required this.onChanged});

  List<(String, String)> _connectorOptions() => [
    ('php_eval', S.connectorUiLabel('php_eval')),
    ('php_b64rot13', S.connectorUiLabel('php_b64rot13')),
    ('php_behinder', S.connectorUiLabel('php_behinder')),
    ('php_passthru', S.connectorUiLabel('php_passthru')),
    ('jsp_classloader', S.connectorUiLabel('jsp_classloader')),
    ('jsp_behinder', S.connectorUiLabel('jsp_behinder')),
    ('jsp_runtime', S.connectorUiLabel('jsp_runtime')),
    ('asp_wscript', S.connectorUiLabel('asp_wscript')),
    ('aspx_cmd', S.connectorUiLabel('aspx_cmd')),
  ];

  @override
  Widget build(BuildContext context) {
    final bool hasValue = _connectorOptions().any((o) => o.$1 == value);
    final List<DropdownMenuItem<String>> items = _connectorOptions().map((o) {
      return DropdownMenuItem<String>(
        value: o.$1,
        child: Text(
          o.$2,
          style: AppTextStyles.body(color: AppColors.textPrimary, size: 13),
        ),
      );
    }).toList();

    if (!hasValue && value.isNotEmpty) {
      items.add(
        DropdownMenuItem<String>(
          value: value,
          child: Text(
            S.unknownConnector(value),
            style: AppTextStyles.body(color: AppColors.red, size: 13),
          ),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: value,
      decoration: InputDecoration(
        labelText: S.fieldConnectorType,
        labelStyle: AppTextStyles.caption(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      dropdownColor: AppColors.bgCard,
      style: AppTextStyles.body(color: AppColors.textPrimary, size: 13),
      items: items,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// ─── 密码/参数名字段（根据 connector 显示上下文提示）────────────────────────────

class _PasswordParamField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscureText;
  final String connectorType;
  final VoidCallback onToggleObscure;

  const _PasswordParamField({
    required this.controller,
    required this.obscureText,
    required this.connectorType,
    required this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    final defaultParam = ConnectorFactory.defaultParam(connectorType);
    final isBehinder =
        connectorType == 'jsp_behinder' || connectorType == 'php_behinder';
    final hint = isBehinder
        ? S.hintPasswordKey
        : (defaultParam.isNotEmpty ? S.hintParamName(defaultParam) : '');

    final labelText = isBehinder ? S.fieldPasswordKey : S.fieldParamName;
    final helperText = isBehinder
        ? S.helperPasswordKey
        : S.helperParamName(defaultParam);

    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'monospace',
      ),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintText: hint,
        hintStyle: AppTextStyles.caption(color: AppColors.textMuted, size: 12),
        helperText: helperText,
        helperStyle: AppTextStyles.caption(
          color: AppColors.textMuted,
          size: 11,
        ),
        helperMaxLines: 2,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.5),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: AppColors.border.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscureText
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: AppColors.textSecondary,
            size: 20,
          ),
          onPressed: onToggleObscure,
        ),
      ),
    );
  }
}

// ─── 连接器行（下拉 + 自动检测按钮）────────────────────────────────────────────

class _ConnectorRow extends StatelessWidget {
  final String value;
  final bool detecting;
  final ValueChanged<String> onChanged;
  final VoidCallback onDetect;

  const _ConnectorRow({
    required this.value,
    required this.detecting,
    required this.onChanged,
    required this.onDetect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ConnectorTypeDropdown(value: value, onChanged: onChanged),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: detecting ? null : onDetect,
            icon: detecting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.radar_rounded, size: 16),
            label: Text(detecting ? S.statusChecking : S.btnAutoDetect),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── 检测结果数据类 ───────────────────────────────────────────────────────────

class _DetectResult {
  final String type;
  final bool ok;
  final String msg;
  const _DetectResult(this.type, this.ok, this.msg);
}

// ─── 检测逻辑（并发探测 7 种连接器）─────────────────────────────────────────────

Future<List<_DetectResult>> _autoDetect({
  required String url,
  required String password,
  required String method,
}) async {
  final futures = ConnectorFactory.allTypes.map((type) async {
    try {
      final ws = Webshell(
        id: 0,
        projectId: 0,
        name: '_probe',
        url: url,
        password: password,
        type: ConnectorFactory.typeLabel(type),
        method: method,
        connectorType: type,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      // ClassLoader 马首包需上传整段 agent + defineClass，远超 6s
      final pingTimeout = type == 'jsp_classloader'
          ? const Duration(seconds: 125)
          : const Duration(seconds: 6);
      final ok = await ConnectorFactory.create(ws).ping().timeout(pingTimeout);
      return _DetectResult(type, ok, ok ? S.detectPingOk : S.detectPingNo);
    } on TimeoutException {
      return _DetectResult(type, false, S.detectPingTimeout);
    } catch (_) {
      return _DetectResult(type, false, S.detectPingConnectFailed);
    }
  });
  return Future.wait(futures);
}

// ─── 检测结果面板 ─────────────────────────────────────────────────────────────

class _DetectResultPanel extends StatelessWidget {
  final List<_DetectResult> results;

  const _DetectResultPanel({required this.results});

  @override
  Widget build(BuildContext context) {
    final working = results.where((r) => r.ok).length;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.bgDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: working > 0
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                working > 0 ? Icons.check_circle_outline : Icons.info_outline,
                size: 13,
                color: working > 0 ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                working > 0 ? S.detectSuccess : S.detectFailed,
                style: AppTextStyles.caption(
                  size: 11,
                  color: working > 0 ? AppColors.primary : AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...results.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Icon(
                    r.ok
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    size: 13,
                    color: r.ok ? AppColors.primary : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: Text(
                      ConnectorFactory.shortLabel(r.type),
                      style: AppTextStyles.caption(
                        size: 12,
                        color: r.ok
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                  Text(
                    r.msg,
                    style: AppTextStyles.caption(
                      size: 11,
                      color: r.ok ? AppColors.primary : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
