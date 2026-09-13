import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';

void main() {
  test(
    'refresh retains comments and failed refresh never replaces them',
    () async {
      final pending = Completer<ComicCommentLoadResult>();
      final loader = _FakeCommentLoader([
        _successResult(),
        pending.future,
        _successResult(),
      ]);
      final controller = ComicCommentSessionController(
        key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
        loader: loader,
      );
      addTearDown(controller.dispose);
      await controller.load();
      final original = controller.state.result;
      final refresh = controller.refreshAfterMutation();
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isRefreshing, isTrue);
      expect(controller.state.result, same(original));
      pending.complete(_failureResult());
      await refresh;
      expect(controller.state.result, same(original));
      expect(controller.state.refreshFailed, isTrue);
      await controller.retry();
      expect(controller.state.refreshFailed, isFalse);
    },
  );

  test('successful mutation supersedes an unfinished initial load', () async {
    final pending = Completer<ComicCommentLoadResult>();
    final loader = _FakeCommentLoader([pending.future, _successResult()]);
    final controller = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
      loader: loader,
    );
    addTearDown(controller.dispose);
    final initial = controller.load();
    await controller.refreshAfterMutation();
    final refreshed = controller.state.result;
    pending.complete(_failureResult());
    await initial;
    expect(controller.state.result, same(refreshed));
    expect(controller.state.result?.items, hasLength(1));
  });

  test('loads one session once and reuses the completed result', () async {
    final loader = _FakeCommentLoader(<ComicCommentLoadResult>[
      _successResult(),
    ]);
    final controller = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
      loader: loader,
    );
    addTearDown(controller.dispose);

    await controller.load();
    await controller.load();

    expect(loader.calls, 1);
    expect(controller.state.result?.items.single.pid, 'p2');
    expect(controller.state.isLoading, isFalse);
  });

  test('retry starts a new load after a failure', () async {
    final loader = _FakeCommentLoader(<ComicCommentLoadResult>[
      _failureResult(),
      _successResult(),
    ]);
    final controller = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
      loader: loader,
      maxAutomaticAttempts: 1,
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.state.result?.status, ComicCommentLoadStatus.failure);

    await controller.retry();

    expect(loader.calls, 2);
    expect(controller.state.result?.status, ComicCommentLoadStatus.success);
  });

  test('automatic load retries one transient first-page failure', () async {
    final delays = <Duration>[];
    final loader = _FakeCommentLoader(<ComicCommentLoadResult>[
      _failureResult(),
      _successResult(),
    ]);
    final controller = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
      loader: loader,
      automaticRetryDelay: const Duration(milliseconds: 500),
      delay: (duration) async => delays.add(duration),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(loader.calls, 2);
    expect(delays, const <Duration>[Duration(milliseconds: 500)]);
    expect(controller.state.result?.status, ComicCommentLoadStatus.success);
  });

  test('automatic load does not retry a non-transient failure', () async {
    final loader = _FakeCommentLoader(<ComicCommentLoadResult>[
      _failureResult(errorCode: ComicCommentLoadErrorCode.unauthorized),
    ]);
    final controller = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
      loader: loader,
      delay: (_) async {},
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(loader.calls, 1);
    expect(controller.state.result?.status, ComicCommentLoadStatus.failure);
  });

  test(
    'dispose invalidates a late result without notifying listeners',
    () async {
      final completer = Completer<ComicCommentLoadResult>();
      final loader = _FakeCommentLoader(<Future<ComicCommentLoadResult>>[
        completer.future,
      ]);
      final controller = ComicCommentSessionController(
        key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
        loader: loader,
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      final load = controller.load();
      expect(controller.state.isLoading, isTrue);
      controller.dispose();
      completer.complete(_successResult());
      await load;

      expect(notifications, 1);
    },
  );
}

class _FakeCommentLoader implements ComicCommentLoader {
  _FakeCommentLoader(this._responses);

  final List<Object> _responses;
  int calls = 0;

  @override
  Future<ComicCommentLoadResult> loadPage({
    int page = 1,
    required String sourceTid,
    ComicCommentCancellationToken? cancellationToken,
  }) async {
    final response = _responses[calls++];
    if (response is Future<ComicCommentLoadResult>) {
      return response;
    }
    return response as ComicCommentLoadResult;
  }
}

ComicCommentLoadResult _successResult() {
  return const ComicCommentLoadResult(
    sourceTid: '573279',
    status: ComicCommentLoadStatus.success,
    items: <ComicCommentItem>[
      ComicCommentItem(
        pid: 'p2',
        authorId: '8',
        authorName: '回复者',
        dateline: '刚刚',
        floorNumber: 2,
        rawMessage: '<p>评论正文</p>',
        avatarUrl: null,
      ),
    ],
    loadedPages: <int>{1},
    expectedPages: 1,
  );
}

ComicCommentLoadResult _failureResult({
  ComicCommentLoadErrorCode errorCode =
      ComicCommentLoadErrorCode.firstPageUnavailable,
}) {
  return ComicCommentLoadResult(
    sourceTid: '573279',
    status: ComicCommentLoadStatus.failure,
    items: <ComicCommentItem>[],
    loadedPages: <int>{},
    expectedPages: 0,
    errorCode: errorCode,
    diagnosticDetail: 'request_failed',
  );
}
