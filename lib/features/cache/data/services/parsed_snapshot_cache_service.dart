import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/cache/data/services/forum_home_snapshot_mirror.dart';

class LocalParsedSnapshotCacheService
    implements
        ParsedSnapshotCacheService,
        GuardedSnapshotCacheWriter,
        CacheBudgetParticipant {
  LocalParsedSnapshotCacheService(
    Future<Database> dbFuture, {
    CacheMutationReporter mutationReporter = const NoopCacheMutationReporter(),
    DateTime Function()? now,
    ForumHomeSnapshotMirror? homeMirror,
  }) : _dbFutureFactory = (() => dbFuture),
       _mutationReporter = mutationReporter,
       _now = now ?? DateTime.now,
       _homeMirror = homeMirror;

  LocalParsedSnapshotCacheService.lazy(
    Future<Database> Function() dbFutureFactory, {
    CacheMutationReporter mutationReporter = const NoopCacheMutationReporter(),
    DateTime Function()? now,
    ForumHomeSnapshotMirror? homeMirror,
  }) : _dbFutureFactory = dbFutureFactory,
       _mutationReporter = mutationReporter,
       _now = now ?? DateTime.now,
       _homeMirror = homeMirror;

  final Future<Database> Function() _dbFutureFactory;
  Future<Database>? _dbFuture;
  final CacheMutationReporter _mutationReporter;
  final DateTime Function() _now;
  final ForumHomeSnapshotMirror? _homeMirror;
  int _homeGeneration = 0;
  int _homeInvalidations = 0;

  Future<Database> get _db => _dbFuture ??= _dbFutureFactory();

  @override
  Future<CachedSnapshot<T>?> get<T>(
    SnapshotCacheDescriptor descriptor,
    SnapshotCodec<T> codec,
  ) async {
    final mirrorGeneration = _homeMirror?.generation;
    final homeGeneration = _homeGeneration;
    bool canReadHome() =>
        homeGeneration == _homeGeneration && _homeInvalidations == 0;
    if (_isHome(descriptor)) {
      if (!canReadHome()) return null;
      final row = await _homeMirror?.read(cacheKey: descriptor.cacheKey);
      if (!canReadHome()) return null;
      if (row != null) {
        final snapshot = _decode(row, codec, retainExpired: true);
        if (snapshot != null) return snapshot;
      }
    }
    final db = await _db;
    final rows = await db.query(
      AppDatabase.cachedSnapshotsTable,
      where: 'cache_key = ?',
      whereArgs: <Object>[descriptor.cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    if (_isHome(descriptor) && !canReadHome()) return null;
    final snapshot = _decode(
      rows.first,
      codec,
      retainExpired: _isHome(descriptor),
    );
    if (snapshot != null) {
      // Access bookkeeping must not delay publication of an already decoded
      // snapshot, especially while startup maintenance holds the DB queue.
      if (_isHome(descriptor)) {
        unawaited(_promoteHome(rows.first, mirrorGeneration, canReadHome));
      } else {
        try {
          await touch(descriptor.cacheKey, _now());
        } catch (_) {
          return null;
        }
      }
    }
    return snapshot;
  }

  CachedSnapshot<T>? _decode<T>(
    Map<String, Object?> row,
    SnapshotCodec<T> codec, {
    bool retainExpired = false,
  }) {
    try {
      final rowCodecVersion = row['codec_version'] as int? ?? -1;
      final rowParserVersion = row['parser_version'] as int? ?? -1;
      final canDecodeVersion = codec is SnapshotCodecVersionCompatibility
          ? (codec as SnapshotCodecVersionCompatibility).canDecodeVersion(
              codecVersion: rowCodecVersion,
              parserVersion: rowParserVersion,
            )
          : rowCodecVersion == codec.codecVersion &&
                rowParserVersion == codec.parserVersion;
      if ((row['snapshot_type'] as String? ?? '') != codec.snapshotType ||
          !canDecodeVersion) {
        return null;
      }
      final now = _now();
      final expiresAt = _toDateTime(row['expires_at']);
      if (!retainExpired && expiresAt != null && !now.isBefore(expiresAt)) {
        return null;
      }

      final decoded = jsonDecode(row['payload_json'] as String);
      final snapshot = _fromRow(row, codec.decode(decoded));
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> put<T>(
    SnapshotCacheDescriptor descriptor,
    T value,
    SnapshotCodec<T> codec, {
    required SnapshotCachePolicy policy,
  }) async {
    await putIfCurrent(
      descriptor,
      value,
      codec,
      policy: policy,
      isCurrent: () => true,
    );
  }

  @override
  Future<bool> putIfCurrent<T>(
    SnapshotCacheDescriptor descriptor,
    T value,
    SnapshotCodec<T> codec, {
    required SnapshotCachePolicy policy,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return false;
    final mirrorGeneration = _homeMirror?.generation;
    final homeGeneration = _homeGeneration;
    bool canWrite() =>
        isCurrent() &&
        (!_isHome(descriptor) ||
            (mirrorGeneration == _homeMirror?.generation &&
                homeGeneration == _homeGeneration &&
                _homeInvalidations == 0));
    final db = await _db;
    Map<String, Object?>? persistedRow;
    try {
      await db.transaction((transaction) async {
        if (!canWrite()) throw const _ExpiredSnapshotWrite();
        final existing = await _getRawByKey(transaction, descriptor.cacheKey);
        if (!canWrite()) throw const _ExpiredSnapshotWrite();
        final now = _now();
        final createdAt =
            _toDateTime(existing?['created_at']) ??
            _toDateTime(existing?['updated_at']) ??
            now;
        final payloadJson = jsonEncode(codec.encode(value));
        final retainLongTerm = policy.retainLongTerm || _isHome(descriptor);
        persistedRow = <String, Object?>{
          'cache_key': descriptor.cacheKey,
          'owner_type': descriptor.ownerType.id,
          'owner_id': descriptor.ownerId,
          'snapshot_type': codec.snapshotType,
          'codec_version': codec.codecVersion,
          'parser_version': codec.parserVersion,
          'source_document_key': _normalizeNullable(
            descriptor.sourceDocumentKey,
          ),
          'payload_json': payloadJson,
          'payload_bytes': utf8.encode(payloadJson).length,
          'created_at': createdAt.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
          'last_accessed_at': now.millisecondsSinceEpoch,
          'stale_at': now.add(policy.freshFor).millisecondsSinceEpoch,
          'retain_long_term': retainLongTerm ? 1 : 0,
          'expires_at': retainLongTerm
              ? null
              : now.add(policy.keepStaleFor).millisecondsSinceEpoch,
        };
        await transaction.insert(
          AppDatabase.cachedSnapshotsTable,
          persistedRow!,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (!canWrite()) throw const _ExpiredSnapshotWrite();
      });
    } on _ExpiredSnapshotWrite {
      return false;
    }
    if (_isHome(descriptor) && persistedRow != null) {
      await _homeMirror?.save(
        persistedRow!,
        generation: mirrorGeneration!,
        isCurrent: canWrite,
      );
    }
    _mutationReporter.reportMutation(CacheNamespace.snapshot);
    return true;
  }

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {
    final db = await _db;
    await db.update(
      AppDatabase.cachedSnapshotsTable,
      <String, Object?>{'last_accessed_at': accessedAt.millisecondsSinceEpoch},
      where: 'cache_key = ?',
      whereArgs: <Object>[cacheKey],
    );
  }

  @override
  Future<int> deleteByOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) => _deleteOwner(ownerType, ownerId, prefix: false);

  @override
  Future<int> deleteByOwnerPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) => _deleteOwner(ownerType, ownerIdPrefix, prefix: true);

  Future<int> _deleteOwner(
    CacheOwnerType ownerType,
    String ownerId, {
    required bool prefix,
  }) async {
    final home =
        ownerType == CacheOwnerType.forum &&
        (prefix ? 'home'.startsWith(ownerId) : ownerId == 'home');
    if (home) {
      _homeGeneration++;
      _homeInvalidations++;
    }
    try {
      await _homeMirror?.deleteOwner(ownerType.id, ownerId, prefix: prefix);
      final db = await _db;
      return await db.delete(
        AppDatabase.cachedSnapshotsTable,
        where: prefix
            ? 'owner_type = ? AND owner_id LIKE ?'
            : 'owner_type = ? AND owner_id = ?',
        whereArgs: <Object>[ownerType.id, prefix ? '$ownerId%' : ownerId],
      );
    } finally {
      if (home) _homeInvalidations--;
    }
  }

  @override
  Future<int> deleteExpired(DateTime now) async {
    final db = await _db;
    return db.delete(
      AppDatabase.cachedSnapshotsTable,
      where:
          'retain_long_term = 0 AND expires_at IS NOT NULL AND expires_at <= ?',
      whereArgs: <Object>[now.millisecondsSinceEpoch],
    );
  }

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT snapshot_type, retain_long_term, COUNT(*) AS count, COALESCE(SUM(payload_bytes), 0) AS total
      FROM ${AppDatabase.cachedSnapshotsTable}
      GROUP BY snapshot_type, retain_long_term
      ORDER BY snapshot_type ASC
      ''');
    final mirrorBytes = await _homeMirror?.bytes() ?? 0;
    final slices = [
      ...rows
          .map((row) {
            final snapshotType = row['snapshot_type'] as String? ?? '';
            final count = row['count'] as int? ?? 0;
            return StorageUsageSlice(
              id: 'snapshot:$snapshotType',
              labelRef: StorageUsageLabelRef(
                kind: StorageUsageLabelKind.snapshotType,
                code: snapshotType,
                count: count,
              ),
              bytes: row['total'] as int? ?? 0,
              protected: row['retain_long_term'] == 1,
            );
          })
          .where((slice) => slice.bytes > 0),
      if (mirrorBytes > 0)
        StorageUsageSlice(
          id: 'startup:forum.home',
          labelRef: const StorageUsageLabelRef(
            kind: StorageUsageLabelKind.snapshotType,
            code: 'forum.home',
            count: 1,
          ),
          bytes: mirrorBytes,
          protected: true,
        ),
    ];
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.bytes);
    return StorageUsageSection(
      bucket: StorageBucket.pageCache,
      labelRef: const StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: 'page_cache',
      ),
      bytes: total,
      clearable: slices.any((slice) => !slice.protected && slice.bytes > 0),
      slices: slices,
    );
  }

  @override
  String get participantId => 'snapshot';

  @override
  Future<CacheParticipantUsage> loadUsage() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN retain_long_term = 0 THEN payload_bytes ELSE 0 END), 0) AS total,
        COALESCE(SUM(CASE WHEN retain_long_term = 1 THEN payload_bytes ELSE 0 END), 0) AS long_term
      FROM ${AppDatabase.cachedSnapshotsTable}
      ''');
    final bytes = rows.first['total'] as int? ?? 0;
    return CacheParticipantUsage(
      clearableBytes: bytes,
      budgetedBytes: bytes,
      longTermBytes:
          (rows.first['long_term'] as int? ?? 0) +
          (await _homeMirror?.bytes() ?? 0),
    );
  }

  @override
  Future<List<CacheEvictionCandidate>> loadEvictionCandidates() async {
    final db = await _db;
    final rows = await db.query(
      AppDatabase.cachedSnapshotsTable,
      columns: const <String>[
        'cache_key',
        'payload_bytes',
        'last_accessed_at',
        'updated_at',
      ],
      where: 'retain_long_term = 0',
      orderBy: 'COALESCE(last_accessed_at, updated_at) ASC, cache_key ASC',
    );
    return rows
        .map((row) {
          return CacheEvictionCandidate(
            participantId: participantId,
            cacheKey: row['cache_key'] as String,
            bytes: row['payload_bytes'] as int? ?? 0,
            lastAccessedAt:
                _toDateTime(row['last_accessed_at']) ??
                _toDateTime(row['updated_at']) ??
                DateTime.fromMillisecondsSinceEpoch(0),
            priority: CacheEvictionPriority.parsedSnapshot,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<bool> deleteCandidate(CacheEvictionCandidate candidate) async {
    if (candidate.participantId != participantId) {
      return false;
    }
    final db = await _db;
    final deleted = await db.delete(
      AppDatabase.cachedSnapshotsTable,
      where: 'cache_key = ? AND retain_long_term = 0',
      whereArgs: <Object>[candidate.cacheKey],
    );
    return deleted > 0;
  }

  @override
  Future<CacheParticipantClearResult> clearRegular() async {
    final usage = await loadUsage();
    final db = await _db;
    final deleted = await db.delete(
      AppDatabase.cachedSnapshotsTable,
      where: 'retain_long_term = 0',
    );
    return CacheParticipantClearResult(
      deletedEntries: deleted,
      deletedBytes: usage.clearableBytes,
    );
  }

  Future<Map<String, Object?>?> _getRawByKey(
    DatabaseExecutor db,
    String cacheKey,
  ) async {
    final rows = await db.query(
      AppDatabase.cachedSnapshotsTable,
      where: 'cache_key = ?',
      whereArgs: <Object>[cacheKey],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  CachedSnapshot<T> _fromRow<T>(Map<String, Object?> row, T value) {
    return CachedSnapshot<T>(
      cacheKey: row['cache_key'] as String,
      ownerType: _ownerTypeFromDb(row['owner_type'] as String?),
      ownerId: row['owner_id'] as String,
      snapshotType: row['snapshot_type'] as String,
      codecVersion: row['codec_version'] as int? ?? 0,
      parserVersion: row['parser_version'] as int? ?? 0,
      sourceDocumentKey: row['source_document_key'] as String?,
      value: value,
      createdAt:
          _toDateTime(row['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          _toDateTime(row['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastAccessedAt: _toDateTime(row['last_accessed_at']),
      staleAt: _toDateTime(row['stale_at']),
      expiresAt: _toDateTime(row['expires_at']),
    );
  }

  CacheOwnerType _ownerTypeFromDb(String? value) {
    for (final ownerType in CacheOwnerType.values) {
      if (ownerType.id == value) {
        return ownerType;
      }
    }
    return CacheOwnerType.thread;
  }

  DateTime? _toDateTime(Object? value) {
    if (value is! int || value <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  bool _isHome(SnapshotCacheDescriptor descriptor) =>
      descriptor.ownerType == CacheOwnerType.forum &&
      descriptor.ownerId == 'home' &&
      descriptor.snapshotType == 'forum.home';

  Future<void> _promoteHome(
    Map<String, Object?> row,
    int? generation,
    bool Function() isCurrent,
  ) async {
    try {
      final retained = {...row, 'retain_long_term': 1, 'expires_at': null};
      await _homeMirror?.save(
        retained,
        generation: generation!,
        isCurrent: isCurrent,
      );
      final db = await _db;
      if (!isCurrent()) return;
      // A legacy hit is protected after publication. Match its version so a
      // concurrent refresh or explicit deletion cannot be overwritten.
      await db.update(
        AppDatabase.cachedSnapshotsTable,
        {
          'retain_long_term': 1,
          'expires_at': null,
          'last_accessed_at': _now().millisecondsSinceEpoch,
        },
        where: 'cache_key = ? AND updated_at = ?',
        whereArgs: [row['cache_key'], row['updated_at']],
      );
    } catch (_) {
      // Cache hit publication does not depend on mirror/LRU bookkeeping.
    }
  }
}

final class _ExpiredSnapshotWrite implements Exception {
  const _ExpiredSnapshotWrite();
}
