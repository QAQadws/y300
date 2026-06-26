import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';

void main() {
  testWidgets(
    'ThreadPostHtml renders post images through request header builder',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
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

  testWidgets('ThreadPostHtml renders text blocks without flutter_html', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ThreadPostHtml(
          data:
              '<p>第一段 <strong>重点</strong></p><p><a href="thread-1-1-1.html">链接</a></p>',
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(_postRichTexts(), findsNWidgets(2));
    expect(_postRichTextPlainTexts(tester), contains('第一段重点'));
    expect(_postRichTextPlainTexts(tester), contains('链接'));
  });

  testWidgets('ThreadPostHtml renders reply quote as a quote block', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ThreadPostHtml(
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
      MaterialApp(
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
          widget is LibraryCachedImage &&
          widget.imageUrl ==
              'https://bbs.yamibo.com/static/image/smiley/comcom/2.gif',
    );
    expect(inlineImages, findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.headers?['Referer'], 'https://bbs.yamibo.com/');
    expect(
      _postRichTextPlainTexts(tester).any((text) => text.contains('那篇很好啊我很喜欢')),
      isTrue,
    );
  });

  testWidgets('ThreadPostHtml treats bare blockquote as a quote block', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ThreadPostHtml(
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
      MaterialApp(
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
    expect(firstText.selectionRegistrar, isNotNull);

    final firstRootSpan = firstText.text as TextSpan;
    final firstSpan = firstRootSpan.children!.single as TextSpan;
    expect(firstSpan.style?.fontSize, 19);

    final spacers = tester.widgetList<SizedBox>(find.byType(SizedBox));
    expect(spacers.any((box) => box.height == 18), isTrue);
  });

  testWidgets('ThreadPostHtml exposes link tap callback', (tester) async {
    String? openedUrl;
    await tester.pumpWidget(
      MaterialApp(
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
        const MaterialApp(
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
        const MaterialApp(
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
        MaterialApp(
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

      expect(find.byType(LibraryCachedImage), findsOneWidget);
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
        const MaterialApp(
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

  testWidgets('ThreadPostImageBlockView switches to resolved image ratio', (
    tester,
  ) async {
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
      MaterialApp(
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
  });

  testWidgets('ThreadPostHtml exposes image group open request', (
    tester,
  ) async {
    ThreadPostImageOpenRequest? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 140,
            child: ThreadPostHtml(
              data: '''
<img file="data/attachment/forum/page-1.jpg" />
<img file="data/attachment/forum/page-2.jpg" />
''',
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
  });
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
