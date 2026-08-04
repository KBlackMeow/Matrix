import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/pages/webshell_initial_connection_state.dart';

void main() {
  group('WebshellInitialConnectionState', () {
    test('offline persisted status does not start a connectivity check', () {
      final state = WebshellInitialConnectionState.fromPersistedStatus(0);

      expect(state.isConnected, isFalse);
      expect(state.shouldCheckOnOpen, isFalse);
    });

    test('online persisted status starts a connectivity check', () {
      final state = WebshellInitialConnectionState.fromPersistedStatus(1);

      expect(state.isConnected, isTrue);
      expect(state.shouldCheckOnOpen, isTrue);
    });
  });
}
