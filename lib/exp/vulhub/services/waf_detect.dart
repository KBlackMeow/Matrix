/// WAF 拦截识别。
///
/// 目的：把"请求被防御设备拦下"与"目标确实不存在漏洞"区分开。
/// 二者都拿不到漏洞特征，但结论完全不同——前者是"没测通"。
library;

/// 是否像被 WAF / 安全设备拦截。
///
/// 判定依据：
/// - 常见拦截状态码（403/406/429/451）；
/// - 响应体中的通用拦截文案（只认强特征，避免把普通 403 页面误判成 WAF）。
bool looksLikeWafBlock(int? status, String? body) {
  final s = status ?? 0;
  final b = (body ?? '').toLowerCase();
  const strongMarkers = <String>[
    'blocked by waf',
    'web application firewall',
    'request blocked',
    'requests blocked',
    'access denied by',
    '安全拦截',
    '拦截页面',
    '存在攻击行为',
  ];
  if (strongMarkers.any(b.contains)) return true;
  // 403/406/429/451 且响应体很短或含通用拒绝文案：按拦截处理。
  if (s == 403 || s == 406 || s == 429 || s == 451) {
    if (b.isEmpty || b.length < 4096) return true;
  }
  return false;
}

/// 响应是否明显不是目标业务响应（例如 WAF 错误页），用于命令执行结果判定。
bool looksLikeBlockedBody(String? body) {
  final b = (body ?? '').toLowerCase();
  if (b.isEmpty) return false;
  const markers = <String>[
    'blocked by waf',
    '403 forbidden',
    'access denied',
    'request rejected',
    '安全拦截',
  ];
  return markers.any(b.contains);
}
