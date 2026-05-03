import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/presentation/novel_shelf_page.dart';
import 'package:y300/shared/widgets/shelf/fixed_slot_pager_header.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_card.dart';

void main() {
  testWidgets('NovelShelfPage aligns with comic shell: default category + menu management', (tester) async {
    final repository = _FakeNovelRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: NovelShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(FixedSlotPagerHeader), findsOneWidget);
    expect(find.byKey(const Key('novel-category-page-view')), findsOneWidget);
    expect(find.byType(ShelfCoverCard), findsNWidgets(2));
    expect(find.byKey(const ValueKey<String>('novel-category-tab-default')), findsOneWidget);
    expect(find.text('文学区小说A'), findsOneWidget);
    expect(find.text('轻小说B'), findsOneWidget);

    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    expect(find.text('新建分类'), findsOneWidget);
    expect(find.text('重命名当前分类'), findsOneWidget);
    expect(find.text('删除当前分类'), findsOneWidget);

    await tester.tap(find.text('新建分类'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '收藏');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('novel-category-tab-fav')), findsOneWidget);
  });
}

class _FakeNovelRepository implements NovelRepository {
  final Map<String, NovelItem> _items = {
    'novel:49:100': NovelItem(
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourceFid: '49',
      title: '文学区小说A',
      author: '作者A',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 5, 3),
      episodeCount: 2,
      categoryId: 'default',
    ),
    'novel:55:200': NovelItem(
      novelId: 'novel:55:200',
      sourceTid: '200',
      sourceFid: '55',
      title: '轻小说B',
      author: '作者B',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 5, 3),
      episodeCount: 1,
      categoryId: 'default',
    ),
  };

  final List<NovelShelfCategory> _categories = [
    NovelShelfCategory(
      categoryId: 'default',
      name: '默认',
      sortOrder: 0,
      createdAt: DateTime(2026, 5, 3),
    ),
  ];

  @override
  Future<String> createCategory({required String name}) async {
    _categories.add(
      NovelShelfCategory(
        categoryId: 'fav',
        name: name,
        sortOrder: _categories.length,
        createdAt: DateTime(2026, 5, 3),
      ),
    );
    return 'fav';
  }

  @override
  Future<void> deleteCategory({required String categoryId}) async {
    _categories.removeWhere((item) => item.categoryId == categoryId && categoryId != 'default');
    for (final entry in _items.entries.toList()) {
      if (entry.value.categoryId == categoryId) {
        _items[entry.key] = NovelItem(
          novelId: entry.value.novelId,
          sourceTid: entry.value.sourceTid,
          sourceFid: entry.value.sourceFid,
          title: entry.value.title,
          author: entry.value.author,
          coverImageUrl: entry.value.coverImageUrl,
          updatedAt: entry.value.updatedAt,
          episodeCount: entry.value.episodeCount,
          categoryId: 'default',
        );
      }
    }
  }

  @override
  Future<List<NovelShelfCategory>> getCategories() async => List<NovelShelfCategory>.from(_categories);

  @override
  Future<NovelItem?> getDetail({required String novelId}) async => _items[novelId];

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async => null;

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({required String novelId, bool descending = false}) async {
    return const <NovelEpisodeItem>[];
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async => NovelReaderPreferences.defaults();

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async {
    return _items.values.where((item) => item.categoryId == categoryId).toList(growable: false);
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async => null;

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {
    final current = _items[novelId];
    if (current == null) {
      return;
    }
    _items[novelId] = NovelItem(
      novelId: current.novelId,
      sourceTid: current.sourceTid,
      sourceFid: current.sourceFid,
      title: current.title,
      author: current.author,
      coverImageUrl: current.coverImageUrl,
      updatedAt: current.updatedAt,
      episodeCount: current.episodeCount,
      categoryId: toCategoryId,
    );
  }

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({required String novelId}) async {
    return const NovelEpisodeRefreshResult(insertedCount: 1, updatedCount: 0, totalCount: 1);
  }

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {
    final index = _categories.indexWhere((item) => item.categoryId == categoryId);
    if (index < 0) {
      return;
    }
    final current = _categories[index];
    _categories[index] = NovelShelfCategory(
      categoryId: current.categoryId,
      name: newName,
      sortOrder: current.sortOrder,
      createdAt: current.createdAt,
    );
  }

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
  }) async {}

  @override
  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed}) async {
    final novelId = 'novel:${seed.fid}:${seed.tid}';
    _items[novelId] = NovelItem(
      novelId: novelId,
      sourceTid: seed.tid,
      sourceFid: seed.fid,
      title: '新增小说',
      author: '新增作者',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 5, 3),
      episodeCount: 1,
      categoryId: 'default',
    );
  }

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {}
}
