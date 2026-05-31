import 'package:y300/features/comic/domain/services/comic_services_impl.dart';

enum ComicSearchRefreshQueueStatus {
  pending,
  running,
  completed,
  failed,
}

extension ComicSearchRefreshQueueStatusX on ComicSearchRefreshQueueStatus {
  String get dbValue {
    switch (this) {
      case ComicSearchRefreshQueueStatus.pending:
        return 'pending';
      case ComicSearchRefreshQueueStatus.running:
        return 'running';
      case ComicSearchRefreshQueueStatus.completed:
        return 'completed';
      case ComicSearchRefreshQueueStatus.failed:
        return 'failed';
    }
  }

  static ComicSearchRefreshQueueStatus fromDbValue(String value) {
    switch (value) {
      case 'running':
        return ComicSearchRefreshQueueStatus.running;
      case 'completed':
        return ComicSearchRefreshQueueStatus.completed;
      case 'failed':
        return ComicSearchRefreshQueueStatus.failed;
      case 'pending':
      default:
        return ComicSearchRefreshQueueStatus.pending;
    }
  }
}

enum ComicSearchRefreshOrigin {
  favoriteSync,
  detailManual,
  backfill,
  unknown,
}

extension ComicSearchRefreshOriginX on ComicSearchRefreshOrigin {
  String get dbValue {
    switch (this) {
      case ComicSearchRefreshOrigin.favoriteSync:
        return 'favorite_sync';
      case ComicSearchRefreshOrigin.detailManual:
        return 'detail_manual';
      case ComicSearchRefreshOrigin.backfill:
        return 'backfill';
      case ComicSearchRefreshOrigin.unknown:
        return 'unknown';
    }
  }

  static ComicSearchRefreshOrigin fromDbValue(String value) {
    switch (value) {
      case 'favorite_sync':
        return ComicSearchRefreshOrigin.favoriteSync;
      case 'detail_manual':
        return ComicSearchRefreshOrigin.detailManual;
      case 'backfill':
        return ComicSearchRefreshOrigin.backfill;
      case 'unknown':
      default:
        return ComicSearchRefreshOrigin.unknown;
    }
  }
}

class ComicSearchRefreshQueueDraft {
  const ComicSearchRefreshQueueDraft({
    required this.title,
    required this.request,
    required this.origin,
  });

  final String title;
  final ComicEpisodeRefreshRequest request;
  final ComicSearchRefreshOrigin origin;
}

class ComicSearchRefreshQueueEntry {
  const ComicSearchRefreshQueueEntry({
    required this.id,
    required this.comicId,
    required this.title,
    required this.request,
    required this.origin,
    required this.status,
    required this.attempts,
    required this.availableAt,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.completedAt,
    this.lastError,
  });

  final int id;
  final String comicId;
  final String title;
  final ComicEpisodeRefreshRequest request;
  final ComicSearchRefreshOrigin origin;
  final ComicSearchRefreshQueueStatus status;
  final int attempts;
  final DateTime availableAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? lastError;

  bool get isActive =>
      status == ComicSearchRefreshQueueStatus.pending ||
      status == ComicSearchRefreshQueueStatus.running;
}

class ComicSearchRefreshQueueUpsertResult {
  const ComicSearchRefreshQueueUpsertResult({
    required this.entry,
    required this.deduplicated,
  });

  final ComicSearchRefreshQueueEntry entry;
  final bool deduplicated;
}

class ComicSearchRefreshEnqueueResult {
  const ComicSearchRefreshEnqueueResult({
    required this.entry,
    required this.position,
    required this.estimatedDuration,
    required this.deduplicated,
  });

  final ComicSearchRefreshQueueEntry entry;
  final int position;
  final Duration estimatedDuration;
  final bool deduplicated;
}

class ComicSearchRefreshQueueSnapshot {
  const ComicSearchRefreshQueueSnapshot({
    required this.entries,
    required this.cadence,
  });

  final List<ComicSearchRefreshQueueEntry> entries;
  final Duration cadence;

  int get totalCount => entries.length;
  bool get active => entries.isNotEmpty;
  ComicSearchRefreshQueueEntry? get head => entries.isEmpty ? null : entries.first;
  String? get headTitle => head?.title;

  Duration get estimatedDuration {
    return Duration(milliseconds: cadence.inMilliseconds * totalCount);
  }

  String? get waitingMessage {
    final title = headTitle?.trim();
    if (title == null || title.isEmpty) {
      return null;
    }
    // Title is already the cleaned book name produced by the title analyzer
    // (stage 2), so we only wrap it for display and avoid leaking raw thread
    // noise. Stage 4 reuses this wording as the comic search notification body.
    return '《$title》正在等待漫画搜索 预计耗时${_formatSeconds(estimatedDuration)}s';
  }

  String _formatSeconds(Duration duration) {
    final tenths = (duration.inMilliseconds / 100).round();
    if (tenths % 10 == 0) {
      return '${tenths ~/ 10}';
    }
    return (tenths / 10).toStringAsFixed(1);
  }

  static const empty = ComicSearchRefreshQueueSnapshot(
    entries: <ComicSearchRefreshQueueEntry>[],
    cadence: Duration(milliseconds: 10500),
  );
}
