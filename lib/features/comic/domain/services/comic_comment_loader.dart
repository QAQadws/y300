import 'dart:async';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/domain/services/comic_comment_diagnostics.dart';

abstract interface class ComicCommentLoader {
  Future<ComicCommentLoadResult> loadPage({
    required String sourceTid,
    int page = 1,
    ComicCommentCancellationToken? cancellationToken,
  });
}

abstract interface class ComicCommentLoaderCache {
  void invalidate(String sourceTid);
}

/// Cancels this waiter; another chapter can still share the underlying read.
class ComicCommentCancellationToken {
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

class DefaultComicCommentLoader
    implements ComicCommentLoader, ComicCommentLoaderCache {
  DefaultComicCommentLoader({
    required ThreadRepository repository,
    this.pageRequestTimeout = const Duration(seconds: 20),
    ComicCommentDiagnosticRecorder? diagnosticRecorder,
  }) : _repository = repository,
       _diagnosticRecorder =
           diagnosticRecorder ?? const NoopComicCommentDiagnosticRecorder();
  final ThreadRepository _repository;
  final Duration pageRequestTimeout;
  final ComicCommentDiagnosticRecorder _diagnosticRecorder;
  // Document/snapshot caching belongs to the forum client, not this loader.
  final Map<(String, int), Future<ComicCommentLoadResult>> _inFlight = {};

  @override
  Future<ComicCommentLoadResult> loadPage({
    required String sourceTid,
    int page = 1,
    ComicCommentCancellationToken? cancellationToken,
  }) {
    final tid = sourceTid.trim();
    if (!RegExp(r'^\d+$').hasMatch(tid) || page < 1) {
      return Future.value(
        ComicCommentLoadResult.failure(
          tid,
          ComicCommentLoadErrorCode.invalidSourceTid,
        ),
      );
    }
    final token = cancellationToken ?? ComicCommentCancellationToken();
    if (token.isCancelled) {
      return Future.value(ComicCommentLoadResult.cancelled(sourceTid: tid));
    }
    final key = (tid, page);
    final task = _inFlight.putIfAbsent(key, () => _fetch(tid, page));
    return Future.any<ComicCommentLoadResult>([
      task.whenComplete(() {
        if (identical(_inFlight[key], task)) _inFlight.remove(key);
      }),
      token.whenCancelled.then(
        (_) => ComicCommentLoadResult.cancelled(sourceTid: tid),
      ),
    ]);
  }

  @override
  void invalidate(String sourceTid) =>
      _inFlight.removeWhere((key, _) => key.$1 == sourceTid.trim());

  Future<ComicCommentLoadResult> _fetch(String tid, int page) async {
    final watch = Stopwatch()..start();
    ComicCommentLoadResult result;
    try {
      final read = await _repository
          .getThreadDetail(tid: tid, page: page)
          .timeout(pageRequestTimeout);
      final data = read.dataOrNull;
      if (data == null) {
        final failure = read.failureOrNull;
        result = ComicCommentLoadResult.failure(
          tid,
          failure?.statusCode == 429
              ? ComicCommentLoadErrorCode.rateLimited
              : switch (failure?.kind) {
                  DataReadFailureKind.unauthorized =>
                    ComicCommentLoadErrorCode.unauthorized,
                  DataReadFailureKind.timeout =>
                    ComicCommentLoadErrorCode.pageTimeout,
                  DataReadFailureKind.parse =>
                    ComicCommentLoadErrorCode.invalidPageResponse,
                  _ =>
                    page == 1
                        ? ComicCommentLoadErrorCode.firstPageUnavailable
                        : ComicCommentLoadErrorCode.pageUnavailable,
                },
        );
      } else if (data.tid.trim() != tid ||
          data.currentPage != page ||
          data.posts.isEmpty ||
          data.posts.any((post) => post.pid.trim().isEmpty)) {
        result = ComicCommentLoadResult.failure(
          tid,
          ComicCommentLoadErrorCode.invalidPageResponse,
        );
      } else {
        result = ComicCommentLoadResult.fromRead(
          read
              as DataReadSuccess<
                ThreadDetailData,
                ThreadDetailReadCapabilities
              >,
        );
      }
    } on TimeoutException {
      result = ComicCommentLoadResult.failure(
        tid,
        ComicCommentLoadErrorCode.pageTimeout,
      );
    } catch (_) {
      result = ComicCommentLoadResult.failure(
        tid,
        page == 1
            ? ComicCommentLoadErrorCode.firstPageUnavailable
            : ComicCommentLoadErrorCode.pageUnavailable,
      );
    }
    if (_diagnosticRecorder.enabled) {
      _diagnosticRecorder.record(
        ComicCommentDiagnosticEvent(
          sourceTidHash: comicCommentTidHash(tid),
          event: result.status.name,
          page: page,
          expectedPages: result.expectedPages,
          postCount: result.items.length,
          filteredFirstCount: 0,
          deduplicatedCount: result.items.length,
          duration: watch.elapsed,
          errorCode: result.errorCode?.name,
        ),
      );
    }
    return result;
  }
}
