import 'package:flutter/material.dart';

import 'app/app.dart';
import 'database/database_helper.dart';
import 'database/database_init.dart';
import 'services/seed_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // _installMatrixDebugPrint();
  initDatabase(); // 初始化 SQLite（桌面端使用 FFI）
  await SeedService.seed(DatabaseHelper()); // 首次启动种子化内置默认数据
  runApp(const MyApp());
}
