import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

/// Presentation surfaces that may later own a server-content projection.
enum TextConversionSurface {
  forumHome,
  forumDisplay,
  threadDetail,
  comicComments,
}

/// Privacy-safe conversion telemetry.
///
/// Callers provide an opaque, stable [sourceRevision]. This event deliberately
/// contains no source text, usernames, URLs or request credentials.
final class TextConversionDiagnosticEvent {
  const TextConversionDiagnosticEvent({
    required this.surface,
    required this.mode,
    required this.converterId,
    required this.sourceRevision,
    required this.plainSourceCount,
    required this.htmlFragmentCount,
    required this.convertedTextNodeCount,
    required this.elapsedMs,
    required this.cacheHit,
    required this.usedIndividualFallback,
    this.failureType,
  });

  final TextConversionSurface surface;
  final TextConversionMode mode;
  final String converterId;
  final String sourceRevision;
  final int plainSourceCount;
  final int htmlFragmentCount;
  final int convertedTextNodeCount;
  final int elapsedMs;
  final bool cacheHit;
  final bool usedIndividualFallback;
  final String? failureType;
}

abstract interface class TextConversionDiagnosticRecorder {
  void record(TextConversionDiagnosticEvent event);
}

final class NoopTextConversionDiagnosticRecorder
    implements TextConversionDiagnosticRecorder {
  const NoopTextConversionDiagnosticRecorder();

  @override
  void record(TextConversionDiagnosticEvent event) {}
}

final textConversionDiagnosticRecorderProvider =
    Provider<TextConversionDiagnosticRecorder>(
      (ref) => const NoopTextConversionDiagnosticRecorder(),
    );
