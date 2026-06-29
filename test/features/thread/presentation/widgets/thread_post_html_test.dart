import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_document_normalizer.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_parser.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';

Widget _testApp({required Widget home}) {
  return ProviderScope(
    overrides: [
      imageCacheServiceProvider.overrideWithValue(_FailingImageCacheService()),
    ],
    child: MaterialApp(home: home),
  );
}

Widget _testAppWithCacheService({
  required ImageCacheService imageCacheService,
  required Widget home,
}) {
  return ProviderScope(
    overrides: [imageCacheServiceProvider.overrideWithValue(imageCacheService)],
    child: MaterialApp(home: home),
  );
}

void main() {
  test('ThreadPostBodyStyle uses smaller default image radius', () {
    expect(
      ThreadPostBodyStyle.defaults.imageBorderRadius,
      const BorderRadius.all(Radius.circular(4)),
    );
  });

  testWidgets(
    'ThreadPostHtml renders post images through request header builder',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          home: Center(
            child: SizedBox(
              width: 140,
              child: ThreadPostHtml(
                data: '<img file="data/attachment/forum/page-1.jpg" />',
                imageHeaderBuilder: const _StaticImageHeaderBuilder(
                  <String, String>{
                    'Referer': 'https://bbs.yamibo.com/',
                    'Cookie': 'auth=token123',
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.image,
        isA<NetworkImage>().having(
          (provider) => provider.url,
          'url',
          'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
        ),
      );
      final provider = image.image as NetworkImage;
      expect(provider.headers, <String, String>{
        'Referer': 'https://bbs.yamibo.com/',
        'Cookie': 'auth=token123',
      });
    },
  );

  testWidgets(
    'ThreadPostHtml renders text blocks without selection diagnostics',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          home: const ThreadPostHtml(
            data:
                '<p>第一段 <strong>重点</strong></p><p><a href="thread-1-1-1.html">链接</a></p>',
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(SelectionArea), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(_postRichTexts(), findsNWidgets(2));
      expect(_postRichTextPlainTexts(tester), contains('第一段重点'));
      expect(_postRichTextPlainTexts(tester), contains('链接'));
    },
  );

  testWidgets('ThreadPostBodyView only creates SelectionArea when enabled', (
    tester,
  ) async {
    const document = ThreadPostBodyDocument(
      blocks: <ThreadPostBodyBlock>[
        ThreadPostTextBlock(
          runs: <ThreadPostTextRun>[ThreadPostTextRun(text: '可复制正文')],
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(
        home: ThreadPostBodyView(
          document: document,
          blocks: document.blocks,
          images: <ThreadPostImageBlock>[],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SelectionArea), findsNothing);
    expect(
      tester.widget<RichText>(find.byType(RichText)).selectionRegistrar,
      isNull,
    );

    await tester.pumpWidget(
      _testApp(
        home: ThreadPostBodyView(
          document: document,
          blocks: document.blocks,
          images: <ThreadPostImageBlock>[],
          selectionEnabled: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(
      tester.widget<RichText>(find.byType(RichText)).selectionRegistrar,
      isNotNull,
    );
  });

  testWidgets('ThreadPostBodyView wires quote text into selection mode', (
    tester,
  ) async {
    const document = ThreadPostBodyDocument(
      blocks: <ThreadPostBodyBlock>[
        ThreadPostQuoteBlock(
          blocks: <ThreadPostBodyBlock>[
            ThreadPostTextBlock(
              runs: <ThreadPostTextRun>[ThreadPostTextRun(text: '引用正文')],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(
        home: ThreadPostBodyView(
          document: document,
          blocks: document.blocks,
          images: <ThreadPostImageBlock>[],
          selectionEnabled: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ThreadPostQuoteBlockView), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(
      tester.widget<RichText>(find.byType(RichText)).selectionRegistrar,
      isNotNull,
    );
  });

  testWidgets('ThreadPostBodyView avoids selection area for image-only body', (
    tester,
  ) async {
    const imageBlock = ThreadPostImageBlock(
      url: 'https://bbs.yamibo.com/data/attachment/forum/page.jpg',
      rawUrl: 'data/attachment/forum/page.jpg',
      index: 0,
    );
    const document = ThreadPostBodyDocument(
      blocks: <ThreadPostBodyBlock>[imageBlock],
    );

    await tester.pumpWidget(
      _testApp(
        home: Center(
          child: SizedBox(
            width: 140,
            child: ThreadPostBodyView(
              document: document,
              blocks: document.blocks,
              images: <ThreadPostImageBlock>[imageBlock],
              selectionEnabled: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SelectionArea), findsNothing);
    expect(
      find.ancestor(
        of: find.byKey(const Key('thread-post-image-0')),
        matching: find.byType(SelectionContainer),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ThreadPostHtml renders reply quote as a quote block', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        home: const ThreadPostHtml(
          data:
              '<div class="quote"><blockquote><b>thessky</b>: 引用正文<br />第二行</blockquote></div><p>回复正文</p>',
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(ThreadPostQuoteBlockView), findsOneWidget);
    expect(_postRichTextPlainTexts(tester), contains('thessky: 引用正文'));
    expect(_postRichTextPlainTexts(tester), contains('第二行'));
    expect(_postRichTextPlainTexts(tester), contains('回复正文'));
  });

  testWidgets('ThreadPostHtml renders smiley gif as inline image', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        home: ThreadPostHtml(
          data:
              '那篇很好啊我很喜欢 <img src="static/image/smiley/comcom/2.gif" class="vm">',
          imageHeaderBuilder: const _StaticImageHeaderBuilder(<String, String>{
            'Referer': 'https://bbs.yamibo.com/',
          }),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(ThreadPostImageBlockView), findsNothing);
    final inlineImages = find.byWidgetPredicate(
      (widget) =>
          widget is CachedLibraryImage &&
          widget.request?.sourceUrl ==
              'https://bbs.yamibo.com/static/image/smiley/comcom/2.gif',
    );
    expect(inlineImages, findsOneWidget);
    final richText = tester.widget<RichText>(_postRichTexts());
    final rootSpan = richText.text as TextSpan;
    final stickerSpan = rootSpan.children!.whereType<WidgetSpan>().single;
    expect(stickerSpan.alignment, PlaceholderAlignment.bottom);
    final fixedSmileyBoxes = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((box) => box.width == 24 && box.height == 24);
    expect(fixedSmileyBoxes, isEmpty);
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.headers?['Referer'], 'https://bbs.yamibo.com/');
    expect(
      _postRichTextPlainTexts(tester).any((text) => text.contains('那篇很好啊我很喜欢')),
      isTrue,
    );
  });

  testWidgets('ThreadPostHtml uses parsed smiley dimensions when available', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        home: const ThreadPostHtml(
          data:
              '喜欢 <img src="static/image/smiley/comcom/2.gif" width="32" height="18">',
        ),
      ),
    );

    await tester.pump();

    final fixedSmileyBoxes = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((box) => box.width == 32 && box.height == 18);
    expect(fixedSmileyBoxes, isNotEmpty);
  });

  testWidgets('ThreadPostHtml reuses cached smiley dimensions when available', (
    tester,
  ) async {
    final cacheService = _SizedImageCacheService(<String, CachedImageResult>{
      'smiley-comcom-2': const CachedImageResult(
        success: true,
        cacheKey: 'smiley-comcom-2',
        width: 40,
        height: 22,
      ),
    });
    await tester.pumpWidget(
      _testAppWithCacheService(
        imageCacheService: cacheService,
        home: ThreadPostHtml(
          data: '喜欢 <img src="static/image/smiley/comcom/2.gif">',
          inlineImageCacheRequestBuilder: (_) => const ImageCacheRequest(
            cacheKey: 'smiley-comcom-2',
            sourceUrl:
                'https://bbs.yamibo.com/static/image/smiley/comcom/2.gif',
            ownerType: ImageCacheOwnerType.sticker,
            ownerId: 'yamibo-smiley-v4',
            role: ImageCacheRole.remoteSmiley,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final smileyBoxes = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((box) => box.width == 40 && box.height == 22);
    expect(smileyBoxes, isNotEmpty);
  });

  testWidgets(
    'ThreadPostHtml ignores async cached smiley dimensions when layout is locked',
    (tester) async {
      final cacheService = _SizedImageCacheService(<String, CachedImageResult>{
        'smiley-comcom-2': const CachedImageResult(
          success: true,
          cacheKey: 'smiley-comcom-2',
          width: 40,
          height: 22,
        ),
      });
      await tester.pumpWidget(
        _testAppWithCacheService(
          imageCacheService: cacheService,
          home: ThreadPostHtml(
            data: '喜欢 <img src="static/image/smiley/comcom/2.gif">',
            resourceLayoutPolicy:
                ThreadPostResourceLayoutPolicy.lockedForReading,
            inlineImageCacheRequestBuilder: (_) => const ImageCacheRequest(
              cacheKey: 'smiley-comcom-2',
              sourceUrl:
                  'https://bbs.yamibo.com/static/image/smiley/comcom/2.gif',
              ownerType: ImageCacheOwnerType.sticker,
              ownerId: 'yamibo-smiley-v4',
              role: ImageCacheRole.remoteSmiley,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      final smileyBoxes = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((box) => box.width == 40 && box.height == 22);
      expect(smileyBoxes, isEmpty);
    },
  );

  testWidgets('ThreadPostHtml caches parsed document across rebuilds', (
    tester,
  ) async {
    final parser = _CountingThreadPostBodyParser();
    final normalizer = _CountingThreadPostBodyDocumentNormalizer();
    await tester.pumpWidget(
      _testApp(
        home: ThreadPostHtml(
          data: '<p>正文</p>',
          parser: parser,
          normalizer: normalizer,
        ),
      ),
    );
    await tester.pumpWidget(
      _testApp(
        home: ThreadPostHtml(
          data: '<p>正文</p>',
          parser: parser,
          normalizer: normalizer,
        ),
      ),
    );

    expect(parser.parseCount, 1);
    expect(normalizer.normalizeCount, 1);
    expect(_postRichTextPlainTexts(tester), contains('正文'));
  });

  testWidgets(
    'ThreadPostHtml reparses when render settings signature changes',
    (tester) async {
      final parser = _CountingThreadPostBodyParser();
      final normalizer = _CountingThreadPostBodyDocumentNormalizer();
      await tester.pumpWidget(
        _testApp(
          home: ThreadPostHtml(
            data: '<p>正文</p>',
            parser: parser,
            normalizer: normalizer,
          ),
        ),
      );
      await tester.pumpWidget(
        _testApp(
          home: ThreadPostHtml(
            data: '<p>正文</p>',
            parser: parser,
            normalizer: normalizer,
            renderSettings: ThreadPostBodyRenderSettings.defaults.copyWith(
              fontSize: 20,
            ),
          ),
        ),
      );

      expect(parser.parseCount, 2);
      expect(normalizer.normalizeCount, 2);
      final rootSpan =
          tester.widget<RichText>(_postRichTexts()).text as TextSpan;
      final bodySpan = rootSpan.children!.single as TextSpan;
      expect(bodySpan.style?.fontSize, 20);
    },
  );

  testWidgets('ThreadPostHtml splits long text without adding block spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        home: const ThreadPostHtml(
          data: '<p>abcdefghijk</p>',
          normalizer: ThreadPostBodyDocumentNormalizer(maxTextRunLength: 4),
        ),
      ),
    );

    await tester.pump();

    expect(_postRichTexts(), findsNWidgets(3));
    expect(_postRichTextPlainTexts(tester).join(), 'abcdefghijk');
    final spacers = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where(
          (box) => box.height == ThreadPostBodyStyle.defaults.blockSpacing,
        );
    expect(spacers, isEmpty);
  });

  testWidgets('ThreadPostHtml treats bare blockquote as a quote block', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        home: const ThreadPostHtml(
          data: '<blockquote><strong>作者</strong>: 独立引用</blockquote>',
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(ThreadPostQuoteBlockView), findsOneWidget);
    expect(_postRichTextPlainTexts(tester), contains('作者: 独立引用'));
  });

  testWidgets('ThreadPostHtml applies style and text transformer hooks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        home: ThreadPostHtml(
          data: '<p>第一段</p><p>第二段</p>',
          textTransformer: (text) => text.replaceAll('第一', '第壹'),
          style: const ThreadPostBodyStyle(
            blockSpacing: 18,
            textStyle: TextStyle(fontSize: 19),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(
      _postRichTextPlainTexts(tester),
      containsAll(<String>['第壹段', '第二段']),
    );

    final firstText = tester.widgetList<RichText>(_postRichTexts()).first;
    expect(firstText.selectionRegistrar, isNull);

    final firstRootSpan = firstText.text as TextSpan;
    final firstSpan = firstRootSpan.children!.single as TextSpan;
    expect(firstSpan.style?.fontSize, 19);

    final spacers = tester.widgetList<SizedBox>(find.byType(SizedBox));
    expect(spacers.any((box) => box.height == 18), isTrue);
  });

  testWidgets('ThreadPostHtml renders Discuz edit status more quietly', (
    tester,
  ) async {
    const bodyStyle = TextStyle(fontSize: 20, color: Colors.black);
    await tester.pumpWidget(
      _testApp(
        home: const DefaultTextStyle(
          style: bodyStyle,
          child: ThreadPostHtml(
            data:
                '<i class="pstatus"> 本帖最后由 GuGu_ 于 2026-6-16 01:41 编辑 </i><br /><p>正文</p>',
          ),
        ),
      ),
    );

    await tester.pump();

    final editText = tester.widget<RichText>(_postRichTexts().first);
    final editRootSpan = editText.text as TextSpan;
    final editSpan = editRootSpan.children!.single as TextSpan;
    expect(editSpan.text, '本帖最后由 GuGu_ 于 2026-6-16 01:41 编辑');
    expect(editSpan.style?.fontStyle, FontStyle.italic);
    expect(editSpan.style?.fontSize, lessThan(bodyStyle.fontSize!));
    expect(editSpan.style?.color?.a, lessThan(bodyStyle.color!.a));

    final bodyText = tester.widget<RichText>(_postRichTexts().last);
    final bodyRootSpan = bodyText.text as TextSpan;
    final bodySpan = bodyRootSpan.children!.single as TextSpan;
    expect(bodySpan.text, '正文');
    expect(bodySpan.style?.fontSize, bodyStyle.fontSize);
    expect(bodySpan.style?.color, bodyStyle.color);
  });

  testWidgets('ThreadPostHtml exposes link tap callback', (tester) async {
    String? openedUrl;
    await tester.pumpWidget(
      _testApp(
        home: ThreadPostHtml(
          data: '<a href="thread-1-1-1.html">链接</a>',
          onOpenLink: (url) => openedUrl = url,
        ),
      ),
    );

    await tester.pump();
    final text = tester.widget<RichText>(_postRichTexts());
    final rootSpan = text.text as TextSpan;
    final linkSpan = rootSpan.children!.single as TextSpan;
    (linkSpan.recognizer! as TapGestureRecognizer).onTap?.call();

    expect(openedUrl, 'https://bbs.yamibo.com/thread-1-1-1.html');
  });

  testWidgets(
    'ThreadPostHtml normalizes lazy-load attributes with shared defaults',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          home: Center(
            child: SizedBox(
              width: 140,
              child: ThreadPostHtml(
                data:
                    '<img data-original="//bbs.yamibo.com/data/attachment/forum/page-2.jpg" />',
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.image,
        isA<NetworkImage>().having(
          (provider) => provider.url,
          'url',
          'https://bbs.yamibo.com/data/attachment/forum/page-2.jpg',
        ),
      );
    },
  );

  testWidgets(
    'ThreadPostHtml prefers desktop attachment file over placeholder src',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          home: Center(
            child: SizedBox(
              width: 140,
              child: ThreadPostHtml(
                data:
                    '<img src="static/image/common/none.gif" file="data/attachment/forum/page-real.jpg" />',
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.image,
        isA<NetworkImage>().having(
          (provider) => provider.url,
          'url',
          'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
        ),
      );
    },
  );

  testWidgets(
    'ThreadPostHtml handles real desktop ignore_js_op attachment image blocks',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          home: Center(
            child: SizedBox(
              width: 140,
              child: ThreadPostHtml(
                data: '''
<ignore_js_op>
  <img id="aimg_1597001"
       aid="1597001"
       src="static/image/common/none.gif"
       zoomfile="data/attachment/forum/202606/03/070117ka05z5dcpjl0prsp.jpg"
       file="data/attachment/forum/202606/03/070117ka05z5dcpjl0prsp.jpg"
       class="zoom"
       width="900"
       inpost="1" />
</ignore_js_op>
''',
                imageHeaderBuilder: const _StaticImageHeaderBuilder(
                  <String, String>{
                    'Referer': 'https://bbs.yamibo.com/',
                    'Cookie': 'auth=token123',
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(CachedLibraryImage), findsOneWidget);
      expect(find.byKey(const Key('thread-post-image-0')), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.image,
        isA<NetworkImage>().having(
          (provider) => provider.url,
          'url',
          'https://bbs.yamibo.com/data/attachment/forum/202606/03/070117ka05z5dcpjl0prsp.jpg',
        ),
      );
      final provider = image.image as NetworkImage;
      expect(provider.headers?['Cookie'], 'auth=token123');
    },
  );

  testWidgets(
    'ThreadPostHtml uses full-width 7/10 placeholders for post images',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          home: Center(
            child: SizedBox(
              width: 140,
              child: ThreadPostHtml(
                data: '''
<img file="data/attachment/forum/page-1.jpg" />
<img file="data/attachment/forum/page-2.jpg" />
''',
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      final imageBlocks = find.byType(ThreadPostImageBlockView);
      expect(imageBlocks, findsNWidgets(2));
      final firstSize = tester.getSize(imageBlocks.first);
      expect(firstSize.width, 140);
      expect(firstSize.width / firstSize.height, closeTo(0.7, 0.01));

      final defaultSpacers = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where(
            (box) => box.height == ThreadPostBodyStyle.defaults.blockSpacing,
          );
      expect(defaultSpacers.length, greaterThanOrEqualTo(1));
    },
  );

  testWidgets(
    'ThreadPostImageBlockView updates unknown fallback ratio after image resolves',
    (tester) async {
      final image = await tester.runAsync(
        () => createTestImage(width: 1000, height: 500, cache: false),
      );
      final testImage = image!;
      addTearDown(testImage.dispose);
      final provider = _SynchronousImageProvider(testImage);
      const imageBlock = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
        rawUrl: 'data/attachment/forum/page-real.jpg',
        index: 0,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[imageBlock],
      );

      await tester.pumpWidget(
        _testApp(
          home: Center(
            child: SizedBox(
              width: 350,
              child: ThreadPostImageBlockView(
                document: document,
                image: imageBlock,
                images: <ThreadPostImageBlock>[imageBlock],
                imageProviderOverride: provider,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      final imageBlockSize = tester.getSize(
        find.byType(ThreadPostImageBlockView),
      );
      expect(imageBlockSize.width, 350);
      expect(imageBlockSize.width / imageBlockSize.height, closeTo(2.0, 0.01));
      final cachedImage = tester.widget<LibraryCachedImage>(
        find.byType(LibraryCachedImage),
      );
      expect(cachedImage.fit, BoxFit.fitWidth);
    },
  );

  testWidgets(
    'ThreadPostImageBlockView starts unknown images with fallback ratio before resolve',
    (tester) async {
      const imageBlock = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
        rawUrl: 'data/attachment/forum/page-real.jpg',
        index: 0,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[imageBlock],
      );

      await tester.pumpWidget(
        _testApp(
          home: const Center(
            child: SizedBox(
              width: 350,
              child: ThreadPostImageBlockView(
                document: document,
                image: imageBlock,
                images: <ThreadPostImageBlock>[imageBlock],
              ),
            ),
          ),
        ),
      );

      final imageBlockSize = tester.getSize(
        find.byType(ThreadPostImageBlockView),
      );
      expect(imageBlockSize.width, 350);
      expect(imageBlockSize.width / imageBlockSize.height, closeTo(0.7, 0.01));
    },
  );

  testWidgets(
    'ThreadPostImageBlockView delays loading spinner until threshold',
    (tester) async {
      const imageBlock = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
        rawUrl: 'data/attachment/forum/page-real.jpg',
        index: 0,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[imageBlock],
      );

      await tester.pumpWidget(
        _testApp(
          home: Center(
            child: SizedBox(
              width: 350,
              child: ThreadPostImageBlockView(
                document: document,
                image: imageBlock,
                images: <ThreadPostImageBlock>[imageBlock],
                imageHeaderBuilder: const _DelayedImageHeaderBuilder(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('图片加载中'), findsNothing);
      expect(
        find.byKey(const Key('thread-post-image-loading-spinner')),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 349));
      expect(
        find.byKey(const Key('thread-post-image-loading-spinner')),
        findsNothing,
      );

      await tester.pump(const Duration(milliseconds: 1));
      expect(
        find.byKey(const Key('thread-post-image-loading-spinner')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      _DelayedImageHeaderBuilder.completePending();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'ThreadPostImageBlockView does not show delayed spinner when image resolves quickly',
    (tester) async {
      final image = await tester.runAsync(
        () => createTestImage(width: 1000, height: 500, cache: false),
      );
      final testImage = image!;
      addTearDown(testImage.dispose);
      final provider = _SynchronousImageProvider(testImage);
      const imageBlock = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
        rawUrl: 'data/attachment/forum/page-real.jpg',
        index: 0,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[imageBlock],
      );

      await tester.pumpWidget(
        _testApp(
          home: Center(
            child: SizedBox(
              width: 350,
              child: ThreadPostImageBlockView(
                document: document,
                image: imageBlock,
                images: <ThreadPostImageBlock>[imageBlock],
                imageProviderOverride: provider,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('图片加载中'), findsNothing);
    },
  );

  test(
    'adaptive reading policy defers only above-viewport block image updates',
    () {
      const policy =
          ThreadPostResourceLayoutPolicy.adaptiveBlockImagesForReading;

      expect(policy.lockImageAspectRatioForCurrentBuild, isFalse);
      expect(policy.lockInlineImageSizeForCurrentBuild, isTrue);
      expect(policy.deferImageAspectRatioUpdateWhenAboveViewport, isTrue);
    },
  );

  testWidgets(
    'ThreadPostImageBlockView defers resolved ratio when above viewport',
    (tester) async {
      final image = await tester.runAsync(
        () => createTestImage(width: 1000, height: 500, cache: false),
      );
      final testImage = image!;
      addTearDown(testImage.dispose);
      final provider = _SynchronousImageProvider(testImage);
      const imageBlock = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
        rawUrl: 'data/attachment/forum/page-real.jpg',
        index: 0,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[imageBlock],
      );
      final controller = ScrollController(initialScrollOffset: 520);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _testApp(
          home: Center(
            child: SizedBox(
              width: 350,
              height: 400,
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ThreadPostImageBlockView(
                      document: document,
                      image: imageBlock,
                      images: const <ThreadPostImageBlock>[imageBlock],
                      resourceLayoutPolicy: ThreadPostResourceLayoutPolicy
                          .adaptiveBlockImagesForReading,
                      imageProviderOverride: provider,
                    ),
                    const SizedBox(height: 900),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      final imageBlockSize = tester.getSize(
        find.byType(ThreadPostImageBlockView),
      );
      expect(imageBlockSize.width, 350);
      expect(imageBlockSize.width / imageBlockSize.height, closeTo(0.7, 0.01));
    },
  );

  testWidgets(
    'ThreadPostImageBlockView can correct ratio when a prior hint exists',
    (tester) async {
      final image = await tester.runAsync(
        () => createTestImage(width: 900, height: 450, cache: false),
      );
      final testImage = image!;
      addTearDown(testImage.dispose);
      final provider = _SynchronousImageProvider(testImage);
      const imageBlock = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
        rawUrl: 'data/attachment/forum/page-real.jpg',
        index: 0,
        originalWidth: 700,
        originalHeight: 700,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[imageBlock],
      );

      await tester.pumpWidget(
        _testApp(
          home: Center(
            child: SizedBox(
              width: 350,
              child: ThreadPostImageBlockView(
                document: document,
                image: imageBlock,
                images: <ThreadPostImageBlock>[imageBlock],
                imageProviderOverride: provider,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      final imageBlockSize = tester.getSize(
        find.byType(ThreadPostImageBlockView),
      );
      expect(imageBlockSize.width, 350);
      expect(imageBlockSize.width / imageBlockSize.height, closeTo(2.0, 0.01));
    },
  );

  testWidgets('ThreadPostImageBlockView reuses cached image ratio hint', (
    tester,
  ) async {
    final cacheService = _SizedImageCacheService(<String, CachedImageResult>{
      'thread-inline-page': const CachedImageResult(
        success: true,
        cacheKey: 'thread-inline-page',
        width: 1000,
        height: 500,
      ),
    });
    const imageBlock = ThreadPostImageBlock(
      url: 'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
      rawUrl: 'data/attachment/forum/page-real.jpg',
      index: 0,
    );
    const document = ThreadPostBodyDocument(
      blocks: <ThreadPostBodyBlock>[imageBlock],
    );

    await tester.pumpWidget(
      _testAppWithCacheService(
        imageCacheService: cacheService,
        home: Center(
          child: SizedBox(
            width: 350,
            child: ThreadPostImageBlockView(
              document: document,
              image: imageBlock,
              images: <ThreadPostImageBlock>[imageBlock],
              blockImageCacheRequestBuilder: (_) => const ImageCacheRequest(
                cacheKey: 'thread-inline-page',
                sourceUrl:
                    'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
                ownerType: ImageCacheOwnerType.thread,
                ownerId: 'tid-1',
                role: ImageCacheRole.threadInline,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final imageBlockSize = tester.getSize(
      find.byType(ThreadPostImageBlockView),
    );
    expect(imageBlockSize.width, 350);
    expect(imageBlockSize.width / imageBlockSize.height, closeTo(2.0, 0.01));
  });

  testWidgets(
    'ThreadPostImageBlockView does not let default layout hint override cached ratio',
    (tester) async {
      final cacheService = _SizedImageCacheService(<String, CachedImageResult>{
        'thread-inline-page': const CachedImageResult(
          success: true,
          cacheKey: 'thread-inline-page',
          width: 1000,
          height: 500,
        ),
      });
      const imageBlock = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
        rawUrl: 'data/attachment/forum/page-real.jpg',
        index: 0,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[imageBlock],
      );
      final hints = ThreadPostResourceLayoutHints(
        blockImages: <String, ThreadPostBlockImageLayoutHint>{
          ThreadPostResourceLayoutHints.blockImageKey(
            imageBlock,
          ): const ThreadPostBlockImageLayoutHint(
            aspectRatio: 0.7,
            source: ThreadPostResourceLayoutHintSource.contentDefault,
            lockForCurrentBuild: false,
          ),
        },
      );

      await tester.pumpWidget(
        _testAppWithCacheService(
          imageCacheService: cacheService,
          home: Center(
            child: SizedBox(
              width: 350,
              child: ThreadPostImageBlockView(
                document: document,
                image: imageBlock,
                images: <ThreadPostImageBlock>[imageBlock],
                resourceLayoutHints: hints,
                blockImageCacheRequestBuilder: (_) => const ImageCacheRequest(
                  cacheKey: 'thread-inline-page',
                  sourceUrl:
                      'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
                  ownerType: ImageCacheOwnerType.thread,
                  ownerId: 'tid-1',
                  role: ImageCacheRole.threadInline,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      final imageBlockSize = tester.getSize(
        find.byType(ThreadPostImageBlockView),
      );
      expect(imageBlockSize.width, 350);
      expect(imageBlockSize.width / imageBlockSize.height, closeTo(2.0, 0.01));
    },
  );

  testWidgets('ThreadPostImageBlockView uses layout hint when locked', (
    tester,
  ) async {
    const imageBlock = ThreadPostImageBlock(
      url: 'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
      rawUrl: 'data/attachment/forum/page-real.jpg',
      index: 0,
    );
    const document = ThreadPostBodyDocument(
      blocks: <ThreadPostBodyBlock>[imageBlock],
    );
    final hints = ThreadPostResourceLayoutHints(
      blockImages: <String, ThreadPostBlockImageLayoutHint>{
        ThreadPostResourceLayoutHints.blockImageKey(
          imageBlock,
        ): const ThreadPostBlockImageLayoutHint(
          aspectRatio: 1.5,
          source: ThreadPostResourceLayoutHintSource.htmlAttribute,
          lockForCurrentBuild: true,
        ),
      },
    );

    await tester.pumpWidget(
      _testApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: ThreadPostImageBlockView(
              document: document,
              image: imageBlock,
              images: <ThreadPostImageBlock>[imageBlock],
              resourceLayoutHints: hints,
              resourceLayoutPolicy:
                  ThreadPostResourceLayoutPolicy.lockedForReading,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final imageBlockSize = tester.getSize(
      find.byType(ThreadPostImageBlockView),
    );
    expect(imageBlockSize.width, 300);
    expect(imageBlockSize.width / imageBlockSize.height, closeTo(1.5, 0.01));
  });

  testWidgets('ThreadPostImageBlockView ignores cached ratio when locked', (
    tester,
  ) async {
    final cacheService = _SizedImageCacheService(<String, CachedImageResult>{
      'thread-inline-page': const CachedImageResult(
        success: true,
        cacheKey: 'thread-inline-page',
        width: 1000,
        height: 500,
      ),
    });
    const imageBlock = ThreadPostImageBlock(
      url: 'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
      rawUrl: 'data/attachment/forum/page-real.jpg',
      index: 0,
    );
    const document = ThreadPostBodyDocument(
      blocks: <ThreadPostBodyBlock>[imageBlock],
    );

    await tester.pumpWidget(
      _testAppWithCacheService(
        imageCacheService: cacheService,
        home: Center(
          child: SizedBox(
            width: 350,
            child: ThreadPostImageBlockView(
              document: document,
              image: imageBlock,
              images: <ThreadPostImageBlock>[imageBlock],
              resourceLayoutPolicy:
                  ThreadPostResourceLayoutPolicy.lockedForReading,
              blockImageCacheRequestBuilder: (_) => const ImageCacheRequest(
                cacheKey: 'thread-inline-page',
                sourceUrl:
                    'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
                ownerType: ImageCacheOwnerType.thread,
                ownerId: 'tid-1',
                role: ImageCacheRole.threadInline,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final imageBlockSize = tester.getSize(
      find.byType(ThreadPostImageBlockView),
    );
    expect(imageBlockSize.width, 350);
    expect(imageBlockSize.width / imageBlockSize.height, closeTo(0.7, 0.01));
  });

  testWidgets(
    'ThreadPostImageBlockView ignores resolved ratio when layout is locked',
    (tester) async {
      final image = await tester.runAsync(
        () => createTestImage(width: 1000, height: 500, cache: false),
      );
      final testImage = image!;
      addTearDown(testImage.dispose);
      final provider = _SynchronousImageProvider(testImage);
      const imageBlock = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
        rawUrl: 'data/attachment/forum/page-real.jpg',
        index: 0,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[imageBlock],
      );

      await tester.pumpWidget(
        _testApp(
          home: Center(
            child: SizedBox(
              width: 350,
              child: ThreadPostImageBlockView(
                document: document,
                image: imageBlock,
                images: <ThreadPostImageBlock>[imageBlock],
                resourceLayoutPolicy:
                    ThreadPostResourceLayoutPolicy.lockedForReading,
                imageProviderOverride: provider,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      final imageBlockSize = tester.getSize(
        find.byType(ThreadPostImageBlockView),
      );
      expect(imageBlockSize.width, 350);
      expect(imageBlockSize.width / imageBlockSize.height, closeTo(0.7, 0.01));
    },
  );

  testWidgets('ThreadPostHtml exposes image group open request', (
    tester,
  ) async {
    ThreadPostImageOpenRequest? opened;
    await tester.pumpWidget(
      _testApp(
        home: Center(
          child: SizedBox(
            width: 140,
            child: ThreadPostHtml(
              data: '''
<img file="data/attachment/forum/page-1.jpg" />
<img file="data/attachment/forum/page-2.jpg" />
''',
              imageOpenContext: ThreadImageOpenContext(
                tid: '100',
                pid: 'p1',
                postNumber: 1,
                referer:
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=1',
                cacheKeyForImage: (image) => 'cache-${image.index}',
              ),
              onOpenImage: (request) => opened = request,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.byKey(const Key('thread-post-image-1')));
    await tester.pump();

    expect(opened, isNotNull);
    expect(opened!.initialIndex, 1);
    expect(opened!.image.url, endsWith('/data/attachment/forum/page-2.jpg'));
    expect(opened!.imageUrls, <String>[
      'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
      'https://bbs.yamibo.com/data/attachment/forum/page-2.jpg',
    ]);
    expect(opened!.document.images, hasLength(2));
    final readerRequest = opened!.readerRequest;
    expect(readerRequest, isNotNull);
    expect(readerRequest!.tid, '100');
    expect(readerRequest.pid, 'p1');
    expect(readerRequest.postNumber, 1);
    expect(
      readerRequest.referer,
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=1',
    );
    expect(readerRequest.initialIndex, 1);
    expect(readerRequest.initialEntry?.cacheKey, 'cache-1');
    expect(readerRequest.group.urls, opened!.imageUrls);
    expect(readerRequest.continuousImages, hasLength(2));
    expect(
      readerRequest.continuousImages.map((item) => item.sourceKind).toSet(),
      <ContinuousImageSourceKind>{ContinuousImageSourceKind.threadImageReader},
    );
    expect(readerRequest.continuousImages[1].cacheKey, 'cache-1');
    expect(readerRequest.continuousImages[1].spacingAfter, 10);
  });

  testWidgets(
    'ThreadPostBodySegmentView opens images with full document group',
    (tester) async {
      ThreadPostImageOpenRequest? opened;
      const firstImage = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
        rawUrl: 'data/attachment/forum/page-1.jpg',
        index: 0,
      );
      const secondImage = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/data/attachment/forum/page-2.jpg',
        rawUrl: 'data/attachment/forum/page-2.jpg',
        index: 1,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[firstImage, secondImage],
      );
      const segment = ThreadPostBodySegment(
        index: 1,
        blocks: <ThreadPostBodyBlock>[secondImage],
        anchorId: 'segment-1',
      );

      await tester.pumpWidget(
        _testApp(
          home: Center(
            child: SizedBox(
              width: 140,
              child: ThreadPostBodySegmentView(
                document: document,
                segment: segment,
                images: document.images,
                imageOpenContext: ThreadImageOpenContext(
                  tid: '100',
                  pid: 'p1',
                  postNumber: 1,
                  referer: 'https://bbs.yamibo.com/thread-100-1-1.html',
                  cacheKeyForImage: (image) => 'cache-${image.index}',
                ),
                onOpenImage: (request) => opened = request,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.byKey(const Key('thread-post-image-1')));
      await tester.pump();

      expect(opened, isNotNull);
      expect(opened!.initialIndex, 1);
      expect(opened!.image, secondImage);
      expect(opened!.imageUrls, <String>[
        'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
        'https://bbs.yamibo.com/data/attachment/forum/page-2.jpg',
      ]);
      expect(opened!.readerRequest?.group.entries, hasLength(2));
      expect(opened!.readerRequest?.initialEntry?.url, secondImage.url);
      expect(opened!.readerRequest?.initialEntry?.cacheKey, 'cache-1');
      expect(opened!.readerRequest?.continuousImages, hasLength(2));
      expect(
        opened!.readerRequest?.continuousImages[1].sourceKind,
        ContinuousImageSourceKind.threadImageReader,
      );
    },
  );
}

Finder _postRichTexts() {
  return find.descendant(
    of: find.byType(ThreadPostHtml),
    matching: find.byType(RichText),
  );
}

List<String> _postRichTextPlainTexts(WidgetTester tester) {
  return tester
      .widgetList<RichText>(_postRichTexts())
      .map((text) => text.text.toPlainText())
      .toList(growable: false);
}

class _StaticImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageHeaderBuilder(this.headers);

  final Map<String, String> headers;

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async => headers;
}

class _CountingThreadPostBodyParser extends ThreadPostBodyParser {
  var parseCount = 0;

  @override
  ThreadPostBodyDocument parse(String html) {
    parseCount += 1;
    return super.parse(html);
  }
}

class _CountingThreadPostBodyDocumentNormalizer
    extends ThreadPostBodyDocumentNormalizer {
  var normalizeCount = 0;

  @override
  ThreadPostBodyDocument normalize(ThreadPostBodyDocument document) {
    normalizeCount += 1;
    return super.normalize(document);
  }
}

class _SynchronousImageProvider
    extends ImageProvider<_SynchronousImageProvider> {
  const _SynchronousImageProvider(this.image);

  final ui.Image image;

  @override
  Future<_SynchronousImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<_SynchronousImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _SynchronousImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
    );
  }
}

class _DelayedImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _DelayedImageHeaderBuilder();

  static final List<Completer<Map<String, String>>> _pending =
      <Completer<Map<String, String>>>[];

  @override
  Future<Map<String, String>> buildHeaders(String url) async {
    final completer = Completer<Map<String, String>>();
    _pending.add(completer);
    return completer.future;
  }

  static void completePending() {
    for (final completer in _pending) {
      if (!completer.isCompleted) {
        completer.complete(const <String, String>{});
      }
    }
    _pending.clear();
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

class _SizedImageCacheService extends _FailingImageCacheService {
  _SizedImageCacheService(this.results);

  final Map<String, CachedImageResult> results;

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    return results[cacheKey];
  }
}
