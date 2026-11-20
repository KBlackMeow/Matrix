import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Payload 库用该前缀把二进制内容编码为 Base64 文本后存入 SQLite 附属文件。
const String payloadBinaryPrefix = '__MATRIX_BINARY_B64__:';

/// 读取 Payload 库中的文件并还原原始字节。
///
/// 文本 payload 原样返回；二进制 payload（带 [payloadBinaryPrefix] 前缀）
/// 会先做 Base64 解码，导出后可直接使用。
Future<Uint8List> readPayloadFileBytes(String filePath) async {
  final path = filePath.trim();
  if (path.isEmpty) {
    throw const PayloadFileException('Payload 文件路径为空');
  }
  final file = File(path);
  if (!await file.exists()) {
    throw PayloadFileException('Payload 文件不存在: $path');
  }

  final bytes = await file.readAsBytes();
  final prefix = utf8.encode(payloadBinaryPrefix);
  if (!_startsWith(bytes, prefix)) return bytes;

  final encoded = ascii
      .decode(bytes.sublist(prefix.length), allowInvalid: true)
      .trim();
  try {
    return base64Decode(encoded);
  } on FormatException {
    throw PayloadFileException('Payload 二进制内容解码失败: $path');
  }
}

/// Payload 导出时的默认本地文件名：保留原名称，去掉任何路径部分。
String defaultPayloadDownloadName({required int id, required String name}) {
  final normalized = name.trim().replaceAll('\\', '/');
  final base = p.posix.basename(normalized);
  if (base.isEmpty ||
      base == '.' ||
      base == '..' ||
      base == '/' ||
      base.contains('\\')) {
    return 'payload_$id';
  }
  return base;
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

class PayloadFileException implements Exception {
  const PayloadFileException(this.message);

  final String message;

  @override
  String toString() => message;
}
