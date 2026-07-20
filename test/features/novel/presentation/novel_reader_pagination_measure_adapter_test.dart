import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_html_reader_preferences_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

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
    final result = await future;

    expect(result.height, greaterThan(0));
  });
}

Future<NovelReaderPreparedChapter> _prepare() {
  const episode = NovelEpisodeItem(
    episodeId: 'measure-episode',
    novelId: 'measure-novel',
    sourceTid: '100',
    episodeTitle: '测量测试',
    orderIndex: 0,
  );
  return const DefaultNovelReaderHtmlPreparationService().prepare(
    rawHtml: '<p>需要由真实 HTML renderer 测量的正文。</p>',
    episode: episode,
    preferences: NovelHtmlReaderPreferencesAdapter().map(
      NovelReaderPreferences.defaults(),
    ),
    theme: _theme,
    sourceId: episode.episodeId,
    threadId: episode.sourceTid,
    imageCacheOwnerId: episode.sourceTid,
  );
}

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
