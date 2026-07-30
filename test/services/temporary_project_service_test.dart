import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/database/database_helper.dart';
import 'package:matrix/models/project.dart';
import 'package:matrix/services/temporary_project_service.dart';

class _MemoryDb implements DatabaseHelper {
  final Map<String, String> _meta = {};
  final List<Project> _projects = [];
  int _nextId = 1;

  @override
  Future<Project> createProject(
    String name, {
    required String domain,
    String? description,
  }) async {
    final now = DateTime.now();
    final project = Project(
      id: _nextId++,
      name: name,
      domain: domain,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
    _projects.add(project);
    return project;
  }

  @override
  Future<Project?> getProjectById(int id) async =>
      _projects.where((project) => project.id == id).firstOrNull;

  @override
  Future<List<Project>> getAllProjects() async => List.unmodifiable(_projects);

  @override
  Future<String?> getMetaValue(String key) async => _meta[key];

  @override
  Future<void> setMetaValue(String key, String value) async {
    _meta[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('creates and persists the temporary project on first launch', () async {
    final db = _MemoryDb();

    final project = await TemporaryProjectService.ensure(db);

    expect(project.name, TemporaryProjectService.name);
    expect(project.domain, isEmpty);
    expect(
      await db.getMetaValue(TemporaryProjectService.projectIdMetaKey),
      project.id.toString(),
    );
  });

  test('returns the same temporary project on subsequent launches', () async {
    final db = _MemoryDb();
    final first = await TemporaryProjectService.ensure(db);

    final second = await TemporaryProjectService.ensure(db);

    expect(second.id, first.id);
  });

  test('identifies only the persisted temporary project', () async {
    final db = _MemoryDb();
    final temporary = await TemporaryProjectService.ensure(db);
    final other = await db.createProject(
      'other',
      domain: 'https://example.com',
    );

    expect(
      await TemporaryProjectService.isTemporaryProject(db, temporary),
      isTrue,
    );
    expect(
      await TemporaryProjectService.isTemporaryProject(db, other),
      isFalse,
    );
  });

  test(
    'adopts an existing temporary project when metadata is unavailable',
    () async {
      final db = _MemoryDb();
      final existing = await db.createProject(
        TemporaryProjectService.name,
        domain: '',
      );

      final project = await TemporaryProjectService.ensure(db);

      expect(project.id, existing.id);
    },
  );
}
