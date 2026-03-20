import 'dart:io';
import 'dart:typed_data';

/// NetBIOS 探测与域控识别（复刻 fscan）
/// 使用 NBSTAT 通配符查询（type 0x21）返回所有注册名称及 MAC
/// 通过名称后缀 0x1C 正确识别域控制器（替代不可靠的字符串匹配）
class NetbiosService {
  final Duration timeout;

  NetbiosService({this.timeout = const Duration(seconds: 3)});

  // ── NBSTAT 响应解析 ───────────────────────────────────────────────────────

  /// 解析 NBSTAT（type 0x21）响应，返回名称表、主机名、MAC 及 DC 标志
  static NetbiosParseResult? parseNbstatResponse(List<int> raw) {
    if (raw.length < 57) return null;
    try {
      final buf = Uint8List.fromList(raw);

      // DNS 头 12 字节 + 应答 RR 名称字段
      int offset = 12;
      if (offset >= buf.length) return null;

      // 名称字段：压缩指针（0xC0 xx）或完整编码（0x20 + 32字节 + 0x00 = 34字节）
      if (buf[offset] == 0xC0) {
        offset += 2;
      } else {
        offset += 1 + 32 + 1; // length(1) + encoded name(32) + null(1)
      }

      // type(2) + class(2) + ttl(4) + rdlength(2) = 10 字节
      offset += 10;
      if (offset >= buf.length) return null;

      final numNames = buf[offset++];
      if (numNames == 0 || offset + numNames * 18 > buf.length) return null;

      final names = <NetbiosName>[];
      bool isDC = false;
      String? primaryName;

      for (var i = 0; i < numNames; i++) {
        if (offset + 18 > buf.length) break;
        // 每条记录：15 字节名称 + 1 字节后缀 + 2 字节标志
        final nameBytes = buf.sublist(offset, offset + 15);
        final suffix = buf[offset + 15];
        final flags = (buf[offset + 16] << 8) | buf[offset + 17];
        offset += 18;

        final name = String.fromCharCodes(nameBytes)
            .replaceAll('\x00', '')
            .replaceAll('\u0000', '')
            .trim();
        if (name.isEmpty) continue;

        names.add(NetbiosName(name: name, suffix: suffix, flags: flags));

        // 0x1C = 域组名（Domain Controllers Group） — 唯一可靠的 DC 标志
        if (suffix == 0x1C) isDC = true;
        // 0x00 unique = 工作站/服务器主名（group 标志 bit15=0）
        if (suffix == 0x00 && (flags & 0x8000) == 0 && primaryName == null) {
          primaryName = name;
        }
      }

      // 统计块：第 0-5 字节为 MAC 地址
      String? mac;
      if (offset + 6 <= buf.length) {
        final m = buf.sublist(offset, offset + 6);
        // 全 0 的 MAC 无意义（如虚拟机占位）
        if (m.any((b) => b != 0)) {
          mac = m.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
        }
      }

      return NetbiosParseResult(
        names: names,
        primaryName: primaryName ?? (names.isNotEmpty ? names.first.name : null),
        isDomainController: isDC,
        mac: mac,
      );
    } catch (_) {
      return null;
    }
  }

  // ── 主探测入口 ────────────────────────────────────────────────────────────

