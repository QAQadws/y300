import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/cache/data/parsed_snapshot_cache_service.dart';
import 'package:y300/features/cache/domain/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'LocalParsedSnapshotCacheService stores and reads matching snapshot',
    () async {
      const dbName = 'parsed_snapshot_cache_service_test.db';
      await deleteDatabase(dbName);
      final now = DateTime(2026, 1, 1, 10);
      var currentTime = now;
      final db = await ComicLocalDb.open(databaseName: dbName);
      final service = LocalParsedSnapshotCacheService(
        Future.value(db),
        now: () => currentTime,
      );
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
      });
      const descriptor = SnapshotCacheDescriptor(
        cacheKey: 'snapshot|thread|1',
        ownerType: CacheOwnerType.thread,
        ownerId: 'tid=1&page=1',
        snapshotType: 'test.snapshot',
      );
      const codec = _StringSnapshotCodec();

      await service.put(
        descriptor,
        'hello',
        codec,
        policy: const SnapshotCachePolicy(
          freshFor: Duration(minutes: 5),
          keepStaleFor: Duration(days: 1),
        ),
      );
      currentTime = now.add(const Duration(minutes: 1));

      final snapshot = await service.get(descriptor, codec);

      expect(snapshot, isNotNull);
      expect(snapshot!.value, 'hello');
      expect(snapshot.isFresh(currentTime), isTrue);
      expect(snapshot.expiresAt, now.add(const Duration(days: 1)));
    },
  );

  test(
    'LocalParsedSnapshotCacheService rejects parser version mismatch',
    () async {
      const dbName = 'parsed_snapshot_cache_version_test.db';
      await deleteDatabase(dbName);
      final db = await ComicLocalDb.open(databaseName: dbName);
      final service = LocalParsedSnapshotCacheService(Future.value(db));
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
      });
      const descriptor = SnapshotCacheDescriptor(
        cacheKey: 'snapshot|thread|1',
        ownerType: CacheOwnerType.thread,
        ownerId: 'tid=1&page=1',
        snapshotType: 'test.snapshot',
      );

      await service.put(
        descriptor,
        'hello',
        const _StringSnapshotCodec(parserVersionValue: 1),
        policy: const SnapshotCachePolicy(
          freshFor: Duration(minutes: 5),
          keepStaleFor: Duration(days: 1),
        ),
      );

      final snapshot = await service.get(
        descriptor,
        const _StringSnapshotCodec(parserVersionValue: 2),
      );

      expect(snapshot, isNull);
    },
  );

  test('LocalParsedSnapshotCacheService rejects expired snapshot', () async {
    const dbName = 'parsed_snapshot_cache_expired_test.db';
    await deleteDatabase(dbName);
    final now = DateTime(2026, 1, 1, 10);
    var currentTime = now;
    final db = await ComicLocalDb.open(databaseName: dbName);
    final service = LocalParsedSnapshotCacheService(
      Future.value(db),
      now: () => currentTime,
    );
    addTearDown(() async {
      await db.close();
      await deleteDatabase(dbName);
    });
    const descriptor = SnapshotCacheDescriptor(
      cacheKey: 'snapshot|thread|1',
      ownerType: CacheOwnerType.thread,
      ownerId: 'tid=1&page=1',
      snapshotType: 'test.snapshot',
    );

    await service.put(
      descriptor,
      'hello',
      const _StringSnapshotCodec(),
      policy: const SnapshotCachePolicy(
        freshFor: Duration(minutes: 1),
        keepStaleFor: Duration(minutes: 2),
      ),
    );
    currentTime = now.add(const Duration(minutes: 2));

    expect(await service.get(descriptor, const _StringSnapshotCodec()), isNull);
  });

  test('LocalParsedSnapshotCacheService calculates page cache usage', () async {
    const dbName = 'parsed_snapshot_cache_usage_test.db';
    await deleteDatabase(dbName);
    final db = await ComicLocalDb.open(databaseName: dbName);
    final service = LocalParsedSnapshotCacheService(Future.value(db));
    addTearDown(() async {
      await db.close();
      await deleteDatabase(dbName);
    });
    const descriptor = SnapshotCacheDescriptor(
      cacheKey: 'snapshot|thread|1',
      ownerType: CacheOwnerType.thread,
      ownerId: 'tid=1&page=1',
      snapshotType: 'test.snapshot',
    );

    await service.put(
      descriptor,
      'hello',
      const _StringSnapshotCodec(),
      policy: const SnapshotCachePolicy(
        freshFor: Duration(minutes: 5),
        keepStaleFor: Duration(days: 1),
      ),
    );

    final section = await service.calculateUsage();

    expect(section.bucket, StorageBucket.pageCache);
    expect(section.clearable, isTrue);
    expect(section.bytes, greaterThan(0));
    expect(section.slices.single.label, 'test.snapshot快照（1）');
  });
}

class _StringSnapshotCodec implements SnapshotCodec<String> {
  const _StringSnapshotCodec({this.parserVersionValue = 1});

  final int parserVersionValue;

  @override
  String get snapshotType => 'test.snapshot';

  @override
  int get codecVersion => 1;

  @override
  int get parserVersion => parserVersionValue;

  @override
  Object? encode(String value) => <String, Object?>{'value': value};

  @override
  String decode(Object? json) {
    return (json as Map<String, dynamic>)['value'] as String;
  }
}
