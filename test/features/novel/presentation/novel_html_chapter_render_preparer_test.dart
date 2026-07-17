import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:material_color_utilities/hct/hct.dart';
import 'package:y300/features/novel/presentation/services/novel_html_chapter_render_preparer.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/reader_shared/presentation/rich_text/color/rich_text_color_contrast.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_author_color_parser.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  const preparer = NovelHtmlChapterRenderPreparer();
  const colorParser = CsslibAuthorColorParser();

  test(
    'adapts black author text against the resolved dark reader surface',
    () async {
      const source = '<font id="body" color="black">深色小说正文</font>';

      final prepared = await preparer.prepare(
        rawHtml: source,
        preferences: ForumHtmlReaderPreferences.defaults(),
        theme: _darkTheme,
        sourceId: 'episode-dark',
        threadId: '100',
        imageCacheOwnerId: '100',
      );
      final body = colorParser.parseOwn(
        html_parser
            .parseFragment(prepared.document.preparedHtml)
            .querySelector('#body')!,
      );

      expect(body.foreground?.toARGB32(), isNot(0xFF000000));
      expect(
        _visibleContrast(body.foreground!, _darkTheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(prepared.document.themeSignature, _darkTheme.signature);
      expect(prepared.document.themeAdaptationStats.remappedForegroundCount, 1);
      expect(source, contains('color="black"'));
    },
  );

  test(
    'uses sepia as a light surface instead of applying dark mapping',
    () async {
      final prepared = await preparer.prepare(
        rawHtml:
            '<span id="highlight" '
            'style="color: black; background-color: #FFE082">棕褐高亮</span>',
        preferences: ForumHtmlReaderPreferences.defaults(),
        theme: _sepiaTheme,
        sourceId: 'episode-sepia',
        threadId: '100',
        imageCacheOwnerId: '100',
      );
      final style = colorParser.parseOwn(
        html_parser
            .parseFragment(prepared.document.preparedHtml)
            .querySelector('#highlight')!,
      );
      final backgroundTone = Hct.fromInt(style.background!.toARGB32()).tone;

      expect(backgroundTone, greaterThan(70));
      expect(
        _visibleContrast(style.foreground!, style.background!),
        greaterThanOrEqualTo(4.5),
      );
      expect(prepared.document.themeSignature, _sepiaTheme.signature);
    },
  );

  test(
    'converts text before adapting colors and preserves image identity',
    () async {
      const convertedHtml =
          '<a id="source-link" href="thread-101-1-1.html">'
          '<font id="converted" color="black">轉換後正文</font></a>'
          '<img id="aimg_9" src="data/attachment/forum/page.jpg">';
      final conversionService = _FixedConversionService(convertedHtml);
      final orderedPreparer = NovelHtmlChapterRenderPreparer(
        conversionService: conversionService,
      );
      const rawHtml =
          '<a id="source-link" href="thread-101-1-1.html">'
          '<font id="converted" color="black">转换前正文</font></a>'
          '<img id="aimg_9" src="data/attachment/forum/page.jpg">';

      final prepared = await orderedPreparer.prepare(
        rawHtml: rawHtml,
        preferences: ForumHtmlReaderPreferences.defaults().copyWith(
          conversionMode: TextConversionMode.toTraditional,
        ),
        theme: _darkTheme,
        sourceId: 'episode-converted',
        threadId: '100',
        imageCacheOwnerId: '100',
      );
      final fragment = html_parser.parseFragment(
        prepared.document.preparedHtml,
      );
      final converted = colorParser.parseOwn(
        fragment.querySelector('#converted')!,
      );

      expect(conversionService.callCount, 1);
      expect(prepared.html, contains('轉換後正文'));
      expect(prepared.document.preparedHtml, contains('轉換後正文'));
      expect(prepared.document.preparedHtml, isNot(contains('转换前正文')));
      expect(converted.foreground?.toARGB32(), isNot(0xFF000000));
      expect(
        fragment.querySelector('#source-link')?.attributes['href'],
        'thread-101-1-1.html',
      );
      expect(prepared.convertedTextNodeCount, 1);
      expect(prepared.document.sequence.entries, hasLength(1));
      expect(prepared.document.sequence.entries.single.attachmentId, '9');
      expect(
        prepared.document.sequence.entries.single.url,
        'https://bbs.yamibo.com/data/attachment/forum/page.jpg',
      );
      expect(rawHtml, contains('转换前正文'));
    },
  );

  test(
    'produces deterministic HTML and image sequences for equal inputs',
    () async {
      const source =
          '<font color="#99BBF1">标题</font>'
          '<img src="data/attachment/forum/page.jpg">';

      final first = await preparer.prepare(
        rawHtml: source,
        preferences: ForumHtmlReaderPreferences.defaults(),
        theme: _sepiaTheme,
        sourceId: 'episode-stable',
        threadId: '100',
        imageCacheOwnerId: '100',
      );
      final second = await preparer.prepare(
        rawHtml: source,
        preferences: ForumHtmlReaderPreferences.defaults(),
        theme: _sepiaTheme,
        sourceId: 'episode-stable',
        threadId: '100',
        imageCacheOwnerId: '100',
      );

      expect(second.document.preparedHtml, first.document.preparedHtml);
      expect(
        second.document.sequence.entries.map((entry) => entry.cacheKey),
        first.document.sequence.entries.map((entry) => entry.cacheKey),
      );
      expect(
        second.document.themeAdaptationStats.minimumResultContrast,
        first.document.themeAdaptationStats.minimumResultContrast,
      );
    },
  );
}

double _visibleContrast(Color foreground, Color background) {
  const contrast = FlutterRichTextColorContrast();
  return contrast.contrastRatio(
    contrast.composite(foreground, background),
    background,
  );
}

final class _FixedConversionService implements HtmlTextNodeConversionService {
  _FixedConversionService(this.outputHtml);

  final String outputHtml;
  int callCount = 0;

  @override
  Future<HtmlTextNodeConversionResult> convert({
    required String html,
    required TextConverter converter,
    HtmlTextNodeConversionOptions options =
        const HtmlTextNodeConversionOptions(),
  }) async {
    callCount++;
    return HtmlTextNodeConversionResult(
      html: outputHtml,
      convertedTextNodeCount: 1,
      converterId: converter.id,
    );
  }
}

const _darkTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.dark,
  surface: Color(0xFF141414),
  foreground: Color(0xFFE9E9E9),
  link: Color(0xFF8DB7FF),
  quoteSurface: Color(0xFF242424),
  quoteForeground: Color(0xFFAAA39A),
  codeSurface: Color(0xFF202020),
  codeForeground: Color(0xFFE9E9E9),
);

const _sepiaTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFF4EAD7),
  foreground: Color(0xFF4C3A21),
  link: Color(0xFF6A55A3),
  quoteSurface: Color(0xFFE8D8B8),
  quoteForeground: Color(0xFF8B7355),
  codeSurface: Color(0xFFEFE0C4),
  codeForeground: Color(0xFF4C3A21),
);
