/// Payload 模型：用于管理本地存储的 Webshell 脚本/片段
class Payload {
  final int id;
  final String name;
  final String type; // php / jsp / asp / other
  /// 脚本内容（IO 端从文件读取，Web 端存内存）
  final String content;

  /// 本地文件路径（Web 端为空字符串）
  final String filePath;

  /// true = 内置默认 payload，不可删除
  final bool isDefault;
  final String? description;
  final String? tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Payload({
    required this.id,
    required this.name,
    required this.type,
    required this.content,
    this.filePath = '',
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
      'type': type,
      'file_path': filePath,
      'is_default': isDefault ? 1 : 0,
      'description': description,
      'tags': tags,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  /// 仅供 Web 内存模式使用（带 content 字段的旧格式）
  factory Payload.fromMapWithContent(Map<String, dynamic> map) {
    return Payload(
      id: map['id'] as int,
      name: map['name'] as String,
      type: (map['type'] as String?) ?? 'php',
      content: (map['content'] as String?) ?? '',
      filePath: '',
      isDefault: (map['is_default'] as int? ?? 0) == 1,
      description: map['description'] as String?,
      tags: map['tags'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Payload copyWith({
    int? id,
    String? name,
    String? type,
    String? content,
    String? filePath,
    bool? isDefault,
    String? description,
    String? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Payload(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      isDefault: isDefault ?? this.isDefault,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
