/// XXL-JOB 家族声明。
library;

import '../core/exploit_module.dart';
import '../core/exp_spec.dart';

const xxljobSpec = ExpSpec(
  id: 'xxljob',
  family: 'XXL-JOB',
  title: 'XXL-JOB 未授权执行器',
  subtitle: '默认 accessToken 直连 GLUE_SHELL',
  category: 'XXL-JOB',
  icon: ExpIcon.xxljob,
  notes: [
    '命令无回显，只能靠执行结果侧证',
    '执行器无 Web 目录，不提供 shell',
  ],
  fields: [],
  variants: [
    ExpVariant(
      id: 'xxl-job-unacc',
      label: '未授权执行器 · XXL-JOB',
      moduleId: 'xxl-job-unacc',
      evidence: ExpEvidence.weak,
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec},
    ),
  ],
);
