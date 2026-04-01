import 'package:flutter/material.dart';

import 'app/app.dart';
import 'database/database_helper.dart';
import 'database/database_init.dart';
import 'services/scan_session_service.dart';
import 'services/seed_service.dart';
import 'utils/matrix_console_log.dart';

/// 将 Flutter [debugPrint] 全部打到运行应用的终端，并带时间戳（不再依赖框架节流/仅 IDE 行为）。
void _installMatrixDebugPrint() {
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null || message.isEmpty) return;
    final ts = matrixConsoleTimestamp();
    final prefix = '[Matrix][debug][$ts] ';
    if (wrapWidth == null) {
      // ignore: avoid_print
      print('$prefix$message');
      return;
    }
    for (final line in message.split('\n')) {
      if (line.length <= wrapWidth) {
        // ignore: avoid_print
        print('$prefix$line');
        continue;
      }
      var rest = line;
      while (rest.isNotEmpty) {
        final chunk = rest.length <= wrapWidth ? rest : rest.substring(0, wrapWidth);
        rest = rest.length <= wrapWidth ? '' : rest.substring(wrapWidth);
        // ignore: avoid_print
        print('$prefix$chunk');
      }
    }
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installMatrixDebugPrint();
  initDatabase(); // 初始化 SQLite（桌面端使用 FFI）
  await ScanSessionService().resetStaleSessions(); // 清理上次异常退出遗留的 running 会话
  await SeedService.seed(DatabaseHelper()); // 首次启动种子化内置默认数据
  runApp(const MyApp());
}
