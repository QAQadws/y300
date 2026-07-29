import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
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

  /// Formats a privacy-safe, single-line diagnostic payload.
  ///
  /// [sourceRevision] is hashed again at the logging boundary so a future
  /// projector cannot accidentally expose source text by supplying an invalid
  /// revision. Other free-form values are restricted to short diagnostic
  /// tokens.
  String toSafeLogFields() {
    return 'surface=${surface.name} mode=${mode.name} '
        'converter=${_safeDiagnosticToken(converterId)} '
        'revision=${_opaqueDiagnosticToken(sourceRevision)} '
        'plain=$plainSourceCount html=$htmlFragmentCount '
        'nodes=$convertedTextNodeCount elapsedMs=$elapsedMs '
        'cacheHit=$cacheHit individualFallback=$usedIndividualFallback '
        'failure=${_safeDiagnosticToken(failureType ?? '-')}';
  }
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

typedef TextConversionDiagnosticLogWriter = void Function(String message);

/// Debug-only conversion recorder.
///
/// It deliberately logs only [TextConversionDiagnosticEvent.toSafeLogFields]
/// and swallows logger failures so observability cannot affect rendering.
final class DeveloperTextConversionDiagnosticRecorder
    implements TextConversionDiagnosticRecorder {
  DeveloperTextConversionDiagnosticRecorder({
    TextConversionDiagnosticLogWriter? writeLog,
  }) : _writeLog = writeLog ?? _writeDeveloperLog;

  final TextConversionDiagnosticLogWriter _writeLog;

  @override
  void record(TextConversionDiagnosticEvent event) {
    try {
      _writeLog(event.toSafeLogFields());
    } catch (_) {
      // Diagnostics must never alter conversion or display behavior.
    }
  }

  static void _writeDeveloperLog(String message) {
    developer.log(message, name: 'ServerContentConversion', level: 800);
  }
}

TextConversionDiagnosticRecorder createTextConversionDiagnosticRecorder({
  bool isDebugMode = kDebugMode,
  TextConversionDiagnosticLogWriter? writeLog,
}) {
  if (!isDebugMode) {
    return const NoopTextConversionDiagnosticRecorder();
  }
  return DeveloperTextConversionDiagnosticRecorder(writeLog: writeLog);
}

final textConversionDiagnosticRecorderProvider =
    Provider<TextConversionDiagnosticRecorder>(
      (ref) => createTextConversionDiagnosticRecorder(),
    );

String _safeDiagnosticToken(String value) {
  final buffer = StringBuffer();
  for (final codePoint in value.runes) {
    final isAsciiLetter =
        (codePoint >= 0x41 && codePoint <= 0x5A) ||
        (codePoint >= 0x61 && codePoint <= 0x7A);
    final isDigit = codePoint >= 0x30 && codePoint <= 0x39;
    final isSafePunctuation =
        codePoint == 0x2D ||
        codePoint == 0x2E ||
        codePoint == 0x3A ||
        codePoint == 0x5F;
    buffer.write(
      isAsciiLetter || isDigit || isSafePunctuation
          ? String.fromCharCode(codePoint)
          : '_',
    );
    if (buffer.length >= 80) {
      break;
    }
  }
  final token = buffer.toString();
  return token.isEmpty ? '-' : token;
}

String _opaqueDiagnosticToken(String value) {
  var hash = 0xcbf29ce484222325;
  for (final codeUnit in value.codeUnits) {
    hash = (hash ^ codeUnit) * 0x100000001b3;
    hash = hash.toUnsigned(64);
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
