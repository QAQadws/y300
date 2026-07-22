import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_card.dart';
import 'package:y300/shared/widgets/shelf/shelf_theme_palette.dart';

void main() {
  testWidgets(
    'ShelfCoverCard renders title and badge with fallback background',
    (tester) async {
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
      expect(
        tester.widget<Text>(find.text('测试标题')).style?.fontWeight,
        FontWeight.w500,
      );
      expect(find.text('角标'), findsOneWidget);
      expect(find.byType(ShelfCoverCard), findsOneWidget);
    },
  );

  testWidgets('ShelfCoverCard supports custom two-line ellipsis mode', (
    tester,
  ) async {
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

  testWidgets('ShelfCoverCard uses shelf placeholder color from app theme', (
    tester,
  ) async {
    final theme = AppTheme.dark();
    final palette = const ShelfThemePaletteResolver().resolve(theme);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 180,
            child: ShelfCoverCard(
              title: 'No Cover',
              coverImageUrl: null,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    final fallback = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Icons.image_not_supported_outlined),
            matching: find.byType(Container),
          )
          .first,
    );

    expect(fallback.color, palette.coverPlaceholderBackground);
  });

  testWidgets('ShelfCoverCard applies focus only to custom covers', (
    tester,
  ) async {
    final alignments = <AlignmentGeometry>[];

    Future<void> pumpCard({
      String? customCoverLocalPath,
      double? focusX,
      double? focusY,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 180,
              child: ShelfCoverCard(
                title: 'Focused Cover',
                coverImageUrl: 'https://example.com/cover.jpg',
                customCoverLocalPath: customCoverLocalPath,
                customCoverFocusX: focusX,
                customCoverFocusY: focusY,
                onTap: () {},
                coverLayerBuilder: (context, config) {
                  alignments.add(config.alignment);
                  return config.placeholder;
                },
              ),
            ),
          ),
        ),
      );
    }

    await pumpCard(
      customCoverLocalPath: 'cache/custom-cover.jpg',
      focusX: 0.75,
      focusY: -0.5,
    );
    expect(alignments.last, const Alignment(0.75, -0.5));

    await pumpCard(focusX: 0.75, focusY: -0.5);
    expect(alignments.last, Alignment.center);

    await pumpCard(customCoverLocalPath: 'cache/custom-cover.jpg', focusX: 1);
    expect(alignments.last, Alignment.center);
  });
}
