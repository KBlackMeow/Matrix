package javax.servlet.http;

import java.io.BufferedReader;
import java.util.Enumeration;

public interface HttpServletRequest {
    String getParameter(String name);
    Object getAttribute(String name);
    void setAttribute(String name, Object value);
    Enumeration<?> getParameterNames();
    String getHeader(String name);
    String getQueryString();
    BufferedReader getReader() throws java.io.IOException;
}

