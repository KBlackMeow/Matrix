import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Core menu entry smoke flow', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 500));

    final menuItems = <String>[
      '项目管理',
      'Webshell管理',
      'Payload管理',
      '字典管理',
      'EXP管理',
    ];

    for (final item in menuItems) {
      final finder = find.text(item).first;
      expect(finder, findsOneWidget);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    }
  });
}
