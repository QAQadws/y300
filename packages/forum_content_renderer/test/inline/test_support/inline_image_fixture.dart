import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class InlineImageDescription implements ForumHtmlDisplayImage {
  const InlineImageDescription({
    this.index,
    this.isSticker = true,
    this.sourceUrl = 'https://example.invalid/a.png',
    this.keyOverride,
    this.htmlSize,
  });
  final int? index;
  final String? keyOverride;
  @override
  final String sourceUrl;
  @override
  final bool isSticker;
  @override
  final Size? htmlSize;
  @override
  String get cacheKey =>
      keyOverride ?? (isSticker ? 'sticker:shared' : 'image:$index');
  @override
  Object get identity => (sourceUrl, cacheKey, isSticker, htmlSize);
  @override
  ForumHtmlImageLayout get initialLayout =>
      const ForumHtmlImageLayout(displaySize: Size(20, 20), aspectRatio: 1);
}

final class _Resource implements ForumHtmlPreparedImageResource {
  const _Resource(this.cacheKey);
  @override
  final String cacheKey;
}

PlaceholderDimensions inlineImageDimensions(Size size) => PlaceholderDimensions(
  size: size,
  alignment: ui.PlaceholderAlignment.baseline,
  baseline: TextBaseline.alphabetic,
  baselineOffset: size.height,
);

final class InlineImageFixture {
  InlineImageFixture({
    this.count = 2,
    this.sticker = true,
    this.before = 'A',
    this.after = 'B',
    this.size = const Size(20, 20),
  }) {
    addTearDown(cache.close);
  }
  final int count;
  final bool sticker;
  final String before, after;
  final Size size;
  final cache = ForumBodyParagraphCache(
    maxEntries: 8,
    maxEstimatedBytes: 1 << 22,
  );
  late final document = const ForumBodyParser().parse(
    html:
        '<p><span>$before</span>${List.filled(count, '<img src="https://example.invalid/a.png" alt="server image">').join()}'
        '<span>$after</span></p>',
    sourceId: 'inline-image-$sticker-$before-$after',
    conversionIdentity: 'none',
  );
  late final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  late final contexts = [text('0/0'), text('0/${count + 1}')];
  late final images = <int, ForumBodyInlineImageInput>{
    for (var i = 0; i < count; i++) i: image(i),
  };
  ForumBodyParagraphContent text(String path) =>
      const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: styles,
        path: path,
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
  ForumBodyInlineImageInput image(int index) {
    final display = InlineImageDescription(
      index: sticker ? null : index,
      isSticker: sticker,
    );
    return ForumBodyInlineImageInput(
      document: document,
      element: document.nodeAtPath('0/${index + 1}')! as ForumBodyElement,
      image: display,
      dimensions: inlineImageDimensions(size),
      entry: sticker
          ? null
          : ForumHtmlReadableImageEntry(
              index: index,
              url: display.sourceUrl,
              rawSrc: display.sourceUrl,
              resource: _Resource(display.cacheKey),
            ),
    );
  }

  ForumBodyInlineSpanContent content({
    Map<int, ForumBodyInlineImageInput>? bindings,
    int maxInputCodeUnits = 16384,
  }) => ForumBodyInlineSpanContent.compose(
    identity: document.identity,
    path: '0',
    fontRevision: styles.fontRevision,
    styleRevision: styles.resolverRevision,
    style: styles.byPath['0']!,
    contexts: contexts,
    resourceAtoms: {for (var i = 0; i < count; i++) i},
    atomicRanges: List.filled(count, (
      startUtf16: contexts.first.projection.text.length,
      endUtf16: contexts.first.projection.text.length,
    )),
    images: bindings ?? images,
    maxInputCodeUnits: maxInputCodeUnits,
  );
  ForumBodyInlineParagraphLease parent({
    ForumBodyInlineSpanContent? input,
    List<PlaceholderDimensions>? dimensions,
  }) => cache.acquireInline(
    content: input ?? content(),
    width: 100,
    dimensions: dimensions ?? List.filled(count, inlineImageDimensions(size)),
  );
  ForumBodyInlineParagraphView view({
    int startLine = 0,
    int? endLine,
    ForumBodyInlineSpanContent? input,
    List<PlaceholderDimensions>? dimensions,
  }) {
    final lease = parent(input: input, dimensions: dimensions);
    return ForumBodyInlineParagraphView.adopt(
      cache: cache,
      parent: lease,
      startLine: startLine,
      endLine: endLine ?? lease.layout.lines.length,
    );
  }
}
