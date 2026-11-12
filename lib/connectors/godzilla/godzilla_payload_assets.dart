import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/asset_loader.dart';

/// 加载 Godzilla 目标端 payload 引擎（base64 文本资产）。
///
/// 资产是 Matrix 自己实现的引擎（PHP / JSP / ASPX / ASP），不是
/// Godzilla 的 jar 内容。引擎用于“标准 Godzilla 马首次连接时”的播种；
/// 如果目标 Session 里已经有引擎，播种失败也不会影响后续调用。
class GodzillaPayloadAssets {
  GodzillaPayloadAssets._();

  static final Map<String, Uint8List?> _cache = {};

  static Future<Uint8List?> load(String assetPath) async {
    if (_cache.containsKey(assetPath)) return _cache[assetPath];

    String raw = '';
    try {
      raw = await loadAssetString(assetPath);
    } catch (_) {
      raw = '';
    }
    if (raw.trim().isEmpty) {
      try {
        final file = File(assetPath);
        if (await file.exists()) raw = await file.readAsString();
      } catch (_) {
        raw = '';
      }
    }

    final cleaned = raw
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('#'))
        .join()
        .replaceAll(RegExp(r'\s'), '')
        .trim();
    if (cleaned.isEmpty) {
      _cache[assetPath] = null;
      return null;
    }
    try {
      final bytes = Uint8List.fromList(base64.decode(cleaned));
      _cache[assetPath] = bytes;
      return bytes;
    } catch (_) {
      _cache[assetPath] = null;
      return null;
    }
  }
}
