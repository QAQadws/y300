import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

/// Runs one Forum surface conversion batch and records privacy-safe metrics.
///
/// Projectors use this small boundary so they only map source fields to
/// display fields. Conversion failures return the original values as a whole
/// batch; a partially converted surface is never exposed to widgets.
final class ForumContentProjectionExecutor {
  const ForumContentProjectionExecutor({
    required this.plainTextBatchConversionService,
    required this.diagnosticRecorder,
  });

  final PlainTextBatchConversionService plainTextBatchConversionService;
  final TextConversionDiagnosticRecorder diagnosticRecorder;

  Future<ForumContentBatchResult> convertAll({
    required List<String> sources,
    required TextConverter converter,
    required TextConversionSurface surface,
    required String sourceRevision,
  }) async {
    final stopwatch = Stopwatch()..start();
    PlainTextBatchConversionMetrics? observedMetrics;
    try {
      final converted =
          plainTextBatchConversionService
              is ObservablePlainTextBatchConversionService
          ? await (plainTextBatchConversionService
                    as ObservablePlainTextBatchConversionService)
                .convertAllObserved(
                  sources: sources,
                  converter: converter,
                  metricsListener: (metrics) {
                    observedMetrics = metrics;
                  },
                )
          : await plainTextBatchConversionService.convertAll(
              sources: sources,
              converter: converter,
            );
      if (converted.length != sources.length) {
        throw PlainTextBatchConversionException(
          expectedCount: sources.length,
          actualCount: converted.length,
        );
      }

      _record(
        TextConversionDiagnosticEvent(
          surface: surface,
          mode: converter.mode,
          converterId: converter.id,
          sourceRevision: sourceRevision,
          plainSourceCount: observedMetrics?.sourceCount ?? sources.length,
          htmlFragmentCount: 0,
          convertedTextNodeCount: 0,
          elapsedMs:
              observedMetrics?.elapsedMs ?? stopwatch.elapsedMilliseconds,
          cacheHit: observedMetrics?.cacheHit ?? false,
          usedIndividualFallback:
              observedMetrics?.usedIndividualFallback ?? false,
          failureType: observedMetrics?.failureType,
        ),
      );
      return ForumContentBatchResult.success(converted);
    } catch (error) {
      _record(
        TextConversionDiagnosticEvent(
          surface: surface,
          mode: converter.mode,
          converterId: converter.id,
          sourceRevision: sourceRevision,
          plainSourceCount: observedMetrics?.sourceCount ?? sources.length,
          htmlFragmentCount: 0,
          convertedTextNodeCount: 0,
          elapsedMs:
              observedMetrics?.elapsedMs ?? stopwatch.elapsedMilliseconds,
          cacheHit: observedMetrics?.cacheHit ?? false,
          usedIndividualFallback:
              observedMetrics?.usedIndividualFallback ?? false,
          failureType: error.runtimeType.toString(),
        ),
      );
      return ForumContentBatchResult.failure(sources);
    }
  }

  void _record(TextConversionDiagnosticEvent event) {
    try {
      diagnosticRecorder.record(event);
    } catch (_) {
      // Diagnostics must never change the projection result.
    }
  }
}

final class ForumContentBatchResult {
  const ForumContentBatchResult._({
    required this.values,
    required this.isConverted,
  });

  factory ForumContentBatchResult.success(List<String> values) {
    return ForumContentBatchResult._(
      values: List<String>.unmodifiable(values),
      isConverted: true,
    );
  }

  factory ForumContentBatchResult.failure(List<String> values) {
    return ForumContentBatchResult._(
      values: List<String>.unmodifiable(values),
      isConverted: false,
    );
  }

  final List<String> values;
  final bool isConverted;
}

/// Creates an opaque source revision without retaining raw server text in
/// diagnostics. Hashes are only used for in-process stale-result guards.
String forumContentSourceRevision(Iterable<Object?> parts) {
  return 'forum:${Object.hashAll(parts)}';
}

String forumContentTextHash(String? value) {
  return Object.hashAll([value ?? '']).toString();
}

String forumContentNullableTextHash(String? value) {
  return value == null ? 'null' : Object.hashAll([value]).toString();
}
