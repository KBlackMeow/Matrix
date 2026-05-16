import 'dart:math' as math;

import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:highlight/highlight.dart' show Mode, Node, Result, highlight;
import 'package:highlight/languages/all.dart';

import '../theme/app_theme.dart';

/// 与 Matrix 深色界面一致的 highlight.js 主题（基于 atom-one-dark）。
final Map<String, TextStyle> matrixCodeHighlightTheme = () {
  final m = Map<String, TextStyle>.from(atomOneDarkTheme);
  const bg = Color(0xFF0D1117);
  const fg = Color(0xFFB8C0CC);
  m['root'] = (m['root'] ?? const TextStyle()).copyWith(
    color: fg,
    backgroundColor: bg,
  );
  return m;
}();

TextStyle matrixCodeTextStyle({double fontSize = 12, double height = 1.65}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      height: height,
      letterSpacing: 0.2,
      color: const Color(0xFFB8C0CC),
    );

/// 与 `flutter_highlight` 的 HighlightView 相同：空格展开 tab。
String _matrixHlExpandTabs(String input, {int tabSize = 8}) =>
    input.replaceAll('\t', ' ' * tabSize);

/// highlight.js 结点树 → [TextSpan]（结构与 HighlightView._convert 一致）。
List<TextSpan> _matrixHlConvertedSpans(List<Node> nodes, Map<String, TextStyle> theme) {
  final spans = <TextSpan>[];
  List<TextSpan> currentSpans = spans;
  final stack = <List<TextSpan>>[];

  TextStyle? styleFor(Node node) {
    final c = node.className;
    if (c == null) return null;
    final s = theme[c];
    if (s != null) return s;
    // 未知 token 不占位样式，与普通文本同色
    return null;
  }

  void traverse(Node node) {
    if (node.value != null) {
      final leafStyle = styleFor(node);
      currentSpans.add(
        leafStyle != null ? TextSpan(text: node.value, style: leafStyle) : TextSpan(text: node.value),
      );
    } else if (node.children != null) {
      final tmp = <TextSpan>[];
      final groupStyle = styleFor(node);
      currentSpans.add(
        TextSpan(children: tmp, style: groupStyle),
      );
      stack.add(currentSpans);
      currentSpans = tmp;

      for (final child in node.children!) {
        traverse(child);
        if (child == node.children!.last) {
          currentSpans = stack.isEmpty ? spans : stack.removeLast();
        }
      }
    }
  }

  for (final node in nodes) {
    traverse(node);
  }
  return spans;
}

TextStyle _matrixHlSelectableRootStyle(
  Map<String, TextStyle> theme, {
  required TextStyle textStyle,
}) {
  const rootKey = 'root';
  const defaultFontColor = Color(0xff000000);
  var merged = TextStyle(
    fontFamily: 'monospace',
    color: theme[rootKey]?.color ?? defaultFontColor,
  );
  return merged.merge(textStyle);
}

/// 可选用 [SelectableText]/[SelectableText.rich]，避免外层横向 [SingleChildScrollView] 抢走拖选手势。
Widget _matrixHighlightSelectableFormatted(
  String source, {
  required String langId,
  required TextStyle textStyle,
}) {
  final expanded = _matrixHlExpandTabs(source);
  final merged = _matrixHlSelectableRootStyle(matrixCodeHighlightTheme, textStyle: textStyle);

  final Result parsed;
  try {
    parsed = highlight.parse(expanded, language: langId);
  } catch (_) {
    return SelectableText(expanded, style: textStyle);
  }

  final nodes = parsed.nodes;
  if (nodes == null) {
    return SelectableText(expanded, style: merged);
  }

  return SelectableText.rich(
    TextSpan(
      style: merged,
      children: _matrixHlConvertedSpans(nodes, matrixCodeHighlightTheme),
    ),
  );
}

