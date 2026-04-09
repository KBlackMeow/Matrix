import 'dart:collection';

import '../../app/constants.dart';

class LogBuffer {
  LogBuffer({int? maxLines}) : _maxLines = maxLines ?? AppConstants.logBufferSize;

  final int _maxLines;
  final Queue<String> _lines = Queue<String>();
  String? _joinedCache;

  void append(String line) {
    _lines.add(line);
    while (_lines.length > _maxLines) {
      _lines.removeFirst();
    }
    _joinedCache = null;
  }

  void clear() {
    _lines.clear();
    _joinedCache = null;
  }

  List<String> get lines => _lines.toList(growable: false);

  String get joined => _joinedCache ??= _lines.join('\n');
}
