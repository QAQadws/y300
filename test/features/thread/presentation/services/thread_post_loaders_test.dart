import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/domain/models/thread_post_rating_details.dart';
import 'package:y300/features/thread/domain/models/thread_ui_feedback.dart';
import 'package:y300/features/thread/presentation/models/thread_post_load_state.dart';
import 'package:y300/features/thread/presentation/models/thread_post_loading_content.dart';
import 'package:y300/features/thread/presentation/services/thread_post_comments_loader.dart';
import 'package:y300/features/thread/presentation/services/thread_post_ratings_loader.dart';

void main() {
  test(
    'ratings coalesce by post, cache successes and keep snapshots immutable',
    () async {
      final f = _Fixture();
      f.content = _content([_post(), _post(pid: 'q')]);
      final first = f.ratings.load(_post());
      await f.ratings.load(_post());
      final other = f.ratings.load(_post(pid: 'q'));
      expect(f.ratingRequests, hasLength(2));
      final loading = f.ratings.values;
      f.ratingRequests[0].complete(const ApiSuccess(_details));
      f.ratingRequests[1].complete(const ApiSuccess(_details));
      await Future.wait([first, other]);
      await f.ratings.load(_post());
      expect(f.ratingRequests, hasLength(2));
      expect(f.ratings.values['p']!.status, ThreadPostRatingsLoadStatus.loaded);
      expect(loading['p']!.status, ThreadPostRatingsLoadStatus.loading);
      expect(() => f.ratings.values.clear(), throwsUnsupportedError);
    },
  );

  test(
    'ratings failures are retryable and thrown errors do not remain loading',
    () async {
      final f = _Fixture();
      final first = f.ratings.load(_post());
      f.ratingRequests.last.complete(
        const ApiFailure(
          ApiError(type: ApiErrorType.unauthorized, message: 'login'),
        ),
      );
      await first;
      expect(
        f.ratings.values['p']!.failure!.code,
        ThreadUiErrorCode.loginRequired,
      );
      final second = f.ratings.load(_post());
      f.ratingRequests.last.completeError(StateError('private payload'));
      await second;
      expect(f.ratings.values['p']!.failure!.code, ThreadUiErrorCode.unknown);
      expect(f.ratings.values['p']!.failure!.detail, isNull);
      final third = f.ratings.load(_post());
      f.ratingRequests.last.complete(const ApiSuccess(_details));
      await third;
      expect(f.ratings.values['p']!.details, same(_details));
    },
  );

  test(
    'ratings reject unavailable capability, missing post and stale entry URL',
    () async {
      final f = _Fixture();
      f.content = ThreadPostLoadingContent(
        tid: 't',
        posts: [_post()],
        supportsRatings: false,
      );
      await f.ratings.load(_post());
      f.content = _content([]);
      await f.ratings.load(_post());
      f.content = _content([_post(url: 'changed')]);
      await f.ratings.load(_post());
      expect(f.ratingRequests, isEmpty);
    },
  );

  for (final change in ['reset', 'close', 'thread', 'entry', 'removed']) {
    test('late rating results are rejected after $change', () async {
      final f = _Fixture();
      final loading = f.ratings.load(_post());
      switch (change) {
        case 'reset':
          f.ratings.reset();
        case 'close':
          f.ratings.close();
        case 'thread':
          f.content = _content([_post()], tid: 'other');
        case 'entry':
          f.content = _content([_post(url: 'other')]);
        case 'removed':
          f.content = _content([]);
      }
      final snapshot = f.ratings.values;
      final publications = f.ratingPublications;
      f.ratingRequests.single.complete(const ApiSuccess(_details));
      await loading;
      expect(f.ratings.values, same(snapshot));
      expect(f.ratingPublications, publications);
    });
  }

  test('comment continuation deduplicates stable IDs without dropping anonymous duplicates', () async {
    final f = _Fixture();
    f.content = _content([
      _post(comments: [_comment('base')]),
    ]);
    final first = f.comments.loadMore(_post());
    await f.comments.loadMore(_post());
    expect(f.commentQueries.map((q) => q.page), [2]);
    f.commentRequests.last.complete(
      _page(
        comments: [
          _comment('base'),
          _comment('new'),
          _comment('new'),
          _comment(null),
          _comment(null),
        ],
        nextPage: 3,
      ),
    );
    await first;
    expect(f.comments.values['p']!.comments.map((c) => c.commentId), [
      'new',
      null,
      null,
    ]);
    final retained = f.comments.values;
    final second = f.comments.loadMore(_post());
    expect(f.commentQueries.map((q) => q.page), [2, 3]);
    f.commentRequests.last.complete(
      _page(page: 3, comments: [_comment('new'), _comment('last')]),
    );
    await second;
    expect(f.comments.values['p']!.comments.map((c) => c.commentId), [
      'new',
      null,
      null,
      'last',
    ]);
    expect(retained['p']!.comments, hasLength(3));
    expect(
      () => f.comments.values['p']!.comments.clear(),
      throwsUnsupportedError,
    );
    await f.comments.loadMore(_post());
    expect(f.commentQueries, hasLength(2));
  });

  for (final failure in ['login', 'permission', 'network', 'throw']) {
    test(
      'comments retain their confirmed page and accumulated content after $failure',
      () async {
        final f = _Fixture();
        final first = f.comments.loadMore(_post());
        f.commentRequests.last.complete(
          _page(comments: [_comment('prior')], nextPage: 3),
        );
        await first;
        final next = f.comments.loadMore(_post());
        if (failure == 'throw') {
          f.commentRequests.last.completeError(StateError('private payload'));
        } else {
          f.commentRequests.last.complete(
            DataReadFailure(
              kind: failure == 'login'
                  ? DataReadFailureKind.unauthorized
                  : DataReadFailureKind.network,
              code: failure == 'permission'
                  ? 'thread_post_comments_permission_denied'
                  : 'offline',
              diagnosticMessage: 'private payload',
            ),
          );
        }
        await next;
        final value = f.comments.values['p']!;
        expect(value.isLoading, isFalse);
        expect(value.nextPage, 3);
        expect(value.comments.single.commentId, 'prior');
        expect(
          value.failure,
          failure == 'login'
              ? ThreadPostCommentsFailure.loginRequired
              : failure == 'permission'
              ? ThreadPostCommentsFailure.permissionDenied
              : ThreadPostCommentsFailure.other,
        );
        final retry = f.comments.loadMore(_post());
        expect(f.commentQueries.map((q) => q.page), [2, 3, 3]);
        f.commentRequests.last.complete(_page(page: 3));
        await retry;
        expect(f.comments.values['p']!.failure, isNull);
      },
    );
  }

  for (final mismatch in ['tid', 'pid', 'page']) {
    test('comments reject a response with mismatched $mismatch', () async {
      final f = _Fixture();
      final loading = f.comments.loadMore(_post());
      f.commentRequests.last.complete(
        _page(
          tid: mismatch == 'tid' ? 'wrong' : 't',
          pid: mismatch == 'pid' ? 'wrong' : 'p',
          page: mismatch == 'page' ? 7 : 2,
          comments: [_comment('wrong')],
        ),
      );
      await loading;
      expect(f.comments.values['p']!.comments, isEmpty);
      expect(f.comments.values['p']!.failure, ThreadPostCommentsFailure.other);
      expect(f.comments.values['p']!.nextPage, 2);
    });
  }

  for (final change in ['reset', 'close', 'thread', 'removed']) {
    test('late comment results are rejected after $change', () async {
      final f = _Fixture();
      final loading = f.comments.loadMore(_post());
      switch (change) {
        case 'reset':
          f.comments.reset();
        case 'close':
          f.comments.close();
        case 'thread':
          f.content = _content([_post()], tid: 'other');
        case 'removed':
          f.content = _content([]);
      }
      final snapshot = f.comments.values;
      final publications = f.commentPublications;
      f.commentRequests.single.complete(_page(comments: [_comment('late')]));
      await loading;
      expect(f.comments.values, same(snapshot));
      expect(f.commentPublications, publications);
    });
  }

  test('old cleanup cannot release requests in a new content epoch', () async {
    final f = _Fixture();
    final oldRatings = f.ratings.load(_post());
    final oldComments = f.comments.loadMore(_post());
    f.ratings.reset();
    f.comments.reset();
    final newRatings = f.ratings.load(_post());
    final newComments = f.comments.loadMore(_post());
    f.ratingRequests.first.complete(const ApiSuccess(_details));
    f.commentRequests.first.complete(_page());
    await Future.wait([oldRatings, oldComments]);
    await f.ratings.load(_post());
    await f.comments.loadMore(_post());
    expect(f.ratingRequests, hasLength(2));
    expect(f.commentRequests, hasLength(2));
    f.ratingRequests.last.complete(const ApiSuccess(_details));
    f.commentRequests.last.complete(_page());
    await Future.wait([newRatings, newComments]);
    expect(f.ratings.values['p']!.status, ThreadPostRatingsLoadStatus.loaded);
    expect(f.comments.values['p']!.isLoading, isFalse);
  });

  test(
    'reset in a loading callback retires work before any I/O starts',
    () async {
      final f = _Fixture();
      f.onRatingPublication = () => f.ratings.reset();
      f.onCommentPublication = () => f.comments.reset();
      await f.ratings.load(_post());
      await f.comments.loadMore(_post());
      expect(f.ratingRequests, isEmpty);
      expect(f.commentRequests, isEmpty);
    },
  );
}

