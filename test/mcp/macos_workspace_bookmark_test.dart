import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS runner persists a security-scoped matrix_home bookmark', () {
    final source = File('macos/Runner/MainFlutterWindow.swift').readAsStringSync();

    expect(source, contains('matrix/local_workspace'));
    expect(source, contains('getWorkspacePath'));
    expect(source, contains('selectWorkspace'));
    expect(source, contains('withSecurityScope'));
    expect(source, contains('panel.directoryURL'));
    expect(source, contains('panel.canCreateDirectories = true'));
    expect(source, isNot(contains('url.lastPathComponent == "matrix_home"')));
  });
}
