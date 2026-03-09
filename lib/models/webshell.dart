/// Webshell 模型
class Webshell {
  final int id;
  final int projectId;
  final String name;
  final String url;
  final String? password;
  /// 请求方法：GET / POST
  final String method;
  /// 1=在线, 0=离线
  final int status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Webshell({
    required this.id,
    required this.projectId,
    required this.name,
    required this.url,
    this.password,
    this.method = 'POST',
    this.status = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'project_id': projectId,
      'name': name,
      'url': url,
      'password': password,
      'method': method,
      'status': status,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Webshell.fromMap(Map<String, dynamic> map) {
    return Webshell(
      id: map['id'] as int,
      projectId: map['project_id'] as int,
      name: map['name'] as String,
      url: map['url'] as String,
      password: map['password'] as String?,
      method: (map['method'] as String?) ?? 'POST',
      status: (map['status'] as int?) ?? 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Webshell copyWith({
    int? id,
    int? projectId,
    String? name,
    String? url,
    String? password,
    String? method,
    int? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Webshell(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      url: url ?? this.url,
      password: password ?? this.password,
      method: method ?? this.method,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
