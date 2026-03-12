import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// 负责从项目根目录下的 `data/` 读取 Shiro 相关的字典 / Payload。
///
/// 约定：
/// - 所有 Base64 编码的 Java serialized payload 存放在 `data/*.b64`
/// - Shiro key 字典文件为 `data/shiro_keys.txt`
class ShiroPayloadRepo {
  const ShiroPayloadRepo();

  /// 读取指定 Base64 payload 文件，并解码为原始字节。
  ///
  /// [fileName] 仅为文件名，例如 `payload_cc1_tomcat_echo.b64`，
  /// 实际路径为 `data/[fileName]`。
  Future<Uint8List> loadPayload(String fileName) async {
    String b64;
    // 优先从 Flutter 资源中读取（打包后的场景）
    try {
      b64 = (await rootBundle.loadString('data/$fileName')).trim();
    } catch (_) {
      // 回退到直接从工作目录读取（开发时直接放在项目根 data/ 下）
      try {
        final file = io.File('data/$fileName');
        b64 = await file.exists() ? (await file.readAsString()).trim() : '';
      } catch (_) {
        b64 = '';
      }
    }
    if (b64.isEmpty) return Uint8List(0);
    final normalized = b64.replaceAll(RegExp(r'\s+'), '');
    final decoded = _decodeB64String(normalized);
    return Uint8List.fromList(base64.decode(decoded));
  }

  /// 加载 Base64 字符串（用于填充输入框），支持 URL 编码（%2B、%2F、%3D）。
  Future<String> loadPayloadB64String(String fileName) async {
    String b64;
    try {
      b64 = (await rootBundle.loadString('data/$fileName')).trim();
    } catch (_) {
      try {
        final file = io.File('data/$fileName');
        b64 = await file.exists() ? (await file.readAsString()).trim() : '';
      } catch (_) {
        b64 = '';
      }
    }
    if (b64.isEmpty) return '';
    final normalized = b64.replaceAll(RegExp(r'\s+'), '');
    return _decodeB64String(normalized);
  }

  static String _decodeB64String(String s) {
    if (s.contains('%')) {
      return Uri.decodeComponent(s);
    }
    return s;
  }

  /// 读取 `data/shiro_keys.txt` 里的 key 列表。
  ///
  /// 每行一个 Base64 编码的 AES key（例如 `kPH+bIxk5D2deZiIxcaaaA==`）。
  Future<List<String>> loadKeys() async {
    String content;
    try {
      content = await rootBundle.loadString('data/shiro_keys.txt');
    } catch (_) {
      try {
        final file = io.File('data/shiro_keys.txt');
        content = await file.exists() ? (await file.readAsString()) : '';
      } catch (_) {
        content = '';
      }
    }
    if (content.isEmpty) return const [];
    return content
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}