/// 根据路径 / 文件名解析 highlight 语言 id（用于 [allLanguages]）。
String? highlightLanguageIdForPath(String path) {
  final name = path.replaceAll('\\', '/').split('/').last.trim();
  if (name.isEmpty) return null;
  final lower = name.toLowerCase();

  if (lower == 'dockerfile') return 'dockerfile';
  if (lower.startsWith('makefile')) return 'makefile';
  if (lower == '.htaccess') return 'apache';
  if (lower.contains('nginx') && lower.endsWith('.conf')) return 'nginx';
  if ((lower.contains('httpd') || lower.contains('apache')) &&
      lower.endsWith('.conf')) {
    return 'apache';
  }

  final dot = lower.lastIndexOf('.');
  if (dot <= 0 || dot == lower.length - 1) {
    if (lower.startsWith('.bash') || lower.endsWith('bashrc')) return 'bash';
    if (lower.startsWith('.zsh')) return 'bash';
    return null;
  }

  final ext = lower.substring(dot + 1);
  switch (ext) {
    case 'php':
    case 'phtml':
    case 'phps':
      return 'php';
    case 'jsp':
    case 'jspf':
    case 'jspx':
    case 'tag':
      return 'java';
    case 'asp':
      return 'vbscript';
    case 'aspx':
    case 'ascx':
    case 'asmx':
      return 'xml';
    case 'cs':
      return 'cs';
    case 'ini':
    case 'cfg':
    case 'cnf':
      return 'ini';
    case 'conf':
    case 'config':
      return 'ini';
    case 'properties':
    case 'props':
      return 'properties';
    case 'env':
      return 'properties';
    case 'sh':
    case 'bash':
    case 'zsh':
      return 'bash';
    case 'ps1':
    case 'psm1':
      return 'powershell';
    case 'bat':
    case 'cmd':
      return 'dos';
    case 'py':
    case 'pyw':
      return 'python';
    case 'pl':
    case 'pm':
      return 'perl';
    case 'rb':
      return 'ruby';
    case 'js':
    case 'mjs':
    case 'cjs':
      return 'javascript';
    case 'ts':
    case 'tsx':
      return 'typescript';
    case 'json':
      return 'json';
    case 'yml':
    case 'yaml':
      return 'yaml';
    case 'sql':
      return 'sql';
    case 'xml':
    case 'xsd':
    case 'xsl':
    case 'xslt':
      return 'xml';
    case 'html':
    case 'htm':
    case 'xhtml':
      return 'xml';
    case 'css':
      return 'css';
    case 'scss':
    case 'sass':
      return 'scss';
    case 'md':
    case 'markdown':
      return 'markdown';
    case 'java':
      return 'java';
    case 'go':
      return 'go';
    case 'rs':
      return 'rust';
    case 'c':
    case 'h':
      return 'cpp';
    case 'cpp':
    case 'cc':
    case 'cxx':
    case 'hpp':
      return 'cpp';
    case 'dart':
      return 'dart';
    case 'toml':
      return 'ini';
    case 'gradle':
      return 'gradle';
    case 'kt':
    case 'kts':
      return 'kotlin';
    case 'swift':
      return 'swift';
    case 'vim':
      return 'vim';
    case 'dockerfile':
      return 'dockerfile';
    default:
      return null;
  }
}

