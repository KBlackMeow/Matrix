class FileEntry {
  final String name;
  final bool isDirectory;
  final int size;
  final String permissions;
  final String modified;

  const FileEntry({
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.permissions,
    required this.modified,
  });

  String get formattedSize {
    if (isDirectory) return '--';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
