import 'dart:io' as io;

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';

class LibraryCoverLegacyMigrator {
  const LibraryCoverLegacyMigrator({
    required Future<Database> database,
    required LibraryCoverStore store,
    required ImageCacheRepository legacyCacheRepository,
  }) : _database = database,
       _store = store,
       _legacyCacheRepository = legacyCacheRepository;

  final Future<Database> _database;
  final LibraryCoverStore _store;
  final ImageCacheRepository _legacyCacheRepository;

  /// Custom covers are user assets and are always migrated before source
  /// covers. A failed item remains untouched and is retried on next startup.
  Future<void> migrateCustomAssets() async {
    final candidates = await _loadCandidates(custom: true);
    for (final candidate in candidates) {
      await _migrate(candidate);
    }
  }

  /// Source covers are best-effort and deliberately batched to avoid startup
  /// I/O spikes. Repeated runs continue from per-asset completion markers.
  Future<void> migrateSourceAssets({int batchSize = 32}) async {
    final candidates = await _loadCandidates(custom: false);
    var attempted = 0;
    for (final candidate in candidates) {
      if (attempted >= batchSize) {
        break;
      }
      if (await _isCompleted(candidate)) {
        continue;
      }
      attempted += 1;
      await _migrate(candidate);
    }
  }

  Future<List<_LegacyCoverCandidate>> _loadCandidates({
    required bool custom,
  }) async {
    final db = await _database;
    final comics = await db.query(
      ComicLocalDb.comicsTable,
      columns: const <String>[
        'comic_id',
        'cover_image_url',
        'custom_cover_image_url',
        'cover_local_path',
        'custom_cover_local_path',
        'cover_revision',
        'custom_cover_revision',
      ],
    );
    final novels = await db.query(
      ComicLocalDb.worksTable,
      columns: const <String>[
        'work_id',
        'cover_image_url',
        'cover_local_path',
        'custom_cover_local_path',
        'cover_revision',
        'custom_cover_revision',
      ],
      where: 'content_type = ?',
      whereArgs: const <Object>['novel'],
    );
    return <_LegacyCoverCandidate>[
      for (final row in comics)
        _candidate(
          ownerType: 'comic',
          ownerId: row['comic_id'] as String,
          row: row,
          custom: custom,
        ),
      for (final row in novels)
        _candidate(
          ownerType: 'novel',
          ownerId: row['work_id'] as String,
          row: row,
          custom: custom,
        ),
    ].where((candidate) => candidate.shouldMigrate).toList(growable: false);
  }

  _LegacyCoverCandidate _candidate({
    required String ownerType,
    required String ownerId,
    required Map<String, Object?> row,
    required bool custom,
  }) {
    final revision = custom
        ? row['custom_cover_revision'] as int? ?? 0
        : row['cover_revision'] as int? ?? 0;
    final assetId = custom
        ? LibraryCoverAssetIds.custom(ownerType: ownerType, ownerId: ownerId)
        : LibraryCoverAssetIds.source(ownerType: ownerType, ownerId: ownerId);
    return _LegacyCoverCandidate(
      ownerType: ownerType,
      ownerId: ownerId,
      asset: LibraryCoverAssetRef(
        assetId: assetId,
        revision: revision > 0 ? revision : 1,
        kind: custom
            ? LibraryCoverAssetKind.custom
            : LibraryCoverAssetKind.source,
        sourceUrl: custom && ownerType == 'comic'
            ? row['custom_cover_image_url'] as String?
            : custom
            ? null
            : row['cover_image_url'] as String?,
        legacyLocalPath: custom
            ? row['custom_cover_local_path'] as String?
            : row['cover_local_path'] as String?,
      ),
      legacyCacheKey: custom
          ? ImageCacheKeys.customCover(ownerType: ownerType, ownerId: ownerId)
          : ownerType == 'comic'
          ? ImageCacheKeys.comicCover(ownerId)
          : ImageCacheKeys.novelCover(ownerId),
    );
  }

  Future<void> _migrate(_LegacyCoverCandidate candidate) async {
    if (await _isCompleted(candidate)) {
      return;
    }
    final target = await _store.fileFor(candidate.asset);
    if (!await _isValidImageFile(target)) {
      final source = await _resolveLegacyFile(candidate);
      if (source != null) {
        await _store.installLocalFile(
          asset: candidate.asset,
          sourcePath: source.path,
        );
        await _store.deleteOlderRevisions(candidate.asset);
      } else if (candidate.asset.kind == LibraryCoverAssetKind.custom &&
          candidate.asset.sourceUrl?.trim().isNotEmpty == true) {
        try {
          await _store.ensureAvailable(
            candidate.asset.copyWith(clearLegacyLocalPath: true),
          );
        } catch (_) {
          return;
        }
      } else if (candidate.asset.kind == LibraryCoverAssetKind.source &&
          candidate.asset.sourceUrl?.trim().isNotEmpty == true) {
        await _complete(candidate, installed: false);
        return;
      } else {
        return;
      }
    }
    if (!await _isValidImageFile(target)) {
      await _store.invalidate(candidate.asset);
      return;
    }
    await _complete(candidate, installed: true);
  }

