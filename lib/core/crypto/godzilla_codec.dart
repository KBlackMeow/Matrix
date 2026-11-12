import 'dart:convert';
import 'dart:typed_data';

import 'deflate_stub.dart' if (dart.library.io) 'deflate_io.dart';

/// Godzilla 参数二进制格式与 gzip 辅助。
///
/// 线上格式（`ReqParameter.formatEx()` → `Parameter.serialize()`）：
///
/// ```text
/// name(UTF-8) + 0x02 + len(int32 LE) + value(raw bytes)
/// ```
///
/// 注意长度是**小端序**。写成大端会让服务端把 `len=2` 读成
/// `0x02000000`，直接触发 Java heap OOM。
class GodzillaCodec {
  GodzillaCodec._();

  static Uint8List encodeParams(Map<String, List<int>> params) {
    final out = BytesBuilder(copy: false);
    params.forEach((name, value) {
      out.add(utf8.encode(name));
      out.addByte(0x02);
      out.add(_int32Le(value.length));
      out.add(value);
    });
    return out.toBytes();
  }

  static Map<String, Uint8List> decodeParams(Uint8List data) {
    final result = <String, Uint8List>{};
    final key = <int>[];
    var i = 0;
    while (i < data.length) {
      final b = data[i];
      if (b == 0x02) {
        if (i + 5 > data.length) break;
        final len = _readInt32Le(data, i + 1);
        i += 5;
        if (len < 0 || i + len > data.length) break;
        result[utf8.decode(key, allowMalformed: true)] =
            Uint8List.fromList(data.sublist(i, i + len));
        key.clear();
        i += len;
      } else {
        key.add(b);
        i++;
      }
    }
    return result;
  }

  static Uint8List _int32Le(int value) {
    final out = Uint8List(4);
    out[0] = value & 0xff;
    out[1] = (value >> 8) & 0xff;
    out[2] = (value >> 16) & 0xff;
    out[3] = (value >> 24) & 0xff;
    return out;
  }

  static int _readInt32Le(Uint8List data, int offset) {
    return (data[offset] & 0xff) |
        ((data[offset + 1] & 0xff) << 8) |
        ((data[offset + 2] & 0xff) << 16) |
        ((data[offset + 3] & 0xff) << 24);
  }

  static bool looksLikeGzip(Uint8List data) =>
      data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b;

  /// 仅当首两字节是 gzip 魔数时才解压；失败时原样返回。
  static Uint8List maybeGunzip(Uint8List data) {
    if (!looksLikeGzip(data)) return data;
    try {
      return Uint8List.fromList(gzipDecompress(data));
    } catch (_) {
      return data;
    }
  }

  static Uint8List gzip(Uint8List data) {
    try {
      return Uint8List.fromList(gzipCompress(data));
    } catch (_) {
      return data;
    }
  }
}