  /// 探测主机：NBSTAT UDP 137，成功后附加 RPC 135 多网卡 IP 发现
  Future<NetbiosResult?> probe(String host) async {
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final target = InternetAddress.tryParse(host);
      if (target == null) return null;

      sock.send(_buildNbstatQuery(), target, 137);

      Datagram? reply;
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        reply = sock.receive();
        if (reply != null && reply.data.length > 50) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (reply == null) return null;

      final parsed = parseNbstatResponse(reply.data);
      if (parsed == null) return null;

      final additionalIps = await _probeRpc135(host);

      return NetbiosResult(
        host: host,
        name: parsed.primaryName ?? '(未知)',
        isDomainController: parsed.isDomainController,
        names: parsed.names,
        mac: parsed.mac,
        additionalIps: additionalIps,
      );
    } catch (_) {
      return null;
    } finally {
      sock?.close();
    }
  }

  // ── NBSTAT 查询包构造 ─────────────────────────────────────────────────────

  /// 构造 NBSTAT 通配符查询（type 0x21）
  /// 通配符 "*"（0x2A）Level-1 编码：
  ///   '*' → high nibble 2 → 0x43, low nibble A → 0x4B
  ///   剩余 15 个 0x00 → 各编码为 0x41 0x41
  List<int> _buildNbstatQuery() {
    // 32 字节编码的通配符名称
    final encoded = [0x43, 0x4B, ...List.filled(30, 0x41)];
    return [
      0xAB, 0xCD, // Transaction ID
      0x00, 0x00, // Flags: Standard query, non-recursive
      0x00, 0x01, // Questions: 1
      0x00, 0x00, // Answer RRs: 0
      0x00, 0x00, // Authority RRs: 0
      0x00, 0x00, // Additional RRs: 0
      0x20,       // Name length: 32
      ...encoded,
      0x00,       // Null terminator
      0x00, 0x21, // Type: NBSTAT (33)
      0x00, 0x01, // Class: IN
    ];
  }

  // ── RPC 135 多网卡发现 ────────────────────────────────────────────────────

  /// 连接 TCP 135，发送 DCE/RPC BIND，扫描响应中的私有 IP 地址
  /// 对应 fscan FindNet.go：通过 EPM 响应发现双网卡主机的额外 IP
  Future<List<String>> _probeRpc135(String host) async {
    Socket? s;
    try {
      s = await Socket.connect(host, 135,
          timeout: const Duration(seconds: 2));

      final allData = <int>[];
      s.listen(
        (data) => allData.addAll(data),
        onError: (_) {},
        cancelOnError: false,
      );

      // 发送 DCE/RPC BIND（绑定 EPM 接口 e1af8308-…）
      s.add(_buildRpcBind());
      await s.flush();
      // 等待服务器响应 BIND_ACK（含接口注册数据）
      await Future.delayed(const Duration(milliseconds: 800));

      return _findPrivateIps(allData, host);
    } catch (_) {
      return [];
    } finally {
      try {
        s?.destroy();
      } catch (_) {}
    }
  }

  /// DCE/RPC BIND 请求，绑定 EPM 接口
  /// UUID: e1af8308-5d1f-11c9-91a4-08002b14a0fa, v3.0
  /// Transfer: NDR 8a885d04-1ceb-11c9-9fe8-08002b104860 v2.0
  List<int> _buildRpcBind() => [
        // ── DCE/RPC header (16 bytes) ────────────────────────────────────
        0x05, 0x00, // rpc_ver = 5, rpc_ver_minor = 0
        0x0B,       // ptype = BIND (11)
        0x03,       // pfc_flags: first_frag | last_frag
        0x10, 0x00, 0x00, 0x00, // packed_drep: little-endian ASCII
        0x48, 0x00, // frag_length = 72
        0x00, 0x00, // auth_length = 0
        0x01, 0x00, 0x00, 0x00, // call_id = 1
        // ── bind body ───────────────────────────────────────────────────
        0xB8, 0x10, // max_xmit_frag = 4280
        0xB8, 0x10, // max_recv_frag = 4280
        0x00, 0x00, 0x00, 0x00, // assoc_group_id = 0
        0x01,       // num_context_items = 1
        0x00, 0x00, 0x00, // padding
        // ── context item 0 ──────────────────────────────────────────────
        0x00, 0x00, // context_id = 0
        0x01, 0x00, // num_trans_items = 1
        // abstract_syntax: EPM uuid (little-endian)
        0x08, 0x83, 0xAF, 0xE1, 0x1F, 0x5D, 0xC9, 0x11,
        0x91, 0xA4, 0x08, 0x00, 0x2B, 0x14, 0xA0, 0xFA,
        0x03, 0x00, 0x00, 0x00, // version 3.0
        // transfer_syntax: NDR uuid
        0x04, 0x5D, 0x88, 0x8A, 0xEB, 0x1C, 0xC9, 0x11,
        0x9F, 0xE8, 0x08, 0x00, 0x2B, 0x10, 0x48, 0x60,
        0x02, 0x00, 0x00, 0x00, // version 2.0
      ];

  /// 在原始字节流中搜索私有 IPv4 地址（RFC 1918）
  List<String> _findPrivateIps(List<int> data, String excludeHost) {
    final ips = <String>{};
    for (var i = 0; i + 3 < data.length; i++) {
      final a = data[i], b = data[i + 1], c = data[i + 2], d = data[i + 3];
      if (a == 0 || d == 0) continue;
      final isPrivate = (a == 10) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168);
      if (isPrivate) {
        final ip = '$a.$b.$c.$d';
        if (ip != excludeHost) ips.add(ip);
      }
    }
    return ips.toList();
  }
}

// ── 数据模型 ─────────────────────────────────────────────────────────────────

/// NetBIOS 名称条目
class NetbiosName {
  final String name;

  /// 后缀含义：0x00=工作站, 0x03=消息, 0x20=文件服务,
  ///           0x1B=域主浏览器(PDC), 0x1C=域控制器组, 0x1D=主浏览器
  final int suffix;

  /// 标志：bit15=1 组名, bit15=0 唯一名
  final int flags;

  bool get isGroup => (flags & 0x8000) != 0;

  NetbiosName({
    required this.name,
    required this.suffix,
    required this.flags,
  });
}

/// parseNbstatResponse 的内部返回结构
class NetbiosParseResult {
  final List<NetbiosName> names;
  final String? primaryName;
  final bool isDomainController;
  final String? mac;

  NetbiosParseResult({
    required this.names,
    required this.primaryName,
    required this.isDomainController,
    required this.mac,
  });
}

/// probe() 的最终返回结果
class NetbiosResult {
  final String host;
  final String name;
  final bool isDomainController;
  final List<NetbiosName> names;
  final String? mac;

  /// RPC 135 发现的额外 IP（多网卡主机）
  final List<String> additionalIps;

  NetbiosResult({
    required this.host,
    required this.name,
    required this.isDomainController,
    required this.names,
    this.mac,
    this.additionalIps = const [],
  });
}
