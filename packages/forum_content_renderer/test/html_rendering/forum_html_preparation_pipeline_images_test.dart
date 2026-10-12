import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html/dom.dart' as html_dom;

import 'render_test_support.dart';

void main() {
  test(
    'one image query preserves retained order, source priority, and counts',
    () {
      final codec = _CountingFragmentCodec();
      final optimized = _prepare(_pipeline(codec: codec), _mixedImages);
      final legacyCodec = _CountingFragmentCodec();
      final legacy = _prepare(
        _pipeline(codec: legacyCodec, deduplicator: _LegacyDeduplicator()),
        _mixedImages,
      );

      expect(codec.fragments.single.imageQueries, 1);
      expect(legacyCodec.fragments.single.imageQueries, 2);
      expect(optimized.preparedHtml, legacy.preparedHtml);
      expect(_imageProjection(optimized), _imageProjection(legacy));
      expect(optimized.attachmentIdsByUrl, legacy.attachmentIdsByUrl);
      expect(_statisticsProjection(optimized), _statisticsProjection(legacy));
      expect(optimized.totalImageCount, 10);
      expect(optimized.skippedStickerCount, 2);
      expect(optimized.skippedNonNetworkCount, 4);
      expect(optimized.duplicatedReadableUrlCount, 1);
      expect(optimized.attachmentTaggedCount, 4);
      expect(optimized.themeAdaptationStats.explicitForegroundCount, 1);
      expect(optimized.sequence.entries.map((entry) => entry.index), [
        0,
        1,
        2,
        3,
      ]);
      expect(optimized.sequence.entries.map((entry) => entry.rawSrc), [
        'data/attachment/forum/first.jpg#inline',
        'https://cdn.example.invalid/repeated.jpg#first',
        'https://cdn.example.invalid/repeated.jpg#second',
        'last.jpg',
      ]);
      expect(optimized.sequence.entries.first.attachmentId, '7');
      expect(optimized.sequence.entries.first.htmlWidth, 640);
      expect(optimized.sequence.entries.first.htmlHeight, 480);
      expect(optimized.sequence.entries.last.alt, 'last alt');
      expect(optimized.sequence.entries.last.title, 'last title');
      expect(
        optimized
            .attachmentIdsByUrl['https://bbs.yamibo.com/data/attachment/forum/first.jpg'],
        '7',
      );
      expect(optimized.attachmentIdsByUrl.values, isNot(contains('99')));
    },
  );

  test(
    'legacy overrides may replace sources, insert images, and reorder DOM',
    () {
      final codec = _CountingFragmentCodec();
      final deduplicator = _RewritingDeduplicator();
      final prepared = _prepare(
        _pipeline(codec: codec, deduplicator: deduplicator),
        '<img id="aimg_1" src="removed.jpg">'
        '<img id="aimg_2" src="before.jpg">'
        '<img id="aimg_3" src="tail.jpg">',
      );

      expect(deduplicator.calls, 1);
      expect(codec.fragments.single.imageQueries, 2);
      expect(prepared.totalImageCount, 3);
      expect(prepared.sequence.entries.map((entry) => entry.rawSrc), [
        'tail.jpg',
        'rewritten.jpg',
        'inserted.jpg',
      ]);
      expect(prepared.sequence.entries.map((entry) => entry.index), [0, 1, 2]);
      expect(prepared.sequence.entries.map((entry) => entry.attachmentId), [
        '3',
        '2',
        '4',
      ]);
      expect(
        prepared.sequence.entries[1].url,
        'https://bbs.yamibo.com/rewritten.jpg',
      );
    },
  );

  test('candidate DOM is scoped to each preparation invocation', () {
    final codec = _CountingFragmentCodec();
    final pipeline = _pipeline(codec: codec);
    final first = _prepare(
      pipeline,
      '<img id="aimg_1" src="data/attachment/forum/first.jpg">'
      '<img id="aimg_1" src="data/attachment/forum/first.jpg">',
    );
    final firstHtml = first.preparedHtml;
    final second = _prepare(
      pipeline,
      '<img id="aimg_1" src="data/attachment/forum/second.jpg">',
    );

    expect(codec.fragments.map((fragment) => fragment.imageQueries), [1, 1]);
    expect(codec.fragments.first, isNot(same(codec.fragments.last)));
    expect(first.preparedHtml, firstHtml);
    expect(
      first.sequence.entries.single.rawSrc,
      'data/attachment/forum/first.jpg',
    );
    expect(
      second.sequence.entries.single.rawSrc,
      'data/attachment/forum/second.jpg',
    );
    expect(first.sequence.entries.single.index, 0);
    expect(second.sequence.entries.single.index, 0);
  });

  test('attachment hints retain the post-normalization source precedence', () {
    final codec = _CountingFragmentCodec();
    final prepared = _prepare(
      _pipeline(
        codec: codec,
        resolveUrl: (raw) => raw == 'opaque.jpg'
            ? 'https://bbs.yamibo.com/image.php?attachmentid=17'
            : _resolveUrl(raw),
      ),
      '<img src="opaque.jpg">'
      '<img data-src="opaque.jpg" src="thumbnail.jpg">',
    );

    expect(codec.fragments.single.imageQueries, 1);
    expect(prepared.sequence.entries.map((entry) => entry.rawSrc), [
      'opaque.jpg',
      'opaque.jpg',
    ]);
    expect(prepared.sequence.entries.map((entry) => entry.attachmentId), [
      '17',
      null,
    ]);
    expect(prepared.attachmentTaggedCount, 1);
    expect(prepared.duplicatedReadableUrlCount, 1);
  });

  test('images added by a custom theme adapter enter the final image scan', () {
    final codec = _CountingFragmentCodec();
    final prepared = _prepare(
      _pipeline(codec: codec, themeAdapter: const _AddingImageThemeAdapter()),
      '<p>正文</p>',
    );

    expect(codec.fragments.single.imageQueries, 1);
    expect(prepared.totalImageCount, 1);
    expect(prepared.sequence.entries.single.rawSrc, 'theme-added.jpg');
    expect(prepared.sequence.entries.single.index, 0);
    expect(prepared.sequence.entries.single.attachmentId, '5');
  });
}

