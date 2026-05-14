import '../models/project.dart';
import '../models/webshell.dart';
import '../models/payload.dart';
import '../models/frp_profile.dart';
import '../models/suo5_profile.dart';
import '../models/suo6_profile.dart';
import '../services/frp_client_service.dart';
import 'database_helper_stub.dart'
    if (dart.library.io) 'database_helper_io.dart'
    as impl;

/// 数据库助手：Web 使用内存存储，桌面/移动端使用 SQLite
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Project> createProject(
    String name, {
    required String domain,
    String? description,
  }) async {
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

  // FRP Profiles

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
  }) => impl.createFrpProfile(
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
  );

  Future<List<FrpProfile>> getAllFrpProfiles() => impl.getAllFrpProfiles();

  Future<FrpProfile?> updateFrpProfile({
    required int id,
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
  }) => impl.updateFrpProfile(
    id: id,
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
  );

  Future<int> deleteFrpProfile(int id) => impl.deleteFrpProfile(id);

  // Suo5 Profiles

  Future<Suo5Profile> createSuo5Profile({
    required int projectId,
    required String name,
    required String targetUrl,
    required String listenHost,
    required int listenPort,
  }) => impl.createSuo5Profile(
    projectId: projectId,
    name: name,
    targetUrl: targetUrl,
    listenHost: listenHost,
    listenPort: listenPort,
  );

  Future<List<Suo5Profile>> getSuo5ProfilesByProject(int projectId) =>
      impl.getSuo5ProfilesByProject(projectId);

  Future<Suo5Profile?> updateSuo5Profile(Suo5Profile profile) =>
      impl.updateSuo5Profile(profile);

  Future<int> deleteSuo5Profile(int id) => impl.deleteSuo5Profile(id);

  // Suo6 Profiles

  Future<Suo6Profile> createSuo6Profile({
    required int projectId,
    required String name,
    required String targetUrl,
    required String listenHost,
    required int listenPort,
  }) => impl.createSuo6Profile(
    projectId: projectId,
    name: name,
    targetUrl: targetUrl,
    listenHost: listenHost,
    listenPort: listenPort,
  );

  Future<List<Suo6Profile>> getSuo6ProfilesByProject(int projectId) =>
      impl.getSuo6ProfilesByProject(projectId);

  Future<Suo6Profile?> updateSuo6Profile(Suo6Profile profile) =>
      impl.updateSuo6Profile(profile);

  Future<int> deleteSuo6Profile(int id) => impl.deleteSuo6Profile(id);
}
