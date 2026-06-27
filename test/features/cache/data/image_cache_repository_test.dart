import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/cache/data/image_cache_repository.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'LocalImageCacheRepository stores protected and unprotected cache records separately',
    () async {
      const dbName = 'comic_shelf_test_image_cache_repo.db';
      await deleteDatabase(dbName);
      final repository = LocalImageCacheRepository(
        ComicLocalDb.open(databaseName: dbName),
      );
      final now = DateTime(2026, 1, 1);

      await repository.upsert(
        CachedImageRecord(
          cacheKey: 'cover/comic/yamibo:100',
          ownerType: 'comic',
          ownerId: 'yamibo:100',
          role: 'cover',
          localPath: '/tmp/cover.jpg',
          bytes: 10,
          protected: true,
          createdAt: now,
          updatedAt: now,
          lastAccessedAt: now,
        ),
      );
      await repository.upsert(
        CachedImageRecord(
          cacheKey: 'comic/yamibo:100/yamibo:100:101/000',
          ownerType: 'comic',
          ownerId: 'yamibo:100',
          episodeId: 'yamibo:100:101',
          imageIndex: 0,
          role: 'comic_page',
          localPath: '/tmp/page.jpg',
          bytes: 20,
          protected: false,
          createdAt: now,
          updatedAt: now,
          lastAccessedAt: now,
        ),
      );

      expect(await repository.calculateUsageBytes(includeProtected: false), 20);
      expect(await repository.calculateUsageBytes(includeProtected: true), 30);
      final usageGroups = await repository.calculateUsageGroups();
      expect(
        usageGroups.map((group) => group.id),
        containsAll(<String>[
          'comic:cover:protected',
          'comic:comic_page:clearable',
        ]),
      );
      expect(
        usageGroups
            .singleWhere((group) => group.id == 'comic:cover:protected')
            .bytes,
        10,
      );
      expect(
        usageGroups
            .singleWhere((group) => group.id == 'comic:comic_page:clearable')
            .bytes,
        20,
      );
      expect(
        (await repository.listUnprotectedByAccessTime()).single.cacheKey,
        contains('/000'),
      );
      expect(
        (await repository.listProtectedCovers()).single.cacheKey,
        'cover/comic/yamibo:100',
      );

      final cover = await repository.getByKey('cover/comic/yamibo:100');
      expect(cover, isNotNull);
      expect(cover!.protected, isTrue);

      await deleteDatabase(dbName);
    },
  );
}