const _details = ThreadPostRatingDetails(
  participantCount: 1,
  totalScoreText: '+1',
  ratings: [],
);
final _commentCapabilities = ThreadPostCommentsReadCapabilities(
  values: DataCapabilitySet.supported(ThreadPostCommentsCapability.values),
);

ThreadPostCommentsRead _page({
  String tid = 't',
  String pid = 'p',
  int page = 2,
  List<ThreadPostCommentEntry> comments = const [],
  int? nextPage,
}) => DataReadSuccess(
  data: ThreadPostCommentsPage(
    tid: tid,
    pid: pid,
    page: page,
    comments: comments,
    nextPage: nextPage,
  ),
  capabilities: _commentCapabilities,
  metadata: const DataReadMetadata.network(),
);

ThreadPostCommentEntry _comment(String? id) => ThreadPostCommentEntry(
  commentId: id,
  author: 'test',
  message: 'identical text',
  dateline: 'today',
);

ThreadPost _post({
  String pid = 'p',
  String url = 'ratings',
  List<ThreadPostCommentEntry> comments = const [],
}) => ThreadPost(
  pid: pid,
  author: 'test',
  authorId: '1',
  message: 'body',
  number: 1,
  isFirst: true,
  dateline: '',
  ratingSummary: ThreadPostRatingSummary(
    participantText: '',
    scoreText: '',
    viewAllUrl: '$url-$pid',
    ratings: const [],
  ),
  commentNextPage: 2,
  comments: comments,
);

