import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/shared/widgets/app_popup_menu.dart';

import '../../test_support/localized_test_app.dart';

void main() {
  testWidgets('uses compact content width and leading-aligns CJK labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        theme: AppTheme.light(),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              AppPopupMenuButton<String>(
                key: const Key('menu'),
                itemBuilder: (_) => [
                  AppPopupMenuItem<String>(value: 'refresh', label: '刷新页面'),
                  AppPopupMenuItem<String>(value: 'favorite', label: '收藏本版'),
                  AppPopupMenuItem<String>(value: 'compose', label: '发帖'),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('menu')));
    await tester.pumpAndSettle();

    final item = find.widgetWithText(AppPopupMenuItem<String>, '刷新页面');
    final itemRect = tester.getRect(item);
    final labelRect = tester.getRect(find.text('刷新页面'));

    expect(itemRect.width, lessThan(112));
    expect(
      labelRect.left,
      closeTo(
        itemRect.left + AppPopupMenuLayout.horizontalItemPadding / 2,
        0.01,
      ),
    );
  });

  testWidgets('grows for localized text and stays within narrow screens', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(220, 640),
          textScaler: TextScaler.linear(1.8),
        ),
        child: LocalizedTestApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            appBar: AppBar(
              actions: [
                AppPopupMenuButton<String>(
                  key: const Key('menu'),
                  itemBuilder: (_) => [
                    AppPopupMenuItem<String>(
                      value: 'long',
                      label: '設定自訂漫畫封面圖片',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('menu')));
    await tester.pumpAndSettle();

    final item = find.byType(AppPopupMenuItem<String>);
    expect(tester.getSize(item).width, lessThanOrEqualTo(188));
    expect(tester.takeException(), isNull);
  });
}
