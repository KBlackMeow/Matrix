import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/project.dart';
import '../models/webshell.dart';
import '../theme/app_theme.dart';
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
    bool obscurePassword = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: Text(
            '添加 Webshell',
            style: AppTextStyles.heading(color: AppColors.primary),
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildField(
                  controller: urlController,
                  label: 'Webshell 地址 *',
                  hint: 'http://example.com/shell.php',
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    labelText: '密码（可选）',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.5)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscurePassword = !obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: nameController,
                  label: '备注名称（可选）',
                  hint: '例如：后台管理 Shell',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      '请求方法：',
                      style: AppTextStyles.body(color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    _MethodToggle(
                      value: selectedMethod,
                      onChanged: (v) => setDialogState(() => selectedMethod = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消',
                  style: AppTextStyles.body(color: AppColors.textSecondary)),
            ),
            FilledButton(
              onPressed: () {
                if (urlController.text.trim().isEmpty) return;
                Navigator.pop(context, true);
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text('添加',
                  style: AppTextStyles.body(color: AppColors.bgDark)),
            ),
          ],
        ),
      ),
    );

    if (result == true && urlController.text.trim().isNotEmpty) {
      final url = urlController.text.trim();
      final name = nameController.text.trim().isEmpty
          ? _deriveNameFromUrl(url)
          : nameController.text.trim();
      await _db.createWebshell(
        widget.project.id,
        name: name,
        url: url,
        password: passwordController.text.isEmpty ? null : passwordController.text,
        method: selectedMethod,
      );
      _loadWebshells();
    }
  }

  Future<void> _showEditDialog(Webshell ws) async {
    final urlController = TextEditingController(text: ws.url);
    final passwordController = TextEditingController(text: ws.password ?? '');
    final nameController = TextEditingController(text: ws.name);
    String selectedMethod = ws.method;
    bool obscurePassword = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: Text(
            '编辑 Webshell',
            style: AppTextStyles.heading(color: AppColors.primary),
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildField(
                  controller: urlController,
                  label: 'Webshell 地址 *',
                  hint: 'http://example.com/shell.php',
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    labelText: '密码（可选）',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.5)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscurePassword = !obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: nameController,
                  label: '备注名称（可选）',
                  hint: '例如：后台管理 Shell',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      '请求方法：',
                      style: AppTextStyles.body(color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    _MethodToggle(
                      value: selectedMethod,
                      onChanged: (v) => setDialogState(() => selectedMethod = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消',
                  style: AppTextStyles.body(color: AppColors.textSecondary)),
            ),
            FilledButton(
              onPressed: () {
                if (urlController.text.trim().isEmpty) return;
                Navigator.pop(context, true);
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text('保存',
                  style: AppTextStyles.body(color: AppColors.bgDark)),
            ),
          ],
        ),
      ),
    );

    if (result == true && urlController.text.trim().isNotEmpty) {
      final url = urlController.text.trim();
      final name = nameController.text.trim().isEmpty
          ? _deriveNameFromUrl(url)
          : nameController.text.trim();
      await _db.updateWebshell(ws.copyWith(
        name: name,
        url: url,
        password: passwordController.text.isEmpty ? null : passwordController.text,
        method: selectedMethod,
      ));
      _loadWebshells();
    }
  }

  Future<void> _showDeleteConfirm(Webshell ws) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('确认删除', style: TextStyle(color: AppColors.red)),
        content: Text(
          '确定要删除「${ws.name}」吗？此操作不可恢复。',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
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
                      color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                child: const Icon(Icons.terminal,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Webshell管理 · ${widget.project.name}',
                      style: AppTextStyles.heading(
                          size: 15, color: AppColors.textPrimary),
                    ),
                    Text(
                      widget.project.domain,
                      style:
                          AppTextStyles.caption(size: 13, color: AppColors.cyan),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: widget.onSwitchProject,
                icon: const Icon(Icons.swap_horiz,
                    size: 16, color: AppColors.textSecondary),
                label: Text('切换项目',
                    style:
                        AppTextStyles.caption(color: AppColors.textSecondary)),
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
              label: const Text('添加 Webshell'),
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
              tooltip: '刷新',
            ),
            const Spacer(),
            if (!_loading)
              Text(
                '共 ${_webshells.length} 条',
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
                            color:
                                AppColors.textSecondary.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无 Webshell，点击「添加 Webshell」开始',
                            style: AppTextStyles.body(
                                color: AppColors.textSecondary),
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
                              builder: (_) =>
                                  WebshellInteractivePage(webshell: ws),
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
          borderSide:
              BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}

// ─── Webshell 卡片 ────────────────────────────────────────────────────────────

class _WebshellCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isOnline = webshell.status == 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
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
                      )
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
                  color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child:
                const Icon(Icons.terminal, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      webshell.name,
                      style: AppTextStyles.body(
                          size: 14, color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    _Tag(
                      label: webshell.method,
                      color: webshell.method == 'POST'
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
                        webshell.url,
                        style: AppTextStyles.caption(
                            size: 12, color: AppColors.primary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: webshell.url));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('已复制到剪贴板'),
                            backgroundColor: AppColors.bgCard,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: const Icon(Icons.copy_outlined,
                          size: 14, color: AppColors.textMuted),
                    ),
                  ],
                ),
                if (webshell.password != null &&
                    webshell.password!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '密码: ${'•' * webshell.password!.length.clamp(1, 12)}',
                    style:
                        AppTextStyles.caption(size: 11, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          // 操作按钮
          Text(
            _formatDate(webshell.createdAt),
            style: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onEnter,
            icon: const Icon(Icons.terminal, size: 14),
            label: const Text('进入'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: AppColors.cyan,
            tooltip: '编辑',
            splashRadius: 18,
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            color: AppColors.red,
            tooltip: '删除',
            splashRadius: 18,
          ),
        ],
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

  const _MethodToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['GET', 'POST'].map((method) {
        final selected = value == method;
        return GestureDetector(
          onTap: () => onChanged(method),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected
                    ? AppColors.primary
                    : AppColors.border,
              ),
            ),
            child: Text(
              method,
              style: AppTextStyles.caption(
                size: 13,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
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
      child: Text(
        label,
        style: AppTextStyles.caption(size: 11, color: color),
      ),
    );
  }
}
