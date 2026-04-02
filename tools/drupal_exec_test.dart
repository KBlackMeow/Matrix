import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final base = 'http://localhost:8080';
  final payload =
      'form_id=user_register_form&_drupal_ajax=1&mail[#post_render][]=exec&mail[#type]=markup&mail[#markup]=' +
      Uri.encodeQueryComponent('id');
  final res = await http.post(
    Uri.parse(
      '$base/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax',
    ),
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: payload,
  );
  print('status: ${res.statusCode}');
  print('body:');
  print(res.body);
  try {
    final list = jsonDecode(res.body) as List<dynamic>;
    print('json OK');
    for (final item in list) {
      if (item is Map && item['command'] == 'insert') {
        final data = (item['data'] as String? ?? '');
        print('data:');
        print(data.replaceAll(RegExp(r'<[^>]*>'), '').trim());
      }
    }
  } catch (e) {
    print('parse error: $e');
  }
}
