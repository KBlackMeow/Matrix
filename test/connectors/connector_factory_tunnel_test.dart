import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/connector_factory.dart';

void main() {
  group('ConnectorFactory.defaultSuo6TunnelProtocol', () {
    test('jsp connectors default to suo6', () {
      expect(ConnectorFactory.defaultSuo6TunnelProtocol('jsp_behinder'), isTrue);
      expect(ConnectorFactory.defaultSuo6TunnelProtocol('jsp_runtime'), isTrue);
      expect(ConnectorFactory.defaultSuo6TunnelProtocol('jsp_classloader'), isTrue);
    });

    test('non-jsp defaults to suo5', () {
      expect(ConnectorFactory.defaultSuo6TunnelProtocol('php_behinder'), isFalse);
      expect(ConnectorFactory.defaultSuo6TunnelProtocol('php_eval'), isFalse);
      expect(ConnectorFactory.defaultSuo6TunnelProtocol('aspx_cmd'), isFalse);
      expect(ConnectorFactory.defaultSuo6TunnelProtocol('asp_wscript'), isFalse);
    });
  });
}
