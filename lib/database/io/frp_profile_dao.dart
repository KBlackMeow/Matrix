import 'package:sqflite/sqflite.dart';

import '../../models/frp_profile.dart';
import '../../services/frp_client_service.dart';

class FrpProfileDao {
  FrpProfileDao(this._databaseProvider);

  final Future<Database> Function() _databaseProvider;

  Future<FrpProfile> createFrpProfile({
    required String name,
    required String serverAddr,
    required int serverPort,
    required String token,
    required String proxyName,
    required int remotePort,
    required String localAddr,
    required int localPort,
    required String version,
    required bool useTcpMux,
    required FrpAuthMode authMode,
  }) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('frp_profiles', {
      'name': name,
      'server_addr': serverAddr,
      'server_port': serverPort,
      'token': token,
      'proxy_name': proxyName,
      'remote_port': remotePort,
      'local_addr': localAddr,
      'local_port': localPort,
      'version': version,
      'use_tcp_mux': useTcpMux ? 1 : 0,
      'auth_mode': authMode.name,
      'created_at': now,
      'updated_at': now,
    });
    return FrpProfile(
      id: id,
      name: name,
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
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  Future<FrpProfile?> updateFrpProfile({
    required int id,
    required String name,
    required String serverAddr,
    required int serverPort,
    required String token,
    required String proxyName,
    required int remotePort,
    required String localAddr,
    required int localPort,
    required String version,
    required bool useTcpMux,
    required FrpAuthMode authMode,
  }) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    final n = await db.update(
      'frp_profiles',
      {
        'name': name,
        'server_addr': serverAddr,
        'server_port': serverPort,
        'token': token,
        'proxy_name': proxyName,
        'remote_port': remotePort,
        'local_addr': localAddr,
        'local_port': localPort,
        'version': version,
        'use_tcp_mux': useTcpMux ? 1 : 0,
        'auth_mode': authMode.name,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (n == 0) return null;
    final maps = await db.query(
      'frp_profiles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return FrpProfile.fromMap(maps.first.map((k, v) => MapEntry(k, v)));
  }

  Future<List<FrpProfile>> getAllFrpProfiles() async {
    final db = await _databaseProvider();
    final maps = await db.query('frp_profiles', orderBy: 'updated_at DESC');
    return maps
        .map((m) => FrpProfile.fromMap(m.map((k, v) => MapEntry(k, v))))
        .toList();
  }

  Future<int> deleteFrpProfile(int id) async {
    final db = await _databaseProvider();
    return db.delete('frp_profiles', where: 'id = ?', whereArgs: [id]);
  }
}
