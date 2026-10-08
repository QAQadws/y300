import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';

/// Projects recorded and live positions without changing their validity or
/// treating a reader bootstrap snapshot as a newly recorded visit.
abstract final class NovelChapterProgressProjector {
  static LibraryChapterProgressInfo? project({
    required String novelId,
    required String episodeId,
    required NovelReadingProgress? progress,
    NovelReaderProgressSnapshot? liveSnapshot,
    bool? isRecentChapter,
  }) {
    final hasRecordedPosition =
        progress != null &&
        progress.novelId == novelId &&
        progress.episodeId == episodeId;
    final isRecent = hasRecordedPosition && (isRecentChapter ?? true);
    final live =
        liveSnapshot?.novelId == novelId && liveSnapshot?.episodeId == episodeId
        ? liveSnapshot
        : null;
    final fraction = live != null
        ? _usableFraction(live.progressPercent, live.isProgressPercentValid)
        : hasRecordedPosition
        ? _usableFraction(
            progress.progressPercent,
            progress.isProgressPercentValid,
          )
        : null;
    if (!isRecent && fraction == null) return null;
    return LibraryChapterProgressInfo(
      kind: LibraryChapterProgressKind.percentage,
      isCurrent: isRecent,
      fraction: fraction,
    );
  }

  static double? _usableFraction(double value, bool? isValid) {
    if (isValid == false ||
        !value.isFinite ||
        value < 0 ||
        value > 1 ||
        (value == 0 && isValid != true)) {
      return null;
    }
    return value;
  }
}