/// 从 `cat a b c.php` / `head -n 20 x.jsp` 等参数段中取最可能的文件路径。
String? _pickPathFromArgs(String rest) {
  final parts = rest
      .split(RegExp(r'\s+'))
      .map((e) => e.replaceAll('"', '').replaceAll("'", ''))
      .where((e) => e.isNotEmpty)
      .toList();
  for (var i = parts.length - 1; i >= 0; i--) {
    final tok = parts[i];
    if (tok.startsWith('-')) continue;
    if (highlightLanguageIdForPath(tok) != null) return tok;
  }
  for (var i = parts.length - 1; i >= 0; i--) {
    final tok = parts[i];
    if (tok.startsWith('-')) continue;
    if (tok.contains('/') || tok.contains(r'\')) return tok;
  }
  return parts.isNotEmpty ? parts.last : null;
}

/// 从 shell 命令中猜测被查看的源文件路径（用于终端输出高亮）。
String? _pathGuessFromShellCommand(String cmd, {required bool isWindowsShell}) {
  final t = cmd.trim();
  if (t.isEmpty) return null;

  if (isWindowsShell) {
    final m = RegExp(
      r'^(?:type|more)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      return _pickPathFromArgs(m.group(1)!) ??
          m.group(1)!.replaceAll('"', '').trim();
    }
  } else {
    final m = RegExp(
      r'^(?:cat|head|tail|less|more)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      return _pickPathFromArgs(m.group(1)!) ??
          m.group(1)!.split(RegExp(r'\s+')).last.replaceAll('"', '').trim();
    }
  }

  final re = RegExp(
    r'''[\w.\-\/\\]+\.(php|phtml|jsp|jspf|jspx|asp|aspx|ascx|ini|conf|config|cnf|sh|bash|zsh|py|pl|rb|js|ts|tsx|json|yml|yaml|sql|xml|html|htm|css|scss|md|java|go|rs|c|h|cpp|hpp|cs|ps1|gradle|kts|kt|properties|env)\b''',
    caseSensitive: false,
  );
  Match? last;
  for (final m in re.allMatches(t)) {
    last = m;
  }
  return last?.group(0);
}

Mode highlightModeForPath(String path) {
  final id = highlightLanguageIdForPath(path) ?? 'plaintext';
  return allLanguages[id] ?? allLanguages['plaintext']!;
}

/// 只读展示：带选区与主题字体；解析失败时退回纯文本。
Widget matrixSyntaxHighlightReadOnly(
  String code, {
  required String pathOrName,
  EdgeInsets padding = const EdgeInsets.all(16),
}) {
  final langId = highlightLanguageIdForPath(pathOrName) ?? 'plaintext';
  final baseStyle = matrixCodeTextStyle();

  Widget child;
  try {
    child = _matrixHighlightSelectableFormatted(
      code,
      langId: langId,
      textStyle: baseStyle,
    );
  } catch (_) {
    child = SelectableText(_matrixHlExpandTabs(code), style: baseStyle);
  }

  const fill = Color(0xFF0D1117);

  return Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: fill,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minW = math.max(
            0.0,
            constraints.maxWidth - padding.horizontal,
          );
          final minH = math.max(
            0.0,
            constraints.maxHeight - padding.vertical,
          );
          return SingleChildScrollView(
            padding: padding,
            scrollDirection: Axis.vertical,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: minW,
                minHeight: minH,
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: child,
              ),
            ),
          );
        },
      ),
    ),
  );
}

// ─── ls -l 长列表行级着色（普通文件 / 目录 / 可执行 / SUID/SGID / rwxrwxrwx）────────

/// 是否为 `ls` 命令（用于输出着色；实际执行可能已由 [augmentLsToLongListingForShell] 补 `-l`）。
bool _isLsCommandForHighlight(String cmd) {
  return RegExp(r'^ls\b', caseSensitive: false).hasMatch(cmd.trim());
}

/// 匹配 `ls -l` 常见首列：类型 + 9 位权限 + 可选 @/+/.（macOS ACL/xattr）。
final _lsLongLineMode = RegExp(
  r'^\s*([\-bcdlps])([\-rwxsStT]{9})([@+.]?)(\s|$)',
);

({String type, String perm})? _parseLsLongLineMode(String line) {
  final m = _lsLongLineMode.firstMatch(line);
  if (m == null) return null;
  return (type: m.group(1)!, perm: m.group(2)!);
}

bool _looksLikeLsLongListing(String output) {
  var hits = 0;
  for (final raw in output.split(RegExp(r'\r?\n'))) {
    if (_parseLsLongLineMode(raw) != null) hits++;
    if (hits >= 2) return true;
  }
  return hits == 1;
}

bool _permHasExecForRegularFile(String perm) {
  bool u = perm[2] == 'x' || perm[2] == 's';
  bool g = perm[5] == 'x' || perm[5] == 's';
  bool o = perm[8] == 'x';
  return u || g || o;
}

bool _permHasSuidOrSgid(String perm) {
  return perm[2] == 'S' ||
      perm[2] == 's' ||
      perm[5] == 'S' ||
      perm[5] == 's';
}

