import 'database_init_stub.dart'
    if (dart.library.io) 'database_init_io.dart' as impl;

/// 初始化 SQLite，根据平台自动选择实现
void initDatabase() => impl.initDatabase();
