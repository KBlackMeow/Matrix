import 'package:flutter/services.dart' show rootBundle;

/// Flutter 环境：从 AssetBundle 加载文件。
Future<String> loadAssetString(String path) => rootBundle.loadString(path);
