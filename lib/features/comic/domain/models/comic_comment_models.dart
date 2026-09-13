import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

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
    this.sourcePost,
    this.sourcePage = 1,
  });

  final String pid;
  final String authorId;
  final String authorName;
  final String dateline;
  final int floorNumber;
  final String rawMessage;
  final String? avatarUrl;
  final ThreadPost? sourcePost;
  final int sourcePage;
  ThreadPost get post =>
      sourcePost ??
      ThreadPost(
        pid: pid,
        author: authorName,
        authorId: authorId,
        message: rawMessage,
        number: floorNumber,
        isFirst: floorNumber == 1,
        dateline: dateline,
        avatarUrl: avatarUrl,
      );
  factory ComicCommentItem.fromPost(ThreadPost post, int page) =>
      ComicCommentItem(
        pid: post.pid,
        authorId: post.authorId,
        authorName: post.author,
        dateline: post.dateline,
        floorNumber: post.number,
        rawMessage: post.message,
        avatarUrl: post.avatarUrl,
        sourcePost: post,
        sourcePage: page,
      );
}

class ComicCommentLoadResult {
  const ComicCommentLoadResult({
    required this.sourceTid,
    required this.status,
    required this.items,
    required this.loadedPages,
    required this.expectedPages,
    this.errorCode,
    this.diagnosticDetail,
    this.reads = const {},
    this.nextPage,
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

  /// Optional diagnostic detail. Presentation must never display it directly.
  final Object? diagnosticDetail;

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

  final Map<
    int,
    DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>
  >
  reads;
  final int? nextPage;
  bool get hasMore => nextPage != null;

  factory ComicCommentLoadResult.failure(
    String tid,
    ComicCommentLoadErrorCode code,
  ) => ComicCommentLoadResult(
    sourceTid: tid,
    status: ComicCommentLoadStatus.failure,
    items: const [],
    loadedPages: const {},
    expectedPages: 0,
    errorCode: code,
  );
  factory ComicCommentLoadResult.fromRead(
    DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities> read,
  ) {
    final data = read.data;
    return ComicCommentLoadResult(
      sourceTid: data.tid,
      status: ComicCommentLoadStatus.success,
      items: List.unmodifiable(
        data.posts.map(
          (post) => ComicCommentItem.fromPost(post, data.currentPage),
        ),
      ),
      loadedPages: {data.currentPage},
      expectedPages: data.lastPage ?? data.currentPage,
      reads: {data.currentPage: read},
      nextPage: data.hasMore ? data.currentPage + 1 : null,
    );
  }

  /// Page ownership is retained for commands; PID identity controls display.
  factory ComicCommentLoadResult.merge(
    String tid,
    Map<int, ComicCommentLoadResult> pages,
  ) {
    final ordered = pages.keys.toList()..sort();
    final byPid = <String, ComicCommentItem>{};
    final reads =
        <
          int,
          DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>
        >{};
    for (final page in ordered) {
      reads.addAll(pages[page]!.reads);
      for (final item in pages[page]!.items) {
        byPid.putIfAbsent(item.pid, () => item);
      }
    }
    final last = pages[ordered.last]!;
    return ComicCommentLoadResult(
      sourceTid: tid,
      status: byPid.isEmpty
          ? ComicCommentLoadStatus.empty
          : ComicCommentLoadStatus.success,
      items: List.unmodifiable(byPid.values),
      loadedPages: Set.unmodifiable(ordered),
      expectedPages: last.expectedPages,
      reads: Map.unmodifiable(reads),
      nextPage: last.nextPage,
    );
  }
}
