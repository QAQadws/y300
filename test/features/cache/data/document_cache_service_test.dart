import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/cache/data/services/document_cache_service.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
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
          sourceUrl:
              'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2',
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
        sourceUrl:
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2',
        body: 'abc',
        fetchedAt: now,
        updatedAt: now,
      ),
    );

    final section = await service.calculateUsage();

    expect(section.bucket, StorageBucket.pageCache);
    expect(section.clearable, isTrue);
    expect(section.bytes, 3);
    expect(
      section.slices.single.labelRef?.kind,
      StorageUsageLabelKind.documentOwner,
    );
    expect(section.slices.single.labelRef?.code, 'thread');
    expect(section.slices.single.labelRef?.count, 1);

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
          sourceUrl:
              'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2',
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

  test(
    'LocalDocumentCacheService deletes documents older than cutoff',
    () async {
      const dbName = 'document_cache_prune_test.db';
      await deleteDatabase(dbName);
      final db = await ComicLocalDb.open(databaseName: dbName);
      final service = LocalDocumentCacheService(Future.value(db));
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
      });

      Future<void> put(String key, DateTime updatedAt) {
        return service.put(
          CachedDocument(
            cacheKey: key,
            ownerType: CacheOwnerType.thread,
            ownerId: key,
            sourceUrl:
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2',
            body: 'cached',
            fetchedAt: updatedAt,
            updatedAt: updatedAt,
          ),
        );
      }

      await put('old', DateTime(2026, 1, 1));
      await put('new', DateTime(2026, 1, 10));

      final deleted = await service.deleteOlderThan(DateTime(2026, 1, 5));

      expect(deleted, 1);
      expect(await service.getByKey('old'), isNull);
      expect(await service.getByKey('new'), isNotNull);
    },
  );

  test(
    'document cache participates in unified capacity and LRU cleanup',
    () async {
      const dbName = 'document_cache_budget_test.db';
      await deleteDatabase(dbName);
      final db = await ComicLocalDb.open(databaseName: dbName);
      final reporter = _RecordingMutationReporter();
      final service = LocalDocumentCacheService(
        Future.value(db),
        mutationReporter: reporter,
      );
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
      });

      Future<void> put(String key, String body, DateTime updatedAt) {
        return service.put(
          CachedDocument(
            cacheKey: key,
            ownerType: CacheOwnerType.thread,
            ownerId: key,
            sourceUrl: 'https://bbs.yamibo.com/$key',
            body: body,
            fetchedAt: updatedAt,
            updatedAt: updatedAt,
          ),
        );
      }

      await put('older', 'abc', DateTime(2026, 1, 1));
      await put('newer', 'defgh', DateTime(2026, 1, 2));

      final usage = await service.loadUsage();
      final candidates = await service.loadEvictionCandidates();
      expect(usage.budgetedBytes, 8);
      expect(candidates.map((candidate) => candidate.cacheKey), <String>[
        'older',
        'newer',
      ]);
      expect(reporter.namespaces, <CacheNamespace>[
        CacheNamespace.document,
        CacheNamespace.document,
      ]);

      expect(await service.deleteCandidate(candidates.first), isTrue);
      final cleared = await service.clearRegular();
      expect(cleared.deletedEntries, 1);
      expect(cleared.deletedBytes, 5);
    },
  );
}

class _RecordingMutationReporter implements CacheMutationReporter {
  final List<CacheNamespace> namespaces = <CacheNamespace>[];

  @override
  void reportMutation(CacheNamespace namespace) {
    namespaces.add(namespace);
  }
}
