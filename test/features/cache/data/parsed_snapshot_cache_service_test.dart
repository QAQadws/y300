import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/cache/data/services/parsed_snapshot_cache_service.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
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

  test(
    'LocalParsedSnapshotCacheService lets a codec decode an explicit legacy version',
    () async {
      const dbName = 'parsed_snapshot_cache_legacy_version_test.db';
      await deleteDatabase(dbName);
      final db = await ComicLocalDb.open(databaseName: dbName);
      final service = LocalParsedSnapshotCacheService(Future.value(db));
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
      });
      const descriptor = SnapshotCacheDescriptor(
        cacheKey: 'snapshot|forum|home',
        ownerType: CacheOwnerType.forum,
        ownerId: 'home',
        snapshotType: 'test.snapshot',
      );
      const legacyCodec = _StringSnapshotCodec(codecVersionValue: 1);
      await service.put(
        descriptor,
        'legacy',
        legacyCodec,
        policy: const SnapshotCachePolicy(
          freshFor: Duration(minutes: 5),
          keepStaleFor: Duration(days: 1),
        ),
      );

      final snapshot = await service.get(
        descriptor,
        const _StringSnapshotCodec(codecVersionValue: 2, legacyCodecVersion: 1),
      );

      expect(snapshot?.value, 'legacy');
      expect(snapshot?.codecVersion, 1);
      expect(snapshot?.parserVersion, 1);
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
    expect(
      section.slices.single.labelRef?.kind,
      StorageUsageLabelKind.snapshotType,
    );
    expect(section.slices.single.labelRef?.code, 'test.snapshot');
    expect(section.slices.single.labelRef?.count, 1);
  });

  test(
    'LocalParsedSnapshotCacheService deletes snapshots by owner prefix',
    () async {
      const dbName = 'parsed_snapshot_cache_owner_prefix_test.db';
      await deleteDatabase(dbName);
      final db = await ComicLocalDb.open(databaseName: dbName);
      final service = LocalParsedSnapshotCacheService(Future.value(db));
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
      });
      const codec = _StringSnapshotCodec();

      Future<void> put(String key, String ownerId, String value) {
        return service.put(
          SnapshotCacheDescriptor(
            cacheKey: key,
            ownerType: CacheOwnerType.thread,
            ownerId: ownerId,
            snapshotType: 'test.snapshot',
          ),
          value,
          codec,
          policy: const SnapshotCachePolicy(
            freshFor: Duration(minutes: 5),
            keepStaleFor: Duration(days: 1),
          ),
        );
      }

      await put('snapshot|thread|tid=1&page=1', 'tid=1&page=1', 'one');
      await put(
        'snapshot|thread|tid=1&page=2&ordertype=1',
        'tid=1&page=2&ordertype=1',
        'two',
      );
      await put('snapshot|thread|tid=2&page=1', 'tid=2&page=1', 'other');

      final deleted = await service.deleteByOwnerPrefix(
        ownerType: CacheOwnerType.thread,
        ownerIdPrefix: 'tid=1',
      );

      expect(deleted, 2);
      expect(
        await service.get(
          const SnapshotCacheDescriptor(
            cacheKey: 'snapshot|thread|tid=1&page=1',
            ownerType: CacheOwnerType.thread,
            ownerId: 'tid=1&page=1',
            snapshotType: 'test.snapshot',
          ),
          codec,
        ),
        isNull,
      );
      expect(
        await service.get(
          const SnapshotCacheDescriptor(
            cacheKey: 'snapshot|thread|tid=2&page=1',
            ownerType: CacheOwnerType.thread,
            ownerId: 'tid=2&page=1',
            snapshotType: 'test.snapshot',
          ),
          codec,
        ),
        isNotNull,
      );
    },
  );

  test('LocalParsedSnapshotCacheService deletes expired snapshots', () async {
    const dbName = 'parsed_snapshot_cache_prune_test.db';
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
    const codec = _StringSnapshotCodec();

    Future<void> put(String key, Duration keepStaleFor) {
      return service.put(
        SnapshotCacheDescriptor(
          cacheKey: key,
          ownerType: CacheOwnerType.thread,
          ownerId: key,
          snapshotType: 'test.snapshot',
        ),
        key,
        codec,
        policy: SnapshotCachePolicy(
          freshFor: const Duration(minutes: 1),
          keepStaleFor: keepStaleFor,
        ),
      );
    }

    await put('expired', const Duration(minutes: 1));
    await put('fresh', const Duration(days: 1));
    currentTime = now.add(const Duration(minutes: 2));

    final deleted = await service.deleteExpired(currentTime);

    expect(deleted, 1);
    expect(
      await service.get(
        const SnapshotCacheDescriptor(
          cacheKey: 'expired',
          ownerType: CacheOwnerType.thread,
          ownerId: 'expired',
          snapshotType: 'test.snapshot',
        ),
        codec,
      ),
      isNull,
    );
    expect(
      await service.get(
        const SnapshotCacheDescriptor(
          cacheKey: 'fresh',
          ownerType: CacheOwnerType.thread,
          ownerId: 'fresh',
          snapshotType: 'test.snapshot',
        ),
        codec,
      ),
      isNotNull,
    );
  });

  test('snapshot cache participates in unified capacity cleanup', () async {
    const dbName = 'parsed_snapshot_cache_budget_test.db';
    await deleteDatabase(dbName);
    final db = await ComicLocalDb.open(databaseName: dbName);
    final reporter = _RecordingMutationReporter();
    final service = LocalParsedSnapshotCacheService(
      Future.value(db),
      mutationReporter: reporter,
      now: () => DateTime(2026, 1, 1),
    );
    addTearDown(() async {
      await db.close();
      await deleteDatabase(dbName);
    });
    const descriptor = SnapshotCacheDescriptor(
      cacheKey: 'budget-snapshot',
      ownerType: CacheOwnerType.thread,
      ownerId: 'tid=1',
      snapshotType: 'test.snapshot',
    );

    await service.put(
      descriptor,
      'cached',
      const _StringSnapshotCodec(),
      policy: const SnapshotCachePolicy(
        freshFor: Duration(minutes: 5),
        keepStaleFor: Duration(days: 1),
      ),
    );

    final usage = await service.loadUsage();
    final candidates = await service.loadEvictionCandidates();
    expect(usage.budgetedBytes, greaterThan(0));
    expect(candidates.single.cacheKey, descriptor.cacheKey);
    expect(reporter.namespaces, <CacheNamespace>[CacheNamespace.snapshot]);
    final cleared = await service.clearRegular();
    expect(cleared.deletedEntries, 1);
    expect(cleared.deletedBytes, usage.budgetedBytes);
  });
}

class _RecordingMutationReporter implements CacheMutationReporter {
  final List<CacheNamespace> namespaces = <CacheNamespace>[];

  @override
  void reportMutation(CacheNamespace namespace) {
    namespaces.add(namespace);
  }
}

class _StringSnapshotCodec
    implements SnapshotCodec<String>, SnapshotCodecVersionCompatibility {
  const _StringSnapshotCodec({
    this.codecVersionValue = 1,
    this.parserVersionValue = 1,
    this.legacyCodecVersion,
  });

  final int codecVersionValue;
  final int parserVersionValue;
  final int? legacyCodecVersion;

  @override
  String get snapshotType => 'test.snapshot';

  @override
  int get codecVersion => codecVersionValue;

  @override
  int get parserVersion => parserVersionValue;

  @override
  bool canDecodeVersion({
    required int codecVersion,
    required int parserVersion,
  }) {
    return codecVersion == codecVersionValue &&
            parserVersion == parserVersionValue ||
        codecVersion == legacyCodecVersion && parserVersion == 1;
  }

  @override
  Object? encode(String value) => <String, Object?>{'value': value};

  @override
  String decode(Object? json) {
    return (json as Map<String, dynamic>)['value'] as String;
  }
}
