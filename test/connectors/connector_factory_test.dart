import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/connector_factory.dart';
import 'package:matrix/connectors/shell_connector.dart';
import 'package:matrix/models/webshell.dart';

Webshell _fakeWebshell(String connectorType) {
  final now = DateTime.now();
  return Webshell(
    id: 1,
    projectId: 1,
    name: 'test',
    url: 'http://127.0.0.1/shell.php',
    password: 'mAtrix_911',
    connectorType: connectorType,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('ConnectorFactory', () {
    test('allTypes contains expected connector types', () {
      expect(ConnectorFactory.allTypes, hasLength(15));
      expect(
        ConnectorFactory.allTypes,
        equals([
          'php_eval',
          'php_b64rot13',
          'php_behinder',
          'php_passthru',
          'jsp_classloader',
          'jsp_behinder',
          'jsp_behinder_v2',
          'jsp_runtime',
          'asp_wscript',
          'aspx_cmd',
          'aspx_behinder',
          'php_godzilla',
          'jsp_godzilla',
          'aspx_godzilla',
          'asp_godzilla',
        ]),
      );
    });

    test('each connector type has a non-empty short label', () {
      for (final type in ConnectorFactory.allTypes) {
        expect(ConnectorFactory.shortLabel(type).trim(), isNotEmpty);
      }
    });

    test('create returns a ShellConnector instance for every type', () {
      for (final type in ConnectorFactory.allTypes) {
        final ws = _fakeWebshell(type);
        final connector = ConnectorFactory.create(ws);
        expect(connector, isA<ShellConnector>());
      }
    });

    test('fixedMethod POST for forced-method connectors', () {
      expect(ConnectorFactory.fixedMethod('php_behinder'), equals('POST'));
      expect(ConnectorFactory.fixedMethod('jsp_behinder'), equals('POST'));
      expect(ConnectorFactory.fixedMethod('jsp_runtime'), equals('POST'));
      expect(ConnectorFactory.fixedMethod('jsp_classloader'), equals('POST'));
      expect(ConnectorFactory.fixedMethod('php_b64rot13'), equals('POST'));
      expect(ConnectorFactory.fixedMethod('jsp_behinder_v2'), equals('POST'));
      expect(ConnectorFactory.fixedMethod('aspx_behinder'), equals('POST'));
      expect(ConnectorFactory.fixedMethod('php_godzilla'), equals('POST'));
      expect(ConnectorFactory.fixedMethod('jsp_godzilla'), equals('POST'));
      expect(ConnectorFactory.fixedMethod('aspx_godzilla'), equals('POST'));
      expect(ConnectorFactory.fixedMethod('asp_godzilla'), equals('POST'));
    });

    test('fixedMethod null for user-selectable-method connectors', () {
      expect(ConnectorFactory.fixedMethod('php_eval'), isNull);
      expect(ConnectorFactory.fixedMethod('php_passthru'), isNull);
      expect(ConnectorFactory.fixedMethod('asp_wscript'), isNull);
      expect(ConnectorFactory.fixedMethod('aspx_cmd'), isNull);
    });

    test('typeLabel mapping is correct', () {
      expect(ConnectorFactory.typeLabel('jsp_runtime'), equals('jsp'));
      expect(ConnectorFactory.typeLabel('jsp_behinder'), equals('jsp'));
      expect(ConnectorFactory.typeLabel('jsp_classloader'), equals('jsp'));
      expect(ConnectorFactory.typeLabel('aspx_cmd'), equals('aspx'));
      expect(ConnectorFactory.typeLabel('asp_wscript'), equals('asp'));
      expect(ConnectorFactory.typeLabel('php_eval'), equals('php'));
      expect(ConnectorFactory.typeLabel('php_passthru'), equals('php'));
      expect(ConnectorFactory.typeLabel('php_godzilla'), equals('php'));
      expect(ConnectorFactory.typeLabel('jsp_godzilla'), equals('jsp'));
      expect(ConnectorFactory.typeLabel('aspx_godzilla'), equals('aspx'));
      expect(ConnectorFactory.typeLabel('asp_godzilla'), equals('asp'));
    });

    test('catalog returns 15 flat entries with usage/scenario metadata', () {
      final catalog = ConnectorFactory.catalog();
      expect(catalog, hasLength(15));
      final byType = {for (final e in catalog) e['type'] as String: e};
      expect(byType.keys, equals(ConnectorFactory.allTypes.toSet()));
      for (final type in ConnectorFactory.allTypes) {
        final entry = byType[type];
        expect(entry, isNotNull, reason: 'catalog 缺少 $type');
        expect(entry!['usage'], isNotEmpty);
        expect(entry['scenario'], isNotEmpty);
        expect(entry['capabilities'], isNotEmpty);
      }
    });

    test('catalog capabilities match create().capabilities', () {
      final byType = {
        for (final e in ConnectorFactory.catalog()) e['type'] as String: e,
      };
      for (final type in ConnectorFactory.allTypes) {
        final connector = ConnectorFactory.create(_fakeWebshell(type));
        expect(
          (byType[type]!['capabilities'] as List).toSet(),
          equals(connector.capabilities.map((c) => c.name).toSet()),
        );
      }
    });
  });

  group('Godzilla 加密器（MCP 目录）', () {
    test('catalog 暴露每个 Godzilla 连接器的加密器与默认值', () {
      final byType = {
        for (final e in ConnectorFactory.catalog()) e['type'] as String: e,
      };
      const expected = {
        'php_godzilla': [
          'PHP_XOR_BASE64',
          'PHP_XOR_RAW',
          'PHP_EVAL_XOR_BASE64',
        ],
        'jsp_godzilla': ['JAVA_AES_BASE64', 'JAVA_AES_RAW'],
        'aspx_godzilla': [
          'CSHAP_AES_BASE64',
          'CSHAP_AES_RAW',
          'CSHAP_ASMX_AES_BASE64',
          'CSHAP_EVAL_AES_BASE64',
        ],
        'asp_godzilla': [
          'ASP_XOR_BASE64',
          'ASP_BASE64',
          'ASP_RAW',
          'ASP_XOR_RAW',
          'ASP_EVAL_BASE64',
        ],
      };
      expected.forEach((type, ids) {
        final entry = byType[type]!;
        final cryptions = (entry['cryptions'] as List)
            .map((c) => (c as Map)['id'] as String)
            .toList();
        expect(cryptions, ids, reason: type);
        expect(entry['default_cryption'], ids.first);
      });

      // 非 Godzilla 连接器不暴露 cryptions。
      expect(byType['php_eval']!.containsKey('cryptions'), isFalse);
    });

    test('cryption 校验：合法 / 跨架构 / 非 Godzilla', () {
      expect(
        ConnectorFactory.cryptionValidationError('php_godzilla', 'PHP_XOR_RAW'),
        isNull,
      );
      expect(
        ConnectorFactory.cryptionValidationError('php_godzilla', 'php_xor_raw'),
        isNull,
        reason: '大小写不敏感',
      );
      expect(
        ConnectorFactory.cryptionValidationError('php_godzilla', ''),
        isNull,
        reason: '空值表示用默认',
      );
      expect(
        ConnectorFactory.cryptionValidationError(
          'php_godzilla',
          'JAVA_AES_RAW',
        ),
        contains('不适用于'),
      );
      expect(
        ConnectorFactory.cryptionValidationError('php_eval', 'PHP_XOR_BASE64'),
        contains('不是 Godzilla 连接器'),
      );
    });
  });
}
