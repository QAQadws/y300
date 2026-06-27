import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/domain/cache_diagnostic_models.dart';
import 'package:y300/features/cache/domain/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

class LocalParsedSnapshotCacheService implements ParsedSnapshotCacheService {
  LocalParsedSnapshotCacheService(
    this._dbFuture, {
    CacheDiagnosticRecorder diagnosticRecorder =
        const NoopCacheDiagnosticRecorder(),
    DateTime Function()? now,
  }) : _diagnosticRecorder = diagnosticRecorder,
       _now = now ?? DateTime.now;

  final Future<Database> _dbFuture;
  final CacheDiagnosticRecorder _diagnosticRecorder;
  final DateTime Function() _now;

  @override
  Future<CachedSnapshot<T>?> get<T>(
    SnapshotCacheDescriptor descriptor,
    SnapshotCodec<T> codec,
  ) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.cachedSnapshotsTable,
      where: 'cache_key = ?',
      whereArgs: <Object>[descriptor.cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      _recordSnapshotEvent(
        event: 'miss',
        descriptor: descriptor,
        reason: 'snapshot_missing',
        hit: false,
      );
      return null;
    }
    final row = rows.first;
    if ((row['snapshot_type'] as String? ?? '') != codec.snapshotType ||
        (row['codec_version'] as int? ?? -1) != codec.codecVersion ||
        (row['parser_version'] as int? ?? -1) != codec.parserVersion) {
      _recordSnapshotEvent(
        event: 'miss',
        descriptor: descriptor,
        reason: 'version_mismatch',
        hit: false,
        fields: <String, Object?>{
          'expectedSnapshotType': codec.snapshotType,
          'actualSnapshotType': row['snapshot_type'],
          'expectedCodecVersion': codec.codecVersion,
          'actualCodecVersion': row['codec_version'],
          'expectedParserVersion': codec.parserVersion,
          'actualParserVersion': row['parser_version'],
        },
      );
      return null;
    }
    final now = _now();
    final expiresAt = _toDateTime(row['expires_at']);
    if (expiresAt != null && !now.isBefore(expiresAt)) {
      _recordSnapshotEvent(
        event: 'miss',
        descriptor: descriptor,
        reason: 'expired',
        hit: false,
        fields: <String, Object?>{
          'expiresAt': expiresAt.toUtc().toIso8601String(),
        },
      );
      return null;
    }

    try {
      final decoded = jsonDecode(row['payload_json'] as String);
      final snapshot = _fromRow(row, codec.decode(decoded));
      await touch(descriptor.cacheKey, now);
      _recordSnapshotEvent(
        event: snapshot.isFresh(now) ? 'hit' : 'stale',
        descriptor: descriptor,
        reason: snapshot.isFresh(now) ? 'fresh_snapshot' : 'stale_snapshot',
        hit: true,
        fields: <String, Object?>{
          if (snapshot.staleAt != null)
            'staleAt': snapshot.staleAt!.toUtc().toIso8601String(),
          if (snapshot.expiresAt != null)
            'expiresAt': snapshot.expiresAt!.toUtc().toIso8601String(),
        },
      );
      return snapshot;
    } catch (_) {
      _recordSnapshotEvent(
        event: 'miss',
        descriptor: descriptor,
        reason: 'decode_failed',
        hit: false,
      );
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
    final db = await _dbFuture;
    final existing = await _getRawByKey(db, descriptor.cacheKey);
    final now = _now();
    final createdAt =
        _toDateTime(existing?['created_at']) ??
        _toDateTime(existing?['updated_at']) ??
        now;
    final payloadJson = jsonEncode(codec.encode(value));
    await db.insert(
      ComicLocalDb.cachedSnapshotsTable,
      <String, Object?>{
        'cache_key': descriptor.cacheKey,
        'owner_type': descriptor.ownerType.id,
        'owner_id': descriptor.ownerId,
        'snapshot_type': codec.snapshotType,
        'codec_version': codec.codecVersion,
        'parser_version': codec.parserVersion,
        'source_document_key': _normalizeNullable(descriptor.sourceDocumentKey),
        'payload_json': payloadJson,
        'payload_bytes': utf8.encode(payloadJson).length,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'last_accessed_at': now.millisecondsSinceEpoch,
        'stale_at': now.add(policy.freshFor).millisecondsSinceEpoch,
        'expires_at': now.add(policy.keepStaleFor).millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _recordSnapshotEvent(
      event: 'write',
      descriptor: descriptor,
      reason: 'snapshot_put',
      fields: <String, Object?>{
        'snapshotType': codec.snapshotType,
        'codecVersion': codec.codecVersion,
        'parserVersion': codec.parserVersion,
        'payloadBytes': utf8.encode(payloadJson).length,
        'freshForSeconds': policy.freshFor.inSeconds,
        'keepStaleForSeconds': policy.keepStaleFor.inSeconds,
      },
    );
  }

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {
    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.cachedSnapshotsTable,
      <String, Object?>{'last_accessed_at': accessedAt.millisecondsSinceEpoch},
      where: 'cache_key = ?',
      whereArgs: <Object>[cacheKey],
    );
  }

  @override
  Future<int> deleteByOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) async {
    final db = await _dbFuture;
    final deleted = await db.delete(
      ComicLocalDb.cachedSnapshotsTable,
      where: 'owner_type = ? AND owner_id = ?',
      whereArgs: <Object>[ownerType.id, ownerId],
    );
    _recordSnapshotEvent(
      event: 'prune',
      descriptor: SnapshotCacheDescriptor(
        cacheKey: '',
        ownerType: ownerType,
        ownerId: ownerId,
        snapshotType: 'unknown',
      ),
      reason: 'owner_deleted',
      fields: <String, Object?>{'deleted': deleted},
    );
    return deleted;
  }