ThreadPostLoadingContent _content(List<ThreadPost> posts, {String tid = 't'}) =>
    ThreadPostLoadingContent(tid: tid, posts: posts, supportsRatings: true);

final class _Fixture {
  _Fixture() {
    content = _content([_post()]);
    ratings = ThreadPostRatingsLoader(
      loadAll: (_) {
        final result = Completer<ApiResult<ThreadPostRatingDetails>>();
        ratingRequests.add(result);
        return result.future;
      },
      readContent: () => content,
      onChanged: (_) {
        ratingPublications++;
        onRatingPublication?.call();
      },
    );
    comments = ThreadPostCommentsLoader(
      loadPage: (query) {
        commentQueries.add(query);
        final result = Completer<ThreadPostCommentsRead>();
        commentRequests.add(result);
        return result.future;
      },
      readContent: () => content,
      onChanged: (_) {
        commentPublications++;
        onCommentPublication?.call();
      },
    );
    addTearDown(() {
      ratings.close();
      comments.close();
    });
  }
  late ThreadPostLoadingContent content;
  late final ThreadPostRatingsLoader ratings;
  late final ThreadPostCommentsLoader comments;
  final ratingRequests = <Completer<ApiResult<ThreadPostRatingDetails>>>[];
  final commentRequests = <Completer<ThreadPostCommentsRead>>[];
  final commentQueries = <ThreadPostCommentsQuery>[];
  int ratingPublications = 0;
  int commentPublications = 0;
  void Function()? onRatingPublication;
  void Function()? onCommentPublication;
}
