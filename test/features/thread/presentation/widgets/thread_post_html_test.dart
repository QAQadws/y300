import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';

void main() {
  testWidgets(
    'ThreadPostHtml renders post images through request header builder',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ThreadPostHtml(
            data: '<img file="data/attachment/forum/page-1.jpg" />',
            imageHeaderBuilder: const _StaticImageHeaderBuilder(
              <String, String>{
                'Referer': 'https://bbs.yamibo.com/',
                'Cookie': 'auth=token123',
              },
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
          home: ThreadPostHtml(
            data:
                '<img data-original="//bbs.yamibo.com/data/attachment/forum/page-2.jpg" />',
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
          home: ThreadPostHtml(
            data:
                '<img src="static/image/common/none.gif" file="data/attachment/forum/page-real.jpg" />',
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
          home: ThreadPostHtml(
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

  testWidgets('ThreadPostHtml exposes image group open request', (
    tester,
  ) async {
    ThreadPostImageOpenRequest? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: ThreadPostHtml(
          data: '''
<img file="data/attachment/forum/page-1.jpg" />
<img file="data/attachment/forum/page-2.jpg" />
''',
          style: const ThreadPostBodyStyle(
            imageMinHeight: 80,
            imageMaxHeight: 120,
          ),
          onOpenImage: (request) => opened = request,
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
