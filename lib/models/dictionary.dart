/// 字典模型：用于管理本地存储的字典/词表文件
class Dictionary {
  final int id;
  final String name;
  /// 字典用途分类：passwords / usernames / paths / subdomains / custom
  final String category;
  /// 哈希后的本地文件路径（Web 端为空字符串）
  final String filePath;
  /// 文件行数（导入时统计，存入 DB）
  final int lineCount;
  /// 文件大小（字节，导入时统计）
  final int fileSize;
  /// true = 内置默认字典，不可删除
  final bool isDefault;
  final String? description;
  final String? tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Dictionary({
    required this.id,
    required this.name,
    required this.category,
    required this.filePath,
    required this.lineCount,
    required this.fileSize,
    this.isDefault = false,
    this.description,
    this.tags,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'file_path': filePath,
      'line_count': lineCount,
      'file_size': fileSize,
      'is_default': isDefault ? 1 : 0,
      'description': description,
      'tags': tags,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Dictionary.fromMap(Map<String, dynamic> map) {
    return Dictionary(
      id: map['id'] as int,
      name: map['name'] as String,
      category: (map['category'] as String?) ?? 'custom',
      filePath: (map['file_path'] as String?) ?? '',
      lineCount: (map['line_count'] as int?) ?? 0,
      fileSize: (map['file_size'] as int?) ?? 0,
      isDefault: (map['is_default'] as int? ?? 0) == 1,
      description: map['description'] as String?,
      tags: map['tags'] as String?,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Dictionary copyWith({
    int? id,
    String? name,
    String? category,
    String? filePath,
    int? lineCount,
    int? fileSize,
    bool? isDefault,
    String? description,
    String? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Dictionary(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      filePath: filePath ?? this.filePath,
      lineCount: lineCount ?? this.lineCount,
      fileSize: fileSize ?? this.fileSize,
      isDefault: isDefault ?? this.isDefault,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
