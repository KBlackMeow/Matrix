import 'dart:io';

/// 本地数据目录/数据库文件的权限收敛。
///
/// Matrix 在 `~/.matrix/matrix.db` 中明文保存目标凭据，因此至少要让
/// 目录 0700、数据库 0600，避免同机其他用户或粗心打包工具读到。
///
/// 说明：这是纵深防御的第一层，不是加密。真正的静态加密（Keychain /
/// sqlcipher）见文档 docs/audit/。
Future<void> hardenPermissions({
  required String dirPath,
  List<String> fileNames = const <String>[],
}) async {
  if (!Platform.isMacOS && !Platform.isLinux) return;
  await _chmod(dirPath, '700');
  for (final name in fileNames) {
    final path = '$dirPath${Platform.pathSeparator}$name';
    if (await FileSystemEntity.isFile(path)) {
      await _chmod(path, '600');
    }
  }
}

/// 单项 chmod；失败静默（例如文件系统不支持 POSIX 权限）。
Future<void> _chmod(String path, String mode) async {
  try {
    final result = await Process.run('chmod', <String>[mode, path]);
    if (result.exitCode != 0) return;
  } catch (_) {
    // 无 chmod 可执行文件时忽略：不影响主流程。
  }
}

/// 数据库及其 WAL/SHM 伴随文件的默认清单。
const List<String> matrixDatabaseArtifacts = <String>[
  'matrix.db',
  'matrix.db-wal',
  'matrix.db-shm',
];
