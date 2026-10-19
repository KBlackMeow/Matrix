import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
