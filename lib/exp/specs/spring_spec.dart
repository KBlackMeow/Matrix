/// Spring 家族声明。
library;

import '../core/exploit_module.dart';
import '../core/exp_spec.dart';

const springSpec = ExpSpec(
  id: 'spring',
  family: 'Spring',
  title: 'Spring Framework SpEL 系列',
  subtitle: '5 个变体：22963 / 22965 / 1273 / 8046 / 4977',
  category: 'Spring',
  icon: ExpIcon.spring,
  notes: [
    '22965（Spring4Shell）会写 JSP 并改 Tomcat valve 配置，属有副作用探测',
    '4977 走 OAuth 错误页 SpEL，需要 Basic 认证头',
  ],
  fields: [
    ExpFieldSpec(
      key: 'path',
      label: '起始路径',
      hint: '留空使用 /',
      defaultValue: '',
    ),
    ExpFieldSpec(
      key: 'creds',
      label: 'Basic Auth',
      hint: 'user:pass，留空回退 admin:admin',
      defaultValue: '',
    ),
  ],
  variants: [
    ExpVariant(
      id: 'spring-22963',
      label: 'Spring Cloud Function SpEL · CVE-2022-22963',
      moduleId: 'spring-22963',
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
    ExpVariant(
      id: 'spring-22965',
      label: 'Spring4Shell · CVE-2022-22965',
      moduleId: 'spring-22965',
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
    ExpVariant(
      id: 'spring-1273',
      label: 'Data Commons SpEL · CVE-2018-1273',
      moduleId: 'spring-1273',
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
    ExpVariant(
      id: 'spring-8046',
      label: 'Data REST PATCH SpEL · CVE-2017-8046',
      moduleId: 'spring-8046',
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
    ExpVariant(
      id: 'spring-4977',
      label: 'Security OAuth SpEL · CVE-2016-4977',
      moduleId: 'spring-4977',
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
  ],
);
