// ignore_for_file: avoid_print

/// 远端文件操作联调：验证"写临时文件 → rename → 读取 → 删除"链路。
///
/// 用法：dart tool/verify/file_ops_live.dart <shellUrl> <password> <remoteDir>
library;

import '../../lib/connectors/connector_factory.dart';
import '../../lib/models/webshell.dart';
import '../../lib/services/webshell_service.dart';

Future<void> main(List<String> args) async {
  final ws = Webshell(
    id: 1, projectId: 1, name: 'f', url: args[0], password: args[1],
    method: 'POST', connectorType: 'php_eval',
    createdAt: DateTime.now(), updatedAt: DateTime.now(),
  );
  final svc = WebshellService(ws);
  ConnectorFactory.create(ws);
  final base = args[2];
  final staged = '$base/probe.mxpart';
  final finalPath = '$base/probe.txt';
  print('write staging: ${await svc.writeFile(staged, 'hello-mx')}');
  print('rename: ${await svc.renameFile(staged, finalPath)}');
  print('read: ${await svc.readFile(finalPath)}');
  print('cleanup: ${await svc.deleteFile(finalPath)}');
  print('staging gone: ${!(await svc.listDirectory(base)).any((e) => e.name == 'probe.mxpart')}');
}
