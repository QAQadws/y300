import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

/// Executes the two batches owned by one Thread detail revision.
///
/// Results are exposed only when both batches succeed and preserve
/// cardinality. This prevents mixed raw/converted pages.
final class ThreadContentProjectionExecutor {
  const ThreadContentProjectionExecutor({
    required this.plainTextBatchConversionService,
    required this.htmlTextNodeConversionService,
    required this.diagnosticRecorder,
  });

  final PlainTextBatchConversionService plainTextBatchConversionService;
  final HtmlTextNodeConversionService htmlTextNodeConversionService;
  final TextConversionDiagnosticRecorder diagnosticRecorder;

  Future<ThreadContentBatchResult> convert({
    required List<String> plainSources,
    required List<String> htmlFragments,
    required TextConverter converter,
    required String sourceRevision,
  }) async {
    final stopwatch = Stopwatch()..start();
    PlainTextBatchConversionMetrics? plainMetrics;
    HtmlTextNodeConversionMetrics? htmlMetrics;
    try {
      final plainValues =
          plainTextBatchConversionService
              is ObservablePlainTextBatchConversionService
          ? await (plainTextBatchConversionService
                    as ObservablePlainTextBatchConversionService)
                .convertAllObserved(
                  sources: plainSources,
                  converter: converter,
                  metricsListener: (value) => plainMetrics = value,
                )
          : await plainTextBatchConversionService.convertAll(
              sources: plainSources,
              converter: converter,
            );
      if (plainValues.length != plainSources.length) {
        throw PlainTextBatchConversionException(
          expectedCount: plainSources.length,
          actualCount: plainValues.length,
        );
      }

      final htmlValues =
          htmlTextNodeConversionService
              is ObservableHtmlTextNodeConversionService
          ? await (htmlTextNodeConversionService
                    as ObservableHtmlTextNodeConversionService)
                .convertAllObserved(
                  htmlFragments: htmlFragments,
                  converter: converter,
                  metricsListener: (value) => htmlMetrics = value,
                )
          : await htmlTextNodeConversionService.convertAll(
              htmlFragments: htmlFragments,
              converter: converter,
            );
      if (htmlValues.length != htmlFragments.length) {
        throw HtmlTextNodeConversionException(
          expectedCount: htmlFragments.length,
          actualCount: htmlValues.length,
        );
      }

      _record(
        converter: converter,
        sourceRevision: sourceRevision,
        stopwatch: stopwatch,
        plainSources: plainSources,
        htmlFragments: htmlFragments,
        plainMetrics: plainMetrics,
        htmlMetrics: htmlMetrics,
      );
      return ThreadContentBatchResult.success(
        plainValues: plainValues,
        htmlValues: htmlValues,
      );
    } catch (error) {
      _record(
        converter: converter,
        sourceRevision: sourceRevision,
        stopwatch: stopwatch,
        plainSources: plainSources,
        htmlFragments: htmlFragments,
        plainMetrics: plainMetrics,
        htmlMetrics: htmlMetrics,
        failureType: error.runtimeType.toString(),
      );
      return const ThreadContentBatchResult.failure();
    }
  }

  void _record({
    required TextConverter converter,
    required String sourceRevision,
    required Stopwatch stopwatch,
    required List<String> plainSources,
    required List<String> htmlFragments,
    required PlainTextBatchConversionMetrics? plainMetrics,
    required HtmlTextNodeConversionMetrics? htmlMetrics,
    String? failureType,
  }) {
    try {
      final applicableCacheHits = <bool>[
        if (plainSources.isNotEmpty) plainMetrics?.cacheHit ?? false,
        if (htmlFragments.isNotEmpty) htmlMetrics?.cacheHit ?? false,
      ];
      diagnosticRecorder.record(
        TextConversionDiagnosticEvent(
          surface: TextConversionSurface.threadDetail,
          mode: converter.mode,
          converterId: converter.id,
          sourceRevision: sourceRevision,
          plainSourceCount: plainMetrics?.sourceCount ?? plainSources.length,
          htmlFragmentCount:
              htmlMetrics?.htmlFragmentCount ?? htmlFragments.length,
          convertedTextNodeCount: htmlMetrics?.convertedTextNodeCount ?? 0,
          elapsedMs: stopwatch.elapsedMilliseconds,
          cacheHit:
              applicableCacheHits.isNotEmpty &&
              applicableCacheHits.every((value) => value),
          usedIndividualFallback:
              (plainMetrics?.usedIndividualFallback ?? false) ||
              (htmlMetrics?.usedIndividualFallback ?? false),
          failureType:
              failureType ??
              plainMetrics?.failureType ??
              htmlMetrics?.failureType,
        ),
      );
    } catch (_) {
      // Diagnostics must never alter the display projection.
    }
  }
}

final class ThreadContentBatchResult {
  const ThreadContentBatchResult._({
    required this.plainValues,
    required this.htmlValues,
    required this.succeeded,
  });

  factory ThreadContentBatchResult.success({
    required List<String> plainValues,
    required List<HtmlTextNodeConversionResult> htmlValues,
  }) {
    return ThreadContentBatchResult._(
      plainValues: List<String>.unmodifiable(plainValues),
      htmlValues: List<HtmlTextNodeConversionResult>.unmodifiable(htmlValues),
      succeeded: true,
    );
  }

  const ThreadContentBatchResult.failure()
    : this._(
        plainValues: const <String>[],
        htmlValues: const <HtmlTextNodeConversionResult>[],
        succeeded: false,
      );

  final List<String> plainValues;
  final List<HtmlTextNodeConversionResult> htmlValues;
  final bool succeeded;
}
