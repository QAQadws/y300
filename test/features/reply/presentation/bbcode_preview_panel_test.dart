import 'dart:convert';
import 'dart:io';

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
    expect(find.textContaining('{:9_656:}', findRichText: true), findsNothing);
  });

  testWidgets('BbCodePreviewPanel aligns sticker bottom with text', (
    tester,
  ) async {
    const sticker = StickerItem(
      code: '{:9_656:}',
      assetPath: 'assets/stickers/bugcat/Capoo16.gif',
      rawCodePattern: '{:9_656:}',
    );

    await tester.pumpWidget(
      _buildPanel(
        source: '文字{:9_656:}',
        stickers: const [sticker],
      ),
    );

    final stickerSpan = _findWidgetSpan(
      tester.widgetList<RichText>(find.byType(RichText)),
      const Key('reply-bbcode-preview-sticker-{:9_656:}'),
    );

    expect(stickerSpan, isNotNull);
    expect(stickerSpan!.alignment, PlaceholderAlignment.bottom);
  });

  testWidgets('BbCodePreviewPanel hides known sticker code when asset fails', (
    tester,
  ) async {
    const sticker = StickerItem(
      code: '{:9_656:}',
      assetPath: 'assets/stickers/missing.gif',
      rawCodePattern: '{:9_656:}',
    );

    await tester.pumpWidget(
      _buildPanel(
        source: '{:9_656:}',
        stickers: const [sticker],
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.textContaining('{:9_656:}', findRichText: true), findsNothing);
  });

  testWidgets('BbCodePreviewPanel keeps unknown sticker code as text', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPanel(source: '未知{:9_999:}'));

    expect(find.textContaining('{:9_999:}', findRichText: true), findsOneWidget);
  });

  testWidgets('BbCodePreviewPanel renders known attach as local image', (
    tester,
  ) async {
    final file = await _createLocalPreviewImage('known.png');
    final attachment = _uploadedAttachment(aid: '123456', path: file.path);

    await tester.pumpWidget(
      _buildPanel(
        source: '正文\n[attach]123456[/attach]',
        imageAttachments: [attachment],
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(
      find.byKey(const Key('reply-bbcode-preview-attach-123456')),
    );
    expect(image.image, isA<FileImage>());
    expect(find.textContaining('[attach]123456[/attach]', findRichText: true),
        findsNothing);
  });

  testWidgets('BbCodePreviewPanel keeps multiple attach images in source order', (
    tester,
  ) async {
    final first = await _createLocalPreviewImage('first.png');
    final second = await _createLocalPreviewImage('second.png');

    await tester.pumpWidget(
      _buildPanel(
        source: '[attach]111[/attach]\n文字\n[attach]222[/attach]',
        imageAttachments: [
          _uploadedAttachment(aid: '222', path: second.path),
          _uploadedAttachment(aid: '111', path: first.path),
        ],
      ),
    );
    await tester.pump();

    final firstCenter = tester.getCenter(
      find.byKey(const Key('reply-bbcode-preview-attach-111')),
    );
    final secondCenter = tester.getCenter(
      find.byKey(const Key('reply-bbcode-preview-attach-222')),
    );
    expect(firstCenter.dy, lessThan(secondCenter.dy));
  });

  testWidgets('BbCodePreviewPanel does not show broken image for missing file', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildPanel(
        source: '[attach]123456[/attach]',
        imageAttachments: [
          _uploadedAttachment(aid: '123456', path: '/missing/local.png'),
        ],
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reply-bbcode-preview-attach-123456')),
      findsNothing,
    );
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });

  testWidgets('BbCodePreviewPanel keeps invalid attachment statuses as text', (
    tester,
  ) async {
    final file = await _createLocalPreviewImage('failed.png');

    for (final status in [
      ReplyImageAttachmentStatus.local,
      ReplyImageAttachmentStatus.failed,
      ReplyImageAttachmentStatus.expired,
    ]) {
      await tester.pumpWidget(
        _buildPanel(
          source: '[attach]123456[/attach]',
          imageAttachments: [
            _uploadedAttachment(
              aid: '123456',
              path: file.path,
              status: status,
            ),
          ],
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('[attach]123456[/attach]', findRichText: true),
        findsOneWidget);
    }
  });

  testWidgets('BbCodePreviewPanel supports stickers and attach images together', (
    tester,
  ) async {
    const sticker = StickerItem(
      code: '{:9_656:}',
      assetPath: 'assets/stickers/bugcat/Capoo16.gif',
      rawCodePattern: '{:9_656:}',
    );
    final file = await _createLocalPreviewImage('mixed.png');

    await tester.pumpWidget(
      _buildPanel(
        source: '{:9_656:}\n[attach]123456[/attach]',
        stickers: const [sticker],
        imageAttachments: [
          _uploadedAttachment(aid: '123456', path: file.path),
        ],
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reply-bbcode-preview-sticker-{:9_656:}')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reply-bbcode-preview-attach-123456')),
      findsOneWidget,
    );
  });
}

Widget _buildPanel({
  required String source,
  ForumBbCodeRenderer renderer = const FlutterBbCodeForumRenderer(),
  List<StickerItem> stickers = const [],
  List<ReplyImageAttachment> imageAttachments =
      const <ReplyImageAttachment>[],
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: BbCodePreviewPanel(
        source: source,
        renderer: renderer,
        stickers: stickers,
        imageAttachments: imageAttachments,
      ),
    ),
  );
}

Future<File> _createLocalPreviewImage(String fileName) async {
  final directory = await Directory.systemTemp.createTemp('y300-reply-preview-');
  addTearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(base64Decode(_transparentPngBase64));
  return file;
}

ReplyImageAttachment _uploadedAttachment({
  required String aid,
  required String path,
  ReplyImageAttachmentStatus status = ReplyImageAttachmentStatus.uploaded,
}) {
  return ReplyImageAttachment(
    localId: 'local-$aid',
    localPath: path,
    fileName: '$aid.png',
    mimeType: 'image/png',
    order: 0,
    status: status,
    aid: aid,
    uploadedAt: DateTime.utc(2026, 6, 8),
  );
}

const _transparentPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6Q'
    'AAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBh'
    'XY/j//z8DAAj8Av6IXwbgAAAAAElFTkSuQmCC';

WidgetSpan? _findWidgetSpan(Iterable<RichText> richTexts, Key childKey) {
  for (final richText in richTexts) {
    final span = _findWidgetSpanInInlineSpan(richText.text, childKey);
    if (span != null) {
      return span;
    }
  }
  return null;
}

WidgetSpan? _findWidgetSpanInInlineSpan(InlineSpan span, Key childKey) {
  if (span is WidgetSpan && span.child.key == childKey) {
    return span;
  }
  final children = span is TextSpan ? span.children : null;
  if (children == null) {
    return null;
  }
  for (final child in children) {
    final match = _findWidgetSpanInInlineSpan(child, childKey);
    if (match != null) {
      return match;
    }
  }
  return null;
}
