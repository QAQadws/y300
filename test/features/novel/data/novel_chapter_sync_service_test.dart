import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/services/default_novel_chapter_sync_service.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_sync_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_author_post_episode_builder.dart';
import 'package:y300/features/novel/domain/services/novel_sync_request_governor.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  test(
    'initial full fetches every page and filters author and duplicate PID',
    () async {
      final gateway = _FakeGateway(<int, Future<ThreadDetailData> Function()>{
        1: () async => _page(
          page: 1,
          posts: <ThreadPost>[
            _post(
              pid: '1',
              number: 1,
              isFirst: true,
              message: '<p>简介</p><p>来源简介</p><p>目录</p>',
            ),
            _post(pid: '2', number: 2, message: '<p>第一章开场。后文</p>'),
          ],
        ),
        2: () async => _page(
          page: 2,
          posts: <ThreadPost>[
            _post(pid: '2', number: 3, message: '<p>重复 PID。</p>'),
            _post(
              pid: '3',
              authorId: '999',
              number: 4,
              message: '<p>其他作者。</p>',
            ),
            _post(
              pid: 'reply',
              number: 5,
              message:
                  '<div class="quote"><blockquote>读者 发表于 2026-7-13</blockquote></div><br>楼主回复。',
            ),
            _post(pid: '4', number: 6, message: '<p>第二章开场！后文</p>'),
          ],
        ),
        3: () async => _page(
          page: 3,
          posts: <ThreadPost>[
            _post(pid: '5', number: 7, message: '<p>第三章开场？后文</p>'),
          ],
        ),
      });
      final repository = _FakeSyncRepository();
      final sourceStateRepository = _FakeSourceStateRepository();
      final governor = _RecordingGovernor();
      final service = DefaultNovelChapterSyncService(
        threadGateway: gateway,
        governor: governor,
        episodeBuilder: const DefaultNovelAuthorPostEpisodeBuilder(),
        repository: repository,
        sourceStateRepository: sourceStateRepository,
        clock: () => DateTime(2026, 7, 13),
        runIdFactory: (_, _) => 'run-1',
      );
      addTearDown(service.dispose);

      final result = await service.synchronize(_request());

      expect(gateway.calls.map((call) => call.page), <int>[1, 2, 3]);
      expect(
        gateway.calls.map((call) => call.authorId),
        everyElement('406769'),
      );
      expect(gateway.calls.map((call) => call.postsPerPage), everyElement(200));
      expect(governor.scheduleCount, 3);
      expect(
        repository.staged.expand((batch) => batch).map((e) => e.sourcePid),
        <String>['2', '4', '5'],
      );
      expect(
        repository.staged.expand((batch) => batch).map((e) => e.orderIndex),
        <int>[0, 1, 2],
      );
      expect(repository.promoteCount, 1);
      expect(repository.discardCount, 0);
      expect(result.fetchedPages, 3);
      expect(result.totalCount, 3);
      expect(result.checkpoint.lastCompletedAuthorPage, 3);
      expect(result.checkpoint.lastSeenPid, '5');
    },
  );

  test('middle page failure discards staging and never promotes', () async {
    final gateway = _FakeGateway(<int, Future<ThreadDetailData> Function()>{
      1: () async => _page(
        page: 1,
        posts: <ThreadPost>[_post(pid: '2', number: 2, message: '<p>第一章。</p>')],
      ),
      2: () async => throw StateError('page 2 failed'),
    });
    final repository = _FakeSyncRepository();
    final sourceStateRepository = _FakeSourceStateRepository();
    final service = DefaultNovelChapterSyncService(
      threadGateway: gateway,
      governor: _RecordingGovernor(),
      episodeBuilder: const DefaultNovelAuthorPostEpisodeBuilder(),
      repository: repository,
      sourceStateRepository: sourceStateRepository,
      runIdFactory: (_, _) => 'run-failure',
    );
    addTearDown(service.dispose);

    await expectLater(service.synchronize(_request()), throwsStateError);

    expect(repository.promoteCount, 0);
    expect(repository.discardCount, 1);
    expect(sourceStateRepository.lastState, NovelChapterHydrationState.failed);
  });

  test(
    'incremental sync refetches the persisted checkpoint page through the new last page',
    () async {
      final gateway = _FakeGateway(<int, Future<ThreadDetailData> Function()>{
        3: () async => _page(
          page: 3,
          replies: 9,
          posts: <ThreadPost>[
            _post(pid: 'old-3', number: 5, message: '<p>修订后的第三章。</p>'),
            _post(pid: 'new-3', number: 6, message: '<p>页尾新增章节。</p>'),
          ],
        ),
        4: () async => _page(
          page: 4,
          replies: 9,
          posts: <ThreadPost>[
            _post(pid: 'new-4', number: 7, message: '<p>第四页章节。</p>'),
          ],
        ),
        5: () async => _page(
          page: 5,
          replies: 9,
          posts: <ThreadPost>[
            _post(pid: 'new-5', number: 8, message: '<p>最新章节。</p>'),
          ],
        ),
      });
      final repository = _FakeSyncRepository();
      final service = DefaultNovelChapterSyncService(
        threadGateway: gateway,
        governor: _RecordingGovernor(),
        episodeBuilder: const DefaultNovelAuthorPostEpisodeBuilder(),
        repository: repository,
        sourceStateRepository: _FakeSourceStateRepository(),
        clock: () => DateTime(2026, 7, 14),
        runIdFactory: (_, _) => 'run-incremental',
      );
      addTearDown(service.dispose);

      final result = await service.synchronize(_incrementalRequest());

      expect(gateway.calls.map((call) => call.page), <int>[3, 4, 5]);
      expect(
        repository.staged.expand((batch) => batch).map((e) => e.sourcePid),
        <String>['old-3', 'new-3', 'new-4', 'new-5'],
      );
      expect(result.mode, NovelChapterSyncMode.incremental);
      expect(result.fetchedPages, 3);
      expect(result.checkpoint.lastCompletedAuthorPage, 5);
      expect(result.checkpoint.lastSeenPid, 'new-5');
    },
  );

  test(
    'incremental middle page failure keeps ready state and does not promote',
    () async {
      final gateway = _FakeGateway(<int, Future<ThreadDetailData> Function()>{
        3: () async => _page(
          page: 3,
          replies: 7,
          posts: <ThreadPost>[
            _post(pid: 'old-3', number: 5, message: '<p>第三章。</p>'),
          ],
        ),
        4: () async => throw StateError('page 4 failed'),
      });
      final repository = _FakeSyncRepository();
      final sourceStateRepository = _FakeSourceStateRepository();
      final service = DefaultNovelChapterSyncService(
        threadGateway: gateway,
        governor: _RecordingGovernor(),
        episodeBuilder: const DefaultNovelAuthorPostEpisodeBuilder(),
        repository: repository,
        sourceStateRepository: sourceStateRepository,
        runIdFactory: (_, _) => 'run-incremental-failure',
      );
      addTearDown(service.dispose);

      await expectLater(
        service.synchronize(_incrementalRequest()),
        throwsStateError,
      );

      expect(gateway.calls.map((call) => call.page), <int>[3, 4]);
      expect(repository.promoteCount, 0);
      expect(repository.discardCount, 1);
      expect(sourceStateRepository.lastState, NovelChapterHydrationState.ready);
    },
  );

  test('concurrent synchronization joins one novel run', () async {
    final response = Completer<ThreadDetailData>();
    final gateway = _FakeGateway(<int, Future<ThreadDetailData> Function()>{
      1: () => response.future,
    });
    final repository = _FakeSyncRepository();
    final service = DefaultNovelChapterSyncService(
      threadGateway: gateway,
      governor: _RecordingGovernor(),
      episodeBuilder: const DefaultNovelAuthorPostEpisodeBuilder(),
      repository: repository,
      sourceStateRepository: _FakeSourceStateRepository(),
      runIdFactory: (_, _) => 'run-shared',
    );
    addTearDown(service.dispose);

    final first = service.synchronize(_request());
    final second = service.synchronize(_request());
    expect(identical(first, second), isTrue);
    response.complete(
      _page(
        page: 1,
        replies: 0,
        posts: <ThreadPost>[
          _post(pid: '2', number: 2, message: '<p>唯一章节。</p>'),
        ],
      ),
    );
    await Future.wait(<Future<NovelChapterSyncResult>>[first, second]);

    expect(gateway.calls, hasLength(1));
    expect(repository.beginCount, 1);
    expect(repository.promoteCount, 1);
  });
}

