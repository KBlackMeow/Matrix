import 'dart:io';

/// 纯 Dart VM 环境：从文件系统加载（相对于工作目录或绝对路径）。
Future<String> loadAssetString(String path) => File(path).readAsString();
