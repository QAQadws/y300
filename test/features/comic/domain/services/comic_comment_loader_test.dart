import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import '../../data/comic_comment_fixtures.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/thread/data/mappers/thread_detail_api_mapper.dart';
import 'package:y300/features/thread/domain/models/thread_reply_page.dart';
import 'package:y300/features/thread/domain/repositories/thread_reply_page_repository.dart';

void main() {
  test(
    'loads both pages, excludes only the first floor, and maps avatars',
    () async {
      final page1 = _fixturePage(1);
      final page2 = _fixturePage(2);
      final repository = _FakeReplyPageRepository(
        <int, DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>{
          1: _success(page1),
          2: _success(page2),
        },
      );
      final loader = DefaultComicCommentLoader(repository: repository);

      final result = await loader.loadAll(sourceTid: '570140');

      expect(result.status, ComicCommentLoadStatus.success);
      expect(result.isComplete, isTrue);
      expect(result.items, hasLength(39));
      expect(result.loadedPages, <int>{1, 2});
      expect(result.expectedPages, 2);
      expect(result.items.any((item) => item.pid == '41519747'), isFalse);
      expect(
        result.items.any(
          (item) => item.authorName == 'thread-owner' && item.floorNumber == 2,
        ),
        isTrue,
      );
      expect(
        result.items.firstWhere((item) => item.authorId == '422014').avatarUrl,
        'https://bbs.yamibo.com/uc_server/data/avatar/000/42/20/14_avatar_middle.jpg',
      );
      expect(
        result.items.firstWhere((item) => item.authorId == '8').avatarUrl,
        'https://bbs.yamibo.com/uc_server/data/avatar/000/00/00/08_avatar_middle.jpg',
      );
      expect(result.items.first.rawMessage, contains('<p>'));
    },
  );

  test('ignores nested comments and deduplicates pid across pages', () async {
    final page1 = _fixturePage(1);
    final sourcePage2 = _fixturePage(2);
    final page2 = ThreadReplyPage(
      tid: sourcePage2.tid,
      page: sourcePage2.page,
      perPage: sourcePage2.perPage,
      replyCount: sourcePage2.replyCount,
      posts: <ThreadReplyEntry>[sourcePage2.posts.first, page1.posts[1]],
    );
    final repository = _FakeReplyPageRepository(
      <int, DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>{
        1: _success(page1),
        2: _success(page2),
      },
    );

    final result = await DefaultComicCommentLoader(
      repository: repository,
    ).loadAll(sourceTid: '570140');

    expect(result.status, ComicCommentLoadStatus.success);
    expect(result.items, hasLength(20));
    expect(
      result.items.where((item) => item.pid == page1.posts[1].pid),
      hasLength(1),
    );
  });

  test('returns partial failure when a later page cannot be loaded', () async {
    final repository = _FakeReplyPageRepository(
      <int, DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>{
        1: _success(_fixturePage(1)),
        2: _failure(DataReadFailureKind.timeout),
      },
    );

    final result = await DefaultComicCommentLoader(
      repository: repository,
    ).loadAll(sourceTid: '570140');

    expect(result.status, ComicCommentLoadStatus.partialFailure);
    expect(result.isComplete, isFalse);
    expect(result.items, hasLength(19));
    expect(result.errorCode, ComicCommentLoadErrorCode.pageTimeout);
    expect(result.loadedPages, <int>{1});
  });

  test('coalesces concurrent loads for the same source thread', () async {
    final repository = _FakeReplyPageRepository(
      <int, DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>{
        1: _success(_fixturePage(1)),
        2: _success(_fixturePage(2)),
      },
      delay: const Duration(milliseconds: 10),
    );
    final loader = DefaultComicCommentLoader(repository: repository);

    final results = await Future.wait<ComicCommentLoadResult>([
      loader.loadAll(sourceTid: '570140'),
      loader.loadAll(sourceTid: '570140'),
    ]);

    expect(results[0].items, hasLength(39));
    expect(results[1].items, hasLength(39));
    expect(repository.calls, <String>['570140:1', '570140:2']);
  });

  test(
    'cancellation stops waiting while the shared request continues',
    () async {
      final repository = _FakeReplyPageRepository(
        <int, DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>{
          1: _success(_fixturePage(1)),
        },
        delay: const Duration(milliseconds: 30),
      );
      final loader = DefaultComicCommentLoader(repository: repository);
      final token = ComicCommentCancellationToken();
      final future = loader.loadAll(
        sourceTid: '570140',
        cancellationToken: token,
      );

      token.cancel();
      final result = await future;

      expect(result.status, ComicCommentLoadStatus.cancelled);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(repository.calls, <String>['570140:1', '570140:2']);
    },
  );

  test('returns empty for a thread with only the first floor', () async {
    final page = ThreadReplyPage(
      tid: '570140',
      page: 1,
      perPage: 20,
      replyCount: 0,
      posts: const <ThreadReplyEntry>[
        ThreadReplyEntry(
          pid: '41519747',
          authorId: '365616',
          authorName: 'owner',
          rawMessage: 'first',
          floorNumber: 1,
          isFirst: true,
          dateline: 'today',
        ),
      ],
    );

    final result = await DefaultComicCommentLoader(
      repository: _FakeReplyPageRepository(
        <int, DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>{
          1: _success(page),
        },
      ),
    ).loadAll(sourceTid: '570140');

    expect(result.status, ComicCommentLoadStatus.empty);
    expect(result.items, isEmpty);
  });

  test('rejects an invalid source tid without a network request', () async {
    final repository = _FakeReplyPageRepository(
      <int, DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>{},
    );

    final result = await DefaultComicCommentLoader(
      repository: repository,
    ).loadAll(sourceTid: 'not-a-tid');

    expect(result.status, ComicCommentLoadStatus.failure);
    expect(result.errorCode, ComicCommentLoadErrorCode.invalidSourceTid);
    expect(repository.calls, isEmpty);
  });

  test('reports truncation when the page safety limit is reached', () async {
    final repository = _FakeReplyPageRepository(
      <int, DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>{
        1: _success(_fixturePage(1)),
      },
    );

    final result = await DefaultComicCommentLoader(
      repository: repository,
      maxPageRequests: 1,
    ).loadAll(sourceTid: '570140');

    expect(result.status, ComicCommentLoadStatus.partialFailure);
    expect(result.errorCode, ComicCommentLoadErrorCode.maxPageRequestsReached);
    expect(result.expectedPages, 1);
  });

  test('reuses complete results within the short memory TTL', () async {
    var now = DateTime(2026, 7, 19, 12);
    final repository = _FakeReplyPageRepository(
      <int, DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>{
        1: _success(_fixturePage(1)),
        2: _success(_fixturePage(2)),
      },
    );
    final loader = DefaultComicCommentLoader(
      repository: repository,
      cacheTtl: const Duration(minutes: 2),
      now: () => now,
    );

    await loader.loadAll(sourceTid: '570140');
    await loader.loadAll(sourceTid: '570140');
    expect(repository.calls, <String>['570140:1', '570140:2']);

    now = now.add(const Duration(minutes: 3));
    await loader.loadAll(sourceTid: '570140');
    expect(repository.calls, <String>[
      '570140:1',
      '570140:2',
      '570140:1',
      '570140:2',
    ]);
  });

  test('invalidate removes a complete result before the next load', () async {
    final repository = _FakeReplyPageRepository(
      <int, DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>{
        1: _success(_fixturePage(1)),
        2: _success(_fixturePage(2)),
      },
    );
    final loader = DefaultComicCommentLoader(repository: repository);

    await loader.loadAll(sourceTid: '570140');
    loader.invalidate('570140');
    await loader.loadAll(sourceTid: '570140');

    expect(repository.calls, <String>[
      '570140:1',
      '570140:2',
      '570140:1',
      '570140:2',
    ]);
  });

  test('maps rate limiting to a stable error code', () async {
    final repository = _FakeReplyPageRepository(
      <int, DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>{
        1: _failure(DataReadFailureKind.server, statusCode: 429),
      },
    );

    final result = await DefaultComicCommentLoader(
      repository: repository,
    ).loadAll(sourceTid: '570140');

    expect(result.errorCode, ComicCommentLoadErrorCode.rateLimited);
    expect(result.diagnosticDetail, DataReadFailureKind.server.name);
  });

  test('times out a slow page without blocking the reader forever', () async {
    final repository = _FakeReplyPageRepository(
      <int, DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>{
        1: _success(_fixturePage(1)),
      },
      delay: const Duration(milliseconds: 20),
    );

    final result = await DefaultComicCommentLoader(
      repository: repository,
      pageRequestTimeout: const Duration(milliseconds: 1),
    ).loadAll(sourceTid: '570140');

    expect(result.errorCode, ComicCommentLoadErrorCode.pageTimeout);
  });
}