NovelChapterSyncRequest _request() {
  return const NovelChapterSyncRequest(
    novelId: 'novel:55:521519',
    tid: '521519',
    publisherId: '406769',
    mode: NovelChapterSyncMode.initialFull,
  );
}

NovelChapterSyncRequest _incrementalRequest() {
  return NovelChapterSyncRequest(
    novelId: 'novel:55:521519',
    tid: '521519',
    publisherId: '406769',
    mode: NovelChapterSyncMode.incremental,
    checkpoint: NovelChapterSyncCheckpoint(
      novelId: 'novel:55:521519',
      publisherId: '406769',
      lastCompletedAuthorPage: 3,
      lastSeenPid: 'old-3',
      completedAt: DateTime(2026, 7, 13),
    ),
  );
}

ThreadDetailData _page({
  required int page,
  required List<ThreadPost> posts,
  int replies = 4,
}) {
  return ThreadDetailData(
    tid: '521519',
    fid: '55',
    subject: '测试小说',
    author: 'INCSKY16',
    replies: replies,
    views: 1,
    currentPage: page,
    perPage: 2,
    posts: posts,
  );
}

ThreadPost _post({
  required String pid,
  required int number,
  required String message,
  String authorId = '406769',
  bool isFirst = false,
}) {
  return ThreadPost(
    pid: pid,
    author: 'INCSKY16',
    authorId: authorId,
    message: message,
    number: number,
    isFirst: isFirst,
    dateline: '2026-07-13',
  );
}

