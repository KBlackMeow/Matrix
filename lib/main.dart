import 'package:flutter/material.dart';

import 'app/app.dart';
import 'database/database_helper.dart';
import 'database/database_init.dart';
import 'services/seed_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // _installMatrixDebugPrint();
  initDatabase(); // 初始化 SQLite（桌面端使用 FFI）
  runApp(const MyApp());
  // seed 在后台运行，不阻塞 UI 启动
  SeedService.seed(DatabaseHelper());
}
