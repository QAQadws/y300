import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_card.dart';

void main() {
  testWidgets('ShelfCoverCard renders title and badge with fallback background', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 180,
            child: ShelfCoverCard(
              title: '测试标题',
              coverImageUrl: null,
              onTap: () {},
              topLeftBadge: const Text('角标'),
              fallbackBackground: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF000000), Color(0xFF333333)],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('测试标题'), findsOneWidget);
    expect(find.text('角标'), findsOneWidget);
    expect(find.byType(ShelfCoverCard), findsOneWidget);
  });

  testWidgets('ShelfCoverCard supports custom two-line ellipsis mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 180,
            child: ShelfCoverCard(
              title: '这是一个非常非常长的标题用于验证通用书架卡片的两行中文省略逻辑是否生效',
              coverImageUrl: null,
              onTap: () {},
              showTwoLineCustomEllipsis: true,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('···'), findsOneWidget);
  });
}
