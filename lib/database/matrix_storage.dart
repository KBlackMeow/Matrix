import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'storage_permissions.dart';

/// Matrix-owned local data storage.
///
/// On macOS, data lives in `~/.matrix` so it remains stable when the app's
/// sandbox entitlement changes. Other platforms retain their normal app
/// documents location.
Future<Directory> getMatrixStorageDirectory() async {
  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final directory = Directory(p.join(home, '.matrix'));
      await directory.create(recursive: true);
      return directory;
    }
  }
  return getApplicationDocumentsDirectory();
}

Future<String> getMatrixDatabasePath() async {
  final directory = await getMatrixStorageDirectory();
  return p.join(directory.path, 'matrix.db');
}

/// 收敛本地数据目录与数据库文件权限（目录 0700、数据库 0600）。
///
/// `matrix.db` 中保存 WebShell 口令、Godzilla 密钥与隧道 token（明文），
/// 至少要让同机其他用户无法读取；启动时调用一次即可。
Future<void> hardenMatrixStorage() async {
  try {
    final directory = await getMatrixStorageDirectory();
    await hardenPermissions(
      dirPath: directory.path,
      fileNames: matrixDatabaseArtifacts,
    );
  } catch (_) {
    // 权限收敛失败不应阻断启动（例如只读文件系统/不支持 POSIX 权限）。
  }
}
