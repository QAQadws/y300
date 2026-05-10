import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/more/presentation/more_page.dart';

void main() {
  testWidgets('MorePage renders stage-1 entries', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: MorePage()),
      ),
    );

    expect(find.text('更多'), findsWidgets);
    expect(find.byKey(const Key('more-login-entry')), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.byKey(const Key('more-cache-settings-entry')), findsNothing);
    expect(find.byKey(const Key('more-data-storage-entry')), findsOneWidget);
    expect(find.text('数据与存储'), findsOneWidget);
    expect(find.text('管理图片缓存与下载位置'), findsOneWidget);
    expect(find.byKey(const Key('more-reader-settings-placeholder')), findsOneWidget);
    expect(find.byKey(const Key('more-about-placeholder')), findsOneWidget);
  });
}
