import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_legacy_markup_normalization.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_legacy_markup_normalizer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_classifier.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_extractor.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

import '../test_support/novel_phase0_api_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const normalizer = DefaultNovelReaderLegacyMarkupNormalizer();

  test('removes only empty and quote-only font face attributes', () {
    const source =
        '<strong><font id="empty" face="" color="red" size="5" '
        'style="background-color:#fff">空值</font></strong>'
        '<font id="entity" face="&amp;quot">实体引号</font>'
        '<font id="literal" face="\'">字面引号</font>'
        '<font id="families" face="&quot;,&apos;">空 family 列表</font>'
        '<font id="boolean" face>布尔空属性</font>';

    final result = normalizer.normalize(source);
    final fragment = html_parser.parseFragment(result.html);

    expect(result.summary.revision, 1);
    expect(result.summary.normalizedAttributeCount, 5);
    expect(result.summary.reasonCounts, {
      NovelReaderLegacyMarkupNormalizationReason.emptyFontFace: 2,
      NovelReaderLegacyMarkupNormalizationReason.invalidQuoteOnlyFontFace: 2,
      NovelReaderLegacyMarkupNormalizationReason.invalidNoUsableFontFamilyToken:
          1,
    });
    for (final font in fragment.querySelectorAll('font')) {
      expect(font.attributes, isNot(contains('face')));
    }
    final empty = fragment.querySelector('#empty')!;
    expect(empty.attributes['color'], 'red');
    expect(empty.attributes['size'], '5');
    expect(empty.attributes['style'], contains('background-color'));
    expect(fragment.text, '空值实体引号字面引号空 family 列表布尔空属性');
    expect(fragment.querySelectorAll('strong'), hasLength(1));
  });

  test('preserves valid known and unknown font families byte for byte', () {
    for (final source in const <String>[
      '<font face="Arial">正文</font>',
      '<font face="Uninstalled Fantasy Font">正文</font>',
      '<font face="\'Noto Serif CJK TC\', serif">正文</font>',
      '<font face="&amp;quotArial&amp;quot">正文</font>',
    ]) {
      final result = normalizer.normalize(source);

      expect(result.html, source, reason: source);
      expect(result.summary.normalizedAttributeCount, 0, reason: source);
      expect(result.summary.reasonCounts, isEmpty, reason: source);
    }
  });

  test('is deterministic and idempotent after a normalization pass', () {
    const source = '<p><font face="&amp;quot">正文</font></p>';

    final first = normalizer.normalize(source);
    final second = normalizer.normalize(first.html);

    expect(second.html, first.html);
    expect(first.summary.normalizedAttributeCount, 1);
    expect(second.summary.normalizedAttributeCount, 0);
    expect(second.summary.revision, first.summary.revision);
  });

  test(
    'shared preparation gives vertical and paged consumers normalized HTML',
    () async {
      final source = File(
        novelComplexHtmlInvalidFontFixturePath,
      ).readAsStringSync();
      final prepared = await _prepare(source, theme: _sepiaTheme);

      expect(prepared.legacyMarkupNormalization.revision, 1);
      expect(prepared.legacyMarkupNormalization.normalizedAttributeCount, 2);
      expect(prepared.html, isNot(contains('face=')));
      expect(prepared.renderDocument.preparedHtml, isNot(contains('face=')));
      expect(
        prepared.flowUnits.map((unit) => unit.html),
        everyElement(isNot(contains('face='))),
      );
      expect(prepared.renderDocument.preparedHtml, contains('喜歡的人和義妹'));
      expect(prepared.renderDocument.preparedHtml, contains('第一話（１）'));
    },
  );

  test('keeps valid unknown fonts on the flowable complex route', () async {
    final prepared = await _prepare(
      '<p><font face="Uninstalled Fantasy Font">有效未知字体</font></p>',
      theme: _lightTheme,
    );
    final classified = const NovelReaderPaginationAtomExtractor()
        .extract(prepared)
        .map(
          (atom) => const NovelReaderPaginationAtomClassifier().classify(
            atom: atom,
            baseStyle: _baseStyle,
            preferences: _preferences,
            theme: _lightTheme,
          ),
        )
        .single;

    expect(prepared.html, contains('face="Uninstalled Fantasy Font"'));
    expect(prepared.legacyMarkupNormalization.normalizedAttributeCount, 0);
    expect(classified.route, NovelReaderPaginationRoute.flowableComplexText);
    expect(classified.reason, NovelReaderPaginationRouteReason.unsupportedFont);
  });

  test(
    'matches the explicit no-face renderer input in every reader theme',
    () async {
      const damaged =
          '<strong><font face="&amp;quot" color="#992211" size="5" '
          'style="background-color:#f2df88">主题正文</font></strong>';
      const control =
          '<strong><font color="#992211" size="5" '
          'style="background-color:#f2df88">主题正文</font></strong>';

      for (final theme in const <ForumHtmlThemeContext>[
        _lightTheme,
        _sepiaTheme,
        _darkTheme,
      ]) {
        final normalized = await _prepare(damaged, theme: theme);
        final expected = await _prepare(control, theme: theme);

        expect(
          normalized.renderDocument.preparedHtml,
          expected.renderDocument.preparedHtml,
          reason: theme.signature,
        );
      }
    },
  );
}

Future<NovelReaderPreparedChapter> _prepare(
  String html, {
  required ForumHtmlThemeContext theme,
}) {
  return const DefaultNovelReaderHtmlPreparationService().prepare(
    rawHtml: html,
    episode: _episode,
    preferences: _preferences,
    theme: theme,
    sourceId: _episode.episodeId,
    threadId: _episode.sourceTid,
    imageCacheOwnerId: _episode.sourceTid,
  );
}

const _episode = NovelEpisodeItem(
  episodeId: 'legacy-normalization-episode',
  novelId: 'legacy-normalization-novel',
  sourceTid: '565218',
  episodeTitle: 'Legacy normalization',
  orderIndex: 0,
);

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
