import 'dart:developer' as developer;

/// Stable, privacy-preserving diagnostics for the reader-scoped comment flow.
///
/// The recorder deliberately accepts counters and error codes instead of raw
/// posts, URLs or authentication data. This keeps performance investigations
/// useful without turning comment content into a log payload.
final class ComicCommentDiagnosticEvent {
  const ComicCommentDiagnosticEvent({
    required this.sourceTidHash,
    required this.event,
    required this.page,
    required this.expectedPages,
    required this.postCount,
    required this.filteredFirstCount,
    required this.deduplicatedCount,
    required this.duration,
    this.errorCode,
  });

  final String sourceTidHash;
  final String event;
  final int page;
  final int expectedPages;
  final int postCount;
  final int filteredFirstCount;
  final int deduplicatedCount;
  final Duration duration;
  final String? errorCode;

  String toLogFields() {
    return 'tid=$sourceTidHash event=$event page=$page '
        'expectedPages=$expectedPages posts=$postCount '
        'filteredFirst=$filteredFirstCount deduplicated=$deduplicatedCount '
        'durationMs=${duration.inMilliseconds} '
        'error=${errorCode ?? '-'}';
  }
}

abstract interface class ComicCommentDiagnosticRecorder {
  bool get enabled;

  void record(ComicCommentDiagnosticEvent event);
}

class DeveloperComicCommentDiagnosticRecorder
    implements ComicCommentDiagnosticRecorder {
  const DeveloperComicCommentDiagnosticRecorder();

  @override
  bool get enabled => true;

  @override
  void record(ComicCommentDiagnosticEvent event) {
    developer.log(event.toLogFields(), name: 'ComicComments', level: 800);
  }
}

final class NoopComicCommentDiagnosticRecorder
    implements ComicCommentDiagnosticRecorder {
  const NoopComicCommentDiagnosticRecorder();

  @override
  bool get enabled => false;

  @override
  void record(ComicCommentDiagnosticEvent event) {}
}

String comicCommentTidHash(String sourceTid) {
  var hash = 0xcbf29ce484222325;
  for (final byte in sourceTid.codeUnits) {
    hash = (hash ^ byte) * 0x100000001b3;
    hash = hash.toUnsigned(64);
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
