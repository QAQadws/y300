import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';

enum ComicReaderNoticeCode {
  bookmarkAdded,
  bookmarkRemoved,
  episodeMarkedRead,
  episodeMarkedUnread,
  coverImageUnavailable,
  coverUpdateFailed,
  coverUpdated,
  episodeSwitchFailed,
}

enum ComicReaderEpisodeRefreshStatus { refreshed, noImages, failed, stale }

final class ComicReaderEpisodeRefreshResult {
  const ComicReaderEpisodeRefreshResult._({
    required this.status,
    this.failureReason,
  });

  const ComicReaderEpisodeRefreshResult.refreshed()
    : this._(status: ComicReaderEpisodeRefreshStatus.refreshed);

  const ComicReaderEpisodeRefreshResult.noImages()
    : this._(status: ComicReaderEpisodeRefreshStatus.noImages);

  const ComicReaderEpisodeRefreshResult.failed({
    ComicEpisodeImagesFetchFailureReason? reason,
  }) : this._(
         status: ComicReaderEpisodeRefreshStatus.failed,
         failureReason: reason,
       );

  const ComicReaderEpisodeRefreshResult.stale()
    : this._(status: ComicReaderEpisodeRefreshStatus.stale);

  final ComicReaderEpisodeRefreshStatus status;
  final ComicEpisodeImagesFetchFailureReason? failureReason;
}

enum ComicReaderLoadFailureCode { episodeNotFound }

final class ComicReaderLoadException implements Exception {
  const ComicReaderLoadException(this.code, {this.detail});

  final ComicReaderLoadFailureCode code;
  final Object? detail;

  @override
  String toString() => 'ComicReaderLoadException(${code.name})';
}

enum ComicDetailRefreshNoticeCode { noLinks, completed, failed }

final class ComicDetailRefreshNotice {
  const ComicDetailRefreshNotice({
    required this.code,
    this.insertedCount = 0,
    this.updatedCount = 0,
    this.detail,
  });

  final ComicDetailRefreshNoticeCode code;
  final int insertedCount;
  final int updatedCount;
  final Object? detail;
}
