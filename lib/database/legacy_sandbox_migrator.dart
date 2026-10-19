import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies Matrix data from a prior storage location.
///
/// A destination database is never overwritten unless the caller has already
/// established that it contains no user-created data. When replacement is
/// allowed, the destination is first retained with a `.pre-migration` suffix.
class LegacySandboxMigrator {
  static const _databaseName = 'matrix.db';
  static const _payloadDirectoryName = 'mx_store';

  static Future<bool> migrateFrom({
    required String sourceDirectory,
    required String destinationDirectory,
    bool replaceDestination = false,
  }) async {
    final sourceDatabase = File(p.join(sourceDirectory, _databaseName));
    final destinationDatabase = File(
      p.join(destinationDirectory, _databaseName),
    );

    if (!await sourceDatabase.exists()) return false;
    if (await destinationDatabase.exists() && !replaceDestination) {
      return false;
    }

    final destination = Directory(destinationDirectory);
    await destination.create(recursive: true);
    final backups = <_Move>[];
    try {
      if (await destinationDatabase.exists()) {
        await _backupExisting(destinationDatabase, backups);
        for (final suffix in ['-wal', '-shm']) {
          await _backupExisting(
            File('${destinationDatabase.path}$suffix'),
            backups,
          );
        }
        await _backupExisting(
          Directory(p.join(destinationDirectory, _payloadDirectoryName)),
          backups,
        );
      }

      await _copyFile(sourceDatabase, destinationDatabase);
      for (final suffix in ['-wal', '-shm']) {
        await _copyFile(
          File('${sourceDatabase.path}$suffix'),
          File('${destinationDatabase.path}$suffix'),
        );
      }
      await _copyDirectory(
        Directory(p.join(sourceDirectory, _payloadDirectoryName)),
        Directory(p.join(destinationDirectory, _payloadDirectoryName)),
      );
      return true;
    } catch (_) {
      await _deleteIfExists(destinationDatabase);
      for (final suffix in ['-wal', '-shm']) {
        await _deleteIfExists(File('${destinationDatabase.path}$suffix'));
      }
      await _deleteIfExists(
        Directory(p.join(destinationDirectory, _payloadDirectoryName)),
      );
      for (final backup in backups.reversed) {
        if (await backup.backup.exists()) {
          await backup.backup.rename(backup.original.path);
        }
      }
      rethrow;
    }
  }

  static Future<void> _backupExisting(
    FileSystemEntity entity,
    List<_Move> moves,
  ) async {
    if (!await entity.exists()) return;
    final backup = '${entity.path}.pre-sandbox-migration';
    final backupEntity = entity is Directory ? Directory(backup) : File(backup);
    if (await backupEntity.exists()) {
      throw StateError('已存在迁移备份: $backup');
    }
    await entity.rename(backup);
    moves.add(_Move(entity, backupEntity));
  }

  static Future<void> _copyFile(File source, File destination) async {
    if (await source.exists()) await source.copy(destination.path);
  }

  static Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    if (!await source.exists()) return;
    await destination.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: source.path);
      final target = p.join(destination.path, relative);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
  }

  static Future<void> _deleteIfExists(FileSystemEntity entity) async {
    if (await entity.exists()) await entity.delete(recursive: true);
  }
}

class _Move {
  const _Move(this.original, this.backup);

  final FileSystemEntity original;
  final FileSystemEntity backup;
}
