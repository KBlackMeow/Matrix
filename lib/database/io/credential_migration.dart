import 'package:sqflite_common/sqlite_api.dart';

import '../../core/crypto/credential_cipher.dart';

/// 把数据库中历史明文凭据就地加密（幂等）。
///
/// 覆盖 `webshells.password / secret_key` 与 `frp_profiles.token`。
/// 返回被改写的记录数；加密器未就绪时返回 0（不写入任何内容）。
Future<int> encryptLegacyCredentialsIn(DatabaseExecutor db) async {
  if (!CredentialCipher.isReady) return 0;
  var changed = 0;

  for (final row in await db.query(
    'webshells',
    columns: <String>['id', 'password', 'secret_key'],
  )) {
    final password = row['password'] as String?;
    final secretKey = row['secret_key'] as String?;
    final nextPassword = CredentialCipher.encryptIfReady(password);
    final nextSecret = CredentialCipher.encryptIfReady(secretKey);
    if (nextPassword == password && nextSecret == secretKey) continue;
    await db.update(
      'webshells',
      <String, Object?>{'password': nextPassword, 'secret_key': nextSecret},
      where: 'id = ?',
      whereArgs: <Object?>[row['id']],
    );
    changed++;
  }

  for (final row in await db.query(
    'frp_profiles',
    columns: <String>['id', 'token'],
  )) {
    final token = row['token'] as String?;
    final next = CredentialCipher.encryptIfReady(token);
    if (next == token) continue;
    await db.update(
      'frp_profiles',
      <String, Object?>{'token': next},
      where: 'id = ?',
      whereArgs: <Object?>[row['id']],
    );
    changed++;
  }

  return changed;
}
