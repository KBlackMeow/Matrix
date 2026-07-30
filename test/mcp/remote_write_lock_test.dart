import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/mcp/remote_write_lock.dart';

void main() {
  RemoteWriteLockCoordinator coordinator() => RemoteWriteLockCoordinator(
    resolveHostId: (url) async => Uri.parse(url).host,
  );

  test(
    'serializes writes for the same IP and normalized remote path',
    () async {
      final locks = coordinator();
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      var secondStarted = false;

      final first = locks.synchronize(
        shellUrl: 'http://10.0.0.8/a.php',
        remotePath: '/var/www/../www/site.zip',
        operation: () async {
          firstStarted.complete();
          await releaseFirst.future;
        },
      );
      await firstStarted.future;
      final second = locks.synchronize(
        shellUrl: 'http://10.0.0.8/other.jsp',
        remotePath: '/var/www/site.zip',
        operation: () async {
          secondStarted = true;
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(secondStarted, isFalse);
      releaseFirst.complete();
      await Future.wait([first, second]);
      expect(secondStarted, isTrue);
    },
  );

  test(
    'allows writes to the same path on different IPs concurrently',
    () async {
      final locks = coordinator();
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      var secondStarted = false;

      final first = locks.synchronize(
        shellUrl: 'http://10.0.0.8/a.php',
        remotePath: '/tmp/archive.zip',
        operation: () async {
          firstStarted.complete();
          await releaseFirst.future;
        },
      );
      await firstStarted.future;
      await locks.synchronize(
        shellUrl: 'http://10.0.0.9/a.php',
        remotePath: '/tmp/archive.zip',
        operation: () async {
          secondStarted = true;
        },
      );

      expect(secondStarted, isTrue);
      releaseFirst.complete();
      await first;
    },
  );
}
