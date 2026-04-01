import 'package:flutter/material.dart';

import '../services/webshell_service.dart';
import '../theme/app_theme.dart';

class TerminalEntry {
  final String command;
  final String dir;
  final DateTime timestamp;
  String? output;

  TerminalEntry({
    required this.command,
    required this.dir,
    required this.timestamp,
  });
}

// ─── 模式切换按钮 ──────────────────────────────────────────────────────────────

class ModeToggle extends StatelessWidget {
  final bool integrated;
  final VoidCallback onToggle;

  const ModeToggle({super.key, required this.integrated, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: integrated ? '切换到分离式（底部输入栏）' : '切换到一体式（模拟真实终端）',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: integrated
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: integrated
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                integrated ? Icons.terminal : Icons.horizontal_split_outlined,
                size: 13,
                color: integrated ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                integrated ? '一体式' : '分离式',
                style: AppTextStyles.caption(
                  size: 11,
                  color: integrated
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tab 补全器 ───────────────────────────────────────────────────────────────
//
// 补全策略（对齐 bash 行为）：
//   • 唯一候选        → 直接填入，目录追加 /，文件追加空格
//   • 多个候选，首次 Tab → 填入最长公共前缀（LCP）；LCP == 当前输入则直接开始循环
//   • 多个候选，再次 Tab → 在候选列表中循环（zsh 风格）
//   • token 已以 / 结尾  → 视为"进入目录"，触发新一轮补全
//   • 命令位置（无空格前缀）→ 内置命令名 + 当前目录文件一起参与补全
//   • $VAR 形式         → 环境变量名补全
//   • ~ 展开           → 用 HOME 目录替换 ~，保留原始 ~ 在输出中
//   • 目录列表按需拉取并缓存，同一目录只请求一次服务器
// ─────────────────────────────────────────────────────────────────────────────
class TabCompleter {
  final WebshellService service;

  final Map<String, List<({String name, bool isDir})>> _cache = {};
  List<String> _envVars = [];
  String _homeDir = '';

  // 常见命令名白名单（仅用于行首 Tab；无法枚举远程 PATH 下全部可执行文件）
  static const List<String> _builtins = [
    'alias',
    'apt',
    'awk',
    'base64',
    'basename',
    'bash',
    'cat',
    'cd',
    'chmod',
    'chown',
    'chroot',
    'clear',
    'cp',
    'crontab',
    'curl',
    'cut',
    'date',
    'dd',
    'df',
    'diff',
    'dirname',
    'du',
    'echo',
    'env',
    'exit',
    'export',
    'find',
    'grep',
    'gunzip',
    'gzip',
    'head',
    'hostname',
    'id',
    'ifconfig',
    'ip',
    'kill',
    'killall',
    'less',
    'ln',
    'ls',
    'lsof',
    'mkdir',
    'md5sum',
    'more',
    'mount',
    'mv',
    'nano',
    'netstat',
    'nohup',
    'nslookup',
    'passwd',
    'perl',
    'php',
    'ping',
    'printenv',
    'ps',
    'python',
    'python3',
    'pwd',
    'rm',
    'rmdir',
    'rsync',
    'scp',
    'sed',
    'sha1sum',
    'sha256sum',
    'sh',
    'sleep',
    'sort',
    'ssh',
    'stat',
    'strings',
    'su',
    'sudo',
    'tail',
    'tar',
    'tee',
    'touch',
    'tr',
    'uname',
    'uniq',
    'unset',
    'unzip',
    'uptime',
    'useradd',
    'vi',
    'vim',
    'wc',
    'wget',
    'which',
    'whoami',
    'xargs',
    'zip',
    'zsh',
  ];

  // 当前补全循环状态
  List<String> _matches = [];
  int _matchIdx = 0;
  String _inputPrefix = ''; // token 前的文本（含末尾空格）
  String _tokenPrefix = ''; // token 中最后 / 前的路径（原样保留输出）
  bool _active = false;
  // true = 当前显示的是 LCP，下次 Tab 才开始循环第一个候选
  bool _atLcp = false;

  TabCompleter(this.service);

  bool get isActive => _active;

  void reset() {
    _matches = [];
    _matchIdx = 0;
    _inputPrefix = '';
    _tokenPrefix = '';
    _active = false;
    _atLcp = false;
  }

  Future<void> warmDir(String dir) async {
    if (_cache.containsKey(dir)) return;
    try {
      _cache[dir] = await service.listNamesForCompletion(dir);
    } catch (_) {}
  }

  /// 使指定目录的缓存失效，写入新文件后调用以便 Tab 补全能识别新文件
  void invalidateDir(String dir) {
    _cache.remove(dir);
  }

  Future<void> fetchEnvVars() async {
    try {
      _envVars = await service.listEnvVarNames();
    } catch (_) {}
  }

  Future<void> fetchHomeDir() async {
    try {
      _homeDir = await service.getHomeDir();
    } catch (_) {}
  }

  // ~ 展开（仅用于服务器查询，输出保留原始 ~）
  String _expandHome(String path) {
    if (_homeDir.isEmpty) return path;
    if (path == '~') return _homeDir;
    if (path.startsWith('~/')) return '$_homeDir${path.substring(1)}';
    return path;
  }

  // 将 rawDir（token 中 / 前的部分）解析为绝对路径，用于 warmDir
  String _resolveDir(String raw, String cwd) {
    final exp = _expandHome(raw);
    if (exp.startsWith('/')) return exp;
    if (exp == '.') return cwd;
    if (exp == '..') {
      final i = cwd.lastIndexOf('/');
      return i > 0 ? cwd.substring(0, i) : '/';
    }
    return '$cwd/$exp';
  }

  // 最长公共前缀
  static String _lcp(List<String> strs) {
    if (strs.isEmpty) return '';
    if (strs.length == 1) return strs[0];
    String prefix = strs[0];
    for (int i = 1; i < strs.length; i++) {
      final s = strs[i];
      int j = 0;
      while (j < prefix.length && j < s.length && prefix[j] == s[j]) {
        j++;
      }
      prefix = prefix.substring(0, j);
      if (prefix.isEmpty) break;
    }
    return prefix;
  }

  // 目录追加 /，文件追加空格（让光标停在参数分隔位置）
  String _fmt(({String name, bool isDir}) e) =>
      e.isDir ? '${e.name}/' : '${e.name} ';

  /// 按 Tab 键时调用，返回新的完整输入字符串；无候选时返回 null
  Future<String?> onTab(String input, String cwd) async {
    // ── 已在补全循环中 ────────────────────────────────────────────────────────
    if (_active && _matches.isNotEmpty) {
      final sp = input.lastIndexOf(' ');
      final tok = sp >= 0 ? input.substring(sp + 1) : input;

      if (tok.endsWith('/')) {
        // 当前 token 是目录 → 进入该目录做新一轮补全
        reset();
        // fall through
      } else if (_atLcp) {
        // 刚刚显示了 LCP，现在开始循环第一个候选
        _atLcp = false;
        _matchIdx = 0;
        return _build();
      } else {
        // 普通循环：移动到下一个候选
        _matchIdx = (_matchIdx + 1) % _matches.length;
        return _build();
      }
    }

    // ── 初始化新一轮补全 ──────────────────────────────────────────────────────
    reset();

    final sp = input.lastIndexOf(' ');
    _inputPrefix = sp >= 0 ? input.substring(0, sp + 1) : '';
    final token = sp >= 0 ? input.substring(sp + 1) : input;

    // 是否在命令位置（输入中无非空白前缀）
    final isCmd = _inputPrefix.trim().isEmpty;

    // ── 空 token：命令位置列出命令+文件，参数位置列出当前目录 ──────────────
    if (token.isEmpty) {
      final all = <String>[];
      if (isCmd) all.addAll(_builtins.map((c) => '$c '));
      await warmDir(cwd);
      all.addAll((_cache[cwd] ?? []).map(_fmt));
      _tokenPrefix = '';
      _matches = all;
      return _startCycle(0);
    }

    // ── 环境变量 $VAR ─────────────────────────────────────────────────────────
    if (token.startsWith(r'$')) {
      final prefix = token.substring(1);
      _matches = _envVars
          .where((v) => v.toLowerCase().startsWith(prefix.toLowerCase()))
          .map((v) => '\$$v ')
          .toList();
      _tokenPrefix = '';
      return _startCycle(token.length);
    }

    // ── 命令补全（命令位置 + token 不含路径特征）────────────────────────────
    final isPathLike =
        token.contains('/') || token.startsWith('~') || token.startsWith('.');
    if (isCmd && !isPathLike) {
      final cmdM = _builtins
          .where((c) => c.startsWith(token))
          .map((c) => '$c ')
          .toList();
      await warmDir(cwd);
      final fileM = (_cache[cwd] ?? [])
          .where((e) => e.name.toLowerCase().startsWith(token.toLowerCase()))
          .map(_fmt)
          .toList();
      // 合并去重（按名称，命令优先）
      final seen = <String>{};
      _matches = [
        for (final m in [...cmdM, ...fileM])
          if (seen.add(
            m.endsWith('/') ? m.substring(0, m.length - 1) : m.trim(),
          ))
            m,
      ];
      _tokenPrefix = '';
      return _startCycle(token.length);
    }

    // ── 路径补全 ──────────────────────────────────────────────────────────────
    final slashIdx = token.lastIndexOf('/');
    String lookupDir;
    String filePrefix;

    if (slashIdx < 0) {
      // 无斜杠：在 cwd 中查找（含 ~ 单独作为 token 的情况）
      lookupDir = token == '~' ? _expandHome('~') : cwd;
      _tokenPrefix = '';
      filePrefix = token == '~' ? '' : token;
    } else if (slashIdx == 0) {
      // 绝对路径，仅有根斜杠：/foo
      lookupDir = '/';
      _tokenPrefix = '/';
      filePrefix = token.substring(1);
    } else {
      final rawDir = token.substring(0, slashIdx);
      _tokenPrefix = '$rawDir/';
      filePrefix = token.substring(slashIdx + 1);
      lookupDir = _resolveDir(rawDir, cwd);
    }

    await warmDir(lookupDir);
    final entries = _cache[lookupDir] ?? [];
    _matches = entries
        .where((e) => e.name.toLowerCase().startsWith(filePrefix.toLowerCase()))
        .map(_fmt)
        .toList();
    return _startCycle(filePrefix.length);
  }

  /// 根据候选列表决定本次返回值：
  ///   唯一候选 → 直接填入
  ///   多个候选 → 若 LCP 比当前前缀更长则填 LCP，否则直接循环第一个
  String? _startCycle(int currentPrefixLen) {
    if (_matches.isEmpty) return null;
    _active = true;

    if (_matches.length == 1) {
      _atLcp = false;
      _matchIdx = 0;
      return _build();
    }

    // 计算所有候选的最长公共前缀
    final lcp = _lcp(_matches);
    final lcpCore = lcp.trimRight(); // 去掉尾部空格/斜杠后再比较长度

    if (lcpCore.length > currentPrefixLen) {
      // LCP 能进一步扩展用户的输入 → 先填 LCP，下次 Tab 再循环
      _atLcp = true;
      _matchIdx = 0;
      return '$_inputPrefix$_tokenPrefix$lcpCore';
    }

    // LCP == 当前前缀 → 直接开始循环
    _atLcp = false;
    _matchIdx = 0;
    return _build();
  }

  String _build() => '$_inputPrefix$_tokenPrefix${_matches[_matchIdx]}';
}

class EntryBlock extends StatelessWidget {
  final TerminalEntry entry;

  const EntryBlock({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 命令行
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${entry.dir}\$ ',
                style: AppTextStyles.terminal(
                  size: 13,
                  color: AppColors.primary,
                ),
              ),
              Expanded(
                child: SelectableText(
                  entry.command,
                  style: AppTextStyles.terminal(
                    size: 13,
                    color: AppColors.cyan,
                  ),
                ),
              ),
              Text(
                '${entry.timestamp.hour.toString().padLeft(2, '0')}'
                ':${entry.timestamp.minute.toString().padLeft(2, '0')}'
                ':${entry.timestamp.second.toString().padLeft(2, '0')}',
                style: AppTextStyles.caption(
                  size: 10,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          // 输出
          if (entry.output != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: SelectableText(
                entry.output!,
                style: const TextStyle(
                  color: Color(0xFFB8C0CC),
                  fontFamily: 'Monaco',
                  fontFamilyFallback: ['Courier New', 'Courier', 'monospace'],
                  fontSize: 12,
                  height: 1.6,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: Color(0xFF1C2128)),
        ],
      ),
    );
  }
}