class _GatewayCall {
  const _GatewayCall({
    required this.authorId,
    required this.page,
    required this.postsPerPage,
  });

  final String authorId;
  final int page;
  final int postsPerPage;
}

class _FakeGateway implements NovelThreadGateway {
  _FakeGateway(this.responses);

  final Map<int, Future<ThreadDetailData> Function()> responses;
  final List<_GatewayCall> calls = <_GatewayCall>[];

  @override
  Future<ThreadDetailData> loadAuthorPostsPage({
    required String tid,
    required String authorId,
    required int page,
    int postsPerPage = 200,
  }) {
    calls.add(
      _GatewayCall(authorId: authorId, page: page, postsPerPage: postsPerPage),
    );
    return responses[page]!();
  }
}

class _RecordingGovernor implements NovelSyncRequestGovernor {
  int scheduleCount = 0;

  @override
  Future<T> schedule<T>(Future<T> Function() request) {
    scheduleCount++;
    return request();
  }
}

class _FakeSyncRepository implements NovelChapterSyncRepository {
  int beginCount = 0;
  int promoteCount = 0;
  int discardCount = 0;
  final List<List<NovelEpisodeDraft>> staged = <List<NovelEpisodeDraft>>[];

  @override
  Future<void> beginRun({
    required String runId,
    required String novelId,
    required NovelChapterSyncMode mode,
  }) async {
    beginCount++;
  }

  @override
  Future<void> stageEpisodes({
    required String runId,
    required List<NovelEpisodeDraft> episodes,
  }) async {
    staged.add(List<NovelEpisodeDraft>.of(episodes));
  }

  @override
  Future<NovelChapterSyncResult> promote({
    required String runId,
    required NovelChapterSyncRequest request,
    required NovelChapterSyncCheckpoint checkpoint,
    required int fetchedPages,
  }) async {
    promoteCount++;
    final count = staged.expand((batch) => batch).length;
    return NovelChapterSyncResult(
      mode: request.mode,
      fetchedPages: fetchedPages,
      insertedCount: count,
      updatedCount: 0,
      totalCount: count,
      checkpoint: checkpoint,
    );
  }

  @override
  Future<void> discardRun(String runId) async {
    discardCount++;
  }
}

class _FakeSourceStateRepository implements NovelSourceStateRepository {
  NovelChapterHydrationState? lastState;

  @override
  Future<NovelSourceState?> getSourceState({required String novelId}) async =>
      null;

  @override
  Future<void> saveCheckpoint(NovelChapterSyncCheckpoint checkpoint) async {}

  @override
  Future<void> saveMetadata(NovelSourceMetadata metadata) async {}

  @override
  Future<void> setHydrationState({
    required String novelId,
    required NovelChapterHydrationState state,
    String? lastError,
    DateTime? chaptersHydratedAt,
  }) async {
    lastState = state;
  }
}
