import 'dart:async';

import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/thread/data/models/thread_reply_page.dart';
import 'package:y300/features/thread/data/repositories/thread_reply_page_repository.dart';
import 'package:y300/features/thread/domain/services/forum_avatar_url_builder.dart';

abstract interface class ComicCommentLoader {
  Future<ComicCommentLoadResult> loadAll({
    required String sourceTid,
    ComicCommentCancellationToken? cancellationToken,
  });
}

/// Small, dependency-free cancellation primitive for a reader-scoped load.
///
/// It lets the caller stop waiting for a stale episode without making the
/// domain layer depend on Dio. The shared request may finish in the background
/// and is still single-flight for other callers of the same source thread.
class ComicCommentCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

class DefaultComicCommentLoader implements ComicCommentLoader {
  DefaultComicCommentLoader({
    required ThreadReplyPageRepository repository,
    ForumAvatarUrlBuilder avatarUrlBuilder =
        const DefaultForumAvatarUrlBuilder(),
    this.maxConcurrentPages = 2,
    this.maxPageRequests = 100,
  }) : _repository = repository,
       _avatarUrlBuilder = avatarUrlBuilder,
       assert(maxConcurrentPages > 0),
       assert(maxPageRequests > 0);

  final ThreadReplyPageRepository _repository;
  final ForumAvatarUrlBuilder _avatarUrlBuilder;
  final int maxConcurrentPages;
  final int maxPageRequests;
  final Map<String, Future<ComicCommentLoadResult>> _inFlight =
      <String, Future<ComicCommentLoadResult>>{};

  @override
  Future<ComicCommentLoadResult> loadAll({
    required String sourceTid,
    ComicCommentCancellationToken? cancellationToken,
  }) {
    final normalizedTid = sourceTid.trim();
    final token = cancellationToken ?? ComicCommentCancellationToken();
    if (!_isValidTid(normalizedTid)) {
      return Future<ComicCommentLoadResult>.value(
        _failure(
          sourceTid: normalizedTid,
          errorCode: ComicCommentLoadErrorCode.invalidSourceTid,
          message: '漫画来源帖子无效',
        ),
      );
    }
    if (token.isCancelled) {
      return Future<ComicCommentLoadResult>.value(
        ComicCommentLoadResult.cancelled(sourceTid: normalizedTid),
      );
    }

    final existing = _inFlight[normalizedTid];
    final task = existing ?? _start(normalizedTid);
    if (existing == null) {
      _inFlight[normalizedTid] = task;
      unawaited(
        task.whenComplete(() {
          if (identical(_inFlight[normalizedTid], task)) {
            _inFlight.remove(normalizedTid);
          }
        }),
      );
    }
    return _waitForTask(
      sourceTid: normalizedTid,
      task: task,
      cancellationToken: token,
    );
  }

  Future<ComicCommentLoadResult> _start(String sourceTid) async {
    try {
      final firstResult = await _repository.getReplyPage(
        tid: sourceTid,
        page: 1,
      );
      final firstPage = firstResult.dataOrNull;
      if (firstPage == null) {
        return _failure(
          sourceTid: sourceTid,
          errorCode: ComicCommentLoadErrorCode.firstPageUnavailable,
          message: _stableErrorMessage(firstResult.errorOrNull),
        );
      }

      final pages = <int, ThreadReplyPage>{1: firstPage};
      final uncappedPageCount =
          firstPage.lastPage ?? firstPage.expectedPageCount;
      final expectedPages = _boundedPageCount(uncappedPageCount);
      final failures = <ComicCommentLoadErrorCode>[];
      if (uncappedPageCount > maxPageRequests) {
        failures.add(ComicCommentLoadErrorCode.maxPageRequestsReached);
      }
      if (expectedPages > 1) {
        await _loadRemainingPages(
          sourceTid: sourceTid,
          expectedPages: expectedPages,
          pages: pages,
          failures: failures,
        );
      }

      final orderedPages = pages.keys.toList()..sort();
      final orderedValues = orderedPages
          .map((pageNumber) => pages[pageNumber]!)
          .toList(growable: false);
      return ComicCommentLoadResult.fromPages(
        sourceTid: sourceTid,
        pages: orderedValues,
        loadedPages: pages.keys.toSet(),
        expectedPages: expectedPages,
        mapPost: _mapPost,
        errorCode: failures.isEmpty ? null : failures.first,
        errorMessage: failures.isEmpty
            ? null
            : failures.first == ComicCommentLoadErrorCode.maxPageRequestsReached
            ? '回帖页数超过安全上限'
            : '部分回帖页面加载失败',
      );
    } catch (_) {
      return _failure(
        sourceTid: sourceTid,
        errorCode: ComicCommentLoadErrorCode.firstPageUnavailable,
        message: '回帖加载失败',
      );
    }
  }

