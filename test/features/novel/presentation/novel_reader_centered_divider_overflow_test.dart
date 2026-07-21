import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/services/novel_forum_html_render_theme_factory.dart';
import 'package:y300/features/novel/presentation/services/novel_html_reader_preferences_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_hybrid_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_renderer_validator.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_style_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';

const _contentWidth = 418.0;
const _contentHeight = 746.8;

void main() {
  testWidgets(
    'planned centered-divider pages fit the real renderer at 418x746.8',
    (tester) async {
      tester.view.physicalSize = const Size(450, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final novelPreferences = NovelReaderPreferences.defaults();
      final appTheme = ThemeData.light();
      final palette = const NovelReaderThemeResolver().resolve(
        preferences: novelPreferences,
        theme: appTheme,
        platformBrightness: Brightness.light,
      );
      final htmlTheme = const NovelForumHtmlRenderThemeFactory().fromPalette(
        palette,
      );
      final htmlPreferences = const NovelHtmlReaderPreferencesAdapter().map(
        novelPreferences,
      );
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme,
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final rawHtml = File(
        'test/features/novel/fixtures/pagination/'
        'centered_divider_overflow_v1.html',
      ).readAsStringSync();
      final chapter = await const DefaultNovelReaderHtmlPreparationService()
          .prepare(
            rawHtml: rawHtml,
            episode: _episode,
            preferences: htmlPreferences,
            theme: htmlTheme,
            sourceId: _episode.episodeId,
            threadId: _episode.sourceTid,
            imageCacheOwnerId: _episode.sourceTid,
          );
      final blockSpacingMode = ForumHtmlBlockSpacingMode.discuzLineDivs;
      final baseStyle = ForumHtmlStylePolicy(
        htmlPreferences,
        theme: htmlTheme,
        blockSpacingMode: blockSpacingMode,
      ).baseTextStyle(hostContext);
      final key = NovelReaderPaginationKey(
        episodeId: chapter.episodeId,
        contentHash: chapter.contentHash,
        viewportWidthPx: NovelReaderPaginationKey.logicalPixels(_contentWidth),
        viewportHeightPx: NovelReaderPaginationKey.logicalPixels(
          _contentHeight,
        ),
        typographySignature: 'centered-divider-overflow-regression',
        themeSignature: chapter.themeSignature,
        imageDimensionRevision: chapter.imageDimensionRevision,
        rendererRevision: 12,
      );
      final plan = await DefaultNovelReaderHybridPaginationPlanner(
        measureAdapter: const _CenteredDividerMeasureAdapter(),
        preferences: htmlPreferences,
        theme: htmlTheme,
        baseStyle: baseStyle,
        validationPolicy: const NovelReaderPaginationValidationPolicy(
          interval: 10000,
        ),
      ).paginate(chapter, key);

      expect(plan.pages, isNotEmpty);
      expect(plan.pages.every((page) => page.html.trim().isNotEmpty), isTrue);
      expect(
        plan.pages.every(
          (page) =>
              page.requiresInnerScroll ||
              page.usedHeight <= key.viewportHeightPx,
        ),
        isTrue,
      );

      for (final page in plan.pages) {
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: _contentWidth,
                  height: _contentHeight,
                  child: ForumHtmlWidgetPostRenderer(
                    key: ValueKey<int>(page.index),
                    html: page.html,
                    theme: htmlTheme,
                    preparedDocument: chapter.renderDocument.copyWith(
                      preparedHtml: page.html,
                    ),
                    preferences: htmlPreferences,
                    sourceId: '${_episode.episodeId}:${page.index}',
                    threadId: _episode.sourceTid,
                    imageCacheOwnerId: _episode.sourceTid,
                    buildAsync: false,
                    enableCaching: false,
                    blockSpacingMode: blockSpacingMode,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Rendered pagination page ${page.index} overflowed.',
        );
      }
    },
  );
}

const _episode = NovelEpisodeItem(
  episodeId: 'overflow-regression-episode',
  novelId: 'overflow-regression-novel',
  sourceTid: '6300',
  episodeTitle: '居中分隔符溢出回归',
  orderIndex: 0,
);

final class _CenteredDividerMeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  const _CenteredDividerMeasureAdapter();

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    return const NovelReaderPaginationMeasureResult(height: 30);
  }
}
