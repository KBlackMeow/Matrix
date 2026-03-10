import '../models/project.dart';
import '../models/webshell.dart';
import '../models/payload.dart';
import '../models/dictionary.dart';
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
    String connectorType = 'php_eval',
  }) async {
    return impl.createWebshell(
      projectId,
      name: name,
      url: url,
      password: password,
      method: method,
      type: type,
      connectorType: connectorType,
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

  // Meta 相关

  Future<String?> getMetaValue(String key) => impl.getMetaValue(key);
  Future<void> setMetaValue(String key, String value) =>
      impl.setMetaValue(key, value);

  // Payload 相关

  Future<Payload> createPayload({
    required String name,
    required String type,
    required String content,
    bool isDefault = false,
    String? description,
    String? tags,
  }) async {
    return impl.createPayload(
      name: name,
      type: type,
      content: content,
      isDefault: isDefault,
      description: description,
      tags: tags,
    );
  }

  Future<List<Payload>> getAllPayloads() async {
    return impl.getAllPayloads();
  }

  Future<int> updatePayload(Payload payload) async {
    return impl.updatePayload(payload);
  }

  Future<int> deletePayload(int id) async {
    return impl.deletePayload(id);
  }

  // Dictionary 相关

  Future<Dictionary> createDictionary({
    required String name,
    required String category,
    required List<int> bytes,
    bool isDefault = false,
    String? description,
    String? tags,
  }) async {
    return impl.createDictionary(
      name: name,
      category: category,
      bytes: bytes,
      isDefault: isDefault,
      description: description,
      tags: tags,
    );
  }

  Future<List<Dictionary>> getAllDictionaries() async {
    return impl.getAllDictionaries();
  }

  Future<String> readDictionaryPreview(String filePath,
      {int maxLines = 300}) async {
    return impl.readDictionaryPreview(filePath, maxLines: maxLines);
  }

  Future<int> deleteDictionary(int id) async {
    return impl.deleteDictionary(id);
  }
}
