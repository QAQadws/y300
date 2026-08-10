import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/shared/widgets/app_popup_menu.dart';
import 'package:y300/shared/widgets/shelf/shelf_app_bar.dart';

void main() {
  testWidgets('ShelfAppBar shows title and menu/search actions', (
    tester,
  ) async {
    String? selected;

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          appBar: ShelfAppBar(
            title: '小说书架',
            onSearchTap: () {},
            onMenuSelected: (value) => selected = value,
            menuItems: [
              AppPopupMenuItem<String>(value: 'add-category', label: '新建分类'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('小说书架'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);

    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    expect(find.text('新建分类'), findsOneWidget);

    await tester.tap(find.text('新建分类'));
    await tester.pumpAndSettle();

    expect(selected, 'add-category');
  });

  testWidgets('ShelfAppBar localizes default tooltips', (tester) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        locale: Locale('zh', 'TW'),
        home: Scaffold(appBar: ShelfAppBar(title: 'Raw title')),
      ),
    );

    expect(find.byTooltip('搜尋'), findsOneWidget);
    expect(find.byTooltip('選單'), findsOneWidget);
    expect(find.text('Raw title'), findsOneWidget);
  });
}
