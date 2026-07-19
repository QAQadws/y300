import 'dart:async';

import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/domain/services/comic_comment_diagnostics.dart';
import 'package:y300/features/thread/data/models/thread_reply_page.dart';
import 'package:y300/features/thread/data/repositories/thread_reply_page_repository.dart';
import 'package:y300/features/thread/domain/services/forum_avatar_url_builder.dart';

abstract interface class ComicCommentLoader {
  Future<ComicCommentLoadResult> loadAll({
    required String sourceTid,
    ComicCommentCancellationToken? cancellationToken,
  });
}

/// Optional cache control exposed separately so existing test doubles and
/// other comment loaders do not need to implement cache-specific behavior.
abstract interface class ComicCommentLoaderCache {
  void invalidate(String sourceTid);
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

class DefaultComicCommentLoader
    implements ComicCommentLoader, ComicCommentLoaderCache {
  DefaultComicCommentLoader({
    required ThreadReplyPageRepository repository,
    ForumAvatarUrlBuilder avatarUrlBuilder =
        const DefaultForumAvatarUrlBuilder(),
    this.maxConcurrentPages = 2,
    this.maxPageRequests = 100,
    this.pageRequestTimeout = const Duration(seconds: 20),
    this.cacheTtl = const Duration(minutes: 2),
    this.maxCachedResults = 8,
    ComicCommentDiagnosticRecorder? diagnosticRecorder,
    DateTime Function()? now,
  }) : _repository = repository,
       _avatarUrlBuilder = avatarUrlBuilder,
       _diagnosticRecorder =
           diagnosticRecorder ?? const NoopComicCommentDiagnosticRecorder(),
       _now = now ?? DateTime.now,
       assert(maxConcurrentPages > 0),
       assert(maxPageRequests > 0),
       assert(pageRequestTimeout > Duration.zero),
       assert(cacheTtl > Duration.zero),
       assert(maxCachedResults > 0);

  final ThreadReplyPageRepository _repository;
  final ForumAvatarUrlBuilder _avatarUrlBuilder;
  final int maxConcurrentPages;
  final int maxPageRequests;
  final Duration pageRequestTimeout;
  final Duration cacheTtl;
  final int maxCachedResults;
  final Map<String, Future<ComicCommentLoadResult>> _inFlight =
      <String, Future<ComicCommentLoadResult>>{};
  final Map<String, _ComicCommentCacheEntry> _cache =
      <String, _ComicCommentCacheEntry>{};
  final ComicCommentDiagnosticRecorder _diagnosticRecorder;
  final DateTime Function() _now;

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
          startedAt: _now(),
          page: 0,
        ),
      );
    }
    if (token.isCancelled) {
      return Future<ComicCommentLoadResult>.value(
        ComicCommentLoadResult.cancelled(sourceTid: normalizedTid),
      );
    }

    final cached = _freshCached(normalizedTid);
    if (cached != null) {
      return Future<ComicCommentLoadResult>.value(cached);
    }

    final existing = _inFlight[normalizedTid];
    final task = existing ?? _startAndCache(normalizedTid);
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

  @override
  void invalidate(String sourceTid) {
    _cache.remove(sourceTid.trim());
  }

  Future<ComicCommentLoadResult> _startAndCache(String sourceTid) async {
    final result = await _start(sourceTid);
    if (result.isComplete) {
      _cache[sourceTid] = _ComicCommentCacheEntry(result, _now());
      _trimCache();
    }
    return result;
  }

  Future<ComicCommentLoadResult> _start(String sourceTid) async {
    final startedAt = _now();
    try {
      final firstResult = await _getPage(sourceTid, 1);
      final firstPage = firstResult.dataOrNull;
      if (firstPage == null) {
        final error = firstResult.errorOrNull;
        return _failure(
          sourceTid: sourceTid,
          errorCode: _errorCode(error, firstPage: true),
          message: _stableErrorMessage(error),
          startedAt: startedAt,
          page: 1,
        );
      }
      if (!_isValidPage(firstPage, sourceTid, 1)) {
        return _failure(
          sourceTid: sourceTid,
          errorCode: ComicCommentLoadErrorCode.invalidPageResponse,
          message: '回帖数据格式无效',
          startedAt: startedAt,
          page: 1,
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

      failures.sort(_compareErrorCodes);

      final orderedPages = pages.keys.toList()..sort();
      final orderedValues = orderedPages
          .map((pageNumber) => pages[pageNumber]!)
          .toList(growable: false);
      final result = ComicCommentLoadResult.fromPages(
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
      _recordDiagnostic(
        sourceTid: sourceTid,
        event: result.status.name,
        page: 0,
        expectedPages: expectedPages,
        postCount: orderedValues.fold<int>(
          0,
          (count, page) => count + page.posts.length,
        ),
        filteredFirstCount: orderedValues.fold<int>(
          0,
          (count, page) =>
              count + page.posts.where((post) => post.isFirst).length,
        ),
        deduplicatedCount: result.items.length,
        startedAt: startedAt,
        errorCode: result.errorCode,
      );
      return result;
    } on TimeoutException {
      return _failure(
        sourceTid: sourceTid,
        errorCode: ComicCommentLoadErrorCode.pageTimeout,
        message: '回帖请求超时',
        startedAt: startedAt,
        page: 1,
      );
    } catch (_) {
      return _failure(
        sourceTid: sourceTid,
        errorCode: ComicCommentLoadErrorCode.firstPageUnavailable,
        message: '回帖加载失败',
        startedAt: startedAt,
        page: 1,
      );
    }
  }

  Future<ApiResult<ThreadReplyPage>> _getPage(String sourceTid, int page) {
    return _repository
        .getReplyPage(tid: sourceTid, page: page)
        .timeout(pageRequestTimeout);
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
          final result = await _getPage(sourceTid, pageNumber);
          final page = result.dataOrNull;
          if (page == null) {
            failures.add(_errorCode(result.errorOrNull));
            continue;
          }
          if (page.page != pageNumber ||
              (page.tid.isNotEmpty && page.tid != sourceTid)) {
            failures.add(ComicCommentLoadErrorCode.invalidPageResponse);
            continue;
          }
          if (page.posts.isEmpty && page.replyCount > 0) {
            failures.add(ComicCommentLoadErrorCode.emptyPageResponse);
            continue;
          }
          pages[pageNumber] = page;
        } on TimeoutException {
          failures.add(ComicCommentLoadErrorCode.pageTimeout);
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
    required DateTime startedAt,
    required int page,
  }) {
    _recordDiagnostic(
      sourceTid: sourceTid,
      event: 'failure',
      page: page,
      expectedPages: 0,
      postCount: 0,
      filteredFirstCount: 0,
      deduplicatedCount: 0,
      startedAt: startedAt,
      errorCode: errorCode,
    );
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

  ComicCommentLoadErrorCode _errorCode(
    ApiError? error, {
    bool firstPage = false,
  }) {
    if (error?.statusCode == 429) {
      return ComicCommentLoadErrorCode.rateLimited;
    }
    return switch (error?.type) {
      ApiErrorType.timeout => ComicCommentLoadErrorCode.pageTimeout,
      ApiErrorType.unauthorized => ComicCommentLoadErrorCode.unauthorized,
      _ =>
        firstPage
            ? ComicCommentLoadErrorCode.firstPageUnavailable
            : ComicCommentLoadErrorCode.pageUnavailable,
    };
  }

  String _stableErrorMessage(ApiError? error) {
    if (error == null) {
      return '回帖加载失败';
    }
    if (error.statusCode == 429) {
      return '请求过于频繁，请稍后重试';
    }
    return switch (error.type) {
      ApiErrorType.timeout => '回帖请求超时',
      ApiErrorType.network => '网络不可用',
      ApiErrorType.unauthorized => '论坛登录状态已失效',
      ApiErrorType.server => '论坛服务暂不可用',
      _ => '回帖加载失败',
    };
  }

  int _compareErrorCodes(
    ComicCommentLoadErrorCode left,
    ComicCommentLoadErrorCode right,
  ) {
    return left.index.compareTo(right.index);
  }

  bool _isValidPage(ThreadReplyPage page, String sourceTid, int pageNumber) {
    if (page.page != pageNumber ||
        (page.tid.isNotEmpty && page.tid != sourceTid)) {
      return false;
    }
    return page.posts.isNotEmpty || page.replyCount == 0;
  }

  ComicCommentLoadResult? _freshCached(String sourceTid) {
    final entry = _cache[sourceTid];
    if (entry == null) {
      return null;
    }
    if (_now().difference(entry.createdAt) > cacheTtl) {
      _cache.remove(sourceTid);
      return null;
    }
    // Reinsert to keep the bounded cache LRU-like without another data
    // structure. Cache reads must not mutate the immutable result itself.
    _cache
      ..remove(sourceTid)
      ..[sourceTid] = entry;
    return entry.result;
  }

  void _trimCache() {
    while (_cache.length > maxCachedResults) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _recordDiagnostic({
    required String sourceTid,
    required String event,
    required int page,
    required int expectedPages,
    required int postCount,
    required int filteredFirstCount,
    required int deduplicatedCount,
    required DateTime startedAt,
    ComicCommentLoadErrorCode? errorCode,
  }) {
    if (!_diagnosticRecorder.enabled) {
      return;
    }
    _diagnosticRecorder.record(
      ComicCommentDiagnosticEvent(
        sourceTidHash: comicCommentTidHash(sourceTid),
        event: event,
        page: page,
        expectedPages: expectedPages,
        postCount: postCount,
        filteredFirstCount: filteredFirstCount,
        deduplicatedCount: deduplicatedCount,
        duration: _now().difference(startedAt),
        errorCode: errorCode?.name,
      ),
    );
  }

  bool _isValidTid(String tid) {
    return RegExp(r'^\d+$').hasMatch(tid);
  }
}

final class _ComicCommentCacheEntry {
  const _ComicCommentCacheEntry(this.result, this.createdAt);

  final ComicCommentLoadResult result;
  final DateTime createdAt;
}
