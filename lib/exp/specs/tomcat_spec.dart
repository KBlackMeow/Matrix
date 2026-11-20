/// Tomcat 家族声明：CVE-2017-12615。
///
/// 最简单的家族（一个变体、一个 URL 字段、原生 PUT 写马），
/// 用来验证 [ExpSpec] 的形状够不够——也用来跑通"声明 → 模块 → 页面"的绑定。
library;

import '../core/exploit_module.dart';
import '../core/exp_spec.dart';

const tomcatSpec = ExpSpec(
  id: 'tomcat',
  family: 'Tomcat',
  title: 'Tomcat CVE-2017-12615',
  subtitle: 'readonly=false 时 PUT 写 JSP 并执行 · 原生 shell',
  category: 'Tomcat',
  icon: ExpIcon.tomcat,
  notes: ['条件：conf/web.xml 的 readonly=false', '写马路径为 web 根下随机 JSP'],
  fields: [],
  variants: [
    ExpVariant(
      id: 'tomcat-2017-12615',
      label: 'PUT 写 JSP',
      moduleId: 'tomcat-2017-12615',
      capabilities: {
        ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell,
      },
    ),
  ],
);
