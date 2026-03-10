import '../models/webshell.dart';
import 'shell_connector.dart';
import 'php_eval_connector.dart';
import 'php_b64rot13_connector.dart';
import 'php_passthru_connector.dart';
import 'php_probe_connector.dart';
import 'jsp_classloader_connector.dart';
import 'jsp_runtime_connector.dart';
import 'asp_wscript_connector.dart';

/// 根据 [Webshell.connectorType] 创建对应的连接器实例
class ConnectorFactory {
  ConnectorFactory._();

  static ShellConnector create(Webshell webshell) {
    return switch (webshell.connectorType) {
      'php_eval'        => PhpEvalConnector(webshell),
      'php_b64rot13'    => PhpB64Rot13Connector(webshell),
      'php_passthru'    => PhpPassthruConnector(webshell),
      'php_probe'       => PhpProbeConnector(webshell),
      'jsp_classloader' => JspClassloaderConnector(webshell),
      'jsp_runtime'     => JspRuntimeConnector(webshell),
      'asp_wscript'     => AspWscriptConnector(webshell),
      _                 => PhpEvalConnector(webshell), // fallback
    };
  }

  /// 从 connectorType 推导显示用的 type 标签（php / jsp / asp）
  static String typeLabel(String connectorType) {
    if (connectorType.startsWith('jsp')) return 'jsp';
    if (connectorType.startsWith('asp')) return 'asp';
    return 'php';
  }

  /// 各 connectorType 的简短显示标签
  static String shortLabel(String connectorType) => switch (connectorType) {
        'php_eval'        => 'PHP-EVAL',
        'php_b64rot13'    => 'PHP-B64',
        'php_passthru'    => 'PHP-CMD',
        'php_probe'       => 'PHP-PROBE',
        'jsp_classloader' => 'JSP-CL',
        'jsp_runtime'     => 'JSP-CMD',
        'asp_wscript'     => 'ASP-CMD',
        _                 => connectorType.toUpperCase(),
      };

  /// 各 connectorType 对应的 payload 文件名（供 UI 提示）
  static String payloadHint(String connectorType) => switch (connectorType) {
        'php_eval'        => 'php_eval_post.php',
        'php_b64rot13'    => 'php_b64rot13_post.php',
        'php_passthru'    => 'php_passthru_req.php',
        'php_probe'       => 'php_probe_info.php',
        'jsp_classloader' => 'jsp_classloader_b64.jsp',
        'jsp_runtime'     => 'jsp_runtime_get.jsp',
        'asp_wscript'     => 'asp_wscript_get.asp',
        _                 => '',
      };

  /// 返回该连接器硬编码的请求方法（不受用户设置影响）。
  /// 返回 null 表示连接器尊重用户选择。
  static String? fixedMethod(String connectorType) => switch (connectorType) {
        'php_b64rot13'    => 'POST', // 只读 $_POST['x']
        'php_probe'       => 'GET',  // 直接 GET，无参数
        'jsp_classloader' => 'POST', // agent body 过大，只走 POST
        _                 => null,
      };

  static const allTypes = [
    'php_eval',
    'php_b64rot13',
    'php_passthru',
    'php_probe',
    'jsp_classloader',
    'jsp_runtime',
    'asp_wscript',
  ];
}
