package javax.servlet.http;

import java.io.OutputStream;
import java.io.PrintWriter;

/** 本地 javac 用桩；运行时由容器实现 */
public interface HttpServletResponse {
    void setCharacterEncoding(String charset);
    void setStatus(int sc);
    void setHeader(String name, String value);
    OutputStream getOutputStream();
    PrintWriter getWriter();
}

