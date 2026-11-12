/// Webshell 模型
class Webshell {
  final int id;
  final int projectId;
  final String name;
  final String url;
  final String? password;
  /// Godzilla 的“密钥”字段（secretKey），与连接密码分离。
  ///
  /// - 连接密码（[password]）用作 HTTP 参数名；
  /// - 密钥用于派生 `key16 = MD5(secretKey)[0:16]`。
  ///
  /// 非 Godzilla 连接器忽略此字段。
  final String secretKey;
  /// Godzilla 的加密器 ID（`PHP_XOR_BASE64` 等）。
  ///
  /// 连接器只表示「架构 + 协议」，加密器独立选择；为空时回退到该架构
  /// 的默认（BASE64）变体。
  final String cryption;
  /// 显示用类型标签：php / jsp / asp
  final String type;
  /// 请求方法：GET / POST
  final String method;
  /// 1=在线, 0=离线
  final int status;
  /// 连接器类型，驱动运行时行为：
  /// php_eval / php_b64rot13 / php_passthru /
  /// jsp_classloader / jsp_runtime / asp_wscript
  final String connectorType;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Webshell({
    required this.id,
    required this.projectId,
    required this.name,
    required this.url,
    this.password,
    this.secretKey = 'key',
    this.cryption = '',
    this.type = 'php',
    this.method = 'POST',
    this.status = 1,
    this.connectorType = 'php_eval',
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
      'secret_key': secretKey,
      'cryption': cryption,
      'type': type,
      'method': method,
      'status': status,
      'connector_type': connectorType,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Webshell.fromMap(Map<String, dynamic> map) {
    final storedType = (map['type'] as String?) ?? 'php';
    // 向后兼容：旧记录无 connector_type，按 type 推断
    final connType = (map['connector_type'] as String?)
        ?? (storedType == 'jsp' ? 'jsp_classloader' : 'php_eval');
    return Webshell(
      id: map['id'] as int,
      projectId: map['project_id'] as int,
      name: map['name'] as String,
      url: map['url'] as String,
      password: map['password'] as String?,
      secretKey: (map['secret_key'] as String?) ?? 'key',
      cryption: (map['cryption'] as String?) ?? '',
      type: storedType,
      method: (map['method'] as String?) ?? 'POST',
      status: (map['status'] as int?) ?? 1,
      connectorType: connType,
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
    String? secretKey,
    String? cryption,
    String? type,
    String? method,
    int? status,
    String? connectorType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Webshell(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      url: url ?? this.url,
      password: password ?? this.password,
      secretKey: secretKey ?? this.secretKey,
      cryption: cryption ?? this.cryption,
      type: type ?? this.type,
      method: method ?? this.method,
      status: status ?? this.status,
      connectorType: connectorType ?? this.connectorType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
