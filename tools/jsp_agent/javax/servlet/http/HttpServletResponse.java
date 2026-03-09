package javax.servlet.http;

import java.io.PrintWriter;

public interface HttpServletResponse {
    void setCharacterEncoding(String charset);
    PrintWriter getWriter();
}

