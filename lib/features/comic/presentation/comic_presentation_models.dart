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
