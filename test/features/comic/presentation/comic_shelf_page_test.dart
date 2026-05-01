import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/presentation/comic_shelf_page.dart';

void main() {
  testWidgets('ComicShelfPage shows empty text when shelf has no data', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_EmptyComicRepository()),
        ],
        child: const MaterialApp(home: ComicShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('书架还是空的，去帖子详情把喜欢的漫画加入书架吧'), findsOneWidget);
    expect(find.byKey(const Key('comic-category-header')), findsOneWidget);
    expect(find.byKey(const Key('comic-category-page-view')), findsOneWidget);
    expect(find.byKey(const Key('comic-category-indicator')), findsOneWidget);
  });

  testWidgets('ComicShelfPage title overlay uses custom two-line ellipsis', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_DataComicRepository()),
        ],
        child: const MaterialApp(home: ComicShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('comic-shelf-grid-default')), findsOneWidget);
    expect(find.textContaining('···'), findsOneWidget);
  });

  testWidgets('ComicShelfPage can switch category by horizontal swipe', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_MultiCategoryComicRepository()),
        ],
        child: const MaterialApp(home: ComicShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('comic-shelf-grid-default')), findsOneWidget);
    expect(find.text('默认分类漫画'), findsOneWidget);

    await tester.drag(find.byKey(const Key('comic-category-page-view')), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('comic-shelf-grid-fav')), findsOneWidget);
    expect(find.text('收藏分类漫画'), findsOneWidget);
  });

  testWidgets('Category tabs always use fixed one-quarter width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_MultiCategoryComicRepository()),
        ],
        child: const MaterialApp(home: ComicShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    final defaultTab = tester.getSize(find.byKey(const ValueKey<String>('comic-category-tab-default')));
    final favTab = tester.getSize(find.byKey(const ValueKey<String>('comic-category-tab-fav')));

    expect(defaultTab.width, closeTo(100, 0.5));
    expect(favTab.width, closeTo(100, 0.5));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Category list can scroll when category count is greater than four', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_MoreThanFourCategoryRepository()),
        ],
        child: const MaterialApp(home: ComicShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    final headerRect = tester.getRect(find.byKey(const Key('comic-category-header')));
    final c5Finder = find.byKey(const ValueKey<String>('comic-category-tab-c5'));
    expect(c5Finder, findsOneWidget);
    final beforeRect = tester.getRect(c5Finder);
    expect(beforeRect.left, greaterThanOrEqualTo(headerRect.right));

    await tester.drag(find.byKey(const Key('comic-category-header')), const Offset(-400, 0));
    await tester.pumpAndSettle();

    final afterRect = tester.getRect(c5Finder);
    expect(afterRect.right, lessThanOrEqualTo(headerRect.right));
  });
}

abstract class _BaseComicRepository implements ComicRepository {
  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {}

  @override
  Future<String> createCategory({required String name}) async => 'new';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async => null;

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({required String comicId, bool descending = true}) async {
    return const <ComicEpisodeItem>[];
  }

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    return const ComicShelfDisplaySettings(gridColumnCount: 3);
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
  Future<bool> isInShelf({required String comicId}) async {
    return false;
  }

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return const ComicEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 0);
  }
}

class _EmptyComicRepository extends _BaseComicRepository {
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
}

class _DataComicRepository extends _BaseComicRepository {
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
    return <ComicShelfItem>[
      ComicShelfItem(
        comicId: 'yamibo:100',
        title: '这是一个非常非常长的漫画标题用于验证第二行结尾使用中文省略号点点点样式并且继续延长文本长度让它在绝大多数测试设备宽度下都必然触发两行截断效果',
        author: '作者A',
        coverImageUrl: null,
        categoryId: categoryId,
        addedAt: DateTime(2026, 1, 1),
      ),
    ];
  }
}

class _MultiCategoryComicRepository extends _BaseComicRepository {
  @override
  Future<List<ComicShelfCategory>> getCategories() async {
    return <ComicShelfCategory>[
      ComicShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      ComicShelfCategory(
        categoryId: 'fav',
        name: '收藏',
        sortOrder: 1,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async {
    if (categoryId == 'fav') {
      return <ComicShelfItem>[
        ComicShelfItem(
          comicId: 'yamibo:200',
          title: '收藏分类漫画',
          author: '作者B',
          coverImageUrl: null,
          categoryId: 'fav',
          addedAt: DateTime(2026, 1, 1),
        ),
      ];
    }

    return <ComicShelfItem>[
      ComicShelfItem(
        comicId: 'yamibo:100',
        title: '默认分类漫画',
        author: '作者A',
        coverImageUrl: null,
        categoryId: 'default',
        addedAt: DateTime(2026, 1, 1),
      ),
    ];
  }
}

class _MoreThanFourCategoryRepository extends _BaseComicRepository {
  @override
  Future<List<ComicShelfCategory>> getCategories() async {
    final now = DateTime(2026, 1, 1);
    return <ComicShelfCategory>[
      ComicShelfCategory(categoryId: 'default', name: '默认', sortOrder: 0, createdAt: now),
      ComicShelfCategory(categoryId: 'c2', name: '二', sortOrder: 1, createdAt: now),
      ComicShelfCategory(categoryId: 'c3', name: '三', sortOrder: 2, createdAt: now),
      ComicShelfCategory(categoryId: 'c4', name: '四', sortOrder: 3, createdAt: now),
      ComicShelfCategory(categoryId: 'c5', name: '五', sortOrder: 4, createdAt: now),
    ];
  }

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async {
    return <ComicShelfItem>[
      ComicShelfItem(
        comicId: 'yamibo:$categoryId',
        title: '$categoryId 分类漫画',
        author: '作者X',
        coverImageUrl: null,
        categoryId: categoryId,
        addedAt: DateTime(2026, 1, 1),
      ),
    ];
  }
}
