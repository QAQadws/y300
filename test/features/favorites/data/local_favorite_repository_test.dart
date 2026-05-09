import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SqfliteLocalFavoriteRepository', () {
    const dbName = 'comic_shelf_test_favorite_repo.db';
    late SqfliteLocalFavoriteRepository repository;

    setUp(() async {
      await deleteDatabase(dbName);
      repository = SqfliteLocalFavoriteRepository(
        ComicLocalDb.open(databaseName: dbName),
      );
    });

    tearDown(() async {
      await deleteDatabase(dbName);
    });

    test('loads visible system categories and keeps default free from comic and novel', () async {
      await repository.upsertRemotePage(
        page: FavoriteThreadsPage(
          page: 1,
          perPage: 20,
          totalCount: 3,
          items: <FavoriteThread>[
            _thread(tid: '100', title: '漫画'),
            _thread(tid: '200', title: '小说'),
            _thread(tid: '300', title: '论坛'),
          ],
        ),
        pageStartOrder: 0,
      );
      await repository.updateThreadDetailMeta(
        tid: '100',
        fid: '30',
        typeid: '398',
        tagName: '韩国漫画',
        contentKind: ThreadContentKind.comic,
        workId: 'yamibo:100',
      );
      await repository.updateThreadDetailMeta(
        tid: '200',
        fid: '49',
        typeid: '293',
        tagName: '原创',
        contentKind: ThreadContentKind.novel,
        workId: 'novel:49:200',
      );
      await repository.updateThreadDetailMeta(
        tid: '300',
        fid: '1',
        typeid: '',
        tagName: null,
        contentKind: ThreadContentKind.forum,
        workId: 'thread:300',
      );

      final categories = await repository.loadVisibleCategories();
      final comicItems = await repository.loadCategoryItems(favoriteComicCategoryId);
      final novelItems = await repository.loadCategoryItems(favoriteNovelCategoryId);
      final defaultItems = await repository.loadCategoryItems(favoriteDefaultCategoryId);

      expect(categories.map((category) => category.categoryId), containsAll(<String>[
        favoriteComicCategoryId,
        favoriteNovelCategoryId,
        favoriteDefaultCategoryId,
      ]));
      expect(comicItems.single.title, '漫画');
      expect(novelItems.single.title, '小说');
      expect(defaultItems.single.title, '论坛');
    });

    test('custom category overrides system category', () async {
      await repository.upsertRemotePage(
        page: FavoriteThreadsPage(
          page: 1,
          perPage: 20,
          totalCount: 1,
          items: <FavoriteThread>[_thread(tid: '100', title: '漫画')],
        ),
        pageStartOrder: 0,
      );
      await repository.updateThreadDetailMeta(
        tid: '100',
        fid: '30',
        typeid: '398',
        tagName: '韩国漫画',
        contentKind: ThreadContentKind.comic,
        workId: 'yamibo:100',
      );
      final customId = await repository.createCategory(name: '追更');
      await repository.moveThreadToCategory(tid: '100', toCategoryId: customId);

      final comicItems = await repository.loadCategoryItems(favoriteComicCategoryId);
      final customItems = await repository.loadCategoryItems(customId);

      expect(comicItems, isEmpty);
      expect(customItems.single.workId, FavoriteShelfWorkId.fromTid('100'));
    });

    test('markRemovedTids returns removed active records', () async {
      await repository.upsertRemotePage(
        page: FavoriteThreadsPage(
          page: 1,
          perPage: 20,
          totalCount: 2,
          items: <FavoriteThread>[
            _thread(tid: '100', title: '保留'),
            _thread(tid: '200', title: '移除'),
          ],
        ),
        pageStartOrder: 0,
      );

      final removed = await repository.markRemovedTids(const <String>{'100'});
      final active = await repository.getActiveTids();

      expect(removed.map((record) => record.tid), <String>['200']);
      expect(active, <String>{'100'});
    });

    test('favorite shelf item reuses comic and novel module covers', () async {
      final db = await ComicLocalDb.open(databaseName: dbName);
      await db.insert(
        ComicLocalDb.comicsTable,
        <String, Object?>{
          'comic_id': 'yamibo:100',
          'source_tid': '100',
          'source_fid': '30',
          'title': '漫画',
          'cover_image_url': 'https://img.test/comic.jpg',
          'custom_cover_image_url': 'https://img.test/comic-custom-network.jpg',
          'cover_local_path': '/cache/comic.jpg',
          'custom_cover_local_path': '/cache/comic-custom.jpg',
          'created_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
          'updated_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
        },
      );
      await db.insert(
        ComicLocalDb.worksTable,
        <String, Object?>{
          'work_id': 'novel:49:200',
          'content_type': 'novel',
          'source_tid': '200',
          'source_fid': '49',
          'title': '小说',
          'cover_image_url': 'https://img.test/novel.jpg',
          'cover_local_path': '/cache/novel.jpg',
          'custom_cover_local_path': '/cache/novel-custom.jpg',
          'updated_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
        },
      );
      await repository.upsertRemotePage(
        page: FavoriteThreadsPage(
          page: 1,
          perPage: 20,
          totalCount: 2,
          items: <FavoriteThread>[
            _thread(tid: '100', title: '漫画'),
            _thread(tid: '200', title: '小说'),
          ],
        ),
        pageStartOrder: 0,
      );
      await repository.updateThreadDetailMeta(
        tid: '100',
        fid: '30',
        typeid: '398',
        tagName: '韩国漫画',
        contentKind: ThreadContentKind.comic,
        workId: 'yamibo:100',
      );
      await repository.updateThreadDetailMeta(
        tid: '200',
        fid: '49',
        typeid: '293',
        tagName: '原创',
        contentKind: ThreadContentKind.novel,
        workId: 'novel:49:200',
      );

      final comicItems = await repository.loadCategoryItems(favoriteComicCategoryId);
      final novelItems = await repository.loadCategoryItems(favoriteNovelCategoryId);

      expect(comicItems.single.coverImageUrl, 'https://img.test/comic-custom-network.jpg');
      expect(comicItems.single.coverLocalPath, '/cache/comic.jpg');
      expect(comicItems.single.customCoverLocalPath, '/cache/comic-custom.jpg');
      expect(novelItems.single.coverImageUrl, 'https://img.test/novel.jpg');
      expect(novelItems.single.coverLocalPath, '/cache/novel.jpg');
      expect(novelItems.single.customCoverLocalPath, '/cache/novel-custom.jpg');
    });
  });
}

FavoriteThread _thread({
  required String tid,
  required String title,
}) {
  return FavoriteThread(
    favid: 'fav-$tid',
    tid: tid,
    title: title,
    description: '',
    author: '作者',
    replies: 0,
    url: 'thread-$tid-1-1.html',
    dateline: 1767225600,
  );
}
