/// 条件导出：Flutter 环境使用 rootBundle，纯 Dart 环境使用 dart:io File。
export 'asset_loader_native.dart'
    if (dart.library.ui) 'asset_loader_flutter.dart';
