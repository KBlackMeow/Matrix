/// 主窗口分页跳转（由子路由中的页面在 [Navigator.pop] 之后调用）。
class MainNavBus {
  MainNavBus._();

  /// 切换到「隧道」管理分页并刷新列表。
  static void Function()? onRequestOpenTunnelTab;
}
