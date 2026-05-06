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

typedef _ConnectorBuilder = ShellConnector Function(Webshell webshell);

class _ConnectorDefinition {
  final String type;
  final String typeLabel;
  final String shortLabel;
  final String payloadHint;
  final String defaultParam;
  final String? fixedMethod;
  final _ConnectorBuilder builder;

  const _ConnectorDefinition({
    required this.type,
    required this.typeLabel,
    required this.shortLabel,
    required this.payloadHint,
    required this.defaultParam,
    required this.fixedMethod,
    required this.builder,
  });
}

/// 根据 [Webshell.connectorType] 创建对应的连接器实例
class ConnectorFactory {
  ConnectorFactory._();

  static final List<_ConnectorDefinition> _definitions = [
    _ConnectorDefinition(
      type: 'php_eval',
      typeLabel: 'php',
      shortLabel: 'PHP-EVAL',
      payloadHint: 'php_eval_post.php',
      defaultParam: 'cmd',
      fixedMethod: null,
      builder: PhpEvalConnector.new,
    ),
    _ConnectorDefinition(
      type: 'php_b64rot13',
      typeLabel: 'php',
      shortLabel: 'PHP-B64',
      payloadHint: 'php_b64rot13_post.php',
      defaultParam: AppConstants.defaultShellPassword,
      fixedMethod: 'POST', // 只读 $_POST['mAtrix_911']
      builder: PhpB64Rot13Connector.new,
    ),
    _ConnectorDefinition(
      type: 'php_behinder',
      typeLabel: 'php',
      shortLabel: 'PHP-BEHINDER',
      payloadHint: 'php_behinder.php',
      defaultParam: AppConstants.defaultShellPassword,
      fixedMethod: 'POST', // AES 加密 body
      builder: PhpBehinderConnector.new,
    ),
    _ConnectorDefinition(
      type: 'php_passthru',
      typeLabel: 'php',
      shortLabel: 'PHP-CMD',
      payloadHint: 'php_passthru_req.php',
      defaultParam: 'cmd',
      fixedMethod: null,
      builder: PhpPassthruConnector.new,
    ),
    _ConnectorDefinition(
      type: 'jsp_classloader',
      typeLabel: 'jsp',
      shortLabel: 'JSP-CL',
      payloadHint: 'jsp_classloader_b64.jsp（排错版：jsp_classloader_b64_debug.jsp）',
      defaultParam: AppConstants.defaultShellPassword, // 与 jsp_classloader_b64.jsp 参数名一致
      fixedMethod: 'POST', // agent body 过大，只走 POST
      builder: JspClassloaderConnector.new,
    ),
    _ConnectorDefinition(
      type: 'jsp_behinder',
      typeLabel: 'jsp',
      shortLabel: 'JSP-BEHINDER',
      payloadHint: 'jsp_behinder.jsp',
      defaultParam: AppConstants.defaultShellPassword,
      fixedMethod: 'POST', // AES 加密 body
      builder: JspBehinderConnector.new,
    ),
    _ConnectorDefinition(
      type: 'jsp_runtime',
      typeLabel: 'jsp',
      shortLabel: 'JSP-CMD',
      payloadHint: 'jsp_runtime_get.jsp（原版 JSP；Matrix 用 echo|base64 -d|bash 传脚本）',
      defaultParam: AppConstants.defaultShellPassword, // 与 jsp_runtime_get.jsp 一致
      fixedMethod: 'POST', // 命令进表单参数；GET 易超长且中文路径 URL 编码膨胀
      builder: JspRuntimeConnector.new,
    ),
    _ConnectorDefinition(
      type: 'asp_wscript',
      typeLabel: 'asp',
      shortLabel: 'ASP-CMD',
      payloadHint: 'asp_wscript_get.asp',
      defaultParam: 'cmd',
      fixedMethod: null,
      builder: AspWscriptConnector.new,
    ),
    _ConnectorDefinition(
      type: 'aspx_cmd',
      typeLabel: 'aspx',
      shortLabel: 'ASPX-CMD',
      payloadHint: 'aspx_cmd_post.aspx',
      defaultParam: 'cmd',
      fixedMethod: null,
      builder: AspxCmdConnector.new,
    ),
  ];

  static final Map<String, _ConnectorDefinition> _definitionsByType = {
    for (final d in _definitions) d.type: d,
  };

  static _ConnectorDefinition? _def(String connectorType) =>
      _definitionsByType[connectorType];

  static String _fallbackTypeLabel(String connectorType) {
    if (connectorType.startsWith('jsp')) return 'jsp';
    if (connectorType == 'aspx_cmd') return 'aspx';
    if (connectorType.startsWith('asp')) return 'asp';
    return 'php';
  }

  static ShellConnector create(Webshell webshell) {
    final definition = _def(webshell.connectorType);
    if (definition != null) return definition.builder(webshell);
    return PhpEvalConnector(webshell); // fallback
  }

  /// 从 connectorType 推导显示用的 type 标签（php / jsp / asp / aspx）
  static String typeLabel(String connectorType) {
    return _def(connectorType)?.typeLabel ?? _fallbackTypeLabel(connectorType);
  }

  /// 各 connectorType 的简短显示标签
  static String shortLabel(String connectorType) =>
      _def(connectorType)?.shortLabel ?? connectorType.toUpperCase();

  /// 各 connectorType 对应的 payload 文件名（供 UI 提示）
  static String payloadHint(String connectorType) =>
      _def(connectorType)?.payloadHint ?? '';

  /// 返回该 connector 对应 payload 里使用的默认参数名。
  /// 用于在 UI 的"密码"字段中显示提示，避免参数名混淆。
  static String defaultParam(String connectorType) =>
      _def(connectorType)?.defaultParam ?? 'cmd';

  /// 返回该连接器硬编码的请求方法（不受用户设置影响）。
  /// 返回 null 表示连接器尊重用户选择。
  static String? fixedMethod(String connectorType) =>
      _def(connectorType)?.fixedMethod;

  static final List<String> allTypes = _definitions
      .map((d) => d.type)
      .toList(growable: false);
}
