package javax.servlet.jsp;

// 与真实 Servlet API 对齐：PageContext 是一个类而不是接口
public abstract class PageContext {
    public abstract Object getRequest();
    public abstract Object getResponse();
}
