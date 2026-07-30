import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../mcp/db.dart';
import '../mcp/handlers.dart';
import '../mcp/local_workspace.dart';
import '../mcp/remote_write_lock.dart';
import '../mcp/session_pool.dart';
import '../database/database_helper.dart';
import '../theme/app_theme.dart';

/// MCP Server 管理页面 —— 直接在进程内启停 Matrix MCP 服务。
class McpServerPage extends StatefulWidget {
  const McpServerPage({super.key});

  @override
  State<McpServerPage> createState() => _McpServerPageState();
}

class _McpServerPageState extends State<McpServerPage> {
  static const _workspaceChannel = MethodChannel('matrix/local_workspace');
  bool _running = false;
  int _httpPort = 3000;
  final _portController = TextEditingController();
  final _log = <String>[];
  final _scrollController = ScrollController();
  final _dbHelper = DatabaseHelper();

  McpDatabase? _mcpDb;
  final _writeLocks = RemoteWriteLockCoordinator();
  LocalWorkspace? _workspace;
  final Map<String, SessionPool> _connectionPools = {};
  StreamableMcpServer? _httpServer;

  static const _metaKeyPort = 'mcp_http_port';

  @override
  void initState() {
    super.initState();
    _loadPort();
  }

  Future<void> _loadPort() async {
    final v = await _dbHelper.getMetaValue(_metaKeyPort);
    final port = int.tryParse(v ?? '') ?? 3000;
    _portController.text = '$port';
    _httpPort = port;
  }

  @override
  void dispose() {
    _portController.dispose();
    _scrollController.dispose();
    _stop();
    super.dispose();
  }

  void _addLog(String msg) {
    if (!mounted) return;
    setState(() {
      _log.add(msg);
      if (_log.length > 500) _log.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _start() async {
    final port = int.tryParse(_portController.text) ?? 3000;
    _httpPort = port;
    await _dbHelper.setMetaValue(_metaKeyPort, '$port');

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docsDir.path, 'matrix.db');
      _addLog('[MCP] 数据库: $dbPath');

      _mcpDb = McpDatabase(dbPath);
      await _mcpDb!.database;
      _workspace = LocalWorkspace(await _resolveWorkspacePath());
      await _workspace!.initialize();
      _addLog('[MCP] 本地文件: ${_workspace!.rootPath}');

      _httpServer = StreamableMcpServer(
        serverFactory: (connectionId) {
          // 每个 MCP 连接持有独立的 SessionPool，避免 shell_use 跨客户端串用
          final pool = SessionPool((id) => _mcpDb!.getWebshell(id));
          _connectionPools[connectionId] = pool;

          final s = McpServer(
            Implementation(name: 'matrix-mcp', version: '1.2.0'),
            options: McpServerOptions(
              capabilities: ServerCapabilities(
                tools: ServerCapabilitiesTools(),
              ),
            ),
          );
          registerAllTools(
            s,
            pool,
            _mcpDb!,
            _workspace!,
            writeLocks: _writeLocks,
            onActivity: _addLog,
          );

          // 连接关闭时清理 pool（框架会通过 factoryOnClose 模式保留此回调）
          s.server.onclose = () {
            pool.clear();
            _connectionPools.remove(connectionId);
          };

          return s;
        },
        host: '127.0.0.1',
        port: port,
        path: '/mcp',
        enableDnsRebindingProtection: true,
        allowedHosts: {'127.0.0.1', 'localhost'},
      );
      await _httpServer!.start();

      setState(() => _running = true);
      _addLog('[MCP] Streamable HTTP → http://127.0.0.1:$port/mcp');
      _addLog('[MCP] 已启动');
    } catch (e) {
      _addLog('[ERROR] $e');
    }
  }

  Future<String> _resolveWorkspacePath() async {
    if (!Platform.isMacOS) return LocalWorkspace.defaultWorkspace().rootPath;
    final restored = await _workspaceChannel.invokeMethod<String>(
      'getWorkspacePath',
    );
    final selected =
        restored ??
        await _workspaceChannel.invokeMethod<String>('selectWorkspace');
    if (selected == null || selected.isEmpty) {
      throw StateError('未选择 ~/matrix_home，MCP 未启动');
    }
    return selected;
  }

  Future<void> _stop() async {
    try {
      await _httpServer?.stop();
    } catch (_) {}
    _httpServer = null;
    for (final pool in _connectionPools.values) {
      pool.clear();
    }
    _connectionPools.clear();
    try {
      await _mcpDb?.close();
    } catch (_) {}
    _mcpDb = null;
    _workspace = null;

    if (mounted) setState(() => _running = false);
    _addLog('[MCP] 已停止');
  }

  @override
  Widget build(BuildContext context) {
    final onlineCount = _connectionPools.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 顶部状态卡 ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (_running ? AppColors.primary : AppColors.border)
                  .withValues(alpha: _running ? 0.5 : 1.0),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.router_outlined,
                color: _running ? AppColors.primary : AppColors.textMuted,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MCP Server',
                      style: AppTextStyles.heading(
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _running
                          ? 'http://127.0.0.1:$_httpPort/mcp'
                          : '提供 WebShell 操作能力给 AI 编码助手',
                      style: AppTextStyles.caption(
                        size: 13,
                        color: _running
                            ? AppColors.textSecondary
                            : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // 状态指示灯
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _running ? AppColors.primary : AppColors.red,
                            shape: BoxShape.circle,
                            boxShadow: _running
                                ? [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _running ? 'Running' : 'Stopped',
                          style: AppTextStyles.caption(
                            size: 12,
                            color: _running ? AppColors.primary : AppColors.red,
                          ),
                        ),
                        if (_running) ...[
                          const SizedBox(width: 16),
                          Text(
                            '会话: $onlineCount',
                            style: AppTextStyles.caption(
                              size: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // 端口 + 启动按钮
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: _portController,
                      enabled: !_running,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: AppTextStyles.body(
                        size: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _running ? _stop : _start,
                    icon: Icon(
                      _running ? Icons.stop : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(_running ? 'Stop' : 'Start'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _running
                          ? AppColors.red
                          : AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 日志区 ──────────────────────────────────────────────────────────────
        Row(
          children: [
            Text(
              '日志',
              style: AppTextStyles.caption(
                size: 12,
                color: AppColors.textMuted,
              ),
            ),
            const Spacer(),
            if (_log.isNotEmpty)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _log.join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制到剪贴板'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '复制全部',
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: _log.isEmpty
                ? Center(
                    child: Text(
                      '启动后 MCP 调用记录将在这里显示',
                      style: AppTextStyles.caption(
                        size: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : SelectionArea(
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: _log.length,
                      itemBuilder: (_, i) => SelectableText(
                        _log[i],
                        style: AppTextStyles.caption(
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