  Future<io.File?> _resolveLegacyFile(_LegacyCoverCandidate candidate) async {
    final path = candidate.asset.legacyLocalPath?.trim();
    if (path != null && path.isNotEmpty) {
      final direct = io.File(path);
      if (await _isValidImageFile(direct)) {
        return direct;
      }
    }
    final record = await _legacyCacheRepository.getByKey(
      candidate.legacyCacheKey,
    );
    final cachedPath = record?.localPath?.trim();
    if (cachedPath == null || cachedPath.isEmpty) {
      return null;
    }
    final cached = io.File(cachedPath);
    return await _isValidImageFile(cached) ? cached : null;
  }

  Future<bool> _isCompleted(_LegacyCoverCandidate candidate) async {
    final db = await _database;
    final rows = await db.query(
      ComicLocalDb.libraryCoverMigrationsTable,
      columns: const <String>['asset_id'],
      where: 'asset_id = ? AND revision = ?',
      whereArgs: <Object>[candidate.asset.assetId, candidate.asset.revision],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }
    final file = await _store.fileFor(candidate.asset);
    if (await file.exists() ||
        candidate.asset.kind == LibraryCoverAssetKind.source) {
      return true;
    }
    await db.delete(
      ComicLocalDb.libraryCoverMigrationsTable,
      where: 'asset_id = ? AND revision = ?',
      whereArgs: <Object>[candidate.asset.assetId, candidate.asset.revision],
    );
    return false;
  }

  Future<void> _complete(
    _LegacyCoverCandidate candidate, {
    required bool installed,
  }) async {
    final db = await _database;
    final isCustom = candidate.asset.kind == LibraryCoverAssetKind.custom;
    final table = candidate.ownerType == 'comic'
        ? ComicLocalDb.comicsTable
        : ComicLocalDb.worksTable;
    final idColumn = candidate.ownerType == 'comic' ? 'comic_id' : 'work_id';
    await db.transaction((txn) async {
      await txn.update(
        table,
        <String, Object?>{
          if (isCustom)
            'custom_cover_revision': candidate.asset.revision
          else
            'cover_revision': candidate.asset.revision,
          if (isCustom)
            'custom_cover_local_path': null
          else
            'cover_local_path': null,
        },
        where: '$idColumn = ?',
        whereArgs: <Object>[candidate.ownerId],
      );
      await txn.insert(
        ComicLocalDb.libraryCoverMigrationsTable,
        <String, Object?>{
          'asset_id': candidate.asset.assetId,
          'revision': candidate.asset.revision,
          'kind': installed ? 'installed' : 'remote',
          'completed_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await _legacyCacheRepository.deleteByKey(candidate.legacyCacheKey);
  }

  Future<bool> _isValidImageFile(io.File file) async {
    if (!await file.exists() || await file.length() < 12) {
      return false;
    }
    final handle = await file.open();
    try {
      final bytes = await handle.read(16);
      final png =
          bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47;
      final jpeg = bytes[0] == 0xff && bytes[1] == 0xd8;
      final gif = bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
      final webp =
          bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50;
      final bm = bytes[0] == 0x42 && bytes[1] == 0x4d;
      final isoMedia =
          bytes.length >= 12 &&
          bytes[4] == 0x66 &&
          bytes[5] == 0x74 &&
          bytes[6] == 0x79 &&
          bytes[7] == 0x70;
      return png || jpeg || gif || webp || bm || isoMedia;
    } finally {
      await handle.close();
    }
  }
}

class _LegacyCoverCandidate {
  const _LegacyCoverCandidate({
    required this.ownerType,
    required this.ownerId,
    required this.asset,
    required this.legacyCacheKey,
  });

  final String ownerType;
  final String ownerId;
  final LibraryCoverAssetRef asset;
  final String legacyCacheKey;

  bool get shouldMigrate {
    return asset.revision > 0 &&
        (asset.legacyLocalPath?.trim().isNotEmpty == true ||
            asset.sourceUrl?.trim().isNotEmpty == true);
  }
}
