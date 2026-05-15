import 'package:flutter/material.dart';

import '../app/localization.dart';
import '../services/webshell_service.dart';
import '../theme/app_theme.dart';
import '../widgets/matrix_syntax_highlight.dart';

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

  const ModeToggle({
    super.key,
    required this.integrated,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: integrated
          ? S.tooltipSwitchToSeparate
          : S.tooltipSwitchToIntegrated,
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
                integrated ? S.modeIntegrated : S.modeSeparate,
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
//   • 命令与目录候选均实时查询目标，不依赖本地硬编码或目录缓存
//   • 发往冰蝎等「脚本在 HTTP 头 X-V」的通道时，脚本中避免 printf 的 %s：
//     部分 Servlet 容器会按百分号解码头值，%s 会被破坏；目录枚举回退改用 echo。
// ─────────────────────────────────────────────────────────────────────────────
class TabCompleter {
  final WebshellService service;

  List<String> _envVars = [];
  String _homeDir = '';

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
  int get matchCount => _matches.length;
  List<String> get previewMatches => _matches.take(8).toList(growable: false);
  List<String> get allMatches => List.unmodifiable(_matches);

  void reset() {
    _matches = [];
    _matchIdx = 0;
    _inputPrefix = '';
    _tokenPrefix = '';
    _active = false;
    _atLcp = false;
  }

  Future<void> warmDir(String dir, {bool force = false}) async {}

  /// 使指定目录的缓存失效，写入新文件后调用以便 Tab 补全能识别新文件
  void invalidateDir(String dir) {}

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

  /// 仅基于目标 PATH 扫描可执行文件，构建命令补全列表（无硬编码兜底）
  Future<List<String>> fetchAvailableCommands(String workingDir) async {
    try {
      final result = await service
          .executeCommand(
            'IFS=:; for d in \$PATH; do '
            '[ -d "\$d" ] || continue; '
            'for f in "\$d"/*; do '
            '[ -f "\$f" ] && [ -x "\$f" ] && echo "\${f##*/}"; '
            'done; '
            'done',
            workingDir: workingDir,
          )
          .timeout(const Duration(seconds: 2));
      final found =
          result
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      return found;
    } catch (_) {
      // 扫描失败时不使用任何本地硬编码命令兜底。
      return [];
    }
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

  static String _sq(String s) => "'${s.replaceAll("'", "'\\''")}'";

  Future<List<({String name, bool isDir})>> _listByPrefix(
    String dir,
    String prefix,
  ) async {
    try {
      final result = await service.executeCommand(
        'd=${_sq(dir)}; p=${_sq(prefix)}; '
        'for f in "\$d"/"\$p"*; do '
        '[ -e "\$f" ] || continue; '
        'n="\${f##*/}"; '
        'if [ -d "\$f" ]; then echo "\$n|d"; '
        'else echo "\$n|f"; fi; '
        'done',
        workingDir: dir,
      );
      if (result.isEmpty) return [];
      final out = <({String name, bool isDir})>[];
      for (final line in result.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        final sep = t.lastIndexOf('|');
        if (sep <= 0 || sep >= t.length - 1) continue;
        final name = t.substring(0, sep);
        final flag = t.substring(sep + 1);
        if (name.isEmpty || name == '.') continue;
        out.add((name: name, isDir: flag == 'd'));
      }
      out.sort((a, b) => a.name.compareTo(b.name));
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<({String name, bool isDir})>> _listDirLive(String dir) async {
    try {
      final out = await service.listNamesForCompletion(dir);
      out.sort((a, b) => a.name.compareTo(b.name));
      return out;
    } catch (_) {
      return [];
    }
  }

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
      if (isCmd) {
        final liveCmds = await fetchAvailableCommands(cwd);
        all.addAll(liveCmds.map((c) => '$c '));
      }
      final cwdEntries = await _listDirLive(cwd);
      all.addAll(cwdEntries.map(_fmt));
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
      final cmdM = (await fetchAvailableCommands(
        cwd,
      )).where((c) => c.startsWith(token)).map((c) => '$c ').toList();
      final fileM = (await _listDirLive(cwd))
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

    final entries = await _listDirLive(lookupDir);
    _matches = entries
        .where((e) => e.name.toLowerCase().startsWith(filePrefix.toLowerCase()))
        .map(_fmt)
        .toList();
    if (_matches.isEmpty) {
      // 目录列表为空或缓存与目标瞬时不一致时，按前缀直接向目标查询一次。
      final direct = await _listByPrefix(lookupDir, filePrefix);
      _matches = direct.map(_fmt).toList();
    }
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

  String? applyMatchAt(int index) {
    if (index < 0 || index >= _matches.length) return null;
    _active = true;
    _atLcp = false;
    _matchIdx = index;
    return _build();
  }
}

/// Windows cmd 风格用 `>`，类 Unix 用 `$`（提示符单独配色，便于与路径、命令区分）。
String shellPromptGlyph(bool isWindowsShell) => isWindowsShell ? '>' : r'$';

/// 将一行 shell 输入拆成「命令名」与「参数」（保留命令后的原始空格）。
(String command, String arguments) splitShellCommandLine(String raw) {
  final lead = raw.length - raw.trimLeft().length;
  final from = raw.substring(lead);
  if (from.isEmpty) return ('', '');
  final m = RegExp(r'^(\S+)').firstMatch(from);
  if (m == null) return (from, '');
  final cmd = m.group(1)!;
  final restStart = lead + m.end;
  final args = restStart < raw.length ? raw.substring(restStart) : '';
  return (cmd, args);
}

// ─── ls：默认补全为长列表（-l），便于按权限着色 ─────────────────────────────

bool _lsAugmentSafeShell(String cmd) {
  final t = cmd.trim();
  if (t.contains('|') || t.contains(';')) return false;
  if (t.contains('&&') || t.contains('||')) return false;
  if (t.contains('`')) return false;
  if (t.contains(r'$(')) return false;
  return true;
}

/// 已为 `ls -l` / `--format=long` 等长列表形式。
bool lsCommandAlreadyLongListing(String cmd) {
  final t = cmd.trim().toLowerCase();
  if (!RegExp(r'^ls\b').hasMatch(t)) return false;
  if (t.contains('--format=long') || t.contains('--format=verbose')) {
    return true;
  }
  for (final m in RegExp(r'\s+-([a-z0-9]+)(?=\s|$)').allMatches(t)) {
    if (m.group(1)!.contains('l')) return true;
  }
  return false;
}

/// 非 Windows、纯 `ls` 且未带长列表选项时，在发往远端前补上 `-l`（或与短选项合并为 `-al` 等）。
///
/// 不改变 [TerminalEntry.command] 展示；仅影响实际执行字符串。显式 `ls -1` 不改写。
String augmentLsToLongListingForShell(String cmd, {required bool isWindowsShell}) {
  if (isWindowsShell) return cmd;
  final trimmed = cmd.trim();
  if (trimmed.isEmpty) return cmd;
  if (!RegExp(r'^ls\b', caseSensitive: false).hasMatch(trimmed)) return cmd;
  if (!_lsAugmentSafeShell(cmd)) return cmd;
  if (lsCommandAlreadyLongListing(cmd)) return cmd;
  if (RegExp(r'(^|\s)-1(\s|$)').hasMatch(trimmed.toLowerCase())) return cmd;

  final wm = RegExp(r'^ls\b', caseSensitive: false).firstMatch(trimmed);
  if (wm == null) return cmd;
  final afterLs = trimmed.substring(wm.end);
  final rest = afterLs.trimLeft();
  final head = trimmed.substring(0, wm.end);
  if (rest.isEmpty) {
    return '$head -l';
  }
  final firstTok = rest.split(RegExp(r'\s+')).first;
  if (firstTok.startsWith('-') && !firstTok.startsWith('--')) {
    final om = RegExp(r'^-([a-zA-Z0-9]+)$').firstMatch(firstTok);
    if (om != null) {
      final f = om.group(1)!;
      if (!f.contains('l')) {
        final afterFirst = rest.substring(firstTok.length).trimLeft();
        final merged = '-${f}l';
        if (afterFirst.isEmpty) return '$head $merged';
        return '$head $merged $afterFirst';
      }
    }
    return '$head -l $rest';
  }
  return '$head -l $rest';
}

class EntryBlock extends StatelessWidget {
  final TerminalEntry entry;
  final bool isWindowsShell;

  const EntryBlock({
    super.key,
    required this.entry,
    this.isWindowsShell = false,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = shellPromptGlyph(isWindowsShell);
    final (cmd, args) = splitShellCommandLine(entry.command);
    final baseTerm = AppTextStyles.terminal(size: 13);
    final pathStyle = baseTerm.copyWith(color: AppColors.cyan);
    final promptStyle = baseTerm.copyWith(color: AppColors.amber);
    final commandStyle = baseTerm.copyWith(color: AppColors.primary);
    final argsStyle = baseTerm.copyWith(color: AppColors.textSecondary);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 命令行：路径 / 提示符 / 命令 / 参数 分色
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText.rich(
                  TextSpan(
                    style: baseTerm,
                    children: [
                      TextSpan(text: entry.dir, style: pathStyle),
                      TextSpan(text: ' $glyph ', style: promptStyle),
                      if (cmd.isNotEmpty)
                        TextSpan(text: cmd, style: commandStyle),
                      if (args.isNotEmpty)
                        TextSpan(text: args, style: argsStyle),
                    ],
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
              child: entry.output == S.noOutput
                  ? SelectableText(
                      entry.output!,
                      style: matrixCodeTextStyle(height: 1.6),
                    )
                  : matrixTerminalOutputBlock(
                      entry.command,
                      entry.output!,
                      isWindowsShell: isWindowsShell,
                    ),
            ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: Color(0xFF1C2128)),
        ],
      ),
    );
  }
}
