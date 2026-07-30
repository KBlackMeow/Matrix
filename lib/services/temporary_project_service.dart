import '../database/database_helper.dart';
import '../models/project.dart';

/// Creates and identifies the persistent project opened by default.
class TemporaryProjectService {
  static const name = '临时项目';
  static const projectIdMetaKey = 'temporary_project_id';

  static Future<Project> ensure(DatabaseHelper db) async {
    final savedId = int.tryParse(await db.getMetaValue(projectIdMetaKey) ?? '');
    if (savedId != null) {
      final existing = await db.getProjectById(savedId);
      if (existing != null) return existing;
    }

    final existing = (await db.getAllProjects()).where(
      (project) => project.name == name,
    );
    if (existing.isNotEmpty) {
      final project = existing.first;
      await db.setMetaValue(projectIdMetaKey, project.id.toString());
      return project;
    }

    final project = await db.createProject(name, domain: '');
    await db.setMetaValue(projectIdMetaKey, project.id.toString());
    return project;
  }

  static Future<bool> isTemporaryProject(
    DatabaseHelper db,
    Project project,
  ) async {
    final savedId = int.tryParse(await db.getMetaValue(projectIdMetaKey) ?? '');
    return savedId == project.id;
  }
}
