import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'forum_html_test_theme.dart';

void main() {
  test('fragment serialization keeps comments out of visible text and DOM', () {
    const codec = HtmlPackageForumHtmlFragmentCodec();
    const html =
        '<!-- fixture comment --><p>正文</p>'
        '<!-- <img src="https://example.invalid/fixture.png"> -->';

    final serialized = codec.serialize(codec.parse(html));
    final reparsed = codec.parse(serialized);

    expect(serialized, html);
    expect(reparsed.nodes.whereType<html_dom.Comment>(), hasLength(2));
    expect(reparsed.text, '正文');
    expect(reparsed.querySelector('img'), isNull);
  });

  group('DefaultForumHtmlRenderPreparer pipeline', () {
    test('parses and serializes exactly once', () {
      final codec = _CountingFragmentCodec();
      final preparer = DefaultForumHtmlRenderPreparer(fragmentCodec: codec);

      preparer.prepare(
        html:
            '<p style="color: black">正文</p>'
            '<img src="data/attachment/forum/page.jpg">',
        preferences: ForumHtmlReaderPreferences.defaults(),
        theme: forumHtmlTestTheme,
        sourceId: 'phase2-single-pass',
        threadId: '100',
        imageCacheOwnerId: '100',
      );

      expect(codec.parseCount, 1);
      expect(codec.serializeCount, 1);
    });

    test('keeps the fixed normalize, dedupe, and annotation order', () {
      const preparer = DefaultForumHtmlRenderPreparer();

      final prepared = preparer.prepare(
        html:
            '<i class="pstatus">编辑提示</i><br><br>'
            '<font size="5" color="black" style="text-align: center">'
            '正文'
            '</font>'
            '<img id="aimg_9" src="data/attachment/forum/page.jpg">'
            '<img id="aimg_9" '
            'src="https://bbs.yamibo.com/data/attachment/forum/page.jpg">',
        preferences: ForumHtmlReaderPreferences.defaults(),
        theme: forumHtmlTestTheme,
        sourceId: 'phase2-order',
        threadId: '100',
        imageCacheOwnerId: '100',
      );
      final fragment = html_parser.parseFragment(prepared.preparedHtml);
      final font = fragment.querySelector('font')!;
      final images = fragment.querySelectorAll('img');

      expect(fragment.querySelectorAll('br'), isEmpty);
      expect(font.attributes['size'], isNull);
      expect(font.attributes['color'], isNull);
      expect(font.attributes['style'], contains('text-align: center'));
      expect(font.attributes['style'], contains('font-size: 125%'));
      expect(font.attributes['style'], contains('color:'));
      expect(images, hasLength(1));
      expect(
        images.single.attributes['src'],
        'https://bbs.yamibo.com/data/attachment/forum/page.jpg',
      );
      expect(
        images.single.attributes[forumHtmlReadableImageIndexAttribute],
        '0',
      );
      expect(prepared.sequence.entries, hasLength(1));
      expect(prepared.sequence.entries.single.attachmentId, '9');
      expect(prepared.totalImageCount, 1);
      expect(prepared.themeSignature, forumHtmlTestTheme.signature);
      expect(prepared.themeAdaptationStats.explicitForegroundCount, 1);
      expect(prepared.themeAdaptationStats.remappedBackgroundCount, 0);
    });

    test('adapts colors before preserving the image sequence', () {
      const preparer = DefaultForumHtmlRenderPreparer();

      final prepared = preparer.prepare(
        html:
            '<font id="body" color="black">正文</font>'
            '<img id="aimg_9" src="data/attachment/forum/page.jpg">',
        preferences: ForumHtmlReaderPreferences.defaults(),
        theme: _darkTheme,
        sourceId: 'phase4-adapt',
        threadId: '100',
        imageCacheOwnerId: '100',
      );
      final fragment = html_parser.parseFragment(prepared.preparedHtml);
      final body = const CsslibAuthorColorParser().parseOwn(
        fragment.querySelector('#body')!,
      );

      expect(body.foreground?.toARGB32(), isNot(0xFF000000));
      expect(prepared.themeAdaptationStats.explicitForegroundCount, 1);
      expect(prepared.themeAdaptationStats.remappedForegroundCount, 1);
      expect(prepared.sequence.entries, hasLength(1));
      expect(prepared.sequence.entries.single.attachmentId, '9');
    });
  });

  test('fragment deduplication mutates the existing DOM without reparsing', () {
    final fragment = html_parser.parseFragment(
      '<img id="aimg_1" src="data/attachment/forum/page.jpg">'
      '<img id="aimg_1" src="data/attachment/forum/page.jpg">',
    );

    final removed = ForumHtmlImageDeduplicator(
      resolveUrl: const SiteUrlResolver().resolve,
    ).deduplicateAttachmentImagesInFragment(fragment);

    expect(removed, 1);
    expect(fragment.querySelectorAll('img'), hasLength(1));
  });

  test('core pipeline uses neutral resources and the explicit URL origin', () {
    final origin = Uri.parse('https://origin.example.invalid/base/');
    final pipeline = ForumHtmlRenderPipeline(
      imagePolicy: const _ImagePolicy(),
      resolveUrl: (raw) => origin.resolve(raw).toString(),
    );
    final prepared = pipeline.prepare(
      html:
          '<img id="aimg_9" src="first.jpg" width="640" height="480">'
          '<img id="aimg_9" '
          'src="https://origin.example.invalid/base/first.jpg">'
          '<img id="aimg_10" src="last.jpg" width="320" height="600">',
      preferences: ForumHtmlReaderPreferences.defaults(),
      theme: forumHtmlTestTheme,
      sourceId: 'neutral-image-pipeline',
      threadId: null,
      imageCacheOwnerId: null,
    );
    final images = html_parser
        .parseFragment(prepared.preparedHtml)
        .querySelectorAll('img');

    expect(images, hasLength(2));
    expect(prepared.totalImageCount, 2);
    expect(prepared.sequence.entries.map((entry) => entry.index), [0, 1]);
    expect(prepared.sequence.entries.map((entry) => entry.cacheKey), [
      'core-0',
      'core-1',
    ]);
    expect(prepared.sequence.entries.first.resource, isA<_ImageResource>());
    expect(prepared.sequence.entries.first.rawSrc, 'first.jpg');
    expect(prepared.sequence.entries.first.url, '${origin}first.jpg');
    expect(prepared.sequence.entries.first.htmlWidth, 640);
    expect(prepared.sequence.entries.first.htmlHeight, 480);
    expect(prepared.sequence.entries.last.url, '${origin}last.jpg');
    expect(prepared.sequence.entries.last.htmlWidth, 320);
    expect(prepared.sequence.entries.last.htmlHeight, 600);
    expect(images.first.attributes[forumHtmlReadableImageIndexAttribute], '0');
    expect(images.last.attributes[forumHtmlReadableImageIndexAttribute], '1');
    expect(prepared.attachmentIdsByUrl['${origin}first.jpg'], '9');
    expect(prepared.attachmentIdsByUrl['${origin}last.jpg'], '10');
  });
}

