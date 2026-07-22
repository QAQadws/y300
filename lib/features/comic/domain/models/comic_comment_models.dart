import 'package:y300/features/thread/data/models/thread_reply_page.dart';

enum ComicCommentLoadStatus {
  success,
  empty,
  partialFailure,
  failure,
  cancelled,
}

enum ComicCommentLoadErrorCode {
  invalidSourceTid,
  firstPageUnavailable,
  pageUnavailable,
  pageTimeout,
  rateLimited,
  unauthorized,
  invalidPageResponse,
  emptyPageResponse,
  maxPageRequestsReached,
}

class ComicCommentItem {
  const ComicCommentItem({
    required this.pid,
    required this.authorId,
    required this.authorName,
    required this.dateline,
    required this.floorNumber,
    required this.rawMessage,
    required this.avatarUrl,
  });

  final String pid;
  final String authorId;
  final String authorName;
  final String dateline;
  final int floorNumber;
  final String rawMessage;
  final String? avatarUrl;
}

class ComicCommentLoadResult {
  const ComicCommentLoadResult({
    required this.sourceTid,
    required this.status,
    required this.items,
    required this.loadedPages,
    required this.expectedPages,
    this.errorCode,
    this.errorMessage,
  });

  factory ComicCommentLoadResult.cancelled({
    required String sourceTid,
    int expectedPages = 0,
  }) {
    return ComicCommentLoadResult(
      sourceTid: sourceTid,
      status: ComicCommentLoadStatus.cancelled,
      items: const <ComicCommentItem>[],
      loadedPages: const <int>{},
      expectedPages: expectedPages,
    );
  }

  final String sourceTid;
  final ComicCommentLoadStatus status;
  final List<ComicCommentItem> items;
  final Set<int> loadedPages;
  final int expectedPages;
  final ComicCommentLoadErrorCode? errorCode;
  final String? errorMessage;

  bool get isComplete =>
      status == ComicCommentLoadStatus.success ||
      status == ComicCommentLoadStatus.empty;

  bool get hasItems => items.isNotEmpty;

  /// Whether an automatic first-load retry can reasonably recover.
  ///
  /// Authentication, rate-limit and payload-shape failures need user action
  /// or a longer delay, so retrying them immediately would only duplicate the
  /// request. Network/timeout-style first-page failures are transient and get
  /// one bounded retry from the reader session.
  bool get isTransientFailure {
    if (status != ComicCommentLoadStatus.failure) {
      return false;
    }
    return errorCode == ComicCommentLoadErrorCode.firstPageUnavailable ||
        errorCode == ComicCommentLoadErrorCode.pageUnavailable ||
        errorCode == ComicCommentLoadErrorCode.pageTimeout;
  }

  static ComicCommentLoadResult fromPages({
    required String sourceTid,
    required List<ThreadReplyPage> pages,
    required Set<int> loadedPages,
    required int expectedPages,
    required ComicCommentItem Function(
      String pid,
      String authorId,
      String authorName,
      String dateline,
      int floorNumber,
      String rawMessage,
    )
    mapPost,
    ComicCommentLoadErrorCode? errorCode,
    String? errorMessage,
  }) {
    final firstPid = _findFirstPostPid(pages);
    final byPid = <String, ComicCommentItem>{};

    for (final page in pages) {
      for (final post in page.posts) {
        final pid = post.pid.trim();
        if (pid.isEmpty || post.isFirst || pid == firstPid) {
          continue;
        }
        byPid.putIfAbsent(
          pid,
          () => mapPost(
            pid,
            post.authorId.trim(),
            post.author.trim(),
            post.dateline.trim(),
            post.number,
            post.message,
          ),
        );
      }
    }

    final items = List<ComicCommentItem>.unmodifiable(byPid.values);
    final status = errorCode != null
        ? ComicCommentLoadStatus.partialFailure
        : items.isEmpty
        ? ComicCommentLoadStatus.empty
        : ComicCommentLoadStatus.success;
    return ComicCommentLoadResult(
      sourceTid: sourceTid,
      status: status,
      items: items,
      loadedPages: Set<int>.unmodifiable(loadedPages),
      expectedPages: expectedPages,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  static String? _findFirstPostPid(List<ThreadReplyPage> pages) {
    for (final page in pages) {
      for (final post in page.posts) {
        if (post.isFirst && post.pid.trim().isNotEmpty) {
          return post.pid.trim();
        }
      }
    }

    // Some cached/legacy responses omit `first`; only use the canonical
    // floor-one identity as a narrow fallback, never the author ID.
    for (final page in pages.where((page) => page.page == 1)) {
      for (final post in page.posts) {
        if (post.number == 1 && post.pid.trim().isNotEmpty) {
          return post.pid.trim();
        }
      }
    }
    return null;
  }
}