  @override
  Future<int> deleteByOwnerPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) async {
    final db = await _dbFuture;
    final deleted = await db.delete(
      ComicLocalDb.cachedSnapshotsTable,
      where: 'owner_type = ? AND owner_id LIKE ?',
      whereArgs: <Object>[ownerType.id, '$ownerIdPrefix%'],
    );
    _recordSnapshotEvent(
      event: 'prune',
      descriptor: SnapshotCacheDescriptor(
        cacheKey: '',
        ownerType: ownerType,
        ownerId: ownerIdPrefix,
        snapshotType: 'unknown',
      ),
      reason: 'owner_prefix_deleted',
      fields: <String, Object?>{'deleted': deleted},
    );
    return deleted;
  }

  @override
  Future<int> deleteExpired(DateTime now) async {
    final db = await _dbFuture;
    final deleted = await db.delete(
      ComicLocalDb.cachedSnapshotsTable,
      where: 'expires_at IS NOT NULL AND expires_at <= ?',
      whereArgs: <Object>[now.millisecondsSinceEpoch],
    );
    _diagnosticRecorder.record(
      CacheDiagnosticEvent(
        event: 'prune',
        namespace: CacheNamespace.snapshot,
        bucket: StorageBucket.pageCache,
        reason: 'expired',
        fields: <String, Object?>{
          'deleted': deleted,
          'now': now.toUtc().toIso8601String(),
        },
      ),
    );
    return deleted;
  }

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final db = await _dbFuture;
    final rows = await db.rawQuery('''
      SELECT snapshot_type, COUNT(*) AS count, COALESCE(SUM(payload_bytes), 0) AS total
      FROM ${ComicLocalDb.cachedSnapshotsTable}
      GROUP BY snapshot_type
      ORDER BY snapshot_type ASC
      ''');
    final slices = rows
        .map((row) {
          final snapshotType = row['snapshot_type'] as String? ?? '';
          final count = row['count'] as int? ?? 0;
          return StorageUsageSlice(
            id: 'snapshot:$snapshotType',
            label: '${_snapshotLabel(snapshotType)}快照（$count）',
            bytes: row['total'] as int? ?? 0,
            protected: false,
          );
        })
        .where((slice) => slice.bytes > 0)
        .toList(growable: false);
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.bytes);
    return StorageUsageSection(
      bucket: StorageBucket.pageCache,
      label: StorageBucket.pageCache.label,
      bytes: total,
      clearable: total > 0,
      slices: slices,
    );
  }

  Future<Map<String, Object?>?> _getRawByKey(
    Database db,
    String cacheKey,
  ) async {
    final rows = await db.query(
      ComicLocalDb.cachedSnapshotsTable,
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

  void _recordSnapshotEvent({
    required String event,
    required SnapshotCacheDescriptor descriptor,
    String? reason,
    bool? hit,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    _diagnosticRecorder.record(
      CacheDiagnosticEvent(
        event: event,
        namespace: CacheNamespace.snapshot,
        bucket: StorageBucket.pageCache,
        cacheKey: descriptor.cacheKey.isEmpty ? null : descriptor.cacheKey,
        ownerType: descriptor.ownerType,
        ownerId: descriptor.ownerId,
        hit: hit,
        reason: reason,
        fields: <String, Object?>{
          'snapshotType': descriptor.snapshotType,
          if (descriptor.sourceDocumentKey != null)
            'sourceDocumentKey': descriptor.sourceDocumentKey,
          ...fields,
        },
      ),
    );
  }

  String _snapshotLabel(String snapshotType) {
    return switch (snapshotType) {
      'forum.home' => '论坛首页',
      'forum.display' => '帖子列表',
      'thread.detail' => '帖子详情',
      _ => snapshotType.isEmpty ? '页面解析' : snapshotType,
    };
  }
}
