import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;

import '../models/webshell.dart';
import '../services/webshell_connectivity_service.dart';
import 'db.dart';
import 'local_workspace.dart';
import 'remote_write_lock.dart';
import 'session_pool.dart';

/// MCP 活动日志回调：tool 名称 + 单行描述。
typedef McpActivityLogger = void Function(String line);

// ═══════════════════════════════════════════════════════════════════════════════
// Tool 注册
// ═══════════════════════════════════════════════════════════════════════════════

void registerAllTools(
  McpServer server,
  SessionPool pool,
  McpDatabase db,
  LocalWorkspace workspace, {
  required RemoteWriteLockCoordinator writeLocks,
  McpActivityLogger? onActivity,
}) {
  final log = onActivity;
  _registerShellList(server, db, log);
  _registerShellAdd(server, db, log);
  _registerShellUse(server, pool, db, log);
  _registerShellRemove(server, pool, db, log);
  _registerShellExec(server, pool, log);
  _registerFileList(server, pool, log);
  _registerFileRead(server, pool, log);
  _registerFileWrite(server, pool, writeLocks, log);
  _registerLocalUploadsList(server, workspace, log);
  _registerLocalDownloadsList(server, workspace, log);
  _registerFileUpload(server, pool, workspace, writeLocks, log);
  _registerFileDownload(server, pool, workspace, log);
  _registerFileDelete(server, pool, writeLocks, log);
  _registerSystemInfo(server, pool, log);
  _registerHomeDir(server, pool, log);
  _registerEnvList(server, pool, log);
}

// ═══════════════════════════════════════════════════════════════════════════════
// 辅助函数
// ═══════════════════════════════════════════════════════════════════════════════

String _trunc(String value, int maxLength) =>
    value.length <= maxLength ? value : '${value.substring(0, maxLength)}…';

CallToolResult _text(String text, {bool isError = false}) {
  return CallToolResult(
    content: [TextContent(text: text)],
    isError: isError,
  );
}

CallToolResult _json(Map<String, dynamic> data) {
  return CallToolResult(
    content: [
      TextContent(text: const JsonEncoder.withIndent('  ').convert(data)),
    ],
  );
}

CallToolResult _error(String message) => _text(message, isError: true);

int _shellId(Map<String, dynamic> args) => args['shell_id'] as int;
int? _optShellId(Map<String, dynamic> args) => args['shell_id'] as int?;

void _logCall(McpActivityLogger? log, String tool, Map<String, dynamic> args) {
  if (log == null) return;
  final details = args.entries
      .where((entry) => entry.key != 'password')
      .map((entry) {
        if (entry.key == 'content') {
          return 'content=<${'${entry.value}'.length} chars>';
        }
        return '${entry.key}=${_trunc('${entry.value}', 200)}';
      })
      .join(', ');
  log('→ $tool($details)');
}

void _logResult(McpActivityLogger? log, String tool, int ms, String summary) {
  log?.call('← $tool (${ms}ms) ${_trunc(summary, 500)}');
}

/// 包装 tool callback，自动记录调用、参数、耗时和结果摘要。
ToolFunction _wrap(String name, ToolFunction fn, McpActivityLogger? log) {
  if (log == null) return fn;
  return (args, extra) async {
    _logCall(log, name, args);
    final sw = Stopwatch()..start();
    try {
      final r = await fn(args, extra);
      final preview = r.content
          .whereType<TextContent>()
          .map((content) => content.text.replaceAll('\n', ' '))
          .join(' ');
      _logResult(log, name, sw.elapsedMilliseconds, preview);
      return r;
    } catch (e) {
      _logResult(log, name, sw.elapsedMilliseconds, 'ERROR: $e');
      rethrow;
    }
  };
}

Future<void> _ensureOnline(SessionPool pool, int? shellId) async {
  final svc = await pool.resolve(shellId);
  if (!await svc.ping()) {
    throw Exception('WebShell 连接失败（ping 超时或返回异常）');
  }
}

