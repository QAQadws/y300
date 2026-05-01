import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/presentation/comic_detail_page.dart';

void main() {
  testWidgets('ComicDetailPage shows detail header and episodes', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_ComicDetailFakeRepository()),
          comicEpisodeRefreshServiceProvider.overrideWithValue(_FakeRefreshService()),
        ],
        child: const MaterialApp(home: ComicDetailPage(comicId: 'yamibo:100')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('测试漫画'), findsOneWidget);
    expect(find.byKey(const Key('comic-detail-episode-list')), findsOneWidget);
    expect(find.text('第2话'), findsOneWidget);
    expect(find.text('第1话'), findsOneWidget);
  });

  testWidgets('ComicDetailPage supports refresh action', (tester) async {
    final repository = _ComicDetailFakeRepository();
    final refreshService = _FakeRefreshService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicEpisodeRefreshServiceProvider.overrideWithValue(refreshService),
        ],
        child: const MaterialApp(home: ComicDetailPage(comicId: 'yamibo:100')),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comic-detail-refresh-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(repository.mergeCalled, isTrue);
    expect(find.byKey(const Key('comic-detail-refresh-hint')), findsOneWidget);
  });
}

class _ComicDetailFakeRepository implements ComicRepository {
  bool mergeCalled = false;

  final List<ComicEpisodeItem> _episodes = <ComicEpisodeItem>[
    const ComicEpisodeItem(
      episodeId: 'yamibo:100:101',
      comicId: 'yamibo:100',
      episodeTitle: '第1话',
      sourceTid: '101',
      sourceUrl: 'thread-101-1-1.html',
      orderIndex: 0,
      publishTimeText: null,
    ),
    const ComicEpisodeItem(
      episodeId: 'yamibo:100:102',
      comicId: 'yamibo:100',
      episodeTitle: '第2话',
      sourceTid: '102',
      sourceUrl: 'thread-102-1-1.html',
      orderIndex: 1,
      publishTimeText: null,
    ),
  ];

  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {}

  @override
  Future<String> createCategory({required String name}) async => 'mock';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    return ComicDetail(
      comicId: comicId,
      sourceTid: '100',
      sourceFid: '30',
      title: '测试漫画',
      author: '作者A',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: _episodes.length,
    );
  }

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({required String comicId, bool descending = true}) async {
    final copy = List<ComicEpisodeItem>.from(_episodes);
    copy.sort((a, b) => descending ? b.orderIndex.compareTo(a.orderIndex) : a.orderIndex.compareTo(b.orderIndex));
    return copy;
  }

  @override
  Future<List<ComicShelfCategory>> getCategories() async => const <ComicShelfCategory>[];

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    return const ComicShelfDisplaySettings(gridColumnCount: 3);
  }

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async => const <ComicShelfItem>[];

  @override
  Future<bool> isInShelf({required String comicId}) async => true;

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    mergeCalled = true;
    _episodes.add(
      const ComicEpisodeItem(
        episodeId: 'yamibo:100:103',
        comicId: 'yamibo:100',
        episodeTitle: '第3话',
        sourceTid: '103',
        sourceUrl: 'thread-103-1-1.html',
        orderIndex: 2,
        publishTimeText: null,
      ),
    );
    return ComicEpisodeRefreshResult(insertedCount: 1, updatedCount: 0, totalCount: _episodes.length);
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
}

class _FakeRefreshService implements ComicEpisodeRefreshService {
  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    return const <ComicEpisodeLink>[
      ComicEpisodeLink(url: 'thread-103-1-1.html', rawText: '3', episodeTitle: '第3话'),
    ];
  }
}
