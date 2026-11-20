import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'macOS runner persists a reusable workspace bookmark while unsandboxed',
    () {
      final source = File(
        'macos/Runner/MainFlutterWindow.swift',
      ).readAsStringSync();

      expect(source, contains('matrix/local_workspace'));
      expect(source, contains('getWorkspacePath'));
      expect(source, contains('selectWorkspace'));
      expect(source, contains('bookmarkData('));
      expect(source, contains('resolvingBookmarkData:'));
      expect(source, contains('bookmarkDataIsStale: &isStale'));
      expect(source, contains('panel.directoryURL'));
      expect(source, contains('panel.canCreateDirectories = true'));
      expect(source, isNot(contains('url.lastPathComponent == "matrix_home"')));
      // The app runs unsandboxed since the ~/.matrix relocation; security-scoped
      // bookmarks would require the sandbox entitlement and are intentionally off.
      expect(source, isNot(contains('withSecurityScope')));
    },
  );
}