  Future<void> _loadRemainingPages({
    required String sourceTid,
    required int expectedPages,
    required Map<int, ThreadReplyPage> pages,
    required List<ComicCommentLoadErrorCode> failures,
  }) async {
    var nextPage = 2;
    final remaining = expectedPages - 1;
    final workerCount = remaining < maxConcurrentPages
        ? remaining
        : maxConcurrentPages;

    Future<void> worker() async {
      while (true) {
        final pageNumber = nextPage;
        if (pageNumber > expectedPages) {
          return;
        }
        nextPage += 1;
        try {
          final result = await _repository.getReplyPage(
            tid: sourceTid,
            page: pageNumber,
          );
          final page = result.dataOrNull;
          if (page == null) {
            failures.add(ComicCommentLoadErrorCode.pageUnavailable);
            continue;
          }
          if (page.page != pageNumber ||
              (page.tid.isNotEmpty && page.tid != sourceTid)) {
            failures.add(ComicCommentLoadErrorCode.invalidPageResponse);
            continue;
          }
          pages[pageNumber] = page;
        } catch (_) {
          failures.add(ComicCommentLoadErrorCode.pageUnavailable);
        }
      }
    }

    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
  }

  int _boundedPageCount(int count) {
    if (count < 1) {
      count = 1;
    }
    return count > maxPageRequests ? maxPageRequests : count;
  }

  ComicCommentItem _mapPost(
    String pid,
    String authorId,
    String authorName,
    String dateline,
    int floorNumber,
    String rawMessage,
  ) {
    return ComicCommentItem(
      pid: pid,
      authorId: authorId,
      authorName: authorName,
      dateline: dateline,
      floorNumber: floorNumber,
      rawMessage: rawMessage,
      avatarUrl: _avatarUrlBuilder.buildMiddleAvatar(authorId)?.toString(),
    );
  }

  Future<ComicCommentLoadResult> _waitForTask({
    required String sourceTid,
    required Future<ComicCommentLoadResult> task,
    required ComicCommentCancellationToken cancellationToken,
  }) {
    return Future.any<ComicCommentLoadResult>([
      task,
      cancellationToken.whenCancelled.then(
        (_) => ComicCommentLoadResult.cancelled(sourceTid: sourceTid),
      ),
    ]);
  }

  ComicCommentLoadResult _failure({
    required String sourceTid,
    required ComicCommentLoadErrorCode errorCode,
    required String message,
  }) {
    return ComicCommentLoadResult(
      sourceTid: sourceTid,
      status: ComicCommentLoadStatus.failure,
      items: const <ComicCommentItem>[],
      loadedPages: const <int>{},
      expectedPages: 0,
      errorCode: errorCode,
      errorMessage: message,
    );
  }

  String _stableErrorMessage(ApiError? error) {
    if (error == null) {
      return '回帖加载失败';
    }
    return switch (error.type) {
      ApiErrorType.timeout => '回帖请求超时',
      ApiErrorType.network => '网络不可用',
      ApiErrorType.unauthorized => '论坛登录状态已失效',
      ApiErrorType.server => '论坛服务暂不可用',
      _ => '回帖加载失败',
    };
  }

  bool _isValidTid(String tid) {
    return RegExp(r'^\d+$').hasMatch(tid);
  }
}
