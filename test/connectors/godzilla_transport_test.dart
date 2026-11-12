import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/connector_factory.dart';
import 'package:matrix/connectors/godzilla/godzilla_variant.dart';
import 'package:matrix/core/crypto/godzilla_crypto.dart';
import 'package:matrix/models/webshell.dart';

/// 进程内伪 Godzilla 服务器（PHP_XOR_BASE64）。
///
/// 不依赖外部目标：在本机回环端口上实现“播种 + 参数解析 + 标记响应”，
/// 用来验证 [GodzillaTransport] / [GodzillaConnectorBase] 的真实往返。
class _FakeGodzillaPhpServer {
  _FakeGodzillaPhpServer._(this._server, this._key16, this._password,
      {this.raw = false});

  final HttpServer _server;
  final String _key16;
  final String _password;
  final bool raw;

  /// 可覆盖 getBasicsInfo 的返回，用于测试脚本目录解析。
  String? basicsOverride;

  Uint8List? seededEngine;
  final Map<String, Uint8List> files = {};
  final Set<String> shellFiles = {};
  final List<String> calls = [];
  int seedCount = 0;
  bool broken = false;

  String get url => 'http://${_server.address.host}:${_server.port}/shell.php';

  static Future<_FakeGodzillaPhpServer> start({
    required String password,
    required String secretKey,
    bool raw = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeGodzillaPhpServer._(
      server,
      GodzillaCrypto.deriveKey16(secretKey),
      password,
      raw: raw,
    );
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Uint8List _xor(Uint8List data) {
    final key = latin1.encode(_key16);
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = data[i] ^ key[(i + 1) & 15];
    }
    return out;
  }

  Map<String, Uint8List> _parseParams(Uint8List data) {
    final result = <String, Uint8List>{};
    final key = <int>[];
    var i = 0;
    while (i < data.length) {
      if (data[i] == 0x02) {
        if (i + 5 > data.length) break;
        final len = (data[i + 1] & 0xff) |
            ((data[i + 2] & 0xff) << 8) |
            ((data[i + 3] & 0xff) << 16) |
            ((data[i + 4] & 0xff) << 24);
        i += 5;
        if (len < 0 || i + len > data.length) break;
        result[utf8.decode(key)] = Uint8List.fromList(data.sublist(i, i + len));
        key.clear();
        i += len;
      } else {
        key.add(data[i]);
        i++;
      }
    }
    return result;
  }

  String _str(Map<String, Uint8List> params, String key) =>
      params[key] == null ? '' : utf8.decode(params[key]!);

  Future<void> _handle(HttpRequest request) async {
    final chunks = await request.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    final response = request.response;

    if (broken) {
      response.statusCode = 500;
      await response.close();
      return;
    }

    Uint8List plain;
    if (raw) {
      if (chunks.isEmpty) {
        response.statusCode = 200;
        await response.close();
        return;
      }
      plain = _xor(Uint8List.fromList(chunks));
    } else {
      final encoded = Uri.splitQueryString(utf8.decode(chunks))[_password] ?? '';
      if (encoded.isEmpty) {
        response.statusCode = 200;
        await response.close();
        return;
      }
      plain = _xor(Uint8List.fromList(base64.decode(encoded)));
    }
    response.headers.add('set-cookie', 'PHPSESSID=fake-session; path=/');

    // 首次请求 = 播种引擎（Godzilla 标准马行为）。
    if (seededEngine == null) {
      seedCount++;
      seededEngine = plain;
      await response.close();
      return;
    }

    final params = _parseParams(plain);
    final method = _str(params, 'methodName');
    calls.add(method);
    final result = _dispatch(method, params);
    final cipher = _xor(Uint8List.fromList(gzip.encode(result)));
    if (raw) {
      response.add(cipher);
    } else {
      final markers = GodzillaCrypto.markers(
        password: _password,
        key16: _key16,
        style: _markerStyle,
      );
      response.write(markers.left);
      response.write(base64.encode(cipher));
      response.write(markers.right);
    }
    await response.close();
  }

  // php_godzilla 的标记是小写 16/16。
  static const _markerStyle = GodzillaMarkerStyle.lower16;

  List<int> _dispatch(String method, Map<String, Uint8List> params) {
    switch (method) {
      case 'getBasicsInfo':
        if (basicsOverride != null) return utf8.encode(basicsOverride!);
        return utf8.encode(
          'OsInfo : FakeOS 1.0 amd64\n'
          'CurrentUser : fakeuser\n'
          'CurrentDir : /fake/dir\n'
          'FileRoot : /\n'
          'memory_limit : 128M\n',
        );
      case 'execCommand':
        final cmdLine = _str(params, 'cmdLine');
        if (cmdLine.contains('printf %s')) {
          for (final file in shellFiles) {
            if (cmdLine.contains(file)) {
              return utf8.encode(file.substring(0, file.lastIndexOf('/')));
            }
          }
          return utf8.encode('');
        }
        return utf8.encode('ran:$cmdLine');
      case 'getFile':
        final dir = _str(params, 'dirName');
        return utf8.encode(
          'ok\n$dir/\n'
          'a.txt\t1\t2026-01-01 00:00:00\t12\tRW\n'
          'sub\t0\t2026-01-01 00:00:00\t0\tRW\n',
        );
      case 'readFileContent':
        return files[_str(params, 'fileName')] ?? utf8.encode('File Not Found');
      case 'uploadFile':
        files[_str(params, 'fileName')] = params['fileValue'] ?? Uint8List(0);
        return utf8.encode('ok');
      case 'deleteFile':
        files.remove(_str(params, 'fileName'));
        return utf8.encode('ok');
      case 'test':
        return utf8.encode('ok');
      default:
        return utf8.encode('unknown method: $method');
    }
  }
}

Webshell _webshell(String url, {String secretKey = 'key'}) {
  final now = DateTime.now();
  return Webshell(
    id: 1,
    projectId: 1,
    name: 'fake',
    url: url,
    password: 'mAtrix_911',
    secretKey: secretKey,
    type: 'php',
    connectorType: 'php_godzilla',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  // eval 变体需要 rootBundle（binding）；同时放开真实回环请求。
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late _FakeGodzillaPhpServer server;

  setUp(() async {
    server = await _FakeGodzillaPhpServer.start(
      password: 'mAtrix_911',
      secretKey: 'key',
    );
  });

  tearDown(() => server.close());

  test('ping seeds the engine once and reports online', () async {
    final connector = ConnectorFactory.create(_webshell(server.url));
    expect(await connector.ping(), isTrue);
    expect(server.seededEngine, isNotNull);
    expect(server.seedCount, 1);

    // 第二次调用不应重复播种。
    expect(await connector.ping(), isTrue);
    expect(server.seedCount, 1);
  });

  test('executeCommand sends cmdLine and returns the body', () async {
    final connector = ConnectorFactory.create(_webshell(server.url));
    final out = await connector.executeCommand('echo hi');
    expect(out, 'ran:echo hi');
    expect(server.calls, contains('execCommand'));
  });

  test('workingDir is wrapped into cd &&', () async {
    final connector = ConnectorFactory.create(_webshell(server.url));
    final out = await connector.executeCommand('ls', workingDir: '/tmp');
    expect(out, "ran:cd '/tmp' && ls");
  });

  test('listDirectory parses the tab-separated listing', () async {
    final connector = ConnectorFactory.create(_webshell(server.url));
    final entries = await connector.listDirectory('/tmp');
    expect(entries.map((e) => e.name), containsAll(['a.txt', 'sub']));
    final file = entries.firstWhere((e) => e.name == 'a.txt');
    expect(file.isDirectory, isFalse);
    expect(file.size, 12);
    final dir = entries.firstWhere((e) => e.name == 'sub');
    expect(dir.isDirectory, isTrue);
    // 目录排在文件前面。
    expect(entries.first.name, 'sub');
  });

  test('binary write/read round-trip keeps raw bytes', () async {
    final connector = ConnectorFactory.create(_webshell(server.url));
    final payload = Uint8List.fromList([0, 1, 2, 255, 254, 0x68, 0x69]);
    expect(await connector.writeFileBinary('/x.bin', payload), isTrue);
    final read = await connector.readFileBinary('/x.bin');
    expect(base64.encode(read), base64.encode(payload));
    expect(await connector.deleteFile('/x.bin'), isTrue);
  });

  test('getSystemInfo maps getBasicsInfo keys to Matrix aliases', () async {
    final connector = ConnectorFactory.create(_webshell(server.url));
    final info = await connector.getSystemInfo();
    expect(info['OS'], 'FakeOS 1.0 amd64');
    expect(info['运行用户'], 'fakeuser');
    expect(info['当前目录'], '/fake/dir');
    expect(info['内存限制'], '128M');
  });

  test('getShellScriptDir 在找不到脚本时回退到 RealFile/DocBase', () async {
    // Godzilla 的 CurrentDir 是进程 cwd，RealFile/DocBase 才是 webapp 目录。
    server.basicsOverride =
        'OsInfo : FakeOS\n'
        'CurrentDir : /jvm/cwd\n'
        'RealFile : /app/root\n'
        'DocBase : /app/root\n';
    final connector = ConnectorFactory.create(_webshell(server.url));
    expect(await connector.getShellScriptDir(), '/app/root');
  });

  test('getShellScriptDir 用 URL 文件名定位到真实父目录', () async {
    server.basicsOverride =
        'OsInfo : FakeOS\n'
        'CurrentDir : /jvm/cwd\n'
        'DocBase : /app/root\n';
    // 伪 shell：只有 /app/root/shell.php 存在。
    server.shellFiles.add('/app/root/shell.php');
    final connector = ConnectorFactory.create(_webshell(server.url));
    expect(await connector.getShellScriptDir(), '/app/root');
  });

  test('wrong secretKey fails ping with a protocol diagnostic', () async {
    final connector = ConnectorFactory.create(
      _webshell(server.url, secretKey: 'wrong-key'),
    );
    expect(await connector.ping(), isFalse);
    expect(connector.lastPingDiagnostic, contains('[Markers]'));
  });

  test('HTTP 500 during seed surfaces the status code', () async {
    server.broken = true;
    final connector = ConnectorFactory.create(_webshell(server.url));
    expect(await connector.ping(), isFalse);
    expect(connector.lastPingDiagnostic, contains('500'));
  });
  group('RAW 变体（裸密文）', () {
    late _FakeGodzillaPhpServer rawServer;

    setUp(() async {
      rawServer = await _FakeGodzillaPhpServer.start(
        password: 'mAtrix_911',
        secretKey: 'key',
        raw: true,
      );
    });

    tearDown(() => rawServer.close());

    Webshell rawShell({String secretKey = 'key'}) {
      final now = DateTime.now();
      return Webshell(
        id: 2,
        projectId: 1,
        name: 'raw',
        url: rawServer.url,
        password: 'mAtrix_911',
        secretKey: secretKey,
        type: 'php',
        connectorType: 'php_godzilla',
        cryption: 'PHP_XOR_RAW',
        createdAt: now,
        updatedAt: now,
      );
    }

    test('ping / exec / 文件往返', () async {
      final connector = ConnectorFactory.create(rawShell());
      expect(await connector.ping(), isTrue,
          reason: connector.lastPingDiagnostic);
      expect(await connector.executeCommand('echo raw'), 'ran:echo raw');

      expect(await connector.writeFileBinary('/raw.bin',
          Uint8List.fromList([9, 8, 7, 255])), isTrue);
      expect(base64.encode(await connector.readFileBinary('/raw.bin')),
          base64.encode(Uint8List.fromList([9, 8, 7, 255])));
      expect(await connector.deleteFile('/raw.bin'), isTrue);
    });

    test('密钥错误时 ping 失败并给出诊断', () async {
      final connector = ConnectorFactory.create(rawShell(secretKey: 'nope'));
      expect(await connector.ping(), isFalse);
      expect(connector.lastPingDiagnostic, isNotNull);
      // XOR 没有 padding 校验，"解密"总是成功但得到乱码，
      // 因此这里只要求 ping 失败 + 有诊断，不要求特定前缀。
      expect(connector.lastPingDiagnostic, isNotEmpty);
    });
  });

  group('eval 变体不把密钥发到线上', () {
    test('请求体里只有密码（参数名），没有 secretKey/key16', () async {
      final captured = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        captured.add(utf8.decode(body, allowMalformed: true));
        req.response.statusCode = 200;
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final connector = ConnectorFactory.create(
        Webshell(
          id: 1,
          projectId: 1,
          name: 'eval',
          url: 'http://127.0.0.1:${server.port}/shell.php',
          password: 'mx_pass',
          secretKey: 'sup3r-secret',
          cryption: 'PHP_EVAL_XOR_BASE64',
          type: 'php',
          connectorType: 'php_godzilla',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await connector.ping().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );

      expect(captured, isNotEmpty);
      final body = captured.first;
      // 密码本来就作为参数名出现（与所有 Godzilla 变体一致）。
      expect(body, contains('mx_pass'));
      // 密钥材料不能出现在明文里（loader 是 base64+反转，不是加密）。
      expect(body, isNot(contains('sup3r-secret')));
      expect(body, contains('mxdata'));
    });
  });
}
