import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_classifier.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_text_run_extractor.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_author_color_parser.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  const classifier = NovelReaderPaginationAtomClassifier();
  const extractor = NovelReaderPaginationTextRunExtractor();

  test('extracts inherited inline styles, links and stable anchors', () {
    final atom = _atom(
      '<p><font color="#123456" style="background-color:#f0f0f0">'
      '前<strong>粗</strong><em>斜</em>'
      '<a href="thread-1-1-1.html">链接</a></font><br>后</p>',
    );
    final classified = classifier.classify(
      atom: atom,
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );

    expect(classified.route, NovelReaderPaginationRoute.safeText);
    final runs = extractor.extract(
      classifiedAtom: classified,
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );

    expect(runs.map((run) => run.text).join(), '前粗斜链接\n后');
    expect(runs.first.style.color?.toARGB32(), 0xFF123456);
    expect(runs.first.style.backgroundColor?.toARGB32(), 0xFFF0F0F0);
    expect(
      runs.singleWhere((run) => run.text == '粗').style.fontWeight,
      FontWeight.w700,
    );
    expect(
      runs.singleWhere((run) => run.text == '斜').style.fontStyle,
      FontStyle.italic,
    );
    final link = runs.singleWhere((run) => run.text == '链接');
    expect(link.href, 'thread-1-1-1.html');
    expect(link.style.color, _lightTheme.link);
    expect(link.style.decoration, TextDecoration.underline);
    final lineBreak = runs.singleWhere((run) => run.isParagraphBreak);
    expect(lineBreak.startAnchor.textOffset, lineBreak.endAnchor.textOffset);
    expect(runs.first.startAnchor.textOffset, 0);
    expect(runs.last.endAnchor.textOffset, atom.textLength);
  });

  test('does not apply a normalized Discuz font size twice', () {
    final atom = _atom(
      '<p><font size="6" style="font-size:150%">正文</font></p>',
    );
    final classified = classifier.classify(
      atom: atom,
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );
    final run = extractor
        .extract(
          classifiedAtom: classified,
          baseStyle: _baseStyle,
          preferences: _preferences,
          theme: _lightTheme,
        )
        .single;

    expect(run.style.fontSize, closeTo(27.75, 0.001));
  });

  test(
    'routes ruby, tables, collapses and inline images away from safe text',
    () {
      final cases =
          <
            String,
            (NovelReaderPaginationRoute, NovelReaderPaginationRouteReason)
          >{
            '<p>前<ruby>字<rt>じ</rt></ruby>后</p>': (
              NovelReaderPaginationRoute.rubyInline,
              NovelReaderPaginationRouteReason.containsRuby,
            ),
            '<table><tr><td>正文</td></tr></table>': (
              NovelReaderPaginationRoute.tableBlock,
              NovelReaderPaginationRouteReason.containsTable,
            ),
            '<div class="showcollapse_box"><div>正文</div></div>': (
              NovelReaderPaginationRoute.collapseBlock,
              NovelReaderPaginationRouteReason.containsCollapse,
            ),
            '<p>前<img src="static/image/smiley/default/smile.gif">后</p>': (
              NovelReaderPaginationRoute.complexHtml,
              NovelReaderPaginationRouteReason.containsImage,
            ),
          };

      for (final entry in cases.entries) {
        final classified = classifier.classify(
          atom: _atom(entry.key),
          baseStyle: _baseStyle,
          preferences: _preferences,
          theme: _lightTheme,
        );
        expect(classified.route, entry.value.$1, reason: entry.key);
        expect(classified.reason, entry.value.$2, reason: entry.key);
        expect(classified.isBreakable, isFalse, reason: entry.key);
      }
    },
  );

  test('routes unknown fonts and unsupported CSS to complex HTML', () {
    final unknownFont = classifier.classify(
      atom: _atom('<p><font face="Uninstalled Fantasy Font">正文</font></p>'),
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );
    final unsupportedCss = classifier.classify(
      atom: _atom('<p><span style="padding:20px">正文</span></p>'),
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );
    final unsupportedDecoration = classifier.classify(
      atom: _atom(
        '<p><span style="text-decoration:line-through">正文</span></p>',
      ),
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );

    expect(unknownFont.route, NovelReaderPaginationRoute.complexHtml);
    expect(
      unknownFont.reason,
      NovelReaderPaginationRouteReason.unsupportedFont,
    );
    expect(unsupportedCss.route, NovelReaderPaginationRoute.complexHtml);
    expect(
      unsupportedCss.reason,
      NovelReaderPaginationRouteReason.unsupportedStyle,
    );
    expect(unsupportedDecoration.route, NovelReaderPaginationRoute.complexHtml);
    expect(
      unsupportedDecoration.reason,
      NovelReaderPaginationRouteReason.unsupportedStyle,
    );
  });

  test('keeps semantic underline in the supported text subset', () {
    final classified = classifier.classify(
      atom: _atom('<p><u>下划线</u></p>'),
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );

    expect(classified.route, NovelReaderPaginationRoute.safeText);
    final run = extractor
        .extract(
          classifiedAtom: classified,
          baseStyle: _baseStyle,
          preferences: _preferences,
          theme: _lightTheme,
        )
        .single;
    expect(run.style.decoration, TextDecoration.underline);
  });

  test('accepts standard root alignment with a known author font', () {
    for (final alignment in const <String>[
      'left',
      'right',
      'center',
      'justify',
    ]) {
      final classified = classifier.classify(
        atom: _atom(
          '<div align="$alignment"><font face="Arial">正文</font></div>',
        ),
        baseStyle: _baseStyle,
        preferences: _preferences,
        theme: _lightTheme,
      );

      expect(
        classified.route,
        NovelReaderPaginationRoute.safeText,
        reason: alignment,
      );
      final run = extractor
          .extract(
            classifiedAtom: classified,
            baseStyle: _baseStyle,
            preferences: _preferences,
            theme: _lightTheme,
          )
          .single;
      expect(run.style.fontFamily, 'Arial', reason: alignment);
    }
  });

  test('rejects unknown or nested alignment attributes', () {
    final unknownValue = classifier.classify(
      atom: _atom('<div align="diagonal">正文</div>'),
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );
    final nestedAlignment = classifier.classify(
      atom: _atom('<div><span align="left">正文</span></div>'),
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );

    expect(unknownValue.route, NovelReaderPaginationRoute.complexHtml);
    expect(
      unknownValue.reason,
      NovelReaderPaginationRouteReason.unsupportedAttribute,
    );
    expect(nestedAlignment.route, NovelReaderPaginationRoute.complexHtml);
    expect(
      nestedAlignment.reason,
      NovelReaderPaginationRouteReason.unsupportedAttribute,
    );
  });

  test('accepts only the controlled pstatus class', () {
    final editStatus = classifier.classify(
      atom: _atom(
        '<i class="pstatus">最后编辑时间</i>',
        kind: NovelReaderPaginationAtomKind.inlineText,
      ),
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );
    final unknownClass = classifier.classify(
      atom: _atom(
        '<i class="custom-status">正文</i>',
        kind: NovelReaderPaginationAtomKind.inlineText,
      ),
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );

    expect(editStatus.route, NovelReaderPaginationRoute.safeText);
    expect(unknownClass.route, NovelReaderPaginationRoute.complexHtml);
    expect(
      unknownClass.reason,
      NovelReaderPaginationRouteReason.unsupportedAttribute,
    );
  });

  test('maps common Song typeface names through the shared resolver', () {
    for (final family in const <String>['宋体', 'SimSun']) {
      final classified = classifier.classify(
        atom: _atom('<div><font face="$family">章节标题</font></div>'),
        baseStyle: _baseStyle,
        preferences: _preferences,
        theme: _lightTheme,
      );

      expect(classified.route, NovelReaderPaginationRoute.safeText);
      final run = extractor
          .extract(
            classifiedAtom: classified,
            baseStyle: _baseStyle,
            preferences: _preferences,
            theme: _lightTheme,
          )
          .single;
      expect(run.style.fontFamily, 'SimSun');
    }
  });

  test('keeps prepared author colors aligned across reader themes', () {
    for (final theme in <ForumHtmlThemeContext>[
      _lightTheme,
      _sepiaTheme,
      _darkTheme,
    ]) {
      final prepared = const DefaultForumHtmlRenderPreparer().prepare(
        html:
            '<p><span style="color:#222222;background-color:#ffffff">'
            '主题正文</span></p>',
        preferences: _preferences,
        theme: theme,
        sourceId: 'theme-${theme.brightness.name}',
        threadId: null,
        imageCacheOwnerId: null,
      );
      final atom = _atom(prepared.preparedHtml);
      final classified = classifier.classify(
        atom: atom,
        baseStyle: _baseStyle.copyWith(color: theme.foreground),
        preferences: _preferences,
        theme: theme,
      );
      expect(classified.route, NovelReaderPaginationRoute.safeText);
      final run = extractor
          .extract(
            classifiedAtom: classified,
            baseStyle: _baseStyle.copyWith(color: theme.foreground),
            preferences: _preferences,
            theme: theme,
          )
          .single;
      final span = html_parser
          .parseFragment(prepared.preparedHtml)
          .querySelector('span')!;
      final preparedColors = const CsslibAuthorColorParser().parse(span);

      expect(run.style.color, preparedColors.foreground);
      expect(run.style.backgroundColor, preparedColors.background);
    }
  });

  test('isolated readable images keep their dedicated route', () {
    final classified = classifier.classify(
      atom: _atom(
        '<img data-y300-readable-image-index="0" src="image.jpg">',
        kind: NovelReaderPaginationAtomKind.image,
        imagePolicy: NovelReaderImagePagePolicy.isolated,
      ),
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );

    expect(classified.route, NovelReaderPaginationRoute.isolatedImage);
    expect(
      classified.reason,
      NovelReaderPaginationRouteReason.isolatedReadableImage,
    );
  });

  test('routes a structural br spacer through the safe text path', () {
    final classified = classifier.classify(
      atom: _atom('<br>', kind: NovelReaderPaginationAtomKind.spacer),
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );

    expect(classified.route, NovelReaderPaginationRoute.safeText);
    expect(classified.isBreakable, isTrue);
    final runs = extractor.extract(
      classifiedAtom: classified,
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _lightTheme,
    );
    expect(runs, hasLength(1));
    expect(runs.single.isParagraphBreak, isTrue);
  });
}

