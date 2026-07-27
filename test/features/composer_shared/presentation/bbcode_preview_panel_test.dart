import 'dart:io';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/bbcode_preview_panel.dart';

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
    await tester.pumpWidget(_buildPanel(source: '[color=#999999]灰色内容[/color]'));

    expect(find.text('灰色内容', findRichText: true), findsOneWidget);
  });

  testWidgets('BbCodePreviewPanel renders Discuz backcolor tag', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildPanel(source: '[backcolor=#fff3b0]高亮内容[/backcolor]'),
    );

    final span = _findTextSpanWithText(
      tester.widgetList<RichText>(find.byType(RichText)),
      '高亮内容',
    );
    expect(span?.style?.backgroundColor, const Color(0xfffff3b0));
  });

  testWidgets('BbCodePreviewPanel renders Discuz size tag', (tester) async {
    await tester.pumpWidget(_buildPanel(source: '[size=5]大字[/size]'));

    final span = _findTextSpanWithText(
      tester.widgetList<RichText>(find.byType(RichText)),
      '大字',
    );
    expect(span?.style?.fontSize, 17.5);
  });

  testWidgets('BbCodePreviewPanel renders Discuz size 3 as body size', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPanel(source: '普通[size=3]默认字[/size]'));

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final ordinaryFontSize = _resolvedFontSizeForText(richTexts, '普通');
    final sizeThreeFontSize = _resolvedFontSizeForText(richTexts, '默认字');

    expect(sizeThreeFontSize, ordinaryFontSize);
  });

  testWidgets('BbCodePreviewPanel falls back invalid Discuz size to 3', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPanel(source: '[size=99]默认字[/size]'));

    final span = _findTextSpanWithText(
      tester.widgetList<RichText>(find.byType(RichText)),
      '默认字',
    );
    expect(span?.style?.fontSize, 14);
  });

  testWidgets('BbCodePreviewPanel renders Discuz align tag', (tester) async {
    await tester.pumpWidget(_buildPanel(source: '[align=center]居中内容[/align]'));

    final alignBox = tester.widget<SizedBox>(
      find.byKey(const Key('reply-bbcode-preview-align-center')),
    );
    expect(alignBox.width, double.infinity);
    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const Key('reply-bbcode-preview-align-center')),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.textAlign, TextAlign.center);
    expect(find.text('居中内容', findRichText: true), findsOneWidget);
  });

  testWidgets('BbCodePreviewPanel renders Discuz code tag as raw text', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPanel(source: '[code][b]raw[/b][/code]'));

    expect(
      find.byKey(const Key('reply-bbcode-preview-code-block')),
      findsOneWidget,
    );
    expect(find.text('[b]raw[/b]'), findsOneWidget);
    expect(find.text('raw', findRichText: true), findsNothing);
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

  testWidgets('BbCodePreviewPanel renders without framed decoration', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPanel(source: '普通文本'));

    final panel = tester.widget<Container>(
      find.byKey(const Key('reply-composer-bbcode-preview-panel')),
    );
    expect(panel.decoration, isNull);
    expect(panel.padding, isNull);
  });

  testWidgets('BbCodePreviewPanel falls back to raw source for bad BBCode', (
    tester,
  ) async {
    const badSource = '[b]hello[/i][/b]';
    await tester.pumpWidget(_buildPanel(source: badSource));

    expect(find.text(badSource), findsOneWidget);
  });

  testWidgets('BbCodePreviewPanel disables remote image preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildPanel(source: '[img]https://example.com/a.png[/img]'),
    );

    expect(find.byType(Image), findsNothing);
    expect(
      find.textContaining('https://example.com/a.png', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('BbCodePreviewPanel renders known sticker with preview builder', (
    tester,
  ) async {
    final sticker = _sticker();

    await tester.pumpWidget(
      _buildPanel(source: '表情{:9_656:}', stickers: [sticker]),
    );

    expect(
      find.byKey(const Key('reply-bbcode-preview-sticker-{:9_656:}')),
      findsOneWidget,
    );
    expect(find.byType(_TestStickerPreviewImage), findsOneWidget);
    expect(find.textContaining('{:9_656:}', findRichText: true), findsNothing);
  });

  testWidgets('BbCodePreviewPanel aligns sticker bottom with text', (
    tester,
  ) async {
    final sticker = _sticker();

    await tester.pumpWidget(
      _buildPanel(source: '文字{:9_656:}', stickers: [sticker]),
    );

    final stickerSpan = _findWidgetSpan(
      tester.widgetList<RichText>(find.byType(RichText)),
      const Key('reply-bbcode-preview-sticker-{:9_656:}'),
    );

    expect(stickerSpan, isNotNull);
    expect(stickerSpan!.alignment, PlaceholderAlignment.bottom);
  });

  testWidgets('BbCodePreviewPanel hides known sticker code when image fails', (
    tester,
  ) async {
    final sticker = _sticker(imagePath: 'missing/missing.gif');

    await tester.pumpWidget(
      _buildPanel(
        source: '{:9_656:}',
        renderer: FlutterBbCodeForumRenderer(
          stickerImageBuilder: (_, key) {
            return Icon(Icons.broken_image_outlined, key: key);
          },
        ),
        stickers: [sticker],
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

    expect(
      find.textContaining('{:9_999:}', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('BbCodePreviewPanel renders known attach as local image', (
    tester,
  ) async {
    const path = 'E:/test/reply/known.png';
    final attachment = _uploadedAttachment(aid: '123456', path: path);

    await tester.pumpWidget(
      _buildPanel(
        source: '正文\n[attach]123456[/attach]',
        imageAttachments: [attachment],
      ),
    );
    await tester.pump();

    final previewImage = tester.widget<_TestAttachPreviewImage>(
      find.byKey(const Key('reply-bbcode-preview-attach-123456')),
    );
    expect(previewImage.file.path, path);
    expect(
      find.textContaining('[attach]123456[/attach]', findRichText: true),
      findsNothing,
    );
  });

  testWidgets(
    'BbCodePreviewPanel keeps multiple attach images in source order',
    (tester) async {
      const firstPath = 'E:/test/reply/first.png';
      const secondPath = 'E:/test/reply/second.png';

      await tester.pumpWidget(
        _buildPanel(
          source: '[attach]111[/attach]\n文字\n[attach]222[/attach]',
          imageAttachments: [
            _uploadedAttachment(aid: '222', path: secondPath),
            _uploadedAttachment(aid: '111', path: firstPath),
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
    },
  );

  testWidgets(
    'BbCodePreviewPanel does not show broken image for missing file',
    (tester) async {
      await tester.pumpWidget(
        _buildPanel(
          source: '[attach]123456[/attach]',
          renderer: FlutterBbCodeForumRenderer(
            attachImageBuilder: _buildTestAttachPreviewImage,
          ),
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
    },
  );

  testWidgets('BbCodePreviewPanel keeps invalid attachment statuses as text', (
    tester,
  ) async {
    const path = 'E:/test/reply/failed.png';

    for (final status in [
      ComposerImageAttachmentStatus.local,
      ComposerImageAttachmentStatus.failed,
      ComposerImageAttachmentStatus.expired,
    ]) {
      await tester.pumpWidget(
        _buildPanel(
          source: '[attach]123456[/attach]',
          imageAttachments: [
            _uploadedAttachment(aid: '123456', path: path, status: status),
          ],
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(
        find.textContaining('[attach]123456[/attach]', findRichText: true),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'BbCodePreviewPanel supports stickers and attach images together',
    (tester) async {
      final sticker = _sticker();
      const path = 'E:/test/reply/mixed.png';

      await tester.pumpWidget(
        _buildPanel(
          source: '{:9_656:}\n[attach]123456[/attach]',
          stickers: [sticker],
          imageAttachments: [_uploadedAttachment(aid: '123456', path: path)],
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
    },
  );
}

Widget _buildPanel({
  required String source,
  ForumBbCodeRenderer? renderer,
  List<StickerItem> stickers = const [],
  List<ComposerImageAttachment> imageAttachments =
      const <ComposerImageAttachment>[],
}) {
  return LocalizedTestApp(
    theme: AppTheme.light(),
    home: ProviderScope(
      overrides: [
        imageCacheServiceProvider.overrideWithValue(
          _FailingImageCacheService(),
        ),
      ],
      child: Scaffold(
        body: BbCodePreviewPanel(
          source: source,
          renderer: renderer ?? _testRenderer,
          stickers: stickers,
          imageAttachments: imageAttachments,
        ),
      ),
    ),
  );
}

StickerItem _sticker({
  String code = '{:9_656:}',
  String imagePath = 'bugcat/Capoo16.gif',
}) {
  return StickerItem(
    code: code,
    rawCodePattern: code,
    imagePath: imagePath,
    imageUrl: 'https://bbs.yamibo.com/static/image/smiley/$imagePath',
    cacheKey: ImageCacheKeys.remoteSmiley(imagePath),
  );
}

ComposerImageAttachment _uploadedAttachment({
  required String aid,
  required String path,
  ComposerImageAttachmentStatus status = ComposerImageAttachmentStatus.uploaded,
}) {
  return ComposerImageAttachment(
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

final _testRenderer = FlutterBbCodeForumRenderer(
  attachImageBuilder: _buildTestAttachPreviewImage,
  attachFileExists: _testAttachFileExists,
  stickerImageBuilder: _buildTestStickerPreviewImage,
);

Widget _buildTestAttachPreviewImage(File file, Key key) {
  return _TestAttachPreviewImage(file: file, key: key);
}

Widget _buildTestStickerPreviewImage(StickerItem sticker, Key key) {
  return _TestStickerPreviewImage(sticker: sticker, key: key);
}

bool _testAttachFileExists(File file) {
  return !file.path.contains('/missing/');
}

class _TestAttachPreviewImage extends StatelessWidget {
  const _TestAttachPreviewImage({super.key, required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 28, height: 28);
  }
}

class _TestStickerPreviewImage extends StatelessWidget {
  const _TestStickerPreviewImage({super.key, required this.sticker});

  final StickerItem sticker;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 28, height: 28);
  }
}

class _FailingImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
}

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

TextSpan? _findTextSpanWithText(Iterable<RichText> richTexts, String text) {
  for (final richText in richTexts) {
    final span = _findTextSpanInInlineSpan(richText.text, text);
    if (span != null) {
      return span;
    }
  }
  return null;
}

TextSpan? _findTextSpanInInlineSpan(InlineSpan span, String text) {
  if (span is TextSpan && span.text == text) {
    return span;
  }
  final children = span is TextSpan ? span.children : null;
  if (children == null) {
    return null;
  }
  for (final child in children) {
    final match = _findTextSpanInInlineSpan(child, text);
    if (match != null) {
      return match;
    }
  }
  return null;
}

double? _resolvedFontSizeForText(Iterable<RichText> richTexts, String text) {
  for (final richText in richTexts) {
    final fontSize = _resolvedFontSizeInInlineSpan(
      richText.text,
      text,
      richText.text.style?.fontSize,
    );
    if (fontSize != null) {
      return fontSize;
    }
  }
  return null;
}

double? _resolvedFontSizeInInlineSpan(
  InlineSpan span,
  String text,
  double? inheritedFontSize,
) {
  if (span is! TextSpan) {
    return null;
  }
  final currentFontSize = span.style?.fontSize ?? inheritedFontSize;
  if (span.text == text) {
    return currentFontSize;
  }
  final children = span.children;
  if (children == null) {
    return null;
  }
  for (final child in children) {
    final match = _resolvedFontSizeInInlineSpan(child, text, currentFontSize);
    if (match != null) {
      return match;
    }
  }
  return null;
}
