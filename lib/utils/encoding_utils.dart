import 'dart:convert';

import 'package:gbk_codec/gbk_codec.dart';

/// 解码字节为字符串，优先 UTF-8，失败或出现替换字符时尝试 GBK。
///
/// 用于 Webshell 文件管理：服务端（Java/PHP/Windows）可能使用 GBK 编码
/// 中文文件名或内容，客户端需兼容显示。
String decodeWithFallback(List<int> bytes) {
  if (bytes.isEmpty) return '';
  try {
    final s = utf8.decode(bytes, allowMalformed: true);
    if (s.contains('\uFFFD')) {
      return gbk.decode(bytes);
    }
    return s;
  } catch (_) {
    return gbk.decode(bytes);
  }
}
