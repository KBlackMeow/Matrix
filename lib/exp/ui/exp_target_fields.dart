/// 目标输入（URL + 超时），所有模块页共用。
///
/// 这两个字段在 12 个旧页面里各写了一遍，且各自的校验、默认值、宽高都不一致。
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../core/exploit_session.dart';
import 'exp_fields.dart';
import 'exp_tokens.dart';

class ExpTargetFields extends StatefulWidget {
  const ExpTargetFields({super.key, required this.session, this.enabled = true});

  final ExploitSessionController session;
  final bool enabled;

  @override
  State<ExpTargetFields> createState() => _ExpTargetFieldsState();
}

class _ExpTargetFieldsState extends State<ExpTargetFields> {
  late final TextEditingController _url = TextEditingController(
    text: widget.session.url,
  );
  late final TextEditingController _timeout = TextEditingController(
    text: '${widget.session.timeoutSeconds}',
  );

  @override
  void dispose() {
    _url.dispose();
    _timeout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _url,
          enabled: widget.enabled,
          style: AppTextStyles.body(size: ExpText.body, color: ExpColors.text),
          decoration: expInputDecoration('目标 URL', 'http://target:8080'),
          onChanged: widget.session.setUrl,
        ),
        ExpSpace.vMd,
        Row(
          children: [
            SizedBox(
              width: 96,
              child: TextField(
                controller: _timeout,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                style: AppTextStyles.body(
                  size: ExpText.body,
                  color: ExpColors.text,
                ),
                decoration: expInputDecoration('超时(秒)'),
                onChanged: (v) {
                  final n = int.tryParse(v.trim());
                  if (n != null && n > 0) widget.session.setTimeoutSeconds(n);
                },
              ),
            ),
            ExpSpace.hMd,
            Expanded(
              child: Text(
                '单次请求超时；网络慢/有 WAF 时调大',
                style: AppTextStyles.caption(
                  size: ExpText.caption,
                  color: ExpColors.muted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
