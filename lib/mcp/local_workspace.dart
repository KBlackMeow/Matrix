import 'dart:io';

import 'package:path/path.dart' as p;

/// Persistent, user-owned files available to the MCP server.
///
/// MCP callers can only address paths relative to [uploadsPath] or
/// [downloadsPath]; arbitrary host paths are never accepted.
class LocalWorkspace {
  LocalWorkspace(String rootPath) : _rootPath = p.normalize(rootPath);

  factory LocalWorkspace.defaultWorkspace() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        (throw StateError('无法确定当前用户的 HOME 目录'));
    return LocalWorkspace(p.join(home, 'matrix_home'));
  }

  final String _rootPath;

  String get rootPath => _rootPath;
  String get uploadsPath => p.join(_rootPath, 'uploads');
  String get downloadsPath => p.join(_rootPath, 'downloads');

  Future<String> relativeToRoot(String absolutePath) async => p.relative(
    absolutePath,
    from: await Directory(_rootPath).resolveSymbolicLinks(),
  );

  Future<List<LocalWorkspaceEntry>> listUploads() => _list(uploadsPath);

  Future<List<LocalWorkspaceEntry>> listDownloads() => _list(downloadsPath);

  Future<void> initialize() async {
    await Directory(uploadsPath).create(recursive: true);
    await Directory(downloadsPath).create(recursive: true);
    await _resolvedDirectoryInsideRoot(uploadsPath);
    await _resolvedDirectoryInsideRoot(downloadsPath);
  }

  /// Resolves an existing upload file from an MCP-relative path.
  Future<String> resolveUploadFile(String relativePath) async {
    final candidate = _relativeCandidate(uploadsPath, relativePath);
    final file = File(candidate);
    if (!await file.exists()) {
      throw LocalWorkspacePathException('上传文件不存在: $relativePath');
    }
    final resolved = await file.resolveSymbolicLinks();
    await _assertInside(
      await _resolvedDirectoryInsideRoot(uploadsPath),
      resolved,
    );
    return resolved;
  }

  /// Resolves a new download destination, creating its parent directories.
  Future<String> resolveDownloadDestination(String relativePath) async {
    final candidate = _relativeCandidate(downloadsPath, relativePath);
    final parent = Directory(p.dirname(candidate));
    await parent.create(recursive: true);
    final resolvedParent = await parent.resolveSymbolicLinks();
    await _assertInside(
      await _resolvedDirectoryInsideRoot(downloadsPath),
      resolvedParent,
    );
    return p.join(resolvedParent, p.basename(candidate));
  }

  Future<List<LocalWorkspaceEntry>> _list(String base) async {
    final entries = await Directory(
      base,
    ).list(recursive: true, followLinks: false).toList();
    entries.sort((a, b) => a.path.compareTo(b.path));
    final result = <LocalWorkspaceEntry>[];
    for (final entry in entries) {
      // Links are intentionally not traversed or exposed: they may point out
      // of the workspace after the directory was authorized.
      if (entry is Link) continue;
      final stat = await entry.stat();
      result.add(
        LocalWorkspaceEntry(
          path: p.relative(entry.path, from: base),
          isDirectory: entry is Directory,
          size: entry is File ? stat.size : null,
        ),
      );
    }
    return result;
  }

  String _relativeCandidate(String base, String relativePath) {
    if (relativePath.trim().isEmpty || p.isAbsolute(relativePath)) {
      throw LocalWorkspacePathException('路径必须是非空相对路径');
    }
    final normalized = p.normalize(relativePath);
    if (normalized == '..' || normalized.startsWith('..${p.separator}')) {
      throw LocalWorkspacePathException('路径不能超出工作区');
    }
    return p.join(base, normalized);
  }

  Future<String> _resolvedDirectoryInsideRoot(String path) async {
    final root = await Directory(_rootPath).resolveSymbolicLinks();
    final resolved = await Directory(path).resolveSymbolicLinks();
    await _assertInside(root, resolved);
    return resolved;
  }

  Future<void> _assertInside(String root, String path) async {
    if (!p.equals(root, path) && !p.isWithin(root, path)) {
      throw LocalWorkspacePathException('路径超出 Matrix 工作区');
    }
  }
}

class LocalWorkspacePathException implements Exception {
  LocalWorkspacePathException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocalWorkspaceEntry {
  const LocalWorkspaceEntry({
    required this.path,
    required this.isDirectory,
    required this.size,
  });

  final String path;
  final bool isDirectory;
  final int? size;
}
