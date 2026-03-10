import 'package:flutter/services.dart';

import '../database/database_helper.dart';

/// 内置默认数据种子化服务
/// 版本号递增时自动补充新增的默认条目
class SeedService {
  static const _kMetaKey = 'seed_version';
  static const _kCurrentVersion = 1;

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
      description: 'ROT13 + Base64 双重编码绕过 WAF，POST 参数 x',
      tags: 'php,bypass,base64,rot13,waf',
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
    // ── ASP ──────────────────────────────────────────────────────────────
    _PayloadDef(
      asset: 'assets/defaults/payloads/asp_wscript_get.asp',
      name: 'asp_wscript_get.asp',
      type: 'asp',
      description: 'ASP WScript.Shell 命令执行，GET 参数 cmd，cmd.exe /c',
      tags: 'asp,wscript,shell,get,cmd',
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

  /// 应用启动时调用，幂等，已种子化则立即返回
  static Future<void> seed(DatabaseHelper db) async {
    final stored = await db.getMetaValue(_kMetaKey);
    final storedVersion = int.tryParse(stored ?? '0') ?? 0;
    if (storedVersion >= _kCurrentVersion) return;

    for (final def in _defaultPayloads) {
      try {
        final data = await rootBundle.load(def.asset);
        final bytes = data.buffer.asUint8List();
        final content = String.fromCharCodes(bytes);
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
}

class _PayloadDef {
  final String asset;
  final String name;
  final String type;
  final String description;
  final String tags;

  const _PayloadDef({
    required this.asset,
    required this.name,
    required this.type,
    required this.description,
    required this.tags,
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
