import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/presentation/novel_detail_page.dart';

void main() {
  testWidgets('NovelDetailPage renders episodes and supports sort/refresh actions', (tester) async {
    final repository = _FakeNovelRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: NovelDetailPage(novelId: 'novel:49:100')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('测试小说'), findsOneWidget);
    expect(find.byKey(const Key('novel-detail-episode-list')), findsOneWidget);
    expect(find.text('第1章'), findsOneWidget);
    expect(find.text('第2章'), findsOneWidget);

    await tester.tap(find.byKey(const Key('novel-detail-sort-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-detail-sort-hint')), findsOneWidget);

    await tester.tap(find.byKey(const Key('novel-detail-refresh-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-detail-refresh-hint')), findsOneWidget);
  });
}

class _FakeNovelRepository implements NovelRepository {
  final List<NovelEpisodeItem> _episodes = [
    const NovelEpisodeItem(
      episodeId: 'novel:49:100:5001',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5001',
      sourcePage: 1,
      episodeTitle: '第1章',
      orderIndex: 0,
      datelineText: '2026-05-03',
    ),
    const NovelEpisodeItem(
      episodeId: 'novel:49:100:5002',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5002',
      sourcePage: 1,
      episodeTitle: '第2章',
      orderIndex: 1,
      datelineText: '2026-05-04',
    ),
  ];

  @override
  Future<String> createCategory({required String name}) async => 'default';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return <NovelShelfCategory>[
      NovelShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    return NovelItem(
      novelId: novelId,
      sourceTid: '100',
      sourceFid: '49',
      title: '测试小说',
      author: '作者A',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 5, 3),
      episodeCount: _episodes.length,
    );
  }

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async => null;

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({required String novelId, bool descending = false}) async {
    final copy = List<NovelEpisodeItem>.from(_episodes);
    copy.sort((a, b) => descending ? b.orderIndex.compareTo(a.orderIndex) : a.orderIndex.compareTo(b.orderIndex));
    return copy;
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async => NovelReaderPreferences.defaults();

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async => const <NovelItem>[];

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async => null;

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({required String novelId}) async {
    _episodes.add(
      const NovelEpisodeItem(
        episodeId: 'novel:49:100:5003',
        novelId: 'novel:49:100',
        sourceTid: '100',
        sourcePid: '5003',
        sourcePage: 2,
        episodeTitle: '第3章',
        orderIndex: 2,
        datelineText: '2026-05-05',
      ),
    );
    return NovelEpisodeRefreshResult(insertedCount: 1, updatedCount: 0, totalCount: _episodes.length);
  }

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
  }) async {}

  @override
  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed}) async {}

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {}
}