NovelReaderPaginationAtom _atom(
  String html, {
  NovelReaderPaginationAtomKind kind = NovelReaderPaginationAtomKind.text,
  NovelReaderImagePagePolicy imagePolicy = NovelReaderImagePagePolicy.inline,
}) {
  final textLength = (html_parser.parseFragment(html).text ?? '').runes.length;
  return NovelReaderPaginationAtom(
    atomId: 'episode:atom',
    kind: kind,
    html: html,
    startAnchor: const NovelReaderTextAnchor(
      episodeId: 'episode',
      nodeId: 'node-1',
    ),
    endAnchor: NovelReaderTextAnchor(
      episodeId: 'episode',
      nodeId: 'node-1',
      textOffset: textLength,
    ),
    textLength: textLength,
    imageIndices: imagePolicy == NovelReaderImagePagePolicy.isolated
        ? <int>[0]
        : const <int>[],
    breakability: imagePolicy == NovelReaderImagePagePolicy.isolated
        ? NovelReaderFlowUnitBreakability.blockImage
        : NovelReaderFlowUnitBreakability.text,
    imagePagePolicy: imagePolicy,
  );
}

const _preferences = ForumHtmlReaderPreferences(
  typography: RichTextTypography(
    fontScale: 18.5 / 14,
    lineHeightScale: 1.6,
    paragraphSpacing: 12,
  ),
  conversionMode: TextConversionMode.none,
);

const _baseStyle = TextStyle(
  color: Color(0xFF1F1F1F),
  fontSize: 18.5,
  height: 1.6,
);

const _lightTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFFDFDFD),
  foreground: Color(0xFF1F1F1F),
  link: Color(0xFF3367D6),
  quoteSurface: Color(0xFFF1F1F1),
  quoteForeground: Color(0xFF737373),
  codeSurface: Color(0xFFF5F5F5),
  codeForeground: Color(0xFF1F1F1F),
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
