import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/exp/vulhub/spring_exp_service.dart';

void main() {
  group('SpringExpService', () {
    test('checkSpringCloudFunction sends expected request and detects signal', () async {
      late HttpServer server;
      String? seenMethod;
      String? seenPath;
      String? seenHeader;
      String? seenBody;

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sub = server.listen((req) async {
        seenMethod = req.method;
        seenPath = req.uri.path;
        seenHeader = req.headers.value('spring.cloud.function.routing-expression');
        seenBody = await utf8.decoder.bind(req).join();

        req.response.statusCode = 500;
        req.response.write('SpEL parseException: 54289');
        await req.response.close();
      });

      addTearDown(() async {
        await sub.cancel();
        await server.close(force: true);
      });

      final svc = SpringExpService(url: 'http://127.0.0.1:${server.port}');
      final result = await svc.checkSpringCloudFunction();

      expect(seenMethod, equals('POST'));
      expect(seenPath, equals('/functionRouter'));
      expect(seenHeader, equals('233*233'));
      expect(seenBody, equals('test'));
      expect(result.vulnerable, isTrue);
      expect(result.vulnName, equals('CVE-2022-22963'));
    });

    test('checkSpringDataCommons detects proxy binding error signature', () async {
      late HttpServer server;
      String? seenMethod;
      Uri? seenUri;
      String? seenContentType;
      String? seenBody;

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sub = server.listen((req) async {
        seenMethod = req.method;
        seenUri = req.uri;
        seenContentType = req.headers.contentType?.mimeType;
        seenBody = await utf8.decoder.bind(req).join();

        req.response.statusCode = 500;
        req.response.headers.contentType = ContentType.html;
        req.response.write(
          "Invalid property 'username' of bean class [example.users.web.\$Proxy]",
        );
        await req.response.close();
      });

      addTearDown(() async {
        await sub.cancel();
        await server.close(force: true);
      });

      final svc = SpringExpService(url: 'http://127.0.0.1:${server.port}');
      final result = await svc.checkSpringDataCommons();

      expect(seenMethod, equals('POST'));
      expect(seenUri?.path, equals('/users'));
      expect(seenUri?.query, equals('page=&size=5'));
      expect(seenContentType, equals('application/x-www-form-urlencoded'));
      expect(seenBody, contains('username%5B'));
      expect(result.vulnerable, isTrue);
      expect(result.vulnName, equals('CVE-2018-1273'));
      expect(result.detail, contains('Invalid property username + \$Proxy'));
    });

    test('checkSpringSecurityOauth retries with basic auth after 401', () async {
      late HttpServer server;
      int requestCount = 0;
      String? firstAuth;
      String? secondAuth;

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sub = server.listen((req) async {
        requestCount++;
        final auth = req.headers.value(HttpHeaders.authorizationHeader);
        if (requestCount == 1) {
          firstAuth = auth;
          req.response.statusCode = 401;
          req.response.write('auth required');
          await req.response.close();
          return;
        }

        secondAuth = auth;
        req.response.statusCode = 200;
        req.response.write('Unsupported response types: [54289]');
        await req.response.close();
      });

      addTearDown(() async {
        await sub.cancel();
        await server.close(force: true);
      });

      final svc = SpringExpService(
        url: 'http://127.0.0.1:${server.port}',
        credentials: 'alice:secret',
      );
      final result = await svc.checkSpringSecurityOauth();

      final expectedAuth = 'Basic ${base64Encode(utf8.encode('alice:secret'))}';
      expect(firstAuth, isNull);
      expect(secondAuth, equals(expectedAuth));
      expect(result.vulnerable, isTrue);
      expect(result.vulnName, equals('CVE-2016-4977'));
    });
  });
}
