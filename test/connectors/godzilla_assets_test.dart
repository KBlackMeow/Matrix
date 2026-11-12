import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/godzilla/godzilla_payload_assets.dart';
import 'package:matrix/connectors/godzilla/godzilla_variant.dart';

/// 引擎资产自检：保证 `data/godzilla/*.b64` 与 `tool/godzilla_engine/`
/// 的源码一致，避免有人改了引擎源码却忘了跑 `build.sh`。
void main() {
  // rootBundle 需要 Flutter binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Godzilla 引擎资产', () {
    test('每个变体的资产路径都指向 data/godzilla/', () {
      for (final variant in GodzillaVariant.values) {
        expect(variant.engineAsset, startsWith('data/godzilla/'));
      }
    });

    test('PHP 引擎是去掉 <?php 的纯 PHP 代码', () async {
      final bytes = await GodzillaPayloadAssets.load(
        GodzillaVariant.phpXorBase64.engineAsset,
      );
      expect(bytes, isNotNull);
      final text = utf8.decode(bytes!);
      expect(text.contains('<?php'), isFalse,
          reason: '引擎会被 eval，不能带 PHP 开标签');
      expect(text, contains(r'function run('));
      expect(text, contains('getBasicsInfo'));
      expect(text, contains('execCommand'));
    });

    test('JSP 引擎是合法的单类 .class（CAFEBABE）', () async {
      final bytes = await GodzillaPayloadAssets.load(
        GodzillaVariant.javaAesBase64.engineAsset,
      );
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(4096));
      expect(bytes[0], 0xCA);
      expect(bytes[1], 0xFE);
      expect(bytes[2], 0xBA);
      expect(bytes[3], 0xBE);
      // 版本号：major 52 = Java 8（--release 8）
      final major = (bytes[6] << 8) | bytes[7];
      expect(major, lessThanOrEqualTo(52));
    });

    test('ASP 引擎提供 run() 与 Base64Encode()', () async {
      final bytes = await GodzillaPayloadAssets.load(
        GodzillaVariant.aspXorBase64.engineAsset,
      );
      expect(bytes, isNotNull);
      final text = latin1.decode(bytes!);
      expect(text, contains('Function run('));
      expect(text, contains('Function Base64Encode('));
    });

    test('ASPX DLL 尚未构建时安全返回 null（不抛异常）', () async {
      // 本仓库没有 .NET 工具链，DLL 需在 Windows 机器上跑 build.sh 生成。
      // 这里只断言“缺失时不炸”，连接器会给出明确诊断。
      final bytes = await GodzillaPayloadAssets.load(
        GodzillaVariant.csharpAesBase64.engineAsset,
      );
      if (bytes != null) {
        // 若已构建，必须是 PE 文件（MZ）。
        final data = Uint8List.fromList(bytes);
        expect(data[0], 0x4D);
        expect(data[1], 0x5A);
      }
    });
  });
}
