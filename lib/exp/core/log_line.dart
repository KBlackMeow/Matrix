/// 日志的唯一真相模型（不依赖 Flutter，供 core 与 ui 共用）。
///
/// 旧代码里有 4 份互不相同的实现，各自用正则解析 `[+] [!] [-] [*] [i]` 前缀，
/// 并且同一符号的配色不一致（`[!]` 在 vulhub 是红、在 universal 是琥珀）。
/// 这里把"语义"与"字符串"分开：**颜色由 level 决定，不由文本前缀决定**，
/// 前缀只是 level 的一种序列化形式，用于跨模块/跨进程边界。
library;

/// 一条日志的语义级别。
enum LogLevel {
  /// 命中 / 成功。
  ok('[+]'),

  /// 失败 / 异常。
  error('[!]'),

  /// 探测完成且未命中（不是错误）。
  miss('[-]'),

  /// 正在执行的动作。
  action('[*]'),

  /// 中性提示。
  note('[i]'),

  /// 无前缀的原始输出（命令回显等）。
  plain('');

  const LogLevel(this.prefix);

  final String prefix;
}

/// 一条结构化日志。
class LogLine {
  const LogLine(this.level, this.text, {this.at});

  final LogLevel level;
  final String text;
  final DateTime? at;

  /// 把旧格式（带前缀的字符串）解析成结构化日志。
  ///
  /// 这是**唯一**的解析点：服务层继续返回字符串，也只在这里被解释一次。
  factory LogLine.parse(String raw, {DateTime? at}) {
    for (final level in LogLevel.values) {
      if (level == LogLevel.plain) continue;
      if (raw.startsWith(level.prefix)) {
        final body = raw.substring(level.prefix.length).trimLeft();
        return LogLine(level, body, at: at);
      }
    }
    return LogLine(LogLevel.plain, raw, at: at);
  }

  static List<LogLine> parseAll(Iterable<String> raws) =>
      raws.map(LogLine.parse).toList(growable: false);

  bool get isEmpty => text.trim().isEmpty;

  /// 序列化回单行文本（复制到剪贴板 / 写文件时使用）。
  String get formatted =>
      level == LogLevel.plain ? text : '${level.prefix} $text';

  @override
  String toString() => formatted;

  @override
  bool operator ==(Object other) =>
      other is LogLine &&
      other.level == level &&
      other.text == text &&
      other.at == at;

  @override
  int get hashCode => Object.hash(level, text, at);
}

/// 日志行在 UI 中的呈现片段（前缀 + 正文）。
///
/// 放在 core 之外由 UI 层决定颜色；这里只负责语义。
extension LogLineText on LogLine {
  /// 无样式的一行文本，用于导出或断言。
  String get plainText => level == LogLevel.plain
      ? text
      : '${level.prefix} $text';
}
