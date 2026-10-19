import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/database/legacy_sandbox_migrator.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String homePath;
  late String destinationPath;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('matrix_sandbox_migration_');
    homePath = p.join(root.path, 'home');
    destinationPath = p.join(root.path, 'documents');
  });

  tearDown(() => root.delete(recursive: true));

  Future<File> legacyDatabase() async {
    final file = File(
      p.join(
        homePath,
        'Library',
        'Containers',
        'com.example.matrix',
        'Data',
        'Documents',
        'matrix.db',
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('legacy database');
    return file;
  }

  test('copies legacy database, SQLite sidecars, and payload store', () async {
    final sourceDatabase = await legacyDatabase();
    await File('${sourceDatabase.path}-wal').writeAsString('wal');
    await File('${sourceDatabase.path}-shm').writeAsString('shm');
    final payload = File(
      p.join(sourceDatabase.parent.path, 'mx_store', 'payload.bin'),
    );
    await payload.parent.create(recursive: true);
    await payload.writeAsBytes([1, 2, 3]);

    final migrated = await LegacySandboxMigrator.migrateFrom(
      sourceDirectory: sourceDatabase.parent.path,
      destinationDirectory: destinationPath,
    );

    expect(migrated, isTrue);
    expect(
      await File(p.join(destinationPath, 'matrix.db')).readAsString(),
      'legacy database',
    );
    expect(
      await File(p.join(destinationPath, 'matrix.db-wal')).readAsString(),
      'wal',
    );
    expect(
      await File(p.join(destinationPath, 'matrix.db-shm')).readAsString(),
      'shm',
    );
    expect(
      await File(
        p.join(destinationPath, 'mx_store', 'payload.bin'),
      ).readAsBytes(),
      [1, 2, 3],
    );
  });

  test('does not overwrite an existing destination database', () async {
    await legacyDatabase();
    final destination = File(p.join(destinationPath, 'matrix.db'));
    await destination.parent.create(recursive: true);
    await destination.writeAsString('current database');

    final migrated = await LegacySandboxMigrator.migrateFrom(
      sourceDirectory: p.join(
        homePath,
        'Library',
        'Containers',
        'com.example.matrix',
        'Data',
        'Documents',
      ),
      destinationDirectory: destinationPath,
    );

    expect(migrated, isFalse);
    expect(await destination.readAsString(), 'current database');
  });
}
