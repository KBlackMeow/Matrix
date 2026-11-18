/// 漏洞检测结果。
///
/// 关键语义：**"没测出来" 不等于 "不存在"**。
/// 网络超时、DNS 失败、证书错误、响应解析失败都会让检测无法完成，
/// 这类情况必须与"探测完成且确认不存在"区分开，否则评估结论会把
/// "没打通" 报成 "目标安全"。
class ExpResult {
  /// 是否确认存在漏洞。
  final bool vulnerable;

  /// 探测是否未能完成（网络/超时/证书/解析等异常）。
  ///
  /// 为 true 时 [vulnerable] 恒为 false，但**不能**据此判定目标安全。
  final bool failed;

  final String vulnName;
  final String detail;

  const ExpResult(
    this.vulnerable,
    this.vulnName,
    this.detail, {
    this.failed = false,
  });

  /// 探测未完成：网络错误、超时、证书/解析异常等。
  const ExpResult.probeFailed(this.vulnName, this.detail)
    : vulnerable = false,
      failed = true;
}
