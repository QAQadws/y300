import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'render_test_support.dart';

void main() {
  testWidgets('readable index distinguishes repeated image URLs', (
    tester,
  ) async {
    final anchors = ForumHtmlImageAnchorController();
    final scroll = ScrollController();
    addTearDown(anchors.dispose);
    addTearDown(scroll.dispose);
    final document = prepareRenderTestDocument(
      _images(['same', 'middle', 'same']),
      sourceId: 'post',
    );
    await tester.pumpWidget(_host(anchors, scroll, document));
    await _frames(tester);

    final result = _reveal(anchors, scroll, document.sequence.entries[2]);
    await _frames(tester);
    expect(await result, isTrue);
    expect(_top(tester, 'post', 2), closeTo(_viewportTop(tester), 0.5));
    expect(_top(tester, 'post', 0), lessThan(_viewportTop(tester)));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'nested table images retain distinct anchors across width changes',
    (tester) async {
      final anchors = ForumHtmlImageAnchorController();
      final scroll = ScrollController();
      addTearDown(anchors.dispose);
      addTearDown(scroll.dispose);
      final document = prepareRenderTestDocument(
        '<table><tr><td>Details</td><td><table><tr><td>'
        '${_images(['same', 'middle', 'same'])}'
        '</td></tr></table></td></tr></table>',
        sourceId: 'table',
      );
      ForumHtmlImageRequest? tapped;
      final callbacks = ForumHtmlRenderCallbacks(
        onTapImage: (value) => tapped = value,
      );
      await tester.pumpWidget(
        _host(anchors, scroll, document, callbacks: callbacks),
      );
      await _frames(tester);
      final target = find.byKey(
        const Key('thread-post-html-first-readable-image-table-2'),
      );
      final element = tester.element(target);
      for (final width in [220.0, 280.0, 240.0]) {
        await tester.pumpWidget(
          _host(anchors, scroll, document, width: width, callbacks: callbacks),
        );
        await _frames(tester);
        expect(tester.element(target), same(element));
      }

      final result = _reveal(anchors, scroll, document.sequence.entries[2]);
      await _frames(tester);
      expect(await result, isTrue);
      expect(_top(tester, 'table', 2), closeTo(_viewportTop(tester), 0.5));
      expect(_top(tester, 'table', 0), lessThan(_viewportTop(tester)));
      await tester.tap(target);
      expect(tapped?.readableIndex, 2);
      expect(tapped?.url, document.sequence.entries[2].url);
      expect(tester.takeException(), isNull);
    },
  );

  for (final expanded in [true, false]) {
    testWidgets(
      '${expanded ? 'expanded' : 'closed'} nested folds share root image identity',
      (tester) async {
        final anchors = ForumHtmlImageAnchorController();
        final scroll = ScrollController();
        addTearDown(anchors.dispose);
        addTearDown(scroll.dispose);
        final document = prepareRenderTestDocument(
          '${_images(['first'])}'
          '<div id="fold" class="showcollapse_box">'
          '<div class="showcollapse_title">Details</div>'
          '<div class="showcollapse_content">${_images(['nested'])}</div>'
          '</div>',
          sourceId: 'post',
        );
        await tester.pumpWidget(
          _host(
            anchors,
            scroll,
            document,
            collapseExpansion: {'post-fold': expanded},
          ),
        );
        await _frames(tester);
        final origin = scroll.offset;

        final result = _reveal(anchors, scroll, document.sequence.entries[1]);
        await _frames(tester);
        expect(await result, expanded);
        if (expanded) {
          expect(
            _top(tester, 'post-fold-content', 1),
            closeTo(_viewportTop(tester), 0.5),
          );
        } else {
          expect(scroll.offset, origin);
          expect(
            find.byKey(
              const Key(
                'thread-post-html-first-readable-image-post-fold-content-1',
              ),
            ),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('missing, mismatched and detached anchors preserve position', (
    tester,
  ) async {
    final anchors = ForumHtmlImageAnchorController();
    final scroll = ScrollController(initialScrollOffset: 30);
    addTearDown(anchors.dispose);
    addTearDown(scroll.dispose);
    final document = prepareRenderTestDocument(_images(['first', 'second']));
    await tester.pumpWidget(_host(anchors, scroll, document));
    await _frames(tester);
    final entry = document.sequence.entries[1];
    for (final key in [
      (index: 99, cacheKey: entry.cacheKey, url: entry.url),
      (index: entry.index, cacheKey: 'different', url: entry.url),
      (
        index: entry.index,
        cacheKey: entry.cacheKey,
        url: 'https://wrong.invalid',
      ),
    ]) {
      expect(
        await anchors.revealImage(
          index: key.index,
          cacheKey: key.cacheKey,
          url: key.url,
          scrollController: scroll,
          isCurrent: () => true,
        ),
        isFalse,
      );
      expect(scroll.offset, 30);
    }
    await tester.pumpWidget(_host(anchors, scroll, document, shown: false));
    expect(await _reveal(anchors, scroll, entry), isFalse);
    expect(scroll.offset, 30);
  });

  testWidgets('retired controller rejects requests without moving', (
    tester,
  ) async {
    final anchors = ForumHtmlImageAnchorController();
    final scroll = ScrollController(initialScrollOffset: 30);
    addTearDown(scroll.dispose);
    final document = prepareRenderTestDocument(_images(['first', 'second']));
    await tester.pumpWidget(_host(anchors, scroll, document));
    await _frames(tester);
    anchors.dispose();
    expect(
      await _reveal(anchors, scroll, document.sequence.entries[1]),
      isFalse,
    );
    expect(scroll.offset, 30);
  });

  testWidgets('stale request cannot correct or roll back newer navigation', (
    tester,
  ) async {
    final anchors = ForumHtmlImageAnchorController();
    final scroll = ScrollController(initialScrollOffset: 30);
    addTearDown(anchors.dispose);
    addTearDown(scroll.dispose);
    final document = prepareRenderTestDocument(_images(['first', 'second']));
    await tester.pumpWidget(_host(anchors, scroll, document));
    await _frames(tester);
    var current = true;
    final result = _reveal(
      anchors,
      scroll,
      document.sequence.entries[1],
      isCurrent: () => current,
    );
    expect(scroll.offset, greaterThan(30));
    current = false;
    scroll.jumpTo(17);
    await _frames(tester);
    expect(await result, isFalse);
    expect(scroll.offset, 17);
  });

  testWidgets('sequence replacement rejects late alignment', (tester) async {
    final anchors = ForumHtmlImageAnchorController();
    final scroll = ScrollController(initialScrollOffset: 30);
    addTearDown(anchors.dispose);
    addTearDown(scroll.dispose);
    final document = prepareRenderTestDocument(_images(['first', 'second']));
    await tester.pumpWidget(_host(anchors, scroll, document));
    await _frames(tester);
    final result = _reveal(anchors, scroll, document.sequence.entries[1]);
    anchors.bindSequence(
      prepareRenderTestDocument(
        _images(['first', 'second']),
        sourceId: 'different-post',
      ).sequence,
    );
    scroll.jumpTo(17);
    await _frames(tester);
    expect(await result, isFalse);
    expect(scroll.offset, 17);
  });

  testWidgets('detachment during alignment restores the original offset', (
    tester,
  ) async {
    final anchors = ForumHtmlImageAnchorController();
    final scroll = ScrollController(initialScrollOffset: 30);
    addTearDown(anchors.dispose);
    addTearDown(scroll.dispose);
    final document = prepareRenderTestDocument(_images(['first', 'second']));
    await tester.pumpWidget(_host(anchors, scroll, document));
    await _frames(tester);
    final result = _reveal(anchors, scroll, document.sequence.entries[1]);
    expect(scroll.offset, greaterThan(30));
    await tester.pumpWidget(_host(anchors, scroll, document, shown: false));
    await _frames(tester);
    expect(await result, isFalse);
    expect(scroll.offset, 30);
  });

  testWidgets(
    'centered sliver layout reveals images in negative scroll space',
    (tester) async {
      final anchors = ForumHtmlImageAnchorController();
      final scroll = ScrollController();
      addTearDown(anchors.dispose);
      addTearDown(scroll.dispose);
      final document = prepareRenderTestDocument(_images(['first', 'second']));
      final centerKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                key: const Key('viewport'),
                width: 240,
                height: 200,
                child: CustomScrollView(
                  controller: scroll,
                  center: centerKey,
                  slivers: [
                    SliverToBoxAdapter(child: _renderer(anchors, document)),
                    SliverToBoxAdapter(
                      key: centerKey,
                      child: const SizedBox(height: 600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await _frames(tester);
      expect(scroll.position.minScrollExtent, lessThan(0));
      final result = _reveal(anchors, scroll, document.sequence.entries.first);
      await _frames(tester);
      expect(await result, isTrue);
      expect(scroll.offset, lessThan(0));
      expect(
        _top(tester, 'render-test', 0),
        closeTo(_viewportTop(tester), 0.5),
      );
    },
  );

  testWidgets('controller and callback updates preserve the ready body', (
    tester,
  ) async {
    final first = ForumHtmlImageAnchorController();
    final second = ForumHtmlImageAnchorController();
    final scroll = ScrollController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(scroll.dispose);
    final document = prepareRenderTestDocument(_images(['first', 'second']));
    await tester.pumpWidget(_host(null, scroll, document));
    await _frames(tester);
    final body = tester.element(find.byType(HtmlWidget));
    final image = tester.element(
      find.byKey(
        const Key('thread-post-html-first-readable-image-render-test-0'),
      ),
    );
    await tester.pumpWidget(_host(first, scroll, document));
    await _frames(tester);
    expect(tester.element(find.byType(HtmlWidget)), same(body));
    expect(
      tester.element(
        find.byKey(
          const Key('thread-post-html-first-readable-image-render-test-0'),
        ),
      ),
      same(image),
    );
    var tapped = false;
    await tester.pumpWidget(
      _host(
        second,
        scroll,
        document,
        callbacks: ForumHtmlRenderCallbacks(onTapImage: (_) => tapped = true),
      ),
    );
    await _frames(tester);
    expect(tester.element(find.byType(HtmlWidget)), same(body));
    expect(
      tester.element(
        find.byKey(
          const Key('thread-post-html-first-readable-image-render-test-0'),
        ),
      ),
      same(image),
    );
    await tester.tap(
      find.byKey(
        const Key('thread-post-html-first-readable-image-render-test-0'),
      ),
    );
    expect(tapped, isTrue);
    expect(await _reveal(first, scroll, document.sequence.entries[1]), isFalse);
    final result = _reveal(second, scroll, document.sequence.entries[1]);
    await _frames(tester);
    expect(await result, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Future<bool> _reveal(
  ForumHtmlImageAnchorController anchors,
  ScrollController scroll,
  ForumHtmlReadableImageEntry entry, {
  bool Function()? isCurrent,
}) => anchors.revealImage(
  index: entry.index,
  cacheKey: entry.cacheKey,
  url: entry.url,
  scrollController: scroll,
  isCurrent: isCurrent ?? () => true,
);

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump();
  }
}

double _top(WidgetTester tester, String sourceId, int index) => tester
    .getTopLeft(
      find.byKey(Key('thread-post-html-first-readable-image-$sourceId-$index')),
    )
    .dy;

double _viewportTop(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const Key('viewport'))).dy;

String _images(List<String> names) => [
  for (final name in names)
    '<div><img src="https://example.invalid/$name.jpg" width="200" height="100"></div>',
].join();

Widget _host(
  ForumHtmlImageAnchorController? anchors,
  ScrollController scroll,
  ForumHtmlPreparedRenderDocument document, {
  bool shown = true,
  double width = 240,
  Map<String, bool>? collapseExpansion,
  ForumHtmlRenderCallbacks callbacks = const ForumHtmlRenderCallbacks(),
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        key: const Key('viewport'),
        width: width,
        height: 200,
        child: SingleChildScrollView(
          controller: scroll,
          child: Column(
            children: [
              const SizedBox(height: 120),
              if (shown)
                _renderer(
                  anchors,
                  document,
                  collapseExpansion: collapseExpansion,
                  callbacks: callbacks,
                ),
              const SizedBox(height: 600),
            ],
          ),
        ),
      ),
    ),
  ),
);

Widget _renderer(
  ForumHtmlImageAnchorController? anchors,
  ForumHtmlPreparedRenderDocument document, {
  Map<String, bool>? collapseExpansion,
  ForumHtmlRenderCallbacks callbacks = const ForumHtmlRenderCallbacks(),
}) => ForumHtmlRenderer(
  preparedDocument: document,
  theme: forumHtmlTestTheme,
  options: renderTestOptions,
  labels: renderTestLabels,
  sourceId: document.sequence.sourceId,
  imageHost: const _ImageHost(),
  imageAnchorController: anchors,
  buildAsync: false,
  enableCaching: true,
  callbacks: callbacks,
  collapseExpansion: collapseExpansion,
);

final class _ImageHost implements ForumHtmlImageHost {
  const _ImageHost();

  @override
  ForumHtmlDisplayImage resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => _ImageBinding(url.toString(), htmlSize, isSticker);

  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) async => null;

  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) {}

  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) async {}

  @override
  Widget buildImage({
    required ForumHtmlDisplayImage image,
    required BoxFit fit,
    required Widget placeholder,
    double? width,
    double? height,
    Widget? errorPlaceholder,
    VoidCallback? onRetry,
    ValueChanged<Size>? onImageResolved,
    VoidCallback? onImageFailed,
    VoidCallback? onFirstFrameRendered,
    bool showDelayedLoadingIndicator = false,
    bool waitForCacheWrite = false,
    int retryToken = 0,
  }) => const ColoredBox(color: Colors.blue);
}

final class _ImageBinding implements ForumHtmlDisplayImage {
  const _ImageBinding(this.sourceUrl, this.htmlSize, this.isSticker);

  @override
  final String sourceUrl;
  @override
  final Size? htmlSize;
  @override
  final bool isSticker;
  @override
  String get cacheKey => 'test:$sourceUrl';
  @override
  Object get identity => cacheKey;
  @override
  ForumHtmlImageLayout get initialLayout => ForumHtmlImageLayout(
    aspectRatio: htmlSize?.aspectRatio ?? 0.7,
    isFallback: htmlSize == null,
  );
}