const _mixedImages =
    '<font color="black">正文</font>'
    '<img id="aimg_7" zoomfile=" data/attachment/forum/first.jpg#inline " '
    'src="placeholder.jpg" width="640" height="480">'
    '<img aid="99" '
    'src="https://bbs.yamibo.com/data/attachment/forum/first.jpg#gallery">'
    '<img src="https://cdn.example.invalid/repeated.jpg#first">'
    '<img src="https://cdn.example.invalid/repeated.jpg#second">'
    '<img aid="40" src="static/image/smiley/default/1.gif">'
    '<img aid="41" src="static/image/smiley/default/1.gif">'
    '<img src="data:image/png;base64,AA">'
    '<img src="file:///local.jpg">'
    '<img>'
    '<img aid="8" src="rejected.jpg">'
    '<img data-original="last.jpg" src="thumbnail.jpg" '
    'alt="last alt" title="last title">';

ForumHtmlPreparationPipeline _pipeline({
  required _CountingFragmentCodec codec,
  ForumHtmlImageDeduplicator? deduplicator,
  ForumHtmlThemeAdapter themeAdapter = const DefaultForumHtmlThemeAdapter(),
  String? Function(String) resolveUrl = _resolveUrl,
}) => ForumHtmlPreparationPipeline(
  imagePolicy: const _ImagePolicy(),
  resolveUrl: resolveUrl,
  imageDeduplicator: deduplicator,
  fragmentCodec: codec,
  themeAdapter: themeAdapter,
);

ForumHtmlPreparedRenderDocument _prepare(
  ForumHtmlPreparationPipeline pipeline,
  String html,
) => pipeline.prepare(
  html: html,
  options: renderTestOptions,
  theme: forumHtmlTestTheme,
  sourceId: 'image-candidates',
  threadId: '100',
  imageCacheOwnerId: '100',
);

List<Object> _imageProjection(ForumHtmlPreparedRenderDocument document) => [
  for (final entry in document.sequence.entries)
    (
      entry.index,
      entry.url,
      entry.rawSrc,
      entry.cacheKey,
      entry.attachmentId,
      entry.alt,
      entry.title,
      entry.htmlWidth,
      entry.htmlHeight,
    ),
];

