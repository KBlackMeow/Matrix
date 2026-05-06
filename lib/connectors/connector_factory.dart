import '../models/webshell.dart';
import '../app/constants.dart';
import 'shell_connector.dart';
import 'php_eval_connector.dart';
import 'php_b64rot13_connector.dart';
import 'php_behinder_connector.dart';
import 'php_passthru_connector.dart';
import 'jsp_classloader_connector.dart';
import 'jsp_behinder_connector.dart';
import 'jsp_runtime_connector.dart';
import 'asp_wscript_connector.dart';
import 'aspx_cmd_connector.dart';

/// 根据 [Webshell.connectorType] 创建对应的连接器实例
class ConnectorFactory {
  ConnectorFactory._();

  static ShellConnector create(Webshell webshell) {
    return switch (webshell.connectorType) {
      'php_eval' => PhpEvalConnector(webshell),
      'php_b64rot13' => PhpB64Rot13Connector(webshell),
      'php_behinder' => PhpBehinderConnector(webshell),
      'php_passthru' => PhpPassthruConnector(webshell),
      'jsp_classloader' => JspClassloaderConnector(webshell),
      'jsp_behinder' => JspBehinderConnector(webshell),
      'jsp_runtime' => JspRuntimeConnector(webshell),
      'asp_wscript' => AspWscriptConnector(webshell),
      'aspx_cmd' => AspxCmdConnector(webshell),
      _ => PhpEvalConnector(webshell), // fallback
    };
  }

  /// 从 connectorType 推导显示用的 type 标签（php / jsp / asp / aspx）
  static String typeLabel(String connectorType) {
    if (connectorType.startsWith('jsp')) return 'jsp';
    if (connectorType == 'aspx_cmd') return 'aspx';
    if (connectorType.startsWith('asp')) return 'asp';
    return 'php';
  }

  /// 各 connectorType 的简短显示标签
  static String shortLabel(String connectorType) => switch (connectorType) {
    'php_eval' => 'PHP-EVAL',
    'php_b64rot13' => 'PHP-B64',
    'php_behinder' => 'PHP-BEHINDER',
    'php_passthru' => 'PHP-CMD',
    'jsp_classloader' => 'JSP-CL',
    'jsp_behinder' => 'JSP-BEHINDER',
    'jsp_runtime' => 'JSP-CMD',
    'asp_wscript' => 'ASP-CMD',
    'aspx_cmd' => 'ASPX-CMD',
    _ => connectorType.toUpperCase(),
  };

  /// 各 connectorType 对应的 payload 文件名（供 UI 提示）
  static String payloadHint(String connectorType) => switch (connectorType) {
    'php_eval' => 'php_eval_post.php',
    'php_b64rot13' => 'php_b64rot13_post.php',
    'php_behinder' => 'php_behinder.php',
    'php_passthru' => 'php_passthru_req.php',
    'jsp_classloader' =>
      'jsp_classloader_b64.jsp（排错版：jsp_classloader_b64_debug.jsp）',
    'jsp_behinder' => 'jsp_behinder.jsp',
    'jsp_runtime' =>
      'jsp_runtime_get.jsp（原版 JSP；Matrix 用 echo|base64 -d|bash 传脚本）',
    'asp_wscript' => 'asp_wscript_get.asp',
    'aspx_cmd' => 'aspx_cmd_post.aspx',
    _ => '',
  };

  /// 返回该 connector 对应 payload 里使用的默认参数名。
  /// 用于在 UI 的"密码"字段中显示提示，避免参数名混淆。
  static String defaultParam(String connectorType) => switch (connectorType) {
    'php_b64rot13' => AppConstants.defaultShellPassword,
    'php_behinder' => AppConstants.defaultShellPassword,
    'jsp_behinder' => AppConstants.defaultShellPassword,
    'jsp_classloader' =>
      AppConstants.defaultShellPassword, // 与 jsp_classloader_b64.jsp 参数名一致
    'jsp_runtime' =>
      AppConstants.defaultShellPassword, // 与 jsp_runtime_get.jsp 一致
    _ => 'cmd',
  };

  /// 返回该连接器硬编码的请求方法（不受用户设置影响）。
  /// 返回 null 表示连接器尊重用户选择。
  static String? fixedMethod(String connectorType) => switch (connectorType) {
    'php_b64rot13' => 'POST', // 只读 $_POST['mAtrix_911']
    'jsp_classloader' => 'POST', // agent body 过大，只走 POST
    'php_behinder' => 'POST', // AES 加密 body
    'jsp_behinder' => 'POST', // AES 加密 body
    'jsp_runtime' => 'POST', // 命令进表单参数；GET 易超长且中文路径 URL 编码膨胀
    _ => null,
  };

  static const allTypes = [
    'php_eval',
    'php_b64rot13',
    'php_behinder',
    'php_passthru',
    'jsp_classloader',
    'jsp_behinder',
    'jsp_runtime',
    'asp_wscript',
    'aspx_cmd',
  ];
}
