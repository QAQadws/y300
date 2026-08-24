import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/favorites/data/services/favorite_detail_context_loader.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/models/favorite_detail_context.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  group('DefaultFavoriteDetailContextLoader', () {
    test('loads detail, resolves tag, and classifies content kind', () async {
      final loader = DefaultFavoriteDetailContextLoader(
        threadRepository: _FakeThreadRepository(
          (tid) async => _success(_detail(tid: tid, fid: '30', typeid: '398')),
        ),
        loadTagLookup: () async => _lookup(comicTagName: '韩国漫画'),
        classifier: const ThreadContentClassifier(),
      );

      final result = await loader.load(_record(tid: '100'));

      expect(
        result,
        isA<
          DataReadSuccess<
            FavoriteDetailResolution,
            FavoriteDetailReadCapabilities
          >
        >(),
      );
      final context = (result.dataOrNull! as ResolvedFavoriteDetail).context;
      expect(context.detail.tid, '100');
      expect(context.tagName, '韩国漫画');
      expect(context.kind, ThreadContentKind.comic);
    });

    test('uses preloaded detail without calling detail loader', () async {
      var detailLoadCount = 0;
      final preloadedDetail = _detail(tid: '100', fid: '49', typeid: '293');
      final loader = DefaultFavoriteDetailContextLoader(
        threadRepository: _FakeThreadRepository((tid) async {
          detailLoadCount++;
          return _success(_detail(tid: tid, fid: '1'));
        }),
        loadTagLookup: () async => _lookup(),
        classifier: const ThreadContentClassifier(),
      );

      final result = await loader.load(
        _record(tid: '100'),
        preloadedDetail: _success(preloadedDetail),
      );

      expect(detailLoadCount, 0);
      final context = (result.dataOrNull! as ResolvedFavoriteDetail).context;
      expect(context.kind, ThreadContentKind.novel);
      expect(identical(context.detail, preloadedDetail), isTrue);
    });

    test(
      'classifies non comic and non novel boards as forum content',
      () async {
        final loader = DefaultFavoriteDetailContextLoader(
          threadRepository: _FakeThreadRepository(
            (tid) async => _success(_detail(tid: tid, fid: '1')),
          ),
          loadTagLookup: () async => _lookup(),
          classifier: const ThreadContentClassifier(),
        );

        final result = await loader.load(_record(tid: '300'));

        final context = (result.dataOrNull! as ResolvedFavoriteDetail).context;
        expect(context.kind, ThreadContentKind.forum);
        expect(context.tagName, isNull);
      },
    );

    test('keeps context when tag lookup fails', () async {
      final loader = DefaultFavoriteDetailContextLoader(
        threadRepository: _FakeThreadRepository(
          (tid) async => _success(_detail(tid: tid, fid: '30', typeid: '398')),
        ),
        loadTagLookup: () => throw StateError('tag unavailable'),
        classifier: const ThreadContentClassifier(),
      );

      final result = await loader.load(_record(tid: '100'));

      expect(result.isSuccess, isTrue);
      final context = (result.dataOrNull! as ResolvedFavoriteDetail).context;
      expect(context.tagName, isNull);
      expect(context.kind, ThreadContentKind.comic);
    });

    test(
      'passes through detail loader failure as context load failure',
      () async {
        final loader = DefaultFavoriteDetailContextLoader(
          threadRepository: _FakeThreadRepository(
            (tid) async => const DataReadFailure(
              kind: DataReadFailureKind.network,
              diagnosticMessage: 'boom',
            ),
          ),
          loadTagLookup: () async => _lookup(),
          classifier: const ThreadContentClassifier(),
        );

        final result = await loader.load(_record(tid: '100'));

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull?.diagnosticMessage, 'boom');
      },
    );

    test(
      'empty postlist resolves as invalid before tag classification',
      () async {
        var tagLookupCount = 0;
        final loader = DefaultFavoriteDetailContextLoader(
          threadRepository: _FakeThreadRepository(
            (tid) async => _success(
              _detail(tid: tid, fid: '30', typeid: '398', hasPosts: false),
            ),
          ),
          loadTagLookup: () async {
            tagLookupCount++;
            return _lookup();
          },
          classifier: const _ThrowingClassifier(),
        );

        final result = await loader.load(_record(tid: '404'));

        expect(result.dataOrNull, isA<InvalidFavoriteDetail>());
        final invalid = result.dataOrNull! as InvalidFavoriteDetail;
        expect(invalid.record.tid, '404');
        expect(invalid.detail.posts, isEmpty);
        expect(tagLookupCount, 0);
      },
    );
  });
}

FavoriteThreadCacheRecord _record({required String tid}) {
  return FavoriteThreadCacheRecord(
    tid: tid,
    remoteFavoriteId: 'fav-$tid',
    title: '收藏$tid',
    replyCount: 0,
    contentKind: ThreadContentKind.unknown,
    firstSeenAt: DateTime(2026, 1, 1),
    lastSeenAt: DateTime(2026, 1, 1),
  );
}

ThreadDetailData _detail({
  required String tid,
  required String fid,
  String typeid = '',
  bool hasPosts = true,
}) {
  return ThreadDetailData(
    tid: tid,
    fid: fid,
    typeid: typeid,
    subject: '主题$tid',
    author: '作者',
    replies: 0,
    views: 1,
    currentPage: 1,
    perPage: 20,
    posts: hasPosts
        ? <ThreadPost>[
            ThreadPost(
              pid: '1',
              author: '作者',
              authorId: '1',
              message: '<p>正文</p>',
              number: 1,
              isFirst: true,
              dateline: '2026-01-01',
            ),
          ]
        : const <ThreadPost>[],
  );
}

class _ThrowingClassifier extends ThreadContentClassifier {
  const _ThrowingClassifier();

  @override
  ThreadContentKind classify({
    required String fid,
    required String typeid,
    String? tagName,
  }) {
    throw StateError('invalid detail must not be classified');
  }
}

ForumTagLookup _lookup({String comicTagName = '韩国漫画'}) {
  return ForumTagLookup(<ForumBoardTagSet>[
    ForumBoardTagSet(
      fid: '30',
      name: '漫画区',
      tags: <ForumTagDefinition>[
        ForumTagDefinition(fid: '30', typeid: '398', name: comicTagName),
      ],
    ),
    const ForumBoardTagSet(
      fid: '49',
      name: '文学区',
      tags: <ForumTagDefinition>[
        ForumTagDefinition(fid: '49', typeid: '293', name: '原创'),
      ],
    ),
  ]);
}

DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities> _success(
  ThreadDetailData detail,
) {
  return DataReadSuccess(
    data: detail,
    capabilities: ThreadDetailSourceCapabilities.full.toReadCapabilities(),
    metadata: const DataReadMetadata.network(),
  );
}

final class _FakeThreadRepository implements ThreadRepository {
  const _FakeThreadRepository(this.loader);

  final Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  Function(String tid)
  loader;

  @override
  ThreadDetailSourceCapabilities get capabilities =>
      ThreadDetailSourceCapabilities.full;

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) {
    return loader(tid);
  }
}
