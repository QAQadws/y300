import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/shared/widgets/inline_search_app_bar.dart';

import '../../test_support/localized_test_app.dart';

void main() {
  testWidgets('renders a borderless field with app bar foreground colors', (
    tester,
  ) async {
    const foreground = Color(0xFFF8EDE7);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      LocalizedTestApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF5B160D),
            foregroundColor: foreground,
          ),
          inputDecorationTheme: const InputDecorationThemeData(filled: true),
        ),
        home: Scaffold(
          appBar: InlineSearchAppBar(
            controller: controller,
            focusNode: focusNode,
            fieldKey: const Key('search-field'),
            hintText: '搜索作品',
            clearTooltip: '清空',
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const Key('search-field')),
    );
    expect(field.focusNode, same(focusNode));
    expect(focusNode.hasFocus, isTrue);
    expect(field.style?.color, foreground);
    expect(field.cursorColor, foreground);
    expect(field.decoration?.filled, isFalse);
    expect(field.decoration?.border, InputBorder.none);
    expect(field.decoration?.enabledBorder, InputBorder.none);
    expect(field.decoration?.focusedBorder, InputBorder.none);
  });

  testWidgets('clear and optional submit actions follow the query state', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final changes = <String>[];
    var submitCount = 0;
    var clearCount = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          appBar: InlineSearchAppBar(
            controller: controller,
            focusNode: focusNode,
            fieldKey: const Key('search-field'),
            hintText: '输入关键词',
            clearTooltip: '清空',
            clearButtonKey: const Key('clear-search'),
            submitButtonKey: const Key('submit-search'),
            submitTooltip: '搜索',
            onBack: () {},
            onChanged: changes.add,
            onCleared: () => clearCount += 1,
            onSubmit: () => submitCount += 1,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('clear-search')), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('submit-search')))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(const Key('search-field')), '关键词');
    await tester.pump();

    expect(find.byKey(const Key('clear-search')), findsOneWidget);
    await tester.tap(find.byKey(const Key('submit-search')));
    expect(submitCount, 1);

    await tester.tap(find.byKey(const Key('clear-search')));
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(changes, contains(''));
    expect(clearCount, 1);
    expect(focusNode.hasFocus, isTrue);
    expect(find.byKey(const Key('clear-search')), findsNothing);
  });

  testWidgets('large Traditional Chinese search chrome does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController(text: '很長的搜尋關鍵字');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      LocalizedTestApp(
        locale: const Locale('zh', 'TW'),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            appBar: InlineSearchAppBar(
              controller: controller,
              focusNode: focusNode,
              fieldKey: const Key('search-field'),
              hintText: '輸入關鍵字',
              clearTooltip: '清空',
              submitTooltip: '搜尋',
              onSubmit: () {},
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('search-field')), findsOneWidget);
  });
}
