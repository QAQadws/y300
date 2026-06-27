import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/cache/data/document_cache_service.dart';
import 'package:y300/features/cache/domain/document_cache_models.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'LocalDocumentCacheService stores, touches, and deletes documents',
    () async {
      const dbName = 'document_cache_service_test.db';
      await deleteDatabase(dbName);
      final db = await ComicLocalDb.open(databaseName: dbName);
      final service = LocalDocumentCacheService(Future.value(db));
      final fetchedAt = DateTime(2026, 1, 1, 10);
      final touchedAt = DateTime(2026, 1, 1, 11);

      await service.put(
        CachedDocument(
          cacheKey: 'document|thread|tid=1&page=1',
          ownerType: CacheOwnerType.thread,
          ownerId: 'tid=1&page=1',
          sourceUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1',
          body: '<html>正文</html>',
          contentType: 'text/html',
          statusCode: 200,
          fetchedAt: fetchedAt,
          updatedAt: fetchedAt,
        ),
      );

      final stored = await service.getByKey('document|thread|tid=1&page=1');
      expect(stored, isNotNull);
      expect(stored!.body, '<html>正文</html>');
      expect(stored.ownerType, CacheOwnerType.thread);
      expect(stored.fetchedAt, fetchedAt);

      await service.touch('document|thread|tid=1&page=1', touchedAt);
      final touched = await service.getByKey('document|thread|tid=1&page=1');
      expect(touched!.lastAccessedAt, touchedAt);

      final deleted = await service.deleteByOwner(
        ownerType: CacheOwnerType.thread,
        ownerId: 'tid=1&page=1',
      );
      expect(deleted, 1);
      expect(await service.getByKey('document|thread|tid=1&page=1'), isNull);

      await db.close();
      await deleteDatabase(dbName);
    },
  );

  test('LocalDocumentCacheService calculates page cache usage', () async {
    const dbName = 'document_cache_usage_test.db';
    await deleteDatabase(dbName);
    final db = await ComicLocalDb.open(databaseName: dbName);
    final service = LocalDocumentCacheService(Future.value(db));
    final now = DateTime(2026, 1, 1);

    await service.put(
      CachedDocument(
        cacheKey: 'document|thread|tid=1&page=1',
        ownerType: CacheOwnerType.thread,
        ownerId: 'tid=1&page=1',
        sourceUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1',
        body: 'abc',
        fetchedAt: now,
        updatedAt: now,
      ),
    );

    final section = await service.calculateUsage();

    expect(section.bucket, StorageBucket.pageCache);
    expect(section.clearable, isTrue);
    expect(section.bytes, 3);
    expect(section.slices.single.label, '帖子详情 HTML（1）');

    await db.close();
    await deleteDatabase(dbName);
  });

  test('LocalDocumentCacheService deletes documents by owner prefix', () async {
    const dbName = 'document_cache_owner_prefix_test.db';
    await deleteDatabase(dbName);
    final db = await ComicLocalDb.open(databaseName: dbName);
    final service = LocalDocumentCacheService(Future.value(db));
    final now = DateTime(2026, 1, 1);
    addTearDown(() async {
      await db.close();
      await deleteDatabase(dbName);
    });

    Future<void> put(String key, String ownerId) {
      return service.put(
        CachedDocument(
          cacheKey: key,
          ownerType: CacheOwnerType.thread,
          ownerId: ownerId,
          sourceUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1',
          body: 'cached',
          fetchedAt: now,
          updatedAt: now,
        ),
      );
    }

    await put('document|thread|tid=1&page=1', 'tid=1&page=1');
    await put(
      'document|thread|tid=1&page=2&authorid=9',
      'tid=1&page=2&authorid=9',
    );
    await put('document|thread|tid=2&page=1', 'tid=2&page=1');

    final deleted = await service.deleteByOwnerPrefix(
      ownerType: CacheOwnerType.thread,
      ownerIdPrefix: 'tid=1',
    );

    expect(deleted, 2);
    expect(await service.getByKey('document|thread|tid=1&page=1'), isNull);
    expect(
      await service.getByKey('document|thread|tid=1&page=2&authorid=9'),
      isNull,
    );
    expect(await service.getByKey('document|thread|tid=2&page=1'), isNotNull);
  });
}
