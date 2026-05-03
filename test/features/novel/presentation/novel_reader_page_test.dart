import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';

void main() {
  testWidgets('NovelReaderPage supports style controls and paragraph render', (tester) async {
    final repository = _FakeNovelRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: NovelReaderPage(
            novelId: 'novel:49:100',
            initialEpisodeId: 'novel:49:100:5001',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-episode-selector')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-paragraph-list')), findsOneWidget);
    expect(find.text('第一段。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('novel-reader-style-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-theme-sepia')), findsOneWidget);

    await tester.tap(find.byKey(const Key('novel-theme-sepia')));
    await tester.pumpAndSettle();

    expect(repository.latestPreferences?.themeMode, 'sepia');
  });
}

class _FakeNovelRepository implements NovelRepository {
  NovelReaderPreferences preferences = NovelReaderPreferences.defaults();
  NovelReaderPreferences? latestPreferences;

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
  Future<NovelItem?> getDetail({required String novelId}) async => null;

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async {
    return NovelChapterContent(
      episodeId: episodeId,
      rawHtml: '<p>第一段。</p><p>第二段。</p>',
      plainText: '第一段。\n第二段。',
      paragraphs: const <String>['第一段。', '第二段。'],
    );
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({required String novelId, bool descending = false}) async {
    return const <NovelEpisodeItem>[
      NovelEpisodeItem(
        episodeId: 'novel:49:100:5001',
        novelId: 'novel:49:100',
        sourceTid: '100',
        sourcePid: '5001',
        sourcePage: 1,
        episodeTitle: '第1章',
        orderIndex: 0,
        datelineText: '2026-05-03',
      ),
    ];
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async => preferences;

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async => const <NovelItem>[];

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async {
    return null;
  }

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({required String novelId}) async {
    return const NovelEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 1);
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
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {
    latestPreferences = preferences;
    this.preferences = preferences;
  }
}
