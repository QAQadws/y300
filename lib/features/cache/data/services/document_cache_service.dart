import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/domain/models/cache_diagnostic_models.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

class LocalDocumentCacheService implements DocumentCacheService {
  LocalDocumentCacheService(
    Future<Database> dbFuture, {
    CacheDiagnosticRecorder diagnosticRecorder =
        const NoopCacheDiagnosticRecorder(),
  }) : _dbFutureFactory = (() => dbFuture),
       _diagnosticRecorder = diagnosticRecorder;

  LocalDocumentCacheService.lazy(
    Future<Database> Function() dbFutureFactory, {
    CacheDiagnosticRecorder diagnosticRecorder =
        const NoopCacheDiagnosticRecorder(),
  }) : _dbFutureFactory = dbFutureFactory,
       _diagnosticRecorder = diagnosticRecorder;

  final Future<Database> Function() _dbFutureFactory;
  Future<Database>? _dbFuture;
  final CacheDiagnosticRecorder _diagnosticRecorder;

  Future<Database> get _db => _dbFuture ??= _dbFutureFactory();

  @override
  Future<CachedDocument?> getByKey(String cacheKey) async {
    final db = await _db;
    final rows = await db.query(
      ComicLocalDb.cachedDocumentsTable,
      where: 'cache_key = ?',
      whereArgs: <Object>[cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      _recordDocumentEvent(
        event: 'miss',
        cacheKey: cacheKey,
        reason: 'document_missing',
        hit: false,
      );
      return null;
    }
    final document = _fromRow(rows.first);
    _recordDocumentEvent(
      event: 'hit',
      cacheKey: cacheKey,
      ownerType: document.ownerType,
      ownerId: document.ownerId,
      reason: 'document_found',
      hit: true,
      fields: <String, Object?>{'bodyBytes': utf8.encode(document.body).length},
    );
    return document;
  }

  @override
  Future<void> put(CachedDocument document) async {
    final db = await _db;
    await db.insert(
      ComicLocalDb.cachedDocumentsTable,
      <String, Object?>{
        'cache_key': document.cacheKey,
        'namespace': document.namespace.id,
        'owner_type': document.ownerType.id,
        'owner_id': document.ownerId,
        'source_url': document.sourceUrl,
        'request_profile': document.requestProfile.id,
        'body': document.body,
        'content_type': _normalizeNullable(document.contentType),
        'status_code': document.statusCode,
        'body_bytes': utf8.encode(document.body).length,
        'fetched_at': document.fetchedAt.millisecondsSinceEpoch,
        'updated_at': document.updatedAt.millisecondsSinceEpoch,
        'last_accessed_at': document.lastAccessedAt?.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _recordDocumentEvent(
      event: 'write',
      cacheKey: document.cacheKey,
      ownerType: document.ownerType,
      ownerId: document.ownerId,
      reason: 'document_put',
      fields: <String, Object?>{
        'bodyBytes': utf8.encode(document.body).length,
        'requestProfile': document.requestProfile.id,
      },
    );
  }

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {
    final db = await _db;
    await db.update(
      ComicLocalDb.cachedDocumentsTable,
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
    final db = await _db;
    final deleted = await db.delete(
      ComicLocalDb.cachedDocumentsTable,
      where: 'owner_type = ? AND owner_id = ?',
      whereArgs: <Object>[ownerType.id, ownerId],
    );
    _recordDocumentEvent(
      event: 'prune',
      ownerType: ownerType,
      ownerId: ownerId,
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
    final db = await _db;
    final deleted = await db.delete(
      ComicLocalDb.cachedDocumentsTable,
      where: 'owner_type = ? AND owner_id LIKE ?',
      whereArgs: <Object>[ownerType.id, '$ownerIdPrefix%'],
    );
    _recordDocumentEvent(
      event: 'prune',
      ownerType: ownerType,
      ownerId: ownerIdPrefix,
      reason: 'owner_prefix_deleted',
      fields: <String, Object?>{'deleted': deleted},
    );
    return deleted;
  }

  @override
  Future<int> deleteOlderThan(DateTime cutoff) async {
    final db = await _db;
    final deleted = await db.delete(
      ComicLocalDb.cachedDocumentsTable,
      where: 'updated_at < ?',
      whereArgs: <Object>[cutoff.millisecondsSinceEpoch],
    );
    _recordDocumentEvent(
      event: 'prune',
      reason: 'older_than_cutoff',
      fields: <String, Object?>{
        'deleted': deleted,
        'cutoff': cutoff.toUtc().toIso8601String(),
      },
    );
    return deleted;
  }

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT owner_type, namespace, COUNT(*) AS count, COALESCE(SUM(body_bytes), 0) AS total
      FROM ${ComicLocalDb.cachedDocumentsTable}
      GROUP BY owner_type, namespace
      ORDER BY owner_type ASC, namespace ASC
      ''');
    final slices = rows
        .map((row) {
          final ownerType = row['owner_type'] as String? ?? '';
          final namespace = row['namespace'] as String? ?? '';
          final count = row['count'] as int? ?? 0;
          return StorageUsageSlice(
            id: 'document:$ownerType:$namespace',
            label: '${_ownerLabel(ownerType)} HTML（$count）',
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

  CachedDocument _fromRow(Map<String, Object?> row) {
    return CachedDocument(
      cacheKey: row['cache_key'] as String,
      namespace: _namespaceFromDb(row['namespace'] as String?),
      ownerType: _ownerTypeFromDb(row['owner_type'] as String?),
      ownerId: row['owner_id'] as String,
      sourceUrl: row['source_url'] as String,
      requestProfile: _requestProfileFromDb(row['request_profile'] as String?),
      body: row['body'] as String,
      contentType: row['content_type'] as String?,
      statusCode: row['status_code'] as int?,
      fetchedAt:
          _toDateTime(row['fetched_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          _toDateTime(row['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastAccessedAt: _toDateTime(row['last_accessed_at']),
    );
  }

  CacheNamespace _namespaceFromDb(String? value) {
    for (final namespace in CacheNamespace.values) {
      if (namespace.id == value) {
        return namespace;
      }
    }
    return CacheNamespace.document;
  }

  CacheOwnerType _ownerTypeFromDb(String? value) {
    for (final ownerType in CacheOwnerType.values) {
      if (ownerType.id == value) {
        return ownerType;
      }
    }
    return CacheOwnerType.thread;
  }

  DocumentRequestProfile _requestProfileFromDb(String? value) {
    for (final requestProfile in DocumentRequestProfile.values) {
      if (requestProfile.id == value) {
        return requestProfile;
      }
    }
    return DocumentRequestProfile.loggedIn;
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

  String _ownerLabel(String ownerType) {
    return switch (ownerType) {
      'forum' => '论坛首页',
      'forum_display' => '帖子列表',
      'thread' => '帖子详情',
      'tag' => '标签页',
      'profile' => '个人资料',
      'blog' => '日志',
      _ => ownerType.isEmpty ? '页面' : ownerType,
    };
  }

  void _recordDocumentEvent({
    required String event,
    String? cacheKey,
    CacheOwnerType? ownerType,
    String? ownerId,
    String? reason,
    bool? hit,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    _diagnosticRecorder.record(
      CacheDiagnosticEvent(
        event: event,
        namespace: CacheNamespace.document,
        bucket: StorageBucket.pageCache,
        cacheKey: cacheKey,
        ownerType: ownerType,
        ownerId: ownerId,
        hit: hit,
        reason: reason,
        fields: fields,
      ),
    );
  }
}
