import '../models/project.dart';
import '../models/webshell.dart';
import '../models/payload.dart';
import '../models/dictionary.dart';

/// Web 平台内存存储（SQLite 不支持 Web，数据仅会话内有效）
class DatabaseHelperWeb {
  static final DatabaseHelperWeb _instance = DatabaseHelperWeb._internal();
  final List<Project> _projects = [];
  final List<Webshell> _webshells = [];
  final List<Payload> _payloads = [];
  final List<Dictionary> _dictionaries = [];
  int _nextId = 1;
  int _nextWebshellId = 1;
  int _nextPayloadId = 1;
  int _nextDictId = 1;

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
    _webshells.removeWhere((w) => w.projectId == id);
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
    String connectorType = 'php_eval',
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
      connectorType: connectorType,
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

  // Payload 内存实现

  Future<Payload> createPayload({
    required String name,
    required String type,
    required String content,
    bool isDefault = false,
    String? description,
    String? tags,
  }) async {
    final now = DateTime.now();
    final payload = Payload(
      id: _nextPayloadId++,
      name: name,
      type: type,
      content: content,
      filePath: '',
      isDefault: isDefault,
      description: description,
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );
    _payloads.insert(0, payload);
    return payload;
  }

  Future<List<Payload>> getAllPayloads() async {
    return List.from(_payloads)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<int> updatePayload(Payload payload) async {
    final index = _payloads.indexWhere((p) => p.id == payload.id);
    if (index < 0) return 0;
    _payloads[index] = payload.copyWith(updatedAt: DateTime.now());
    return 1;
  }

  Future<int> deletePayload(int id) async {
    final len = _payloads.length;
    _payloads.removeWhere((p) => p.id == id);
    return len - _payloads.length;
  }

  // Dictionary 内存实现

  Future<Dictionary> createDictionary({
    required String name,
    required String category,
    required List<int> bytes,
    bool isDefault = false,
    String? description,
    String? tags,
  }) async {
    final now = DateTime.now();
    final lineCount =
        bytes.where((b) => b == 10).length +
        (bytes.isNotEmpty && bytes.last != 10 ? 1 : 0);
    final dict = Dictionary(
      id: _nextDictId++,
      name: name,
      category: category,
      filePath: '',
      lineCount: lineCount,
      fileSize: bytes.length,
      isDefault: isDefault,
      description: description,
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );
    _dictionaries.insert(0, dict);
    return dict;
  }

  Future<List<Dictionary>> getAllDictionaries() async {
    return List.from(_dictionaries)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> updateDictionaryContent(Dictionary dict, List<int> bytes) async {
    final lineCount = bytes.where((b) => b == 10).length +
        (bytes.isNotEmpty && bytes.last != 10 ? 1 : 0);
    final fileSize = bytes.length;
    final index = _dictionaries.indexWhere((d) => d.id == dict.id);
    if (index >= 0) {
      _dictionaries[index] = dict.copyWith(
        lineCount: lineCount,
        fileSize: fileSize,
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<String> readDictionaryPreview(String filePath,
      {int maxLines = 300}) async =>
      '// Web 模式：文件预览不可用';

  Future<int> deleteDictionary(int id) async {
    final len = _dictionaries.length;
    _dictionaries.removeWhere((d) => d.id == id);
    return len - _dictionaries.length;
  }
}
