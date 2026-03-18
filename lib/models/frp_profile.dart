import '../services/frp_client_service.dart';

class FrpProfile {
  final int id;
  final String name;
  final String serverAddr;
  final int serverPort;
  final String token;
  final String proxyName;
  final int remotePort;
  final String localAddr;
  final int localPort;
  final String version;
  final bool useTcpMux;
  final FrpAuthMode authMode;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FrpProfile({
    required this.id,
    required this.name,
    required this.serverAddr,
    required this.serverPort,
    required this.token,
    required this.proxyName,
    required this.remotePort,
    required this.localAddr,
    required this.localPort,
    required this.version,
    required this.useTcpMux,
    required this.authMode,
    required this.createdAt,
    required this.updatedAt,
  });

  FrpTunnelConfig toConfig() => FrpTunnelConfig(
        serverAddr: serverAddr,
        serverPort: serverPort,
        token: token,
        proxyName: proxyName,
        remotePort: remotePort,
        localAddr: localAddr,
        localPort: localPort,
        version: version,
        useTcpMux: useTcpMux,
        authMode: authMode,
      );

  static FrpProfile fromMap(Map<String, dynamic> m) => FrpProfile(
        id: m['id'] as int,
        name: m['name'] as String,
        serverAddr: m['server_addr'] as String,
        serverPort: m['server_port'] as int,
        token: (m['token'] as String?) ?? '',
        proxyName: m['proxy_name'] as String,
        remotePort: m['remote_port'] as int,
        localAddr: (m['local_addr'] as String?) ?? '127.0.0.1',
        localPort: m['local_port'] as int,
        version: (m['version'] as String?) ?? '',
        useTcpMux: (m['use_tcp_mux'] as int? ?? 1) == 1,
        authMode: _modeFromString(m['auth_mode'] as String? ?? 'md5'),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );

  static FrpAuthMode _modeFromString(String s) {
    switch (s) {
      case 'hmacSha1':
        return FrpAuthMode.hmacSha1;
      case 'hmacSha256':
        return FrpAuthMode.hmacSha256;
      case 'rawToken':
        return FrpAuthMode.rawToken;
      default:
        return FrpAuthMode.md5;
    }
  }
}
