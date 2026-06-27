import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/protected_cover_cache_maintenance.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

abstract class ImageCacheRepository implements ProtectedCoverCacheStore {
  Future<CachedImageRecord?> getByKey(String cacheKey);

  Future<void> upsert(CachedImageRecord record);

  Future<void> touch(String cacheKey, DateTime accessedAt);

  Future<List<CachedImageRecord>> listByOwner({
    required String ownerType,
    required String ownerId,
  }) {
    throw UnimplementedError('listByOwner($ownerType, $ownerId)');
  }

  Future<int> calculateUsageBytes({required bool includeProtected});

  Future<List<ImageCacheUsageGroup>> calculateUsageGroups();

  Future<List<CachedImageRecord>> listUnprotectedByAccessTime();

  @override
  Future<List<CachedImageRecord>> listProtectedCovers();

  @override
  Future<void> deleteByKey(String cacheKey);
}

class LocalImageCacheRepository implements ImageCacheRepository {
  LocalImageCacheRepository(this._dbFuture);

  final Future<Database> _dbFuture;

  @override
  Future<CachedImageRecord?> getByKey(String cacheKey) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.cachedImagesTable,
      where: 'cache_key = ?',
      whereArgs: <Object>[cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromRow(rows.first);
  }

  @override
  Future<void> upsert(CachedImageRecord record) async {
    final db = await _dbFuture;
    final existing = await getByKey(record.cacheKey);
    final createdAt = existing?.createdAt ?? record.createdAt;
    final retentionClass = _effectiveRetentionClass(record);
    await db.insert(ComicLocalDb.cachedImagesTable, <String, Object?>{
      'cache_key': record.cacheKey,
      'owner_type': record.ownerType,
      'owner_id': record.ownerId,
      'episode_id': _normalizeNullable(record.episodeId),
      'image_index': record.imageIndex,
      'role': record.role,
      'last_source_url': _normalizeNullable(record.lastSourceUrl),
      'local_path': _normalizeNullable(record.localPath),
      'bytes': record.bytes,
      'mime_type': _normalizeNullable(record.mimeType),
      'protected': record.protected ? 1 : 0,
      'retention_class': retentionClass.dbValue,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': record.updatedAt.millisecondsSinceEpoch,
      'last_accessed_at': record.lastAccessedAt?.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {
    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.cachedImagesTable,
      <String, Object?>{
        'last_accessed_at': accessedAt.millisecondsSinceEpoch,
        'updated_at': accessedAt.millisecondsSinceEpoch,
      },
      where: 'cache_key = ?',
      whereArgs: <Object>[cacheKey],
    );
  }

  @override
  Future<List<CachedImageRecord>> listByOwner({
    required String ownerType,
    required String ownerId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.cachedImagesTable,
      where: 'owner_type = ? AND owner_id = ?',
      whereArgs: <Object>[ownerType, ownerId],
      orderBy: 'updated_at ASC, created_at ASC, cache_key ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<int> calculateUsageBytes({required bool includeProtected}) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(bytes), 0) AS total
      FROM ${ComicLocalDb.cachedImagesTable}
      ${includeProtected ? '' : 'WHERE protected = 0'}
      ''');
    return rows.first['total'] as int? ?? 0;
  }

  @override
  Future<List<ImageCacheUsageGroup>> calculateUsageGroups() async {
    final db = await _dbFuture;
    final rows = await db.rawQuery('''
      SELECT owner_type, role, retention_class, protected, COALESCE(SUM(bytes), 0) AS total
      FROM ${ComicLocalDb.cachedImagesTable}
      GROUP BY owner_type, role, retention_class, protected
      ORDER BY owner_type ASC, role ASC, retention_class ASC, protected ASC
      ''');
    return rows
        .map((row) {
          return ImageCacheUsageGroup(
            ownerType: row['owner_type'] as String? ?? '',
            role: row['role'] as String? ?? '',
            retentionClass: row['retention_class'] as String? ?? '',
            protected: (row['protected'] as int? ?? 0) == 1,
            bytes: row['total'] as int? ?? 0,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<CachedImageRecord>> listUnprotectedByAccessTime() async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.cachedImagesTable,
      where: 'protected = 0',
      orderBy: 'COALESCE(last_accessed_at, updated_at, created_at) ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<List<CachedImageRecord>> listProtectedCovers() async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.cachedImagesTable,
      where: 'protected = 1 AND role IN (?, ?)',
      whereArgs: <Object>[
        ImageCacheRole.cover.dbValue,
        ImageCacheRole.customCover.dbValue,
      ],
      orderBy: 'updated_at ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> deleteByKey(String cacheKey) async {
    final db = await _dbFuture;
    await db.delete(
      ComicLocalDb.cachedImagesTable,
      where: 'cache_key = ?',
      whereArgs: <Object>[cacheKey],
    );
  }

  CachedImageRecord _fromRow(Map<String, Object?> row) {
    return CachedImageRecord(
      cacheKey: row['cache_key'] as String,
      ownerType: row['owner_type'] as String,
      ownerId: row['owner_id'] as String,
      episodeId: row['episode_id'] as String?,
      imageIndex: row['image_index'] as int?,
      role: row['role'] as String,
      lastSourceUrl: row['last_source_url'] as String?,
      localPath: row['local_path'] as String?,
      bytes: row['bytes'] as int? ?? 0,
      mimeType: row['mime_type'] as String?,
      protected: (row['protected'] as int? ?? 0) == 1,
      retentionClass: _retentionClassFromDb(
        row['retention_class'] as String?,
        protected: (row['protected'] as int? ?? 0) == 1,
      ),
      createdAt:
          _toDateTime(row['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          _toDateTime(row['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastAccessedAt: _toDateTime(row['last_accessed_at']),
    );
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

  ImageRetentionClass _effectiveRetentionClass(CachedImageRecord record) {
    if (record.protected &&
        record.retentionClass == ImageRetentionClass.ephemeral) {
      return ImageRetentionClass.protected;
    }
    return record.retentionClass;
  }

  ImageRetentionClass _retentionClassFromDb(
    String? value, {
    required bool protected,
  }) {
    final normalized = value?.trim();
    for (final retentionClass in ImageRetentionClass.values) {
      if (retentionClass.dbValue == normalized) {
        return retentionClass;
      }
    }
    return protected
        ? ImageRetentionClass.protected
        : ImageRetentionClass.ephemeral;
  }
}
