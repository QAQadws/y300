import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_html_reader_preferences_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';

void main() {
  testWidgets('measures a candidate with the real HTML renderer', (
    tester,
  ) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final chapter = await _prepare();
    final key = NovelReaderPaginationKey(
      episodeId: chapter.episodeId,
      contentHash: chapter.contentHash,
      viewportWidthPx: 320,
      viewportHeightPx: 600,
      typographySignature: 'font=18.5|line=1.6',
      themeSignature: chapter.themeSignature,
      imageDimensionRevision: chapter.imageDimensionRevision,
      rendererRevision: 1,
    );
    final adapter = NovelReaderHtmlPaginationMeasureAdapter(
      hostContext: hostContext,
      theme: _theme,
      preferences: ForumHtmlReaderPreferences.defaults(),
      sourceId: chapter.episodeId,
      threadId: '100',
      imageCacheOwnerId: '100',
    );

    final future = adapter.measure(
      NovelReaderPaginationMeasureRequest(
        html: chapter.html,
        chapter: chapter,
        key: key,
      ),
    );
    await tester.pump();
    await tester.pump();
    final result = await future;

    expect(result.height, greaterThan(0));
  });

  testWidgets('matches the production renderer across the layout matrix', (
    tester,
  ) async {
    final cases =
        <
          ({
            ForumHtmlThemeContext theme,
            ForumHtmlReaderPreferences preferences,
            double textScale,
            int width,
          })
        >[
          (
            theme: _theme,
            preferences: _preferences(fontScale: 0.7, lineHeight: 1),
            textScale: 1,
            width: 240,
          ),
          (
            theme: _sepiaTheme,
            preferences: _preferences(fontScale: 18.5 / 14, lineHeight: 1.6),
            textScale: 1,
            width: 320,
          ),
          (
            theme: _darkTheme,
            preferences: _preferences(fontScale: 2, lineHeight: 2.5),
            textScale: 1,
            width: 600,
          ),
          (
            theme: _theme,
            preferences: _preferences(fontScale: 1.15, lineHeight: 1.5),
            textScale: 1.4,
            width: 420,
          ),
        ];

    for (final testCase in cases) {
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: testCase.theme.brightness == ForumHtmlBrightness.dark
                ? Brightness.dark
                : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(testCase.textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final chapter = await _prepare(
        rawHtml: _matrixHtml,
        preferences: testCase.preferences,
        theme: testCase.theme,
      );
      final key = NovelReaderPaginationKey(
        episodeId: chapter.episodeId,
        contentHash: chapter.contentHash,
        viewportWidthPx: testCase.width,
        viewportHeightPx: 800,
        typographySignature:
            'font=${testCase.preferences.typography.fontScale}'
            '|line=${testCase.preferences.typography.lineHeightScale}'
            '|scale=${testCase.textScale}',
        themeSignature: chapter.themeSignature,
        imageDimensionRevision: chapter.imageDimensionRevision,
        rendererRevision: 14,
      );
      final adapter = NovelReaderHtmlPaginationMeasureAdapter(
        hostContext: hostContext,
        theme: testCase.theme,
        preferences: testCase.preferences,
        sourceId: chapter.episodeId,
        threadId: '100',
        imageCacheOwnerId: '100',
      );
      final session = adapter.create(chapter: chapter, key: key);
      final measuredFuture = session.measure(
        NovelReaderPaginationMeasureRequest(
          html: chapter.html,
          chapter: chapter,
          key: key,
          atomId: 'matrix-candidate',
          startOffset: 0,
          endOffset: 24,
        ),
      );
      var measurementCompleted = false;
      unawaited(
        measuredFuture.then<void>(
          (_) => measurementCompleted = true,
          onError: (Object error, StackTrace stackTrace) {
            measurementCompleted = true;
          },
        ),
      );
      for (var frame = 0; frame < 20 && !measurementCompleted; frame += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(measurementCompleted, isTrue);
      final measured = await measuredFuture;
      await session.dispose();
      await tester.pump();

      final rendererKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: testCase.theme.brightness == ForumHtmlBrightness.dark
                ? Brightness.dark
                : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(testCase.textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: testCase.width.toDouble(),
                  child: ForumHtmlWidgetPostRenderer(
                    key: rendererKey,
                    html: chapter.html,
                    theme: testCase.theme,
                    preparedDocument: chapter.renderDocument.copyWith(
                      preparedHtml: chapter.html,
                    ),
                    preferences: testCase.preferences,
                    sourceId: chapter.episodeId,
                    threadId: '100',
                    imageCacheOwnerId: '100',
                    buildAsync: false,
                    enableCaching: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final renderedHeight = tester.getSize(find.byKey(rendererKey)).height;
      expect(
        measured.height,
        closeTo(renderedHeight, 0.01),
        reason:
            'width=${testCase.width}, '
            'fontScale=${testCase.preferences.typography.fontScale}, '
            'lineHeight=${testCase.preferences.typography.lineHeightScale}, '
            'textScale=${testCase.textScale}, '
            'theme=${testCase.theme.brightness.name}',
      );
      expect(tester.takeException(), isNull);
    }
  });
}

Future<NovelReaderPreparedChapter> _prepare({
  String rawHtml = '<p>需要由真实 HTML renderer 测量的正文。</p>',
  ForumHtmlReaderPreferences? preferences,
  ForumHtmlThemeContext theme = _theme,
}) {
  const episode = NovelEpisodeItem(
    episodeId: 'measure-episode',
    novelId: 'measure-novel',
    sourceTid: '100',
    episodeTitle: '测量测试',
    orderIndex: 0,
  );
  return const DefaultNovelReaderHtmlPreparationService().prepare(
    rawHtml: rawHtml,
    episode: episode,
    preferences:
        preferences ??
        const NovelHtmlReaderPreferencesAdapter().map(
          NovelReaderPreferences.defaults(),
        ),
    theme: theme,
    sourceId: episode.episodeId,
    threadId: episode.sourceTid,
    imageCacheOwnerId: episode.sourceTid,
  );
}

ForumHtmlReaderPreferences _preferences({
  required double fontScale,
  required double lineHeight,
}) {
  return ForumHtmlReaderPreferences.defaults().copyWith(
    typography: RichTextTypography(
      fontScale: fontScale,
      lineHeightScale: lineHeight,
      paragraphSpacing: ForumHtmlReaderPreferences.defaultParagraphSpacing,
    ),
  );
}

const _matrixHtml =
    '<div><font face="Fantasy Novel Font"><strong>复杂样式标题</strong></font>'
    '<br>正文 mixed 123，包含 <ruby>漢<rt>かん</rt><rp>(</rp><rp>)</rp></ruby>'
    ' 与连续换行。<br>第二行正文用于验证实际行盒高度。</div>';

const _theme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFF4EAD7),
  foreground: Color(0xFF4C3A21),
  link: Color(0xFF6A55A3),
  quoteSurface: Color(0xFFE8D8B8),
  quoteForeground: Color(0xFF8B7355),
  codeSurface: Color(0xFFEFE0C4),
  codeForeground: Color(0xFF4C3A21),
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
  surface: Color(0xFF171717),
  foreground: Color(0xFFE7E7E7),
  link: Color(0xFFB9A7FF),
  quoteSurface: Color(0xFF2A2A2A),
  quoteForeground: Color(0xFFD0D0D0),
  codeSurface: Color(0xFF242424),
  codeForeground: Color(0xFFF0F0F0),
);
