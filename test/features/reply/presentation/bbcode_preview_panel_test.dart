import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/reply/presentation/widgets/bbcode_preview_panel.dart';

void main() {
  testWidgets('BbCodePreviewPanel renders ordinary text', (tester) async {
    await tester.pumpWidget(_buildPanel(source: '普通文本'));

    expect(find.text('普通文本', findRichText: true), findsOneWidget);
  });

  testWidgets('BbCodePreviewPanel renders quote content without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPanel(source: '[quote]引用内容[/quote]'));

    expect(find.textContaining('引用内容', findRichText: true), findsOneWidget);
  });

  testWidgets('BbCodePreviewPanel renders color tag without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildPanel(source: '[color=#999999]灰色内容[/color]'),
    );

    expect(find.text('灰色内容', findRichText: true), findsOneWidget);
  });

  testWidgets('BbCodePreviewPanel keeps url label visible', (tester) async {
    await tester.pumpWidget(
      _buildPanel(source: '[url=https://example.com]链接文字[/url]'),
    );

    expect(find.text('链接文字', findRichText: true), findsOneWidget);
  });

  testWidgets('BbCodePreviewPanel renders stable empty state', (tester) async {
    await tester.pumpWidget(_buildPanel(source: '   '));

    expect(
      find.byKey(const Key('reply-composer-bbcode-preview-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reply-composer-bbcode-preview-empty')),
      findsOneWidget,
    );
  });

  testWidgets('BbCodePreviewPanel falls back to raw source for bad BBCode', (
    tester,
  ) async {
    const badSource = '[b]hello[/i][/b]';
    await tester.pumpWidget(_buildPanel(source: badSource));

    expect(find.text(badSource), findsOneWidget);
  });

  testWidgets('BbCodePreviewPanel disables remote image preview', (tester) async {
    await tester.pumpWidget(
      _buildPanel(source: '[img]https://example.com/a.png[/img]'),
    );

    expect(find.byType(Image), findsNothing);
    expect(
      find.textContaining('https://example.com/a.png', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('BbCodePreviewPanel renders known sticker as asset image', (
    tester,
  ) async {
    const sticker = StickerItem(
      code: '{:9_656:}',
      assetPath: 'assets/stickers/bugcat/Capoo16.gif',
      rawCodePattern: '{:9_656:}',
    );

    await tester.pumpWidget(
      _buildPanel(
        source: '表情{:9_656:}',
        stickers: const [sticker],
      ),
    );

    expect(
      find.byKey(const Key('reply-bbcode-preview-sticker-{:9_656:}')),
      findsOneWidget,
    );
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('BbCodePreviewPanel keeps unknown sticker code as text', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPanel(source: '未知{:9_999:}'));

    expect(find.textContaining('{:9_999:}', findRichText: true), findsOneWidget);
  });
}

Widget _buildPanel({
  required String source,
  ForumBbCodeRenderer renderer = const FlutterBbCodeForumRenderer(),
  List<StickerItem> stickers = const [],
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: BbCodePreviewPanel(
        source: source,
        renderer: renderer,
        stickers: stickers,
      ),
    ),
  );
}
