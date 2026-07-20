import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/services/novel_forum_html_render_theme_factory.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';

void main() {
  testWidgets('performance policy falls back through the surface callback', (
    tester,
  ) async {
    final preferences = NovelReaderPreferences.defaults().copyWith(
      flowMode: NovelReaderFlowMode.pagedLtr,
    );
    final theme = ThemeData.light();
    final palette = const NovelReaderThemeResolver().resolve(
      preferences: preferences,
      theme: theme,
      platformBrightness: Brightness.light,
    );
    final typography = const NovelReaderTypographyResolver().resolve(
      preferences: preferences,
      theme: theme,
      palette: palette,
    );
    final htmlTheme = const NovelForumHtmlRenderThemeFactory().fromPalette(
      palette,
    );
    var fallbackCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: NovelReaderHtmlPagedSurface(
            rawHtml: '<p>${List<String>.filled(80, '自动性能降级验证正文。').join()}</p>',
            episode: _episode,
            preferences: preferences,
            typography: typography,
            theme: htmlTheme,
            imageReferer: 'https://bbs.yamibo.com/',
            progressSnapshot: const NovelReaderProgressSnapshot(
              novelId: 'performance-novel',
              episodeId: 'performance-episode',
              flowMode: NovelReaderFlowMode.pagedLtr,
              scrollOffset: 0,
              pageIndex: 0,
              progressPercent: 0,
            ),
            performancePolicy: const NovelReaderPaginationPerformancePolicy(
              enforceBudgets: true,
              plainTextBudget: NovelReaderPaginationPerformanceBudget(
                firstPage: Duration.zero,
                fullPlan: Duration.zero,
              ),
              mixedContentBudget: NovelReaderPaginationPerformanceBudget(
                firstPage: Duration.zero,
                fullPlan: Duration.zero,
              ),
            ),
            onFallbackToVertical: () {
              fallbackCount += 1;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fallbackCount, 1);
  });
}

const _episode = NovelEpisodeItem(
  episodeId: 'performance-episode',
  novelId: 'performance-novel',
  sourceTid: '6300',
  episodeTitle: '性能降级',
  orderIndex: 0,
);
