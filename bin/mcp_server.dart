import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

import 'package:matrix/mcp/db.dart';
import 'package:matrix/mcp/handlers.dart';
import 'package:matrix/mcp/session_pool.dart';

void main(List<String> args) async {
  // ── 参数解析 ────────────────────────────────────────────────────────────────
  String? dbPath;
  int httpPort = 3000;
  bool noHttp = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--db-path':
        dbPath = args[++i];
      case '--http-port':
        httpPort = int.parse(args[++i]);
      case '--no-http':
        noHttp = true;
      case '--help':
        stdout.writeln('用法: dart run bin/mcp_server.dart [选项]\n'
            '  --db-path <path>     Matrix 数据库路径（默认：自动检测）\n'
            '  --http-port <port>   Streamable HTTP 端口（默认：3000）\n'
            '  --no-http            只启动 Stdio，不启动 HTTP\n'
            '  --help               显示此帮助');
        return;
    }
  }

  dbPath ??= Platform.environment['MATRIX_DB_PATH'] ?? McpDatabase.defaultPath();

  // ── 初始化数据库 ────────────────────────────────────────────────────────────
  McpDatabase.initFfi();
  final db = McpDatabase(dbPath);
  await db.database; // 预加载，确保路径正确
  stderr.writeln('[Matrix MCP] 数据库: $dbPath');

  // ── 会话池（所有 transport 共享）─────────────────────────────────────────────
  final pool = SessionPool((id) => db.getWebshell(id));

  // ── Stdio Transport ────────────────────────────────────────────────────────
  final stdioServer = McpServer(
    Implementation(name: 'matrix-mcp', version: '1.2.0'),
    options: McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );
  registerAllTools(stdioServer, pool, db);
  stderr.writeln('[Matrix MCP] Stdio 就绪');

  // ── Streamable HTTP Transport（后台）────────────────────────────────────────
  StreamableMcpServer? httpServer;
  if (!noHttp) {
    httpServer = StreamableMcpServer(
      serverFactory: (connectionId) {
        final s = McpServer(
          Implementation(name: 'matrix-mcp', version: '1.2.0'),
          options: McpServerOptions(
            capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
          ),
        );
        registerAllTools(s, pool, db);
        return s;
      },
      host: '127.0.0.1',
      port: httpPort,
      path: '/mcp',
      enableDnsRebindingProtection: true,
      allowedHosts: {'127.0.0.1', 'localhost'},
    );
    unawaited(httpServer.start());
    stderr.writeln('[Matrix MCP] Streamable HTTP: http://127.0.0.1:$httpPort/mcp');
  }

  // ── 优雅退出 ────────────────────────────────────────────────────────────────
  ProcessSignal.sigint.watch().listen((_) async {
    stderr.writeln('[Matrix MCP] 正在关闭...');
    await stdioServer.close();
    await httpServer?.stop();
    await db.close();
    exit(0);
  });

  // Stdio 阻塞主线程
  await stdioServer.connect(StdioServerTransport());
}
