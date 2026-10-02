import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import '../../data/comic_comment_fixtures.dart';

void main() {
  ComicCommentSessionController session(CommentDetailRepository repo) {
    final value = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e', sourceTid: '100'),
      loader: DefaultComicCommentLoader(repository: repo),
    );
    addTearDown(value.dispose);
    return value;
  }

  test(
    'first-page action context stays collapsed; explicit expansion reuses it',
    () async {
      final repo = CommentDetailRepository();
      final feed = session(repo);
      await feed.loadContext();
      expect(feed.state.isExpanded, isFalse);
      await feed.loadMore();
      expect(repo.calls, [1]);
      await feed.load();
      expect(feed.state.isExpanded, isTrue);
      expect(repo.calls, [1]);
      await feed.loadMore();
      expect(repo.calls, [1, 2]);
    },
  );
  test(
    'sequential lazy pages deduplicate repeated first posts and keep original page ownership',
    () async {
      final repo = CommentDetailRepository(
        respond: (page) => commentDetailPage(
          page: page,
          posts: page == 2
              ? [commentPost(1), commentPost(2), commentPost(3), commentPost(4)]
              : null,
        ),
      );
      final feed = session(repo);
      await feed.load();
      final owner = feed.generation;
      expect(repo.calls, [1]);
      await Future.wait([feed.loadMore(), feed.loadMore()]);
      expect(repo.calls, [1, 2]);
      expect(feed.isCurrent(owner), isTrue);
      expect(feed.state.result!.items.map((p) => p.pid), ['1', '2', '3', '4']);
      expect(feed.state.result!.items.first.sourcePage, 1);
      expect(feed.state.result!.items.last.sourcePage, 2);
      await feed.loadMore();
      await feed.loadMore();
      expect(repo.calls, [1, 2, 3]);
      expect(feed.state.result!.hasMore, isFalse);
    },
  );
  test(
    'failed append preserves rows and retries only the failed page',
    () async {
      var fail = true;
      final repo = CommentDetailRepository(
        respond: (page) => page == 2 && fail
            ? const DataReadFailure(
                kind: DataReadFailureKind.network,
                diagnosticMessage: 'unavailable',
              )
            : commentDetailPage(page: page),
      );
      final feed = session(repo);
      await feed.load();
      final previous = feed.state.result;
      await feed.loadMore();
      expect(feed.state.result, same(previous));
      expect(feed.state.appendError, ComicCommentLoadErrorCode.pageUnavailable);
      await feed.loadMore();
      expect(repo.calls, [1, 2]);
      fail = false;
      await feed.retry();
      expect(repo.calls, [1, 2, 2]);
      expect(feed.state.result!.items, hasLength(4));
    },
  );
  test(
    'non-advancing pages stop automatic loading without dropping visible floors',
    () async {
      final repo = CommentDetailRepository(
        respond: (page) => commentDetailPage(
          page: page,
          posts: [commentPost(1), commentPost(2)],
        ),
      );
      final feed = session(repo);
      await feed.load();
      await feed.loadMore();
      await feed.loadMore();
      expect(repo.calls, [1, 2]);
      expect(
        feed.state.appendError,
        ComicCommentLoadErrorCode.invalidPageResponse,
      );
      expect(feed.state.result!.items, hasLength(2));
    },
  );
  test(
    'post mutations refresh their page, replies refresh first and loaded last page',
    () async {
      var revised = false;
      final repo = CommentDetailRepository(
        respond: (page) => commentDetailPage(
          page: page,
          posts: page == 2 && revised
              ? [commentPost(3, message: '<p>changed</p>'), commentPost(4)]
              : null,
        ),
      );
      final feed = session(repo);
      await feed.load();
      await feed.loadMore();
      await feed.loadMore();
      final first = feed.state.result!.items.first;
      revised = true;
      await feed.refreshAfterMutation(page: 2);
      expect(repo.calls, [1, 2, 3, 2]);
      expect(feed.state.result!.items.first, same(first));
      expect(feed.state.result!.items[2].rawMessage, contains('changed'));
      await feed.refreshAfterMutation();
      expect(repo.calls, [1, 2, 3, 2, 1, 3]);
      expect(feed.state.result!.items, hasLength(6));
    },
  );
  test(
    'mutation supersedes a late append and account reset invalidates open action guards',
    () async {
      final pending = Completer<CommentDetailRead>();
      final repo = CommentDetailRepository(
        respond: (page) =>
            page == 2 ? pending.future : commentDetailPage(page: page),
      );
      final feed = session(repo);
      await feed.load();
      final append = feed.loadMore();
      await feed.refreshAfterMutation(page: 1);
      pending.complete(commentDetailPage(page: 2));
      await append;
      expect(feed.state.result!.items, hasLength(2));
      final guard = feed.generation;
      await feed.resetSession();
      expect(feed.isCurrent(guard), isFalse);
      expect(feed.state.isExpanded, isTrue);
      expect(feed.state.result!.items, hasLength(2));
    },
  );
  test(
    'partial refresh keeps successful pages and retries only failures',
    () async {
      var refreshing = false;
      var failLast = true;
      final repo = CommentDetailRepository(
        respond: (page) {
          if (refreshing && page == 3 && failLast) {
            return const DataReadFailure(
              kind: DataReadFailureKind.network,
              diagnosticMessage: 'fixture_unavailable',
            );
          }
          return commentDetailPage(
            page: page,
            posts: refreshing && page == 1
                ? [commentPost(1, message: '<p>refreshed</p>'), commentPost(2)]
                : null,
          );
        },
      );
      final feed = session(repo);
      await feed.load();
      await feed.loadMore();
      await feed.loadMore();
      final last = feed.state.result!.items.last;
      refreshing = true;
      await feed.refreshAfterMutation();
      expect(feed.state.refreshFailed, isTrue);
      expect(feed.state.result!.items.first.rawMessage, contains('refreshed'));
      expect(feed.state.result!.items.last, same(last));
      failLast = false;
      await feed.retry();
      expect(repo.calls, [1, 2, 3, 1, 3, 3]);
      expect(feed.state.refreshFailed, isFalse);
    },
  );
  test(
    'visibility waits for account cache invalidation before reading',
    () async {
      final barrier = Completer<void>();
      final repo = CommentDetailRepository();
      final feed = ComicCommentSessionController(
        key: const ComicCommentSessionKey(episodeId: 'e', sourceTid: '100'),
        loader: DefaultComicCommentLoader(repository: repo),
        invalidateThread: (_) => barrier.future,
      );
      addTearDown(feed.dispose);
      await feed.load();
      final reset = feed.resetSession();
      final visible = feed.loadContext();
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, [1]);
      expect(feed.state.result, isNull);
      barrier.complete();
      await Future.wait([reset, visible]);
      expect(repo.calls, [1, 1]);
      expect(feed.state.result!.items, hasLength(2));
    },
  );
}
