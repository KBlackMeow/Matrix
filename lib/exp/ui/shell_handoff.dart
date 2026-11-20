/// WebShell 产物的编排：选项目 → 入库 → 跳转工作区。
///
/// 旧实现把"选项目对话框 + 建项目对话框 + createWebshell + Navigator.push"
/// 抄了 5 份（struts2 / drupal / thinkphp / zentao / universal）。
/// 这属于跨页面副作用，不属于一次利用会话，因此独立于 `ExploitSessionController`。
library;

import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../models/project.dart';
import '../../models/webshell.dart';
import '../../pages/webshell_interactive_page.dart';
import '../../theme/app_theme.dart';
import '../core/exploit_module.dart';
import 'exp_fields.dart';
import 'exp_tokens.dart';

abstract final class ShellHandoff {
  ShellHandoff._();

  /// 持久化一条 WebShell。`projectId` 为 0 表示临时会话（不入库）。
  static Future<Webshell> persist(
    ShellSession session, {
    required String name,
    Project? project,
  }) async {
    final now = DateTime.now();
    if (project == null) {
      return Webshell(
        id: 0,
        projectId: 0,
        name: name,
        url: session.url,
        password: session.password,
        type: session.type,
        method: session.method,
        status: 1,
        connectorType: session.connectorType,
        createdAt: now,
        updatedAt: now,
      );
    }
    return DatabaseHelper().createWebshell(
      project.id,
      name: name,
      url: session.url,
      password: session.password,
      method: session.method,
      type: session.type,
      connectorType: session.connectorType,
    );
  }

  /// 选项目（可取消）→ 入库 → 打开工作区。
  static Future<void> open(
    BuildContext context,
    ShellSession session, {
    String? name,
  }) async {
    final db = DatabaseHelper();
    Project? project;
    try {
      project = await _pickProject(context, db);
    } catch (_) {
      project = null;
    }
    final Webshell shell;
    try {
      shell = await persist(session, name: name ?? 'Shell · ${session.kind}', project: project);
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WebshellInteractivePage(webshell: shell)),
    );
  }

  static Future<Project?> _pickProject(
    BuildContext context,
    DatabaseHelper db,
  ) async {
    final projects = await db.getAllProjects();
    if (!context.mounted) return null;
    if (projects.isEmpty) return _createProject(context, db);

    return showDialog<Project>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Select project',
          style: AppTextStyles.heading(color: ExpColors.ok),
        ),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: projects.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(
                projects[i].name,
                style: AppTextStyles.body(color: ExpColors.text),
              ),
              subtitle: Text(
                projects[i].domain,
                style: AppTextStyles.caption(color: ExpColors.textSecondary),
              ),
              onTap: () => Navigator.pop(ctx, projects[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: ExpButton.ghost(),
            child: const Text('跳过（临时会话）'),
          ),
        ],
      ),
    );
  }

  static Future<Project?> _createProject(
    BuildContext context,
    DatabaseHelper db,
  ) async {
    final nameCtrl = TextEditingController();
    final domainCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            '暂无项目',
            style: AppTextStyles.heading(color: ExpColors.ok),
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '请先创建一个项目以保存 WebShell',
                  style: AppTextStyles.caption(color: ExpColors.textSecondary),
                ),
                ExpSpace.vLg,
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: AppTextStyles.body(color: ExpColors.text),
                  decoration: expInputDecoration('项目名称'),
                ),
                ExpSpace.vMd,
                TextField(
                  controller: domainCtrl,
                  style: AppTextStyles.body(color: ExpColors.text),
                  decoration: expInputDecoration('域名或 ID'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: ExpButton.ghost(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ExpButton.primary(),
              child: const Text('创建'),
            ),
          ],
        ),
      );
      final name = nameCtrl.text.trim();
      final domain = domainCtrl.text.trim();
      if (ok != true || name.isEmpty || domain.isEmpty) return null;
      await db.createProject(name, domain: domain);
      final projects = await db.getAllProjects();
      return projects.isEmpty ? null : projects.last;
    } finally {
      nameCtrl.dispose();
      domainCtrl.dispose();
    }
  }
}
