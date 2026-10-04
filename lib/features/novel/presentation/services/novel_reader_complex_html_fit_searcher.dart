import 'package:y300/core/html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_fit.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_search_budget.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';

final class NovelReaderPaginationMeasureContext {
  const NovelReaderPaginationMeasureContext({
    required this.session,
    required this.chapter,
    required this.key,
    required this.atomId,
  });

  final NovelReaderPaginationMeasureSession session;
  final NovelReaderPreparedChapter chapter;
  final NovelReaderPaginationKey key;
  final String atomId;
}

abstract interface class NovelReaderComplexHtmlFitSearcher {
  /// Returns a verified legal prefix within the search budget, not a globally
  /// optimal boundary for arbitrary non-monotonic HTML layout.
  Future<NovelReaderComplexHtmlFitResult> findLargestFittingPrefix({
    required NovelReaderComplexHtmlSliceSession session,
    required int startOffset,
    required String bufferedPageHtml,
    required double availableHeight,
    required NovelReaderPaginationMeasureContext context,
    required NovelReaderPaginationCancellationToken cancellationToken,
    int? preferredWindowGraphemes,
  });
}

final class DefaultNovelReaderComplexHtmlFitSearcher
    implements NovelReaderComplexHtmlFitSearcher {
  const DefaultNovelReaderComplexHtmlFitSearcher({
    this.budget = const NovelReaderComplexHtmlSearchBudget(),
    this.fitTolerance = 0.5,
    this.monotonicityTolerance = 0.5,
  }) : assert(fitTolerance >= 0),
       assert(monotonicityTolerance >= 0);

  final NovelReaderComplexHtmlSearchBudget budget;
  final double fitTolerance;
  final double monotonicityTolerance;

  @override
  Future<NovelReaderComplexHtmlFitResult> findLargestFittingPrefix({
    required NovelReaderComplexHtmlSliceSession session,
    required int startOffset,
    required String bufferedPageHtml,
    required double availableHeight,
    required NovelReaderPaginationMeasureContext context,
    required NovelReaderPaginationCancellationToken cancellationToken,
    int? preferredWindowGraphemes,
  }) async {
    // Preserve Host error precedence before entering the neutral search port.
    if (startOffset < 0 ||
        startOffset > session.textLength ||
        !session.isLegalBoundary(startOffset)) {
      throw ArgumentError.value(startOffset, 'startOffset', 'Must be legal.');
    }
    if (!availableHeight.isFinite || availableHeight <= 0) {
      throw ArgumentError.value(availableHeight, 'availableHeight');
    }
    if (context.chapter.episodeId != context.key.episodeId) {
      throw ArgumentError('The measurement chapter and key do not match.');
    }
    cancellationToken.throwIfCancelled();
    try {
      final result =
          await DefaultHtmlComplexFitSearcher(
            budget: budget,
            fitTolerance: fitTolerance,
            monotonicityTolerance: monotonicityTolerance,
          ).findLargestFittingPrefix(
            session: session.coreSession,
            startOffset: startOffset,
            bufferedPageHtml: bufferedPageHtml,
            availableHeight: availableHeight,
            measure: (candidate) async {
              final measured = await context.session.measure(
                NovelReaderPaginationMeasureRequest(
                  html: candidate.html,
                  chapter: context.chapter,
                  key: context.key,
                  atomId: context.atomId,
                  startOffset: candidate.startOffset,
                  endOffset: candidate.endOffset,
                ),
              );
              return HtmlPaginationMeasurement(
                height: measured.height,
                fromCache: measured.fromCache,
              );
            },
            cancellationToken: cancellationToken,
            preferredWindowGraphemes: preferredWindowGraphemes,
          );
      return NovelReaderComplexHtmlFitResult(
        slice: session.projectSlice(result.slice),
        measuredHeight: result.measuredHeight,
        probeCount: result.probeCount,
        cacheHitCount: result.cacheHitCount,
        fits: result.fits,
        exhaustedAtom: result.exhaustedAtom,
        requiresFreshPage: result.requiresFreshPage,
        budgetExceeded: result.budgetExceeded,
        oversizedMinimumFragment: result.oversizedMinimumFragment,
      );
    } on HtmlPaginationException catch (error, stackTrace) {
      // Measurement/cancellation keep their Host exceptions; only pure search
      // diagnostics are projected back to the existing recovery contract.
      Error.throwWithStackTrace(
        NovelReaderPaginationException(
          code: error.code,
          message: error.message,
        ),
        stackTrace,
      );
    }
  }
}
