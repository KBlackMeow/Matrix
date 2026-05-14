import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';
import '../app/localization.dart';

/// 项目管理页面：创建、编辑、删除
class ProjectManagementPage extends StatefulWidget {
  final Project? selectedProject;
  final void Function(Project project) onEnterWebshell;
  final void Function(Project project) onEnterExp;
  final void Function(Project project) onEnterSuo5;
  final void Function(Project project)? onProjectUpdated;
  final void Function(int projectId)? onProjectDeleted;

  const ProjectManagementPage({
    super.key,
    this.selectedProject,
    required this.onEnterWebshell,
    required this.onEnterExp,
    required this.onEnterSuo5,
    this.onProjectUpdated,
    this.onProjectDeleted,
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

  Future<List<Project>> _loadProjects() async {
    setState(() => _loading = true);
    final projects = await _db.getAllProjects();
    setState(() {
      _projects = projects;
      _loading = false;
    });
    return projects;
  }

  Future<void> _showCreateDialog() async {
    final nameController = TextEditingController();
    final domainController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          S.btnCreate,
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
                  labelText: S.fieldProjectName,
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
              ),
              const SizedBox(height: 16),
              TextField(
                controller: domainController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: S.fieldDomainOrId,
                  hintText: S.hintDomainOrId,
                  hintStyle: const TextStyle(color: Color(0xFF6E7681)),
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
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                maxLines: 3,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: S.fieldDescription,
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
              ),
            ],
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
              if (nameController.text.trim().isEmpty ||
                  domainController.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(context, true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(
              S.btnCreate,
              style: AppTextStyles.body(color: AppColors.bgDark),
            ),
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
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
      );
      await _loadProjects();
    }
  }

  Future<void> _showEditDialog(Project project) async {
    final nameController = TextEditingController(text: project.name);
    final domainController = TextEditingController(text: project.domain);
    final descController = TextEditingController(
      text: project.description ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          S.titleEditProject(project.id),
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
                  labelText: S.fieldProjectName,
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
              ),
              const SizedBox(height: 16),
              TextField(
                controller: domainController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: S.fieldDomainOrId,
                  hintText: S.hintDomainOrId,
                  hintStyle: const TextStyle(color: Color(0xFF6E7681)),
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
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                maxLines: 3,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: S.fieldDescription,
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
              ),
            ],
          ),
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
            onPressed: () {
              if (nameController.text.trim().isEmpty ||
                  domainController.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(context, true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(
              S.btnSave,
              style: const TextStyle(color: Color(0xFF0D1117)),
            ),
          ),
        ],
      ),
    );

    if (result == true &&
        nameController.text.trim().isNotEmpty &&
        domainController.text.trim().isNotEmpty) {
      await _db.updateProject(
        project.copyWith(
          name: nameController.text.trim(),
          domain: domainController.text.trim(),
          description: descController.text.trim().isEmpty
              ? null
              : descController.text.trim(),
        ),
      );
      final projects = await _loadProjects();
      final updated = projects.where((p) => p.id == project.id).firstOrNull;
      if (updated != null) {
        widget.onProjectUpdated?.call(updated);
      }
    }
  }

  Future<void> _showDeleteConfirm(Project project) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: MatrixDialogStyle.outlineDanger(0.28),
        title: Text(S.btnDelete, style: const TextStyle(color: AppColors.red)),
        content: Text(
          S.confirmDeleteProject(project.name),
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
      await _db.deleteProject(project.id);
      await _loadProjects();
      widget.onProjectDeleted?.call(project.id);
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
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.cyan, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    S.webModeWarning,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
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
              label: Text(S.actionNewProject),
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
              tooltip: S.actionRefresh,
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
                      Text(
                        S.projectEmptyHint(S.actionNewProject),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
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
                      onEnterWebshell: () => widget.onEnterWebshell(project),
                      onEnterExp: () => widget.onEnterExp(project),
                      onEnterSuo5: () => widget.onEnterSuo5(project),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatefulWidget {
  final Project project;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onEnterWebshell;
  final VoidCallback onEnterExp;
  final VoidCallback onEnterSuo5;

  const _ProjectCard({
    required this.project,
    required this.onEdit,
    required this.onDelete,
    required this.onEnterWebshell,
    required this.onEnterExp,
    required this.onEnterSuo5,
  });

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  bool _hovered = false;

  Future<void> _showChooseEntryDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          S.dialogChooseProjectEntryTitle,
          style: AppTextStyles.heading(color: AppColors.primary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.project.name,
              style: AppTextStyles.body(size: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              widget.project.domain,
              style: AppTextStyles.caption(size: 12, color: AppColors.cyan),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.onEnterWebshell();
              },
              icon: const Icon(Icons.terminal, size: 20),
              label: Text(S.menuEnterWebshell),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.bgDark,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.onEnterExp();
              },
              icon: const Icon(Icons.bug_report, size: 20),
              label: Text(S.menuEnterExp),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.bgDark,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.onEnterSuo5();
              },
              icon: const Icon(AppTunnelIcons.outlined, size: 20),
              label: Text(S.menuEnterSuoTunnel),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.bgDark,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              S.btnCancel,
              style: AppTextStyles.body(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _showChooseEntryDialog,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.bgElevated : AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : AppColors.border,
              width: _hovered ? 1.2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: _hovered ? 0.14 : 0.0),
                blurRadius: 14,
                spreadRadius: 0,
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Icon(
                      Icons.folder,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox.expand(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.project.name,
                                  style: AppTextStyles.heading(
                                    size: 16,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.border,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.project.domain,
                                  style: AppTextStyles.caption(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.border,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'ID: ${widget.project.id}',
                                  style: AppTextStyles.caption(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (widget.project.description != null &&
                              widget.project.description!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.project.description!,
                              style: AppTextStyles.body(
                                size: 13,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            S.projectCreatedUpdated(
                              _formatDate(widget.project.createdAt),
                              _formatDate(widget.project.updatedAt),
                            ),
                            style: AppTextStyles.caption(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                  color: AppColors.bgCard,
                  onSelected: (value) {
                    if (value == 'webshell') widget.onEnterWebshell();
                    if (value == 'exp') widget.onEnterExp();
                    if (value == 'tunnel') widget.onEnterSuo5();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'webshell',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.terminal,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            S.menuEnterWebshell,
                            style: AppTextStyles.body(color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'exp',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.bug_report,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            S.menuEnterExp,
                            style: AppTextStyles.body(color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'tunnel',
                      child: Row(
                        children: [
                          const Icon(
                            AppTunnelIcons.outlined,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            S.menuEnterSuoTunnel,
                            style: AppTextStyles.body(color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  color: AppColors.cyan,
                  tooltip: S.tooltipEdit,
                ),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.red,
                  tooltip: S.tooltipDelete,
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
