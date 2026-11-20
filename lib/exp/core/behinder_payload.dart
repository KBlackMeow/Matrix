/// WebShell 资产补丁：把内置载荷里的连接密钥替换成运行时生成的 MD5 前缀。
///
/// 旧实现把这段 `rootBundle.loadString + md5 + RegExp.replaceFirst` 抄了 5 份
/// （struts2 / spring / drupal / thinkphp / zentao）。密钥派生规则：
/// `key16 = MD5(password)[0:16]`。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 内置 WebShell 载荷。
enum ShellPayload {
  jspBehinder('assets/defaults/payloads/webshell/jsp_behinder.jsp'),
  jspRuntime('assets/defaults/payloads/webshell/jsp_runtime_get.jsp'),
  phpBehinder('assets/defaults/payloads/webshell/php_behinder.php'),
  phpPassthru('assets/defaults/payloads/webshell/php_passthru_req.php');

  const ShellPayload(this.asset);

  final String asset;

  /// 密钥替换规则；为 null 表示该载荷不需要打补丁。
  RegExp? get keyPattern => switch (this) {
    ShellPayload.jspBehinder => RegExp(r'String k="[0-9a-f]{16}"'),
    ShellPayload.phpBehinder => RegExp(r'\$key="[0-9a-f]{16}"'),
    _ => null,
  };

  String? get replacement => switch (this) {
    ShellPayload.jspBehinder => 'String k="__KEY__"',
    ShellPayload.phpBehinder => '\$key="__KEY__"',
    _ => null,
  };
}

abstract final class BehinderPayload {
  BehinderPayload._();

  /// `key16 = MD5(password)[0:16]`。
  static String key16(String password) =>
      md5.convert(utf8.encode(password)).toString().substring(0, 16);

  /// 读取载荷并打上密钥补丁；不需要补丁的载荷原样返回。
  static Future<String> load(ShellPayload kind, {required String password}) async {
    final content = await rootBundle.loadString(kind.asset);
    final pattern = kind.keyPattern;
    if (pattern == null) return content;
    final replacement = kind.replacement!.replaceAll('__KEY__', key16(password));
    return content.replaceFirst(pattern, replacement);
  }
}
