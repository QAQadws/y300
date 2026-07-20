import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_hybrid_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_renderer_validator.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final targetPages in const <int>[20, 80, 200]) {
    test(
      '$targetPages-page plain-text benchmark stays on the linear path',
      () async {
        final chapter = await const DefaultNovelReaderHtmlPreparationService()
            .prepare(
              rawHtml: _htmlFor(targetPages),
              episode: _episode,
              preferences: _preferences,
              theme: _theme,
              sourceId: _episode.episodeId,
              threadId: _episode.sourceTid,
              imageCacheOwnerId: _episode.sourceTid,
            );
        final key = NovelReaderPaginationKey(
          episodeId: chapter.episodeId,
          contentHash: chapter.contentHash,
          viewportWidthPx: 320,
          viewportHeightPx: 600,
          typographySignature: 'phase6-default',
          themeSignature: chapter.themeSignature,
          imageDimensionRevision: chapter.imageDimensionRevision,
          rendererRevision: 3,
        );
        final planner = DefaultNovelReaderHybridPaginationPlanner(
          measureAdapter: const _ConstantMeasureAdapter(),
          preferences: _preferences,
          theme: _theme,
          baseStyle: _baseStyle,
          validationPolicy: const NovelReaderPaginationValidationPolicy(
            interval: 10000,
          ),
        );
        final stopwatch = Stopwatch()..start();
        Duration? firstPageDuration;

        final events = await planner
            .planIncrementally(
              chapter: chapter,
              key: key,
              cancellationToken: NovelReaderPaginationCancellationToken(),
            )
            .map((event) {
              firstPageDuration ??= stopwatch.elapsed;
              return event;
            })
            .toList();
        stopwatch.stop();
        final plan = events.last.plan;

        expect(events.first.isComplete, isFalse);
        expect(events.last.isComplete, isTrue);
        expect(plan.pageCount, greaterThan(targetPages ~/ 2));
        expect(plan.pageCount, lessThan(targetPages * 2));
        expect(plan.textLayoutCount, plan.atomCount);
        expect(plan.complexBlockCount, 0);
        expect(plan.safeTextFallbackCount, 0);
        expect(plan.rendererValidationCount, 1);
        expect(plan.measurementCount, 1);
        expect(plan.frameWaitCount, 0);
        expect(firstPageDuration, isNotNull);
        printOnFailure(
          'target=$targetPages actual=${plan.pageCount} '
          'firstPageMs=${firstPageDuration!.inMilliseconds} '
          'fullPlanMs=${stopwatch.elapsedMilliseconds}',
        );
      },
    );
  }
}

String _htmlFor(int targetPages) {
  const unit = '长篇小说分页性能基准 mixed 123，保持中文、英文和数字的稳定换行。';
  final paragraph = List<String>.filled(6, unit).join();
  return List<String>.filled(targetPages * 2, '<p>$paragraph</p>').join();
}

const _episode = NovelEpisodeItem(
  episodeId: 'phase6-performance-episode',
  novelId: 'phase6-performance-novel',
  sourceTid: '6100',
  episodeTitle: 'Phase 6 性能基准',
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
  color: Color(0xFF4C3A21),
  fontSize: 18.5,
  height: 1.6,
);

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

final class _ConstantMeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  const _ConstantMeasureAdapter();

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    return const NovelReaderPaginationMeasureResult(height: 100);
  }
}
