import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/shared/widgets/shelf/shelf_app_bar.dart';

void main() {
  testWidgets('ShelfAppBar shows title and menu/search actions', (tester) async {
    String? selected;

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          appBar: ShelfAppBar(
            title: '小说书架',
            onSearchTap: () {},
            onMenuSelected: (value) => selected = value,
            menuItems: const [
              PopupMenuItem<String>(
                value: 'add-category',
                child: Text('新建分类'),
              ),
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
}
