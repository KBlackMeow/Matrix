import '../models/project.dart';
import '../models/webshell.dart';
import 'database_helper_stub.dart'
    if (dart.library.io) 'database_helper_io.dart' as impl;

/// 数据库助手：Web 使用内存存储，桌面/移动端使用 SQLite
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Project> createProject(String name, {required String domain, String? description}) async {
    return impl.createProject(name, domain: domain, description: description);
  }

  Future<List<Project>> getAllProjects() async {
    return impl.getAllProjects();
  }

  Future<Project?> getProjectById(int id) async {
    return impl.getProjectById(id);
  }

  Future<int> updateProject(Project project) async {
    return impl.updateProject(project);
  }

  Future<int> deleteProject(int id) async {
    return impl.deleteProject(id);
  }

  Future<Webshell> createWebshell(
    int projectId, {
    required String name,
    required String url,
    String? password,
    String method = 'POST',
    String type = 'php',
  }) async {
    return impl.createWebshell(
      projectId,
      name: name,
      url: url,
      password: password,
      method: method,
      type: type,
    );
  }

  Future<List<Webshell>> getWebshellsByProject(int projectId) async {
    return impl.getWebshellsByProject(projectId);
  }

  Future<int> updateWebshell(Webshell webshell) async {
    return impl.updateWebshell(webshell);
  }

  Future<int> deleteWebshell(int id) async {
    return impl.deleteWebshell(id);
  }
}
