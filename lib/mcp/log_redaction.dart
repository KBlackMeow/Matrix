/// MCP 工具调用日志的脱敏规则。
///
/// 只做"能否出现在日志里"的判断，不改变实际调用参数。
library;

/// 参数名（小写）命中即整体遮蔽。
///
/// 说明：`password` 是连接参数名，`secret_key` 是 Godzilla 密钥，
/// `token` 覆盖 FRP 等隧道口令，`cookie`/`authorization` 兜底。
const Set<String> sensitiveArgumentKeys = <String>{
  'password',
  'secret_key',
  'secretkey',
  'token',
  'cookie',
  'authorization',
  'authorization_token',
};

/// 内容型参数只记录长度，避免把文件正文/大段 payload 灌进日志。
const Set<String> lengthOnlyArgumentKeys = <String>{'content'};

bool isSensitiveArgument(String key) =>
    sensitiveArgumentKeys.contains(key.toLowerCase());

/// 把工具参数渲染成一行日志文本（已脱敏）。
///
/// 输出示例：`name=web1, url=https://t/x.php, password=***, content=<1024 chars>`
String describeToolArguments(
  Map<String, dynamic> args, {
  int maxValueLength = 200,
}) {
  final parts = <String>[];
  args.forEach((key, value) {
    if (isSensitiveArgument(key)) {
      parts.add('$key=***');
      return;
    }
    if (lengthOnlyArgumentKeys.contains(key)) {
      parts.add('$key=<${'$value'.length} chars>');
      return;
    }
    final text = '$value';
    parts.add(
      '$key=${text.length > maxValueLength ? '${text.substring(0, maxValueLength)}…' : text}',
    );
  });
  return parts.join(', ');
}
