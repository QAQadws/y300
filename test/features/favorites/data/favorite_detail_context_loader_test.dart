import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/favorites/data/favorite_detail_context_loader.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/favorite_detail_context.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  group('DefaultFavoriteDetailContextLoader', () {
    test('loads detail, resolves tag, and classifies content kind', () async {
      final loader = DefaultFavoriteDetailContextLoader(
        loadThreadDetail: (tid) async => ApiSuccess(
          _detail(tid: tid, fid: '30', typeid: '398'),
        ),
        loadTagLookup: () async => _lookup(comicTagName: '韩国漫画'),
        classifier: const ThreadContentClassifier(),
      );

      final result = await loader.load(_record(tid: '100'));

      expect(result, isA<ApiSuccess<FavoriteDetailContext>>());
      final context = result.dataOrNull!;
      expect(context.detail.tid, '100');
      expect(context.tagName, '韩国漫画');
      expect(context.kind, ThreadContentKind.comic);
    });

    test('uses preloaded detail without calling detail loader', () async {
      var detailLoadCount = 0;
      final loader = DefaultFavoriteDetailContextLoader(
        loadThreadDetail: (tid) async {
          detailLoadCount++;
          return ApiSuccess(_detail(tid: tid, fid: '1'));
        },
        loadTagLookup: () async => _lookup(),
        classifier: const ThreadContentClassifier(),
      );

      final result = await loader.load(
        _record(tid: '100'),
        preloadedDetail: _detail(tid: '100', fid: '49', typeid: '293'),
      );

      expect(detailLoadCount, 0);
      expect(result.dataOrNull?.kind, ThreadContentKind.novel);
    });

    test('classifies non comic and non novel boards as forum content', () async {
      final loader = DefaultFavoriteDetailContextLoader(
        loadThreadDetail: (tid) async => ApiSuccess(
          _detail(tid: tid, fid: '1'),
        ),
        loadTagLookup: () async => _lookup(),
        classifier: const ThreadContentClassifier(),
      );

      final result = await loader.load(_record(tid: '300'));

      expect(result.dataOrNull?.kind, ThreadContentKind.forum);
      expect(result.dataOrNull?.tagName, isNull);
    });

    test('keeps context when tag lookup fails', () async {
      final loader = DefaultFavoriteDetailContextLoader(
        loadThreadDetail: (tid) async => ApiSuccess(
          _detail(tid: tid, fid: '30', typeid: '398'),
        ),
        loadTagLookup: () => throw StateError('tag unavailable'),
        classifier: const ThreadContentClassifier(),
      );

      final result = await loader.load(_record(tid: '100'));

      expect(result, isA<ApiSuccess<FavoriteDetailContext>>());
      final context = result.dataOrNull!;
      expect(context.tagName, isNull);
      expect(context.kind, ThreadContentKind.comic);
    });

    test('passes through detail loader failure as context load failure', () async {
      const error = ApiError(type: ApiErrorType.network, message: 'boom');
      final loader = DefaultFavoriteDetailContextLoader(
        loadThreadDetail: (tid) async =>
            const ApiFailure<ThreadDetailData>(error),
        loadTagLookup: () async => _lookup(),
        classifier: const ThreadContentClassifier(),
      );

      final result = await loader.load(_record(tid: '100'));

      expect(result, isA<ApiFailure<FavoriteDetailContext>>());
      expect(result.errorOrNull?.message, 'boom');
    });
  });
}

FavoriteThreadCacheRecord _record({required String tid}) {
  return FavoriteThreadCacheRecord(
    tid: tid,
    favid: 'fav-$tid',
    title: '收藏$tid',
    replies: 0,
    contentKind: ThreadContentKind.unknown,
    firstSeenAt: DateTime(2026, 1, 1),
    lastSeenAt: DateTime(2026, 1, 1),
  );
}

ThreadDetailData _detail({
  required String tid,
  required String fid,
  String typeid = '',
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
    posts: const <ThreadPost>[],
  );
}

ForumTagLookup _lookup({String comicTagName = '韩国漫画'}) {
  return ForumTagLookup(
    <ForumBoardTagSet>[
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
    ],
  );
}
