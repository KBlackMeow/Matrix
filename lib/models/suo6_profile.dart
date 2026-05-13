import '../services/suo6_client_service.dart';

class Suo6Profile {
  final int id;
  final int projectId;
  final String name;
  final String targetUrl;
  final String listenHost;
  final int listenPort;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Suo6Profile({
    required this.id,
    required this.projectId,
    required this.name,
    required this.targetUrl,
    required this.listenHost,
    required this.listenPort,
    required this.createdAt,
    required this.updatedAt,
  });

  Suo6Config toConfig() => Suo6Config(
        targetUrl: targetUrl,
        listenHost: listenHost,
        listenPort: listenPort,
      );

  Suo6Profile copyWith({
    int? id,
    int? projectId,
    String? name,
    String? targetUrl,
    String? listenHost,
    int? listenPort,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Suo6Profile(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      targetUrl: targetUrl ?? this.targetUrl,
      listenHost: listenHost ?? this.listenHost,
      listenPort: listenPort ?? this.listenPort,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static Suo6Profile fromMap(Map<String, dynamic> m) => Suo6Profile(
        id: m['id'] as int,
        projectId: m['project_id'] as int,
        name: (m['name'] as String?) ?? '',
        targetUrl: (m['target_url'] as String?) ?? '',
        listenHost: (m['listen_host'] as String?) ?? '127.0.0.1',
        listenPort: (m['listen_port'] as int?) ?? 1080,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );
}
