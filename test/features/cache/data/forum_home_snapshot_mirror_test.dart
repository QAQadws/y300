import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/config/technical_storage_keys.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/cache/data/services/forum_home_snapshot_mirror.dart';
import 'package:y300/features/cache/data/services/parsed_snapshot_cache_service.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

const _home = SnapshotCacheDescriptor(
  cacheKey: 'forum_source_v1|parsing|1|10|snapshot|forum|home|logged_in|',
  ownerType: CacheOwnerType.forum,
  ownerId: 'home',
  snapshotType: 'forum.home',
);
const _policy = SnapshotCachePolicy(
  freshFor: Duration(minutes: 5),
  keepStaleFor: Duration(days: 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cold home hit never opens the pending library database', () async {
    final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
    addTearDown(db.close);
    final writer = LocalParsedSnapshotCacheService(
      Future.value(db),
      homeMirror: ForumHomeSnapshotMirror(),
      now: () => DateTime(2026),
    );
    await writer.put(_home, 'last home', const _Codec(), policy: _policy);
    var opens = 0;
    final pending = Completer<Database>();
    final cold = LocalParsedSnapshotCacheService.lazy(
      () {
        opens++;
        return pending.future;
      },
      homeMirror: ForumHomeSnapshotMirror(),
      now: () => DateTime(2027),
    );
    final snapshot = await cold.get(_home, const _Codec());
    expect(snapshot?.value, 'last home');
    expect(snapshot?.isFresh(DateTime(2027)), isFalse);
    expect(opens, 0);
  });

  test(
    'home survives expiry and regular clearing, owner invalidation removes both copies',
    () async {
      final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
      addTearDown(db.close);
      final service = LocalParsedSnapshotCacheService(
        Future.value(db),
        homeMirror: ForumHomeSnapshotMirror(),
      );
      await service.put(_home, 'last home', const _Codec(), policy: _policy);
      expect(await service.deleteExpired(DateTime(9999)), 0);
      expect((await service.clearRegular()).deletedEntries, 0);
      expect(await service.loadEvictionCandidates(), isEmpty);
      final usage = await service.calculateUsage();
      expect(usage.slices, hasLength(2));
      expect(usage.slices.every((slice) => slice.protected), isTrue);
      expect((await service.loadUsage()).longTermBytes, usage.bytes);
      await service.deleteByOwner(
        ownerType: CacheOwnerType.forum,
        ownerId: 'home',
      );
      expect(await service.get(_home, const _Codec()), isNull);
      expect(await ForumHomeSnapshotMirror().bytes(), 0);
    },
  );

  test(
    'mirror requires exact account/source key and compatible codec',
    () async {
      final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
      addTearDown(db.close);
      final mirror = ForumHomeSnapshotMirror();
      final writer = LocalParsedSnapshotCacheService(
        Future.value(db),
        homeMirror: mirror,
      );
      await writer.put(_home, 'private home', const _Codec(), policy: _policy);
      await db.delete(AppDatabase.cachedSnapshotsTable);
      for (final key in [
        _home.cacheKey.replaceFirst('|10|', '|20|'),
        _home.cacheKey.replaceFirst('|parsing|1|', '|parsing|2|'),
      ]) {
        final other = SnapshotCacheDescriptor(
          cacheKey: key,
          ownerType: CacheOwnerType.forum,
          ownerId: 'home',
          snapshotType: 'forum.home',
        );
        expect(await writer.get(other, const _Codec()), isNull);
      }
      expect(await writer.get(_home, const _Codec(version: 2)), isNull);
      expect((await writer.get(_home, const _Codec()))?.value, 'private home');
      final prefs = await SharedPreferences.getInstance();
      final row = (await mirror.read())!..['codec_version'] = 'damaged';
      await prefs.setString(
        TechnicalStorageKeys.forumHomeStartupSnapshotV1,
        jsonEncode(row),
      );
      expect(await writer.get(_home, const _Codec()), isNull);
    },
  );

  test(
    'explicit invalidation retires a home write waiting for SQLite',
    () async {
      final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
      addTearDown(db.close);
      final pending = Completer<Database>();
      final mirror = ForumHomeSnapshotMirror();
      final service = LocalParsedSnapshotCacheService(
        pending.future,
        homeMirror: mirror,
      );
      final writing = service.putIfCurrent(
        _home,
        'late home',
        const _Codec(),
        policy: _policy,
        isCurrent: () => true,
      );
      final deleting = service.deleteByOwnerPrefix(
        ownerType: CacheOwnerType.forum,
        ownerIdPrefix: 'ho',
      );
      pending.complete(db);
      expect(await writing, isFalse);
      await deleting;
      expect(await service.get(_home, const _Codec()), isNull);
      expect(await mirror.bytes(), 0);
    },
  );

  test(
    'expired legacy SQLite home is published and seeds the next cold boot',
    () async {
      final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
      addTearDown(db.close);
      final writer = LocalParsedSnapshotCacheService(Future.value(db));
      await writer.put(_home, 'legacy home', const _Codec(), policy: _policy);
      await db.update(AppDatabase.cachedSnapshotsTable, {
        'retain_long_term': 0,
        'expires_at': DateTime(2025).millisecondsSinceEpoch,
      });
      final service = LocalParsedSnapshotCacheService(
        Future.value(db),
        homeMirror: ForumHomeSnapshotMirror(),
      );
      expect((await service.get(_home, const _Codec()))?.value, 'legacy home');
      // Drain the detached mirror write and SQL promotion.
      for (
        var attempt = 0;
        attempt < 20 && await ForumHomeSnapshotMirror().bytes() == 0;
        attempt++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(await ForumHomeSnapshotMirror().bytes(), greaterThan(0));
      final cold = LocalParsedSnapshotCacheService.lazy(
        () => throw StateError('DB must stay lazy'),
        homeMirror: ForumHomeSnapshotMirror(),
      );
      expect((await cold.get(_home, const _Codec()))?.value, 'legacy home');
    },
  );

  test(
    'pending owner clearing rejects reads without waiting for SQLite',
    () async {
      final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
      addTearDown(db.close);
      final prefs = await SharedPreferences.getInstance();
      await LocalParsedSnapshotCacheService(
        Future.value(db),
        homeMirror: ForumHomeSnapshotMirror(),
      ).put(_home, 'old home', const _Codec(), policy: _policy);
      final loadingPreferences = Completer<SharedPreferences>();
      final loadingDatabase = Completer<Database>();
      final service = LocalParsedSnapshotCacheService(
        loadingDatabase.future,
        homeMirror: ForumHomeSnapshotMirror(
          preferencesLoader: () => loadingPreferences.future,
        ),
      );
      final oldRead = service.get(_home, const _Codec());
      final clearing = service.deleteByOwner(
        ownerType: CacheOwnerType.forum,
        ownerId: 'home',
      );
      expect(await service.get(_home, const _Codec()), isNull);
      loadingPreferences.complete(prefs);
      expect(await oldRead, isNull);
      expect(await service.get(_home, const _Codec()), isNull);
      loadingDatabase.complete(db);
      await clearing;
      expect(await ForumHomeSnapshotMirror().bytes(), 0);
    },
  );
}

final class _Codec implements SnapshotCodec<String> {
  const _Codec({this.version = 1});
  final int version;
  @override
  String get snapshotType => 'forum.home';
  @override
  int get codecVersion => version;
  @override
  int get parserVersion => 1;
  @override
  String decode(Object? json) => json as String;
  @override
  Object encode(String value) => value;
}
