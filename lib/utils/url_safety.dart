/// URL 脱敏工具：日志与剪贴板都不应该带出凭据。
library;

/// 去掉 URL 中的 userinfo（`user:pass@`），其余部分保持不变。
///
/// 用于"复制链接"等需要保留原始路径/参数、但不该带凭据的场景。
String stripUrlCredentials(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.userInfo.isEmpty) return url;
  return parsed.replace(userInfo: '').toString();
}

/// 日志用的收敛形式：只保留 scheme/host/port/path，丢弃 userinfo、query 与 fragment。
///
/// query 里经常出现 token / session / 命令回显，不应进日志。
String redactUrlForLog(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.host.isEmpty) return '(invalid url)';
  final port = parsed.hasPort ? ':${parsed.port}' : '';
  return '${parsed.scheme}://${parsed.host}$port${parsed.path}';
}
