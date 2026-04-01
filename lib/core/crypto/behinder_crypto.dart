import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../../app/constants.dart';

class BehinderCrypto {
  static String deriveKey(String? rawPassword) {
    final pass = rawPassword?.trim().isNotEmpty == true
        ? rawPassword!.trim()
        : AppConstants.defaultShellPassword;
    if (_isHex(pass, 16)) return pass.toLowerCase();
    final md5 = crypto.md5.convert(utf8.encode(pass)).toString();
    return md5.substring(0, 16);
  }

  static bool _isHex(String s, int expectedLength) {
    if (s.length != expectedLength) return false;
    for (var i = 0; i < expectedLength; i++) {
      final c = s.codeUnitAt(i);
      if (!((c >= 0x30 && c <= 0x39) ||
          (c >= 0x61 && c <= 0x66) ||
          (c >= 0x41 && c <= 0x46))) {
        return false;
      }
    }
    return true;
  }
}