const _darkTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.dark,
  surface: Color(0xFF241916),
  foreground: Color(0xFFF6E8DD),
  link: Color(0xFF8DB7FF),
  quoteSurface: Color(0xFF30231F),
  quoteForeground: Color(0xFFF6E8DD),
  codeSurface: Color(0xFF332622),
  codeForeground: Color(0xFFF6E8DD),
);

final class _CountingFragmentCodec implements ForumHtmlFragmentCodec {
  final _delegate = const HtmlPackageForumHtmlFragmentCodec();
  var parseCount = 0;
  var serializeCount = 0;

  @override
  html_dom.DocumentFragment parse(String html) {
    parseCount++;
    return _delegate.parse(html);
  }

  @override
  String serialize(html_dom.DocumentFragment fragment) {
    serializeCount++;
    return _delegate.serialize(fragment);
  }
}

final class _ImageResource implements ForumHtmlPreparedImageResource {
  const _ImageResource(this.cacheKey);

  @override
  final String cacheKey;
}

final class _ImagePolicy implements ForumHtmlPreparationImagePolicy {
  const _ImagePolicy();

  @override
  ForumHtmlPreparedImageResource prepareInline({
    required Uri url,
    required String? threadId,
    required String? imageCacheOwnerId,
    required int imageIndex,
    double? htmlWidth,
    double? htmlHeight,
    String? alt,
    String? title,
  }) => _ImageResource('core-$imageIndex');
}