Object _statisticsProjection(ForumHtmlPreparedRenderDocument document) => (
  document.totalImageCount,
  document.skippedStickerCount,
  document.skippedNonNetworkCount,
  document.duplicatedReadableUrlCount,
  document.attachmentTaggedCount,
  document.themeSignature,
  document.themeAdaptationStats.explicitForegroundCount,
  document.themeAdaptationStats.remappedForegroundCount,
  document.themeAdaptationStats.explicitBackgroundCount,
  document.themeAdaptationStats.remappedBackgroundCount,
  document.themeAdaptationStats.semanticFallbackCount,
  document.themeAdaptationStats.unsupportedColorCount,
  document.themeAdaptationStats.concealedTextRangeCount,
  document.themeAdaptationStats.minimumResultContrast,
);

String? _resolveUrl(String raw) =>
    Uri.parse('https://bbs.yamibo.com/').resolve(raw).toString();

final class _CountingFragmentCodec implements ForumHtmlFragmentCodec {
  final fragments = <_CountingFragment>[];
  final _delegate = const HtmlPackageForumHtmlFragmentCodec();

  @override
  html_dom.DocumentFragment parse(String html) {
    final fragment = _CountingFragment()
      ..nodes.addAll(_delegate.parse(html).nodes.toList());
    fragments.add(fragment);
    return fragment;
  }

  @override
  String serialize(html_dom.DocumentFragment fragment) =>
      _delegate.serialize(fragment);
}

final class _CountingFragment extends html_dom.DocumentFragment {
  var imageQueries = 0;

  @override
  List<html_dom.Element> querySelectorAll(String selector) {
    if (selector == 'img') imageQueries++;
    return super.querySelectorAll(selector);
  }
}

class _LegacyDeduplicator extends ForumHtmlImageDeduplicator {
  _LegacyDeduplicator() : super(resolveUrl: _resolveUrl);
}

final class _RewritingDeduplicator extends ForumHtmlImageDeduplicator {
  _RewritingDeduplicator() : super(resolveUrl: _resolveUrl);

  var calls = 0;

  @override
  int deduplicateAttachmentImagesInFragment(
    html_dom.DocumentFragment fragment,
  ) {
    calls++;
    final images = fragment.querySelectorAll('img');
    images.first.remove();
    images[1].attributes['src'] = 'rewritten.jpg';
    images.last.remove();
    fragment.nodes.insert(0, images.last);
    fragment.nodes.add(
      html_dom.Element.tag('img')
        ..attributes['id'] = 'aimg_4'
        ..attributes['src'] = 'inserted.jpg',
    );
    return 1;
  }
}

final class _AddingImageThemeAdapter implements ForumHtmlThemeAdapter {
  const _AddingImageThemeAdapter();

  @override
  ForumHtmlThemeAdaptationResult adapt({
    required html_dom.DocumentFragment fragment,
    required ForumHtmlThemeContext theme,
    required ForumHtmlColorAdaptationPolicy policy,
  }) {
    final result = const DefaultForumHtmlThemeAdapter().adapt(
      fragment: fragment,
      theme: theme,
      policy: policy,
    );
    fragment.nodes.add(
      html_dom.Element.tag('img')
        ..attributes['id'] = 'aimg_5'
        ..attributes['src'] = 'theme-added.jpg',
    );
    return result;
  }
}

final class _ImagePolicy implements ForumHtmlPreparationImagePolicy {
  const _ImagePolicy();

  @override
  ForumHtmlPreparedImageResource? prepareInline({
    required Uri url,
    required String? threadId,
    required String? imageCacheOwnerId,
    required int imageIndex,
    double? htmlWidth,
    double? htmlHeight,
    String? alt,
    String? title,
  }) => url.path.endsWith('/rejected.jpg')
      ? null
      : _ImageResource('test:$imageIndex:$url');
}

final class _ImageResource implements ForumHtmlPreparedImageResource {
  const _ImageResource(this.cacheKey);

  @override
  final String cacheKey;
}
