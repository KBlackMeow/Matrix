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
      expect(ConnectorFactory.allTypes, hasLength(11));
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
    });

    test('catalog returns 11 flat entries with usage/scenario metadata', () {
      final catalog = ConnectorFactory.catalog();
      expect(catalog, hasLength(11));
      final byType = {
        for (final e in catalog) e['type'] as String: e,
      };
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
}