bool _isBinary(List<int> bytes) {
  if (bytes.isEmpty) return false;
  final sampleLen = bytes.length > 4096 ? 4096 : bytes.length;
  for (var i = 0; i < sampleLen; i++) {
    if (bytes[i] == 0) return true;
  }
  try {
    utf8.decode(bytes, allowMalformed: false);
    return false;
  } catch (_) {
    return true;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 管理工具
// ═══════════════════════════════════════════════════════════════════════════════

void _registerShellList(
  McpServer server,
  McpDatabase db,
  McpActivityLogger? log,
) {
  server.registerTool(
    'shell_list',
    description: '列出所有已保存的 WebShell 配置，并检测连通性',
    inputSchema: JsonSchema.object(properties: {}, required: []),
    callback: _wrap('shell_list', (args, extra) async {
      try {
        final rows = await db.listWebshellsWithProject();
        final webshells = rows.map((r) => Webshell.fromMap(r)).toList();

        final onlineMap = await WebshellConnectivityService.pingAll(
          webshells,
          timeout: const Duration(seconds: 5),
        );

        final list = webshells
            .map(
              (ws) => {
                'id': ws.id,
                'name': ws.name,
                'url': ws.url,
                'type': ws.type,
                'connector_type': ws.connectorType,
                'project_name':
                    rows.firstWhere((r) => r['id'] == ws.id)['project_name'] ??
                    '',
                'online': onlineMap[ws.id] ?? false,
              },
            )
            .toList();

        final onlineCount = list.where((w) => w['online'] == true).length;
        return _json({
          'count': list.length,
          'online': onlineCount,
          'webshells': list,
        });
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

void _registerShellAdd(
  McpServer server,
  McpDatabase db,
  McpActivityLogger? log,
) {
  server.registerTool(
    'shell_add',
    description: '添加一个新的 WebShell 配置',
    inputSchema: JsonSchema.object(
      properties: {
        'name': JsonSchema.string(description: 'WebShell 名称'),
        'url': JsonSchema.string(description: '目标 URL'),
        'password': JsonSchema.string(description: '连接密码'),
        'type': JsonSchema.string(description: '脚本类型：php, jsp, asp, aspx'),
        'connector_type': JsonSchema.string(
          description:
              '连接器类型。PHP: php_eval, php_b64rot13, php_behinder, php_passthru；'
              'JSP: jsp_classloader, jsp_behinder, jsp_runtime；ASP: asp_wscript; ASPX: aspx_cmd',
        ),
        'method': JsonSchema.string(description: 'HTTP 方法：GET 或 POST'),
      },
      required: ['name', 'url', 'password', 'type', 'connector_type'],
    ),
    callback: _wrap('shell_add', (args, extra) async {
      try {
        final projectId = await db.ensureDefaultProject();
        final ws = await db.createWebshell(
          projectId: projectId,
          name: args['name'] as String,
          url: args['url'] as String,
          password: args['password'] as String,
          type: (args['type'] as String?) ?? 'php',
          connectorType: (args['connector_type'] as String?) ?? 'php_eval',
          method: (args['method'] as String?) ?? 'POST',
        );
        return _json({
          'id': ws.id,
          'name': ws.name,
          'url': ws.url,
          'type': ws.type,
          'connector_type': ws.connectorType,
          'message': 'WebShell 已创建',
        });
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

void _registerShellUse(
  McpServer server,
  SessionPool pool,
  McpDatabase db,
  McpActivityLogger? log,
) {
  server.registerTool(
    'shell_use',
    description: '设置默认 WebShell（后续操作可省略 shell_id 参数）',
    inputSchema: JsonSchema.object(
      properties: {'shell_id': JsonSchema.integer(description: 'WebShell ID')},
      required: ['shell_id'],
    ),
    callback: _wrap('shell_use', (args, extra) async {
      try {
        final id = _shellId(args);
        final ws = await db.getWebshell(id);
        if (ws == null) return _error('WebShell $id 不存在');
        pool.defaultShellId = id;
        return _text('已切换到 WebShell #$id (${ws.name})');
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

void _registerShellRemove(
  McpServer server,
  SessionPool pool,
  McpDatabase db,
  McpActivityLogger? log,
) {
  server.registerTool(
    'shell_remove',
    description: '删除一个 WebShell 配置',
    inputSchema: JsonSchema.object(
      properties: {'shell_id': JsonSchema.integer(description: 'WebShell ID')},
      required: ['shell_id'],
    ),
    callback: _wrap('shell_remove', (args, extra) async {
      try {
        final id = _shellId(args);
        final ws = await db.getWebshell(id);
        if (ws == null) return _error('WebShell $id 不存在');
        pool.evict(id);
        await db.deleteWebshell(id);
        if (pool.defaultShellId == id) pool.defaultShellId = null;
        return _text('已删除 WebShell #$id (${ws.name})');
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// 命令执行
// ═══════════════════════════════════════════════════════════════════════════════

void _registerShellExec(
  McpServer server,
  SessionPool pool,
  McpActivityLogger? log,
) {
  server.registerTool(
    'shell_exec',
    description: '在目标机器上执行 shell 命令并返回输出',
    inputSchema: JsonSchema.object(
      properties: {
        'shell_id': JsonSchema.integer(
          description: 'WebShell ID（已设置默认 shell 时可省略）',
        ),
        'command': JsonSchema.string(description: '要执行的命令'),
        'working_dir': JsonSchema.string(description: '工作目录（可选）'),
      },
      required: ['command'],
    ),
    callback: _wrap('shell_exec', (args, extra) async {
      try {
        final svc = await pool.resolve(_optShellId(args));
        await _ensureOnline(pool, _optShellId(args));
        final output = await svc.executeCommand(
          args['command'] as String,
          workingDir: (args['working_dir'] as String?) ?? '',
        );
        return _text(output);
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// 文件操作
// ═══════════════════════════════════════════════════════════════════════════════

void _registerLocalUploadsList(
  McpServer server,
  LocalWorkspace workspace,
  McpActivityLogger? log,
) {
  server.registerTool(
    'local_uploads_list',
    description: '列出本地工作区 uploads 目录中可上传的文件。目录绝对路径：${workspace.uploadsPath}',
    inputSchema: JsonSchema.object(properties: {}, required: []),
    callback: _wrap('local_uploads_list', (args, extra) async {
      try {
        final entries = await workspace.listUploads();
        return _json({
          'directory': workspace.uploadsPath,
          'relative_directory': 'uploads',
          'entries': entries
              .map(
                (entry) => {
                  'path': entry.path,
                  'is_directory': entry.isDirectory,
                  'size': entry.size,
                },
              )
              .toList(),
        });
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

void _registerLocalDownloadsList(
  McpServer server,
  LocalWorkspace workspace,
  McpActivityLogger? log,
) {
  server.registerTool(
    'local_downloads_list',
    description:
        '列出本地工作区 downloads 目录中已下载的文件。目录绝对路径：${workspace.downloadsPath}',
    inputSchema: JsonSchema.object(properties: {}, required: []),
    callback: _wrap('local_downloads_list', (args, extra) async {
      try {
        final entries = await workspace.listDownloads();
        return _json({
          'directory': workspace.downloadsPath,
          'relative_directory': 'downloads',
          'entries': entries
              .map(
                (entry) => {
                  'path': entry.path,
                  'is_directory': entry.isDirectory,
                  'size': entry.size,
                },
              )
              .toList(),
        });
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

void _registerFileList(
  McpServer server,
  SessionPool pool,
  McpActivityLogger? log,
) {
  server.registerTool(
    'file_list',
    description: '列出目标机器上的目录内容',
    inputSchema: JsonSchema.object(
      properties: {
        'shell_id': JsonSchema.integer(
          description: 'WebShell ID（已设置默认 shell 时可省略）',
        ),
        'path': JsonSchema.string(description: '目录路径'),
      },
      required: ['path'],
    ),
    callback: _wrap('file_list', (args, extra) async {
      try {
        final svc = await pool.resolve(_optShellId(args));
        final entries = await svc.listDirectory(args['path'] as String);
        final list = entries
            .map(
              (e) => {
                'name': e.name,
                'is_directory': e.isDirectory,
                'size': e.size,
                'permissions': e.permissions,
                'modified': e.modified,
              },
            )
            .toList();
        return _json({'path': args['path'], 'entries': list});
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

void _registerFileRead(
  McpServer server,
  SessionPool pool,
  McpActivityLogger? log,
) {
  server.registerTool(
    'file_read',
    description: '读取目标机器上的文本文件内容',
    inputSchema: JsonSchema.object(
      properties: {
        'shell_id': JsonSchema.integer(
          description: 'WebShell ID（已设置默认 shell 时可省略）',
        ),
        'path': JsonSchema.string(description: '文件路径'),
      },
      required: ['path'],
    ),
    callback: _wrap('file_read', (args, extra) async {
      try {
        final svc = await pool.resolve(_optShellId(args));
        final content = await svc.readFile(args['path'] as String);
        return _text(content);
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

void _registerFileWrite(
  McpServer server,
  SessionPool pool,
  RemoteWriteLockCoordinator writeLocks,
  McpActivityLogger? log,
) {
  server.registerTool(
    'file_write',
    description: '向目标机器写入文本文件内容',
    inputSchema: JsonSchema.object(
      properties: {
        'shell_id': JsonSchema.integer(
          description: 'WebShell ID（已设置默认 shell 时可省略）',
        ),
        'path': JsonSchema.string(description: '目标文件路径'),
        'content': JsonSchema.string(description: '要写入的文本内容'),
      },
      required: ['path', 'content'],
    ),
    callback: _wrap('file_write', (args, extra) async {
      try {
        final svc = await pool.resolve(_optShellId(args));
        final remotePath = args['path'] as String;
        final ok = await writeLocks.synchronize(
          shellUrl: svc.webshell.url,
          remotePath: remotePath,
          operation: () => svc.writeFile(remotePath, args['content'] as String),
        );
        return _text(ok ? '写入成功' : '写入失败');
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

void _registerFileUpload(
  McpServer server,
  SessionPool pool,
  LocalWorkspace workspace,
  RemoteWriteLockCoordinator writeLocks,
  McpActivityLogger? log,
) {
  server.registerTool(
    'file_upload',
    description:
        '上传本地工作区 uploads 目录中的文件到目标机器（自动判断文本/二进制路径）。'
        '需要上传的文件必须先放入 ${workspace.uploadsPath}；'
        '请先调用 local_uploads_list 确认可用文件，再将返回的相对路径作为 upload_path。',
    inputSchema: JsonSchema.object(
      properties: {
        'shell_id': JsonSchema.integer(
          description: 'WebShell ID（已设置默认 shell 时可省略）',
        ),
        'upload_path': JsonSchema.string(
          description: '相对于 ~/matrix_home/uploads/ 的本地文件路径',
        ),
        'remote_path': JsonSchema.string(description: '目标机器上的写入路径'),
      },
      required: ['upload_path', 'remote_path'],
    ),
    callback: _wrap('file_upload', (args, extra) async {
      try {
        final uploadPath = args['upload_path'] as String;
        final remotePath = args['remote_path'] as String;

        final localPath = await workspace.resolveUploadFile(uploadPath);
        final file = File(localPath);

        final bytes = await file.readAsBytes();
        final svc = await pool.resolve(_optShellId(args));

        if (!svc.supportsFileWrite) {
          return _error('当前连接器不支持文件写入');
        }

        final looksBinary = _isBinary(bytes);
        final useBinaryPath =
            svc.isWindowsTarget || looksBinary || bytes.length > 100 * 1024;

        final ok = await writeLocks.synchronize(
          shellUrl: svc.webshell.url,
          remotePath: remotePath,
          operation: () async {
            if (!useBinaryPath) {
              return svc.writeFile(remotePath, utf8.decode(bytes));
            }
            return svc.writeFileBinaryWithProgress(
              remotePath,
              bytes,
              (sent, total) {},
            );
          },
        );

        return ok
            ? _text('上传成功 (${bytes.length} bytes → $remotePath)')
            : _error('上传失败：目标可能无写权限、磁盘满、或 base64 命令不可用');
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

void _registerFileDownload(
  McpServer server,
  SessionPool pool,
  LocalWorkspace workspace,
  McpActivityLogger? log,
) {
  server.registerTool(
    'file_download',
    description: '从目标机器下载文件并保存到本地下载目录',
    inputSchema: JsonSchema.object(
      properties: {
        'shell_id': JsonSchema.integer(
          description: 'WebShell ID（已设置默认 shell 时可省略）',
        ),
        'remote_path': JsonSchema.string(description: '目标机器上的文件路径'),
        'download_path': JsonSchema.string(
          description: '可选：相对于 ~/matrix_home/downloads/ 的保存路径',
        ),
      },
      required: ['remote_path'],
    ),
    callback: _wrap('file_download', (args, extra) async {
      try {
        final svc = await pool.resolve(_optShellId(args));
        final remotePath = args['remote_path'] as String;
        final requestedPath = args['download_path'] as String?;
        final fallbackName = p.posix.basename(remotePath.replaceAll('\\', '/'));
        final localName =
            requestedPath ??
            (fallbackName.isEmpty || fallbackName == '.'
                ? 'download.bin'
                : fallbackName);
        final localPath = await workspace.resolveDownloadDestination(localName);
        final bytes = await svc.readFileBinary(remotePath);
        await File(localPath).writeAsBytes(bytes, flush: true);
        return _json({
          'remote_path': remotePath,
          'local_path': await workspace.relativeToRoot(localPath),
          'size': bytes.length,
          'message': '已保存到本地下载目录',
        });
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

void _registerFileDelete(
  McpServer server,
  SessionPool pool,
  RemoteWriteLockCoordinator writeLocks,
  McpActivityLogger? log,
) {
  server.registerTool(
    'file_delete',
    description: '删除目标机器上的文件或空目录',
    inputSchema: JsonSchema.object(
      properties: {
        'shell_id': JsonSchema.integer(
          description: 'WebShell ID（已设置默认 shell 时可省略）',
        ),
        'path': JsonSchema.string(description: '要删除的文件路径'),
      },
      required: ['path'],
    ),
    callback: _wrap('file_delete', (args, extra) async {
      try {
        final svc = await pool.resolve(_optShellId(args));
        final remotePath = args['path'] as String;
        final ok = await writeLocks.synchronize(
          shellUrl: svc.webshell.url,
          remotePath: remotePath,
          operation: () => svc.deleteFile(remotePath),
        );
        return _text(ok ? '删除成功' : '删除失败');
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// 信息收集
// ═══════════════════════════════════════════════════════════════════════════════

void _registerSystemInfo(
  McpServer server,
  SessionPool pool,
  McpActivityLogger? log,
) {
  server.registerTool(
    'system_info',
    description: '获取目标机器的系统信息（OS、用户、内核版本等）',
    inputSchema: JsonSchema.object(
      properties: {
        'shell_id': JsonSchema.integer(
          description: 'WebShell ID（已设置默认 shell 时可省略）',
        ),
      },
      required: [],
    ),
    callback: _wrap('system_info', (args, extra) async {
      try {
        final svc = await pool.resolve(_optShellId(args));
        final info = await svc.getSystemInfo();
        return _json(info);
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

void _registerHomeDir(
  McpServer server,
  SessionPool pool,
  McpActivityLogger? log,
) {
  server.registerTool(
    'home_dir',
    description: '获取目标机器上的 HOME 目录路径',
    inputSchema: JsonSchema.object(
      properties: {
        'shell_id': JsonSchema.integer(
          description: 'WebShell ID（已设置默认 shell 时可省略）',
        ),
      },
      required: [],
    ),
    callback: _wrap('home_dir', (args, extra) async {
      try {
        final svc = await pool.resolve(_optShellId(args));
        final home = await svc.getHomeDir();
        return _text(home);
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}

void _registerEnvList(
  McpServer server,
  SessionPool pool,
  McpActivityLogger? log,
) {
  server.registerTool(
    'env_list',
    description: '列出目标机器上的环境变量名',
    inputSchema: JsonSchema.object(
      properties: {
        'shell_id': JsonSchema.integer(
          description: 'WebShell ID（已设置默认 shell 时可省略）',
        ),
      },
      required: [],
    ),
    callback: _wrap('env_list', (args, extra) async {
      try {
        final svc = await pool.resolve(_optShellId(args));
        final vars = await svc.listEnvVarNames();
        return _json({'count': vars.length, 'variables': vars});
      } catch (e) {
        return _error('$e');
      }
    }, log),
  );
}
