import '../models/project.dart';
import '../models/webshell.dart';

/// Web 平台内存存储（SQLite 不支持 Web，数据仅会话内有效）
class DatabaseHelperWeb {
  static final DatabaseHelperWeb _instance = DatabaseHelperWeb._internal();
  final List<Project> _projects = [];
  final List<Webshell> _webshells = [];
  int _nextId = 1;
  int _nextWebshellId = 1;

  factory DatabaseHelperWeb() => _instance;

  DatabaseHelperWeb._internal();

  Future<Project> createProject(String name, {required String domain, String? description}) async {
    final now = DateTime.now();
    final project = Project(
      id: _nextId++,
      name: name,
      domain: domain,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
    _projects.insert(0, project);
    return project;
  }

  Future<List<Project>> getAllProjects() async {
    return List.from(_projects)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<Project?> getProjectById(int id) async {
    try {
      return _projects.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<int> updateProject(Project project) async {
    final index = _projects.indexWhere((p) => p.id == project.id);
    if (index < 0) return 0;
    _projects[index] = project.copyWith(updatedAt: DateTime.now());
    return 1;
  }

  Future<int> deleteProject(int id) async {
    final len = _projects.length;
    _projects.removeWhere((p) => p.id == id);
    return len - _projects.length;
  }

  Future<Webshell> createWebshell(
    int projectId, {
    required String name,
    required String url,
    String? password,
    String method = 'POST',
    String type = 'php',
  }) async {
    final now = DateTime.now();
    final ws = Webshell(
      id: _nextWebshellId++,
      projectId: projectId,
      name: name,
      url: url,
      password: password,
      type: type,
      method: method,
      createdAt: now,
      updatedAt: now,
    );
    _webshells.insert(0, ws);
    return ws;
  }

  Future<List<Webshell>> getWebshellsByProject(int projectId) async {
    return _webshells
        .where((w) => w.projectId == projectId)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<int> updateWebshell(Webshell webshell) async {
    final index = _webshells.indexWhere((w) => w.id == webshell.id);
    if (index < 0) return 0;
    _webshells[index] = webshell.copyWith(updatedAt: DateTime.now());
    return 1;
  }

  Future<int> deleteWebshell(int id) async {
    final len = _webshells.length;
    _webshells.removeWhere((w) => w.id == id);
    return len - _webshells.length;
  }
}
