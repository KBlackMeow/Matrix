import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';

/// 项目管理页面：创建、编辑、删除
class ProjectManagementPage extends StatefulWidget {
  final Project? selectedProject;
  final void Function(Project project) onEnterInfoCollection;
  final void Function(Project project) onEnterWebshell;
  final void Function(Project project) onEnterExp;

  const ProjectManagementPage({
    super.key,
    this.selectedProject,
    required this.onEnterInfoCollection,
    required this.onEnterWebshell,
    required this.onEnterExp,
  });

  @override
  State<ProjectManagementPage> createState() => _ProjectManagementPageState();
}

class _ProjectManagementPageState extends State<ProjectManagementPage> {
  final DatabaseHelper _db = DatabaseHelper();
  List<Project> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _loading = true);
    final projects = await _db.getAllProjects();
    setState(() {
      _projects = projects;
      _loading = false;
    });
  }

  Future<void> _showCreateDialog() async {
    final nameController = TextEditingController();
    final domainController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(
          '新建项目',
          style: AppTextStyles.heading(color: AppColors.primary),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: '项目名称',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: domainController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: '域名或ID *',
                  hintText: '例如：example.com 或 target-001',
                  hintStyle: const TextStyle(color: Color(0xFF6E7681)),
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                maxLines: 3,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: '描述（可选）',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: AppTextStyles.body(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty ||
                  domainController.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(context, true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text('创建', style: AppTextStyles.body(color: AppColors.bgDark)),
          ),
        ],
      ),
    );

    if (result == true &&
        nameController.text.trim().isNotEmpty &&
        domainController.text.trim().isNotEmpty) {
      await _db.createProject(
        nameController.text.trim(),
        domain: domainController.text.trim(),
        description: descController.text.trim().isEmpty ? null : descController.text.trim(),
      );
      _loadProjects();
    }
  }

  Future<void> _showEditDialog(Project project) async {
    final nameController = TextEditingController(text: project.name);
    final domainController = TextEditingController(text: project.domain);
    final descController = TextEditingController(text: project.description ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(
          '编辑项目 #${project.id}',
          style: AppTextStyles.heading(color: AppColors.primary),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: '项目名称',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: domainController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: '域名或ID *',
                  hintText: '例如：example.com 或 target-001',
                  hintStyle: const TextStyle(color: Color(0xFF6E7681)),
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                maxLines: 3,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: '描述（可选）',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty ||
                  domainController.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(context, true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('保存', style: TextStyle(color: Color(0xFF0D1117))),
          ),
        ],
      ),
    );

    if (result == true &&
        nameController.text.trim().isNotEmpty &&
        domainController.text.trim().isNotEmpty) {
      await _db.updateProject(project.copyWith(
        name: nameController.text.trim(),
        domain: domainController.text.trim(),
        description: descController.text.trim().isEmpty ? null : descController.text.trim(),
      ));
      _loadProjects();
    }
  }

  Future<void> _showDeleteConfirm(Project project) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text(
          '确认删除',
          style: TextStyle(color: AppColors.red),
        ),
        content: Text(
          '确定要删除项目「${project.name}」吗？此操作不可恢复。',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
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
      await _db.deleteProject(project.id);
      _loadProjects();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Web 模式提示
        if (kIsWeb)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.5)),
        ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.cyan, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Web 模式：数据仅保存在内存中，刷新页面将丢失。请使用桌面版以持久化存储。',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        // 工具栏
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _showCreateDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建项目'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.bgDark,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: _loading ? null : _loadProjects,
              icon: const Icon(Icons.refresh),
              color: const Color(0xFF8B949E),
              tooltip: '刷新',
            ),
          ],
        ),
        const SizedBox(height: 24),
        // 项目列表
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : _projects.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.folder_off_outlined,
                            size: 64,
                            color: AppColors.textSecondary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '暂无项目，点击「新建项目」开始',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _projects.length,
                      itemBuilder: (context, index) {
                        final project = _projects[index];
                        return _ProjectCard(
                          project: project,
                          onEdit: () => _showEditDialog(project),
                          onDelete: () => _showDeleteConfirm(project),
                          onEnterInfoCollection: () => widget.onEnterInfoCollection(project),
                          onEnterWebshell: () => widget.onEnterWebshell(project),
                          onEnterExp: () => widget.onEnterExp(project),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onEnterInfoCollection;
  final VoidCallback onEnterWebshell;
  final VoidCallback onEnterExp;

  const _ProjectCard({
    required this.project,
    required this.onEdit,
    required this.onDelete,
    required this.onEnterInfoCollection,
    required this.onEnterWebshell,
    required this.onEnterExp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
            ),
            child: const Icon(Icons.folder, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      project.name,
        style: AppTextStyles.heading(size: 16, color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        project.domain,
                        style: AppTextStyles.caption(color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ID: ${project.id}',
                        style: AppTextStyles.caption(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                if (project.description != null && project.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    project.description!,
                    style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '创建于 ${_formatDate(project.createdAt)} · 更新于 ${_formatDate(project.updatedAt)}',
                  style: AppTextStyles.caption(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
            color: AppColors.bgCard,
            onSelected: (value) {
              if (value == 'info') onEnterInfoCollection();
              if (value == 'webshell') onEnterWebshell();
              if (value == 'exp') onEnterExp();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    const Icon(Icons.search, color: AppColors.primary, size: 20),
                    const SizedBox(width: 12),
                    Text('进入信息收集', style: AppTextStyles.body(color: AppColors.textPrimary)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'webshell',
                child: Row(
                  children: [
                    const Icon(Icons.terminal, color: AppColors.primary, size: 20),
                    const SizedBox(width: 12),
                    Text('进入Webshell', style: AppTextStyles.body(color: AppColors.textPrimary)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'exp',
                child: Row(
                  children: [
                    const Icon(Icons.bug_report, color: AppColors.primary, size: 20),
                    const SizedBox(width: 12),
                    Text('进入EXP', style: AppTextStyles.body(color: AppColors.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            color: AppColors.cyan,
            tooltip: '编辑',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            color: AppColors.red,
            tooltip: '删除',
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
