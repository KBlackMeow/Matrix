import '../models/project.dart';
import '../models/webshell.dart';
import '../models/payload.dart';
import '../models/dictionary.dart';
import '../models/frp_profile.dart';
import '../services/frp_client_service.dart';
import 'database_helper_web.dart';

final _web = DatabaseHelperWeb();

Future<Project> createProject(String name, {required String domain, String? description}) =>
    _web.createProject(name, domain: domain, description: description);

Future<List<Project>> getAllProjects() => _web.getAllProjects();

Future<Project?> getProjectById(int id) => _web.getProjectById(id);

Future<int> updateProject(Project project) => _web.updateProject(project);

Future<int> deleteProject(int id) => _web.deleteProject(id);

Future<Webshell> createWebshell(
  int projectId, {
  required String name,
  required String url,
  String? password,
  String method = 'POST',
  String type = 'php',
  String connectorType = 'php_eval',
}) =>
    _web.createWebshell(
      projectId,
      name: name,
      url: url,
      password: password,
      method: method,
      type: type,
      connectorType: connectorType,
    );

Future<List<Webshell>> getWebshellsByProject(int projectId) =>
    _web.getWebshellsByProject(projectId);

Future<int> updateWebshell(Webshell webshell) => _web.updateWebshell(webshell);

Future<int> deleteWebshell(int id) => _web.deleteWebshell(id);

// Meta 顶层方法（Web 无持久化，返回 null / 忽略）
Future<String?> getMetaValue(String key) async => null;
Future<void> setMetaValue(String key, String value) async {}

// Payload 顶层方法（Web 内存实现）

Future<Payload> createPayload({
  required String name,
  required String type,
  required String content,
  bool isDefault = false,
  String? description,
  String? tags,
}) =>
    _web.createPayload(
      name: name,
      type: type,
      content: content,
      isDefault: isDefault,
      description: description,
      tags: tags,
    );

Future<List<Payload>> getAllPayloads() => _web.getAllPayloads();

Future<int> updatePayload(Payload payload) => _web.updatePayload(payload);

Future<int> deletePayload(int id) => _web.deletePayload(id);

// Dictionary 顶层方法（Web 内存实现）

Future<Dictionary> createDictionary({
  required String name,
  required String category,
  required List<int> bytes,
  bool isDefault = false,
  String? description,
  String? tags,
}) =>
    _web.createDictionary(
      name: name,
      category: category,
      bytes: bytes,
      isDefault: isDefault,
      description: description,
      tags: tags,
    );

Future<List<Dictionary>> getAllDictionaries() => _web.getAllDictionaries();

Future<void> updateDictionaryContent(Dictionary dict, List<int> bytes) =>
    _web.updateDictionaryContent(dict, bytes);

Future<String> readDictionaryPreview(String filePath, {int maxLines = 300}) =>
    _web.readDictionaryPreview(filePath, maxLines: maxLines);

Future<int> deleteDictionary(int id) => _web.deleteDictionary(id);

// Scan Sessions（Web 内存实现，会话内有效）
Future<int> createScanSession({
  required int projectId,
  required String scanType,
  required String target,
  String? configJson,
}) =>
    _web.createScanSession(
      projectId: projectId,
      scanType: scanType,
      target: target,
      configJson: configJson,
    );

Future<Map<String, dynamic>?> getLatestScanSession(int projectId, String scanType) =>
    _web.getLatestScanSession(projectId, scanType);

Future<void> updateScanSession(int id, {String? logText, String? status}) =>
    _web.updateScanSession(id, logText: logText, status: status);

Future<void> appendScanLog(int id, String line) => _web.appendScanLog(id, line);

// Web 内存存储，重启即清空，无需重置
Future<void> resetStaleRunningSessions() async {}

// FRP Profiles（Web 无持久化，仅会话内有效）
final _frpProfiles = <FrpProfile>[];
int _frpProfileIdSeq = 1;

Future<FrpProfile> createFrpProfile({
  required String name,
  required String serverAddr,
  required int serverPort,
  required String token,
  required String proxyName,
  required int remotePort,
  required String localAddr,
  required int localPort,
  required String version,
  required bool useTcpMux,
  required FrpAuthMode authMode,
}) async {
  final now = DateTime.now();
  final profile = FrpProfile(
    id: _frpProfileIdSeq++,
    name: name,
    serverAddr: serverAddr,
    serverPort: serverPort,
    token: token,
    proxyName: proxyName,
    remotePort: remotePort,
    localAddr: localAddr,
    localPort: localPort,
    version: version,
    useTcpMux: useTcpMux,
    authMode: authMode,
    createdAt: now,
    updatedAt: now,
  );
  _frpProfiles.add(profile);
  return profile;
}

Future<List<FrpProfile>> getAllFrpProfiles() async =>
    List.unmodifiable(_frpProfiles.reversed.toList());

Future<int> deleteFrpProfile(int id) async {
  final before = _frpProfiles.length;
  _frpProfiles.removeWhere((p) => p.id == id);
  return before - _frpProfiles.length;
}
