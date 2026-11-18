import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'core/crypto/credential_cipher.dart';
import 'database/database_helper.dart';
import 'database/database_init.dart';
import 'database/matrix_storage.dart';
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
  // 凭据主密钥：优先 Keychain，退回 ~/.matrix/credentials.key（0600）。
  await CredentialCipher.initialize();
  // 本地数据目录 0700 / 数据库 0600，限制同机其它用户读取。
  await hardenMatrixStorage();
  runApp(const MyApp());
  // 历史明文凭据迁移到加密格式；幂等，失败不影响启动。
  unawaited(
    DatabaseHelper().encryptLegacyCredentials().catchError((Object _) => 0),
  );
  // seed 在后台运行，不阻塞 UI 启动
  SeedService.seed(DatabaseHelper());
}
