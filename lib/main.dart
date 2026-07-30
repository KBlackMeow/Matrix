import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'database/database_helper.dart';
import 'database/database_init.dart';
import 'services/seed_service.dart';

/// macOS 下偶发引擎与框架按键表不一致，会在 Debug 触发 HardwareKeyboard 断言；
/// 启动与回到前台时向引擎拉取真实状态以对齐 [HardwareKeyboard]。
class _MacOSKeyboardSyncObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(HardwareKeyboard.instance.syncKeyboardState());
    }
  }
}

final _macOSKeyboardSyncObserver = _MacOSKeyboardSyncObserver();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    WidgetsBinding.instance.addObserver(_macOSKeyboardSyncObserver);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(HardwareKeyboard.instance.syncKeyboardState());
    });
  }
  // _installMatrixDebugPrint();
  initDatabase(); // 初始化 SQLite（桌面端使用 FFI）
  runApp(const MyApp());
  // seed 在后台运行，不阻塞 UI 启动
  SeedService.seed(DatabaseHelper());
}