ThreadReplyPage _fixturePage(int page) {
  final data = const ThreadDetailApiMapper().mapVariables(
    comicCommentPageVariables(page: page),
    page: page,
  );
  return ThreadReplyPage(
    tid: data.tid,
    page: data.currentPage,
    perPage: data.perPage,
    replyCount: data.replies,
    lastPage: data.lastPage,
    hasNext: data.hasMore,
    posts: data.posts
        .map(
          (post) => ThreadReplyEntry(
            pid: post.pid,
            authorId: post.authorId,
            authorName: post.author,
            dateline: post.dateline,
            floorNumber: post.number,
            isFirst: post.isFirst,
            rawMessage: post.message,
          ),
        )
        .toList(growable: false),
  );
}

final _replyCapabilities = ThreadReplyPageReadCapabilities(
  DataCapabilitySet<ThreadReplyPageCapability>({
    ThreadReplyPageCapability.stableThreadIdentity:
        DataCapabilitySupport.supported,
    ThreadReplyPageCapability.orderedReplies: DataCapabilitySupport.supported,
    ThreadReplyPageCapability.stablePostIdentity:
        DataCapabilitySupport.supported,
    ThreadReplyPageCapability.pagination: DataCapabilitySupport.supported,
  }),
);

DataReadSuccess<ThreadReplyPage, ThreadReplyPageReadCapabilities> _success(
  ThreadReplyPage page,
) {
  return DataReadSuccess(
    data: page,
    capabilities: _replyCapabilities,
    metadata: const DataReadMetadata.network(),
  );
}

DataReadFailure<ThreadReplyPage, ThreadReplyPageReadCapabilities> _failure(
  DataReadFailureKind kind, {
  int? statusCode,
}) {
  return DataReadFailure(
    kind: kind,
    statusCode: statusCode,
    diagnosticMessage: kind.name,
  );
}

class _FakeReplyPageRepository implements ThreadReplyPageRepository {
  _FakeReplyPageRepository(this.responses, {this.delay = Duration.zero});

  final Map<
    int,
    DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>
  >
  responses;
  final Duration delay;
  final List<String> calls = <String>[];

  @override
  Future<DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>
  loadPage({required String tid, required int page}) async {
    calls.add('$tid:$page');
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return responses[page] ?? _failure(DataReadFailureKind.server);
  }
}
