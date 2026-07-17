import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/thread/presentation/html_rendering/forum_html_fragment_codec.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_image_deduplicator.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_author_color_parser.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'forum_html_test_theme.dart';

void main() {
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

    final removed = const ForumHtmlImageDeduplicator()
        .deduplicateAttachmentImagesInFragment(fragment);

    expect(removed, 1);
    expect(fragment.querySelectorAll('img'), hasLength(1));
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
