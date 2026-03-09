import '../models/project.dart';
import '../models/webshell.dart';
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
}) => _web.createWebshell(projectId, name: name, url: url, password: password, method: method);

Future<List<Webshell>> getWebshellsByProject(int projectId) =>
    _web.getWebshellsByProject(projectId);

Future<int> updateWebshell(Webshell webshell) => _web.updateWebshell(webshell);

Future<int> deleteWebshell(int id) => _web.deleteWebshell(id);
