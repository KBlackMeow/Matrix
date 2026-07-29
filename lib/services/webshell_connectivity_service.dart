import 'dart:async';

import '../connectors/connector_factory.dart';
import '../models/webshell.dart';

/// 批量 WebShell 连通性检测服务。
class WebshellConnectivityService {
  /// 默认 ping 超时（快速检测，不等待慢速协议）。
  static const defaultPingTimeout = Duration(seconds: 5);

  /// 并行 ping 所有 [webshells]，返回 id → isOnline 映射。
  ///
  /// 每个连接器使用 [timeout] 限制等待时间。
  /// [onStatusChanged] 回调在每个 ping 完成时触发（含更新后的 Webshell 副本），
  /// 调用方可在此回调中持久化到数据库或更新 UI。
  static Future<Map<int, bool>> pingAll(
    List<Webshell> webshells, {
    Duration timeout = defaultPingTimeout,
    Future<void> Function(Webshell ws)? onStatusChanged,
  }) async {
    final results = <int, bool>{};
    await Future.wait(webshells.map((ws) async {
      bool ok;
      try {
        ok = await ConnectorFactory.create(ws).ping().timeout(timeout);
      } on TimeoutException {
        ok = false;
      } catch (_) {
        ok = false;
      }
      results[ws.id] = ok;

      if (ws.status != (ok ? 1 : 0)) {
        await onStatusChanged?.call(ws.copyWith(status: ok ? 1 : 0));
      }
    }));
    return results;
  }
}
