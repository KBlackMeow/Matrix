import 'dart:io';

/// NetBIOS 探测与域控识别（复刻 fscan）
class NetbiosService {
  final Duration timeout;

  NetbiosService({this.timeout = const Duration(seconds: 3)});

  /// NetBIOS 名称查询响应
  static String? parseNetbiosName(List<int> data) {
    if (data.length < 57) return null;
    try {
      // NetBIOS 响应中名称在偏移 13 开始，33 字节，需解码
      final nameBytes = data.sublist(13, 46);
      final sb = StringBuffer();
      for (var i = 0; i < nameBytes.length; i += 2) {
        if (i + 1 >= nameBytes.length) break;
        final c = ((nameBytes[i] - 0x41) << 4) | (nameBytes[i + 1] - 0x41);
        if (c == 0 || c == 32) break;
        if (c > 0 && c < 256) sb.writeCharCode(c);
      }
      final name = sb.toString().trim();
      return name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }

  /// 发送 NetBIOS 名称查询，解析主机名
  Future<NetbiosResult?> probe(String host) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.listen((event) {});

      // NetBIOS 名称查询请求（简化）
      final query = _buildNetbiosQuery(host);
      final target = InternetAddress.tryParse(host);
      if (target == null) return null;

      socket.send(query, target, 137);
      await Future.delayed(const Duration(milliseconds: 500));

      Datagram? reply;
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        reply = socket.receive();
        if (reply != null && reply.data.length > 50) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (reply == null) return null;

      final name = parseNetbiosName(reply.data);
      final isDC = name != null &&
          (name.toUpperCase().contains('DC') ||
              name.toUpperCase().endsWith('DC') ||
              reply.data.length > 100);

      return NetbiosResult(
        host: host,
        name: name ?? '(未知)',
        isDomainController: isDC,
      );
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  List<int> _buildNetbiosQuery(String host) {
    // 简化 NetBIOS 名称查询包
    final name = host.replaceAll('.', ' ');
    final encoded = <int>[];
    for (var i = 0; i < name.length.clamp(0, 32); i++) {
      final c = name.codeUnitAt(i);
      encoded.add(0x41 + (c >> 4));
      encoded.add(0x41 + (c & 0x0f));
    }
    while (encoded.length < 32) {
      encoded.add(0x43); // C
      encoded.add(0x41); // A
    }

    return [
      0x00, 0x00, // Transaction ID
      0x10, 0x00, // Flags: Query
      0x00, 0x01, // Questions: 1
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Answers, etc.
      0x20, // Name length 32
      ...encoded,
      0x00, // Null
      0x00, 0x20, // Type NB
      0x00, 0x01, // Class IN
    ];
  }
}

class NetbiosResult {
  final String host;
  final String name;
  final bool isDomainController;

  NetbiosResult({
    required this.host,
    required this.name,
    required this.isDomainController,
  });
}
