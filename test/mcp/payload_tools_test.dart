import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:matrix/mcp/db.dart';
import 'package:matrix/mcp/handlers.dart';
import 'package:matrix/mcp/local_workspace.dart';
import 'package:matrix/mcp/session_pool.dart';
import 'package:matrix/services/remote_write_lock.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = [];
  bool started = false;

  @override
  String? get sessionId => null;

  @override
  Future<void> close() async => onclose?.call();

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
  }

  @override
  Future<void> start() async => started = true;

  void receive(JsonRpcMessage message) {
    onmessage?.call(message);
    if (message is JsonRpcInitializeRequest) {
      Future<void>.delayed(Duration.zero, () {
        onmessage?.call(const JsonRpcInitializedNotification());
      });
    }
  }
}

Future<JsonRpcResponse> _call(
  _MockTransport transport,
  int id,
  String name,
  Map<String, dynamic> args,
) async {
  transport.receive(
    JsonRpcCallToolRequest(
      id: id,
      params: CallToolRequest(name: name, arguments: args).toJson(),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 80));
  final response = transport.sentMessages
      .whereType<JsonRpcResponse>()
      .lastWhere((r) => r.id == id);
  return response;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('payload_list / payload_download work through MCP transport', () async {
    McpDatabase.initFfi();
    final tmp = await Directory.systemTemp.createTemp('matrix_payload_mcp_');
    addTearDown(() => tmp.delete(recursive: true));
    final payloadDir = Directory(p.join(tmp.path, 'mx_store'));
    await payloadDir.create();
    final payloadFile = File(p.join(payloadDir.path, 'demo.php'));
    await payloadFile.writeAsString('<?php echo "demo";');

    final dbPath = p.join(tmp.path, 'matrix.db');
    final raw = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 13,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE payloads (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL DEFAULT 'php',
              file_path TEXT NOT NULL DEFAULT '',
              is_default INTEGER NOT NULL DEFAULT 0,
              description TEXT,
              tags TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final payloadId = await raw.insert('payloads', {
      'name': 'demo.php',
      'type': 'php',
      'file_path': payloadFile.path,
      'is_default': 0,
      'created_at': now,
      'updated_at': now,
    });
    await raw.close();

    final db = McpDatabase(dbPath);
    addTearDown(db.close);
    final workspace = LocalWorkspace(p.join(tmp.path, 'workspace'));
    await workspace.initialize();

    final server = McpServer(
      const Implementation(name: 'test', version: '1.0.0'),
      options: const ServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    );
    registerAllTools(
      server,
      SessionPool((id) async => null),
      db,
      workspace,
      projectId: 1,
      writeLocks: RemoteWriteLockCoordinator(),
    );
    final transport = _MockTransport();
    await server.connect(transport);

    transport.receive(
      JsonRpcInitializeRequest(
        id: 1,
        initParams: const InitializeRequestParams(
          protocolVersion: latestInitializationProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'test-client', version: '1.0.0'),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final listResponse = await _call(transport, 10, 'payload_list', {});
    expect(listResponse.result['isError'], isNot(true));
    final listText =
        (listResponse.result['content'] as List).first['text'] as String;
    final listJson = jsonDecode(listText) as Map<String, dynamic>;
    expect(listJson['count'], 1);
    expect(listJson['payloads'][0]['name'], 'demo.php');

    final downloadResponse = await _call(transport, 11, 'payload_download', {
      'payload_id': payloadId,
      'overwrite': true,
    });
    expect(downloadResponse.result['isError'], isNot(true));
    final downloadText =
        (downloadResponse.result['content'] as List).first['text'] as String;
    final downloadJson = jsonDecode(downloadText) as Map<String, dynamic>;
    expect(downloadJson['local_path'], 'downloads/demo.php');
    final downloaded = File(
      p.join(workspace.rootPath, downloadJson['local_path'] as String),
    );
    expect(await downloaded.readAsString(), '<?php echo "demo";');
  });
}
