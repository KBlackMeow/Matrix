/// 由菜单持久化的连通性状态决定详情页的初始显示和是否自动重检。
class WebshellInitialConnectionState {
  final bool isConnected;
  final bool shouldCheckOnOpen;

  const WebshellInitialConnectionState({
    required this.isConnected,
    required this.shouldCheckOnOpen,
  });

  factory WebshellInitialConnectionState.fromPersistedStatus(int status) {
    final isOnline = status == 1;
    return WebshellInitialConnectionState(
      isConnected: isOnline,
      shouldCheckOnOpen: isOnline,
    );
  }
}
