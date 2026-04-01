import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/main.dart';

void main() {
  testWidgets('App boots and shows core navigation entries', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('项目管理'), findsWidgets);
    expect(find.text('Webshell管理'), findsWidgets);
    expect(find.text('Payload管理'), findsWidgets);
    expect(find.text('字典管理'), findsWidgets);
    expect(find.text('EXP管理'), findsWidgets);
  });
}
