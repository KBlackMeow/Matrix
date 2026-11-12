import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/godzilla/godzilla_shell_generator.dart';
import 'package:matrix/models/project.dart';
import 'package:matrix/pages/webshell_management_page.dart';

/// 覆盖「创建连接时找不到加密器 / 只有一个加密器」的问题：
/// - 选中 Godzilla 连接器后必须出现 `Cryption (加密器)` 下拉
/// - 下拉包含全部 8 种加密器（4 语言 × BASE64/RAW）
/// - 切换加密器会同步切换连接器类型
void main() {
  final project = Project(
    id: 1,
    name: 'test-project',
    domain: '127.0.0.1',
    description: '',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  Future<void> openAddDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebshellManagementPage(
            project: project,
            onSwitchProject: () {},
            loadWebshells: (_) async => const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add Webshell'));
    await tester.pumpAndSettle();
  }

  /// 直接触发连接器下拉的 onChanged（避免 19 项菜单的滚动差异）。
  Future<void> pickConnector(WidgetTester tester, String connectorType) async {
    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    field.onChanged!(connectorType);
    await tester.pumpAndSettle();
  }

  Future<void> pickCryption(WidgetTester tester, String cryptionId) async {
    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).at(1),
    );
    field.onChanged!(cryptionId);
    await tester.pumpAndSettle();
  }

  testWidgets('普通连接器不显示加密器', (tester) async {
    await openAddDialog(tester);
    expect(find.text('Cryption (加密器)'), findsNothing);
    expect(find.text('Godzilla key (secretKey) *'), findsNothing);
  });

  testWidgets('选中 Godzilla 连接器后出现加密器、密钥与生成入口', (tester) async {
    await openAddDialog(tester);
    await pickConnector(tester, 'php_godzilla');

    expect(find.text('Cryption (加密器)'), findsOneWidget);
    expect(find.text('Godzilla key (secretKey) *'), findsOneWidget);
    expect(find.text('PHP_XOR_BASE64'), findsWidgets);
  });

  testWidgets('切到 JSP 时加密器列表只剩 JSP 的两种', (tester) async {
    await openAddDialog(tester);
    await pickConnector(tester, 'jsp_godzilla');

    expect(find.text('Cryption (加密器)'), findsOneWidget);
    expect(find.text('JAVA_AES_BASE64'), findsWidgets);
    // 切到 JSP 后加密器列表应只剩 JSP 的两个。
    final button = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).at(1),
    );
    expect(button.items, hasLength(2));
  });

  testWidgets('加密器下拉按架构过滤', (tester) async {
    await openAddDialog(tester);
    await pickConnector(tester, 'php_godzilla');

    final button = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).at(1),
    );
    final ids = button.items!
        .map((item) => ((item.child as Text).data)!)
        .toList(growable: false);

    // 只显示当前架构（PHP）的加密器。
    expect(ids, hasLength(3));
    expect(ids, containsAll(['PHP_XOR_BASE64', 'PHP_XOR_RAW', 'PHP_EVAL_XOR_BASE64']));
  });

  testWidgets('加密器独立选择，连接器保持架构+协议不变', (tester) async {
    await openAddDialog(tester);
    await pickConnector(tester, 'php_godzilla');

    await pickCryption(tester, 'PHP_XOR_RAW');

    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    // 连接器仍是“PHP + Godzilla”，加密器单独变化。
    expect(field.initialValue, 'php_godzilla');
    expect(find.text('PHP_XOR_RAW'), findsWidgets);
  });
}
