import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_repository.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

void main() {
  group('ThreadDetailPage', () {
    testWidgets('shows posts and loads more replies', (tester) async {
      var callCount = 0;
      final repository = _FakeThreadRepository((tid, page) async {
        callCount++;
        if (page == 1) {
          return ApiSuccess(
            ThreadDetailData(
              tid: tid,
              fid: '2',
              subject: '测试主题',
              author: 'alice',
              replies: 1,
              views: 12,
              currentPage: 1,
              perPage: 1,
              posts: [
                ThreadPost(
                  pid: 'p1',
                  author: 'alice',
                  authorId: '1',
                  message: '<p>第一条回复</p>',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                ),
              ],
            ),
          );
        }

        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '2',
            subject: '测试主题',
            author: 'alice',
            replies: 1,
            views: 12,
            currentPage: 2,
            perPage: 1,
            posts: [
              ThreadPost(
                pid: 'p2',
                author: 'bob',
                authorId: '2',
                message: '<div>第二条回复</div>',
                number: 2,
                isFirst: false,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('thread-detail-list')), findsOneWidget);
      expect(find.text('第一条回复'), findsOneWidget);

      expect(find.byKey(const Key('thread-detail-load-more-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('thread-detail-load-more-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('第一条回复'), findsOneWidget);
      expect(find.text('第二条回复'), findsOneWidget);
      expect(callCount, 2);
    });

    testWidgets('shows comic add-to-shelf button for comic candidate post', (tester) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '30',
            subject: '【测试汉化组】第1话',
            author: 'alice',
            replies: 0,
            views: 12,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message:
                    '<img src="https://img.test/1.jpg"/><img src="https://img.test/2.jpg"/><a href="thread-100-1-1.html">1</a><a href="thread-101-1-1.html">2</a>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('comic-add-to-shelf-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('comic-add-to-shelf-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('comic-in-shelf-button')), findsOneWidget);
      expect(find.textContaining('漫画候选（评分'), findsOneWidget);
    });

    testWidgets('includes second floor images when floor2 is same author and image-dominant', (tester) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '30',
            subject: '【测试汉化组】第1话',
            author: 'alice',
            replies: 1,
            views: 12,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>前言</p><img src="https://img.test/cover.jpg"/>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
              ThreadPost(
                pid: 'p2',
                author: 'alice',
                authorId: '1',
                message: '<img src="https://img.test/page-1.jpg"/><img src="https://img.test/page-2.jpg"/>',
                number: 2,
                isFirst: false,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('comic-add-to-shelf-button')), findsOneWidget);
    });
  });
}

Widget _buildTestApp(ThreadRepository repository) {
  return ProviderScope(
    overrides: [
      threadRepositoryProvider.overrideWithValue(repository),
      comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
    ],
    child: const MaterialApp(
      home: ThreadDetailPage(tid: '100', subject: '测试主题'),
    ),
  );
}

class _FakeThreadRepository implements ThreadRepository {
  _FakeThreadRepository(this._loader);

  final Future<ApiResult<ThreadDetailData>> Function(String tid, int page) _loader;

  @override
  Future<ApiResult<ThreadDetailData>> getThreadDetail({required String tid, int page = 1}) {
    return _loader(tid, page);
  }
}

class _FakeComicRepository implements ComicRepository {
  final Set<String> _ids = <String>{};

  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {
    _ids.add(comicId);
  }

  @override
  Future<String> createCategory({required String name}) async => 'mock-category';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async => null;

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({required String comicId, bool descending = true}) async {
    return const <ComicEpisodeItem>[];
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({required String episodeId}) async {
    return const <ComicEpisodeImageItem>[];
  }

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    return const ComicShelfDisplaySettings(gridColumnCount: 3);
  }

  @override
  Future<List<ComicShelfCategory>> getCategories() async {
    return <ComicShelfCategory>[
      ComicShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async {
    return const <ComicShelfItem>[];
  }

  @override
  Future<bool> isInShelf({required String comicId}) async {
    return _ids.contains(comicId);
  }

  @override
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) async => null;

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return const ComicEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 0);
  }

  @override
  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

  @override
  Future<void> updateCustomCover({required String comicId, required String? customCoverImageUrl}) async {}

  @override
  Future<void> updateGridColumnCount({required int columnCount}) async {}

  @override
  Future<void> saveEpisodeImages({required String episodeId, required List<String> imageUrls}) async {}

  @override
  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  }) async {}

  @override
  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {}
}
