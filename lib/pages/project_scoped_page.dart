import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';

/// 需要选择项目的页面包装器（信息收集、Webshell）
class ProjectScopedPage extends StatefulWidget {
  final Project? selectedProject;
  final void Function(Project) onSelectProject;
  final VoidCallback onClearProject;
  final VoidCallback onNavigateToProjectManagement;
  final String title;
  final IconData icon;
  final Widget Function(Project project, VoidCallback onSwitchProject) contentBuilder;

  const ProjectScopedPage({
    super.key,
    required this.selectedProject,
    required this.onSelectProject,
    required this.onClearProject,
    required this.onNavigateToProjectManagement,
    required this.title,
    required this.icon,
    required this.contentBuilder,
  });

  @override
  State<ProjectScopedPage> createState() => _ProjectScopedPageState();
}

class _ProjectScopedPageState extends State<ProjectScopedPage> {
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

  @override
  Widget build(BuildContext context) {
    if (widget.selectedProject != null) {
      return widget.contentBuilder(
        widget.selectedProject!,
        widget.onClearProject,
      );
    }

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_projects.isEmpty) {
      return _buildNoProjectsPrompt();
    }

    return _buildProjectSelectPrompt();
  }

  Widget _buildNoProjectsPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.icon,
            size: 64,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 24),
          Text(
            '暂无项目',
            style: AppTextStyles.heading(size: 18, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            '请先创建项目后再使用此功能',
            style: AppTextStyles.body(size: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: widget.onNavigateToProjectManagement,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('去创建项目'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.bgDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectSelectPrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '请选择项目',
                  style: AppTextStyles.body(size: 16, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _projects.length,
            itemBuilder: (context, index) {
              final project = _projects[index];
              return _ProjectSelectCard(
                project: project,
                onTap: () => widget.onSelectProject(project),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProjectSelectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;

  const _ProjectSelectCard({
    required this.project,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
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
                      Text(
                        project.name,
                        style: AppTextStyles.heading(size: 16, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        project.domain,
                        style: AppTextStyles.caption(size: 13, color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: AppColors.textSecondary, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
