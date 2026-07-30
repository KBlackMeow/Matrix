import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/mcp/local_workspace.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LocalWorkspace workspace;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('matrix_workspace_test_');
    workspace = LocalWorkspace(root.path);
    await workspace.initialize();
  });

  tearDown(() => root.delete(recursive: true));

  test('initializes uploads and downloads directories', () {
    expect(Directory(workspace.uploadsPath).existsSync(), isTrue);
    expect(Directory(workspace.downloadsPath).existsSync(), isTrue);
  });

  test('resolves a relative upload path inside uploads directory', () async {
    final file = File(p.join(workspace.uploadsPath, 'payload.txt'));
    await file.writeAsString('payload');

    expect(
      await workspace.resolveUploadFile('payload.txt'),
      await file.resolveSymbolicLinks(),
    );
  });

  test('rejects upload paths that escape the uploads directory', () async {
    await expectLater(
      () => workspace.resolveUploadFile('../secret.txt'),
      throwsA(isA<LocalWorkspacePathException>()),
    );
  });

  test('rejects absolute upload paths', () async {
    await expectLater(
      () => workspace.resolveUploadFile('/tmp/secret.txt'),
      throwsA(isA<LocalWorkspacePathException>()),
    );
  });

  test('creates download parent directories under downloads only', () async {
    final path = await workspace.resolveDownloadDestination('reports/a.txt');

    expect(
      path,
      p.join(
        await Directory(
          p.join(workspace.downloadsPath, 'reports'),
        ).resolveSymbolicLinks(),
        'a.txt',
      ),
    );
    expect(
      Directory(p.join(workspace.downloadsPath, 'reports')).existsSync(),
      isTrue,
    );
  });

  test('lists upload files by paths relative to uploads directory', () async {
    await Directory(p.join(workspace.uploadsPath, 'tools')).create();
    await File(
      p.join(workspace.uploadsPath, 'tools', 'scanner.bin'),
    ).writeAsBytes([1, 2, 3]);

    final entries = await workspace.listUploads();

    expect(entries.map((entry) => entry.path), ['tools', 'tools/scanner.bin']);
    expect(entries.first.isDirectory, isTrue);
    expect(entries.last.size, 3);
  });
}