TextStyle _lsLongListLineStyle(String line, TextStyle base) {
  final trimmedLeft = line.trimLeft();
  if (RegExp(r'^total\s+\d+', caseSensitive: false).hasMatch(trimmedLeft)) {
    return base.copyWith(
      color: AppColors.textMuted,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w400,
    );
  }

  final parsed = _parseLsLongLineMode(line);
  if (parsed == null) {
    return base.copyWith(color: AppColors.textSecondary);
  }

  final type = parsed.type;
  final perm = parsed.perm;

  // 符号链接：常为 lrwxrwxrwx，不按 777 告警色处理
  if (type == 'l') {
    return base.copyWith(
      color: const Color(0xFF6EC9FF),
      fontWeight: FontWeight.w400,
    );
  }

  // rwxrwxrwx：危险权限 — 整行浅红底；前景按目录 / 普通文件区分
  if (perm == 'rwxrwxrwx') {
    final bg = AppColors.red.withValues(alpha: 0.22);
    if (type == 'd') {
      return base.copyWith(
        color: AppColors.cyan,
        fontWeight: FontWeight.w600,
        backgroundColor: bg,
      );
    }
    if (type == '-') {
      return base.copyWith(
        color: AppColors.amber,
        fontWeight: FontWeight.w600,
        backgroundColor: bg,
      );
    }
    return base.copyWith(
      color: AppColors.primaryDim,
      fontWeight: FontWeight.w600,
      backgroundColor: bg,
    );
  }

  if (_permHasSuidOrSgid(perm)) {
    return base.copyWith(
      color: AppColors.amber,
      fontWeight: FontWeight.w600,
    );
  }

  if (type == 'd') {
    return base.copyWith(
      color: AppColors.cyan,
      fontWeight: FontWeight.w500,
    );
  }

  // 普通文件：其它类用户可写（如 666、662），非 777 全满
  if (type == '-' && perm.length >= 9 && perm[7] == 'w') {
    return base.copyWith(
      color: const Color(0xFFFFB74D),
      fontWeight: FontWeight.w500,
    );
  }

  if (type == '-' && _permHasExecForRegularFile(perm)) {
    return base.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w500,
    );
  }

  if (type == 'b' || type == 'c') {
    return base.copyWith(color: AppColors.textMuted);
  }
  if (type == 'p') {
    return base.copyWith(color: const Color(0xFFD670D6));
  }

  return base.copyWith(color: AppColors.textPrimary);
}

/// `ls -l` 风格输出：按行着色（可选中复制）。
Widget matrixLsLongListingOutput(String output) {
  final base = matrixCodeTextStyle(height: 1.6);
  final lines = output.split(RegExp(r'\r?\n'));
  final children = <InlineSpan>[];
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) {
      children.add(TextSpan(text: '\n', style: base));
    }
    final line = lines[i];
    children.add(
      TextSpan(text: line, style: _lsLongListLineStyle(line, base)),
    );
  }

  return SelectableText.rich(TextSpan(children: children));
}

/// Webshell 终端块中的命令输出：在可识别为「查看源码文件」时做语法高亮。
Widget matrixTerminalOutputBlock(
  String command,
  String output, {
  required bool isWindowsShell,
}) {
  const maxBytes = 192 * 1024;
  if (output.length > maxBytes) {
    return SelectableText(
      output,
      style: matrixCodeTextStyle(height: 1.6),
    );
  }

  if (!isWindowsShell &&
      _isLsCommandForHighlight(command) &&
      _looksLikeLsLongListing(output)) {
    return matrixLsLongListingOutput(output);
  }

  final pathGuess = _pathGuessFromShellCommand(command, isWindowsShell: isWindowsShell);
  final langId =
      pathGuess != null ? highlightLanguageIdForPath(pathGuess) : null;

  if (langId == null || langId == 'plaintext') {
    return SelectableText(
      output,
      style: matrixCodeTextStyle(height: 1.6),
    );
  }

  try {
    return _matrixHighlightSelectableFormatted(
      output,
      langId: langId,
      textStyle: matrixCodeTextStyle(height: 1.6),
    );
  } catch (_) {
    return SelectableText(
      output,
      style: matrixCodeTextStyle(height: 1.6),
    );
  }
}

/// 可编辑代码区：行号 + highlight.js 着色（依赖外层 [CodeTheme]）。
Widget matrixCodeEditorField({
  required CodeController controller,
  required FocusNode? focusNode,
  void Function(String)? onChanged,
}) {
  return CodeTheme(
    data: CodeThemeData(styles: matrixCodeHighlightTheme),
    child: CodeField(
      controller: controller,
      focusNode: focusNode,
      expands: true,
      wrap: true,
      horizontalScroll: false,
      lineNumbers: true,
      textStyle: matrixCodeTextStyle(),
      cursorColor: AppColors.primary,
      background: const Color(0xFF0D1117),
      padding: const EdgeInsets.all(12),
      lineNumberStyle: LineNumberStyle(
        width: 42,
        textAlign: TextAlign.right,
        textStyle: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          color: AppColors.textMuted,
          height: 1.65,
        ),
      ),
      onChanged: onChanged,
    ),
  );
}
