import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/composer_shared/data/local/composer_draft_local_db.dart';
import 'package:y300/features/history/data/local/history_local_db.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/storage/domain/storage_root_access_gate.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';

class LibraryCoverStorageAccountingAdapter implements StorageAccountingAdapter {
  const LibraryCoverStorageAccountingAdapter({required LibraryCoverStore store})
    : _store = store;

  final LibraryCoverStore _store;

  @override
  StorageBucket get bucket => StorageBucket.libraryCover;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final bytes = await _store.calculateUsageBytes();
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: bytes,
      clearable: false,
      slices: <StorageUsageSlice>[
        if (bytes > 0)
          StorageUsageSlice(
            id: 'library_cover:protected',
            labelRef: StorageUsageLabelRef(
              kind: StorageUsageLabelKind.bucket,
              code: bucket.id,
            ),
            bytes: bytes,
            protected: true,
          ),
      ],
    );
  }
}

class ImageCacheStorageAccountingAdapter implements StorageAccountingAdapter {
  const ImageCacheStorageAccountingAdapter({
    required ImageCacheRepository repository,
  }) : _repository = repository;

  final ImageCacheRepository _repository;

  @override
  StorageBucket get bucket => StorageBucket.imageCache;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final groups = await _repository.calculateUsageGroups();
    final slices = groups
        .map((group) {
          return StorageUsageSlice(
            id: group.id,
            labelRef: StorageUsageLabelRef(
              kind: StorageUsageLabelKind.imageRole,
              code: group.role,
              qualifier: group.retentionClass,
            ),
            bytes: group.bytes,
            protected: group.protected,
          );
        })
        .where((slice) => slice.bytes > 0)
        .toList(growable: false);
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.bytes);
    final categories = _imageCategories(groups);
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: total,
      clearable: slices.any((slice) => !slice.protected),
      slices: slices,
      categories: categories,
    );
  }

  List<StorageUsageCategory> _imageCategories(
    List<ImageCacheUsageGroup> groups,
  ) {
    var clearable = 0;
    var sticky = 0;
    var protectedAssets = 0;
    for (final group in groups) {
      if (group.bytes <= 0) {
        continue;
      }
      if (group.protected ||
          group.retentionClass == ImageRetentionClass.protected.dbValue ||
          group.retentionClass == ImageRetentionClass.downloaded.dbValue) {
        protectedAssets += group.bytes;
      } else if (group.retentionClass == ImageRetentionClass.sticky.dbValue) {
        sticky += group.bytes;
      } else {
        clearable += group.bytes;
      }
    }
    return <StorageUsageCategory>[
      StorageUsageCategory(
        id: 'clearable',
        labelRef: const StorageUsageLabelRef(
          kind: StorageUsageLabelKind.imageCategory,
          code: 'clearable',
        ),
        bytes: clearable,
        clearable: true,
        protected: false,
      ),
      StorageUsageCategory(
        id: 'sticky',
        labelRef: const StorageUsageLabelRef(
          kind: StorageUsageLabelKind.imageCategory,
          code: 'sticky',
        ),
        bytes: sticky,
        clearable: false,
        protected: false,
      ),
      StorageUsageCategory(
        id: 'protected',
        labelRef: const StorageUsageLabelRef(
          kind: StorageUsageLabelKind.imageCategory,
          code: 'protected',
        ),
        bytes: protectedAssets,
        clearable: false,
        protected: true,
      ),
    ].where((category) => category.bytes > 0).toList(growable: false);
  }
}

class PageCacheStorageAccountingAdapter implements StorageAccountingAdapter {
  const PageCacheStorageAccountingAdapter({
    required DocumentCacheService documentCacheService,
    ParsedSnapshotCacheService? snapshotCacheService,
  }) : _documentCacheService = documentCacheService,
       _snapshotCacheService = snapshotCacheService;

  final DocumentCacheService _documentCacheService;
  final ParsedSnapshotCacheService? _snapshotCacheService;

  @override
  StorageBucket get bucket => StorageBucket.pageCache;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final documentSection = await _documentCacheService.calculateUsage();
    final snapshotSection = await _snapshotCacheService?.calculateUsage();
    final sections = <StorageUsageSection>[documentSection, ?snapshotSection];
    final slices = sections
        .expand((section) => section.slices)
        .where((slice) => slice.bytes > 0)
        .toList(growable: false);
    final total = sections.fold<int>(0, (sum, section) => sum + section.bytes);
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: total,
      clearable: slices.any((slice) => !slice.protected),
      slices: slices,
    );
  }
}

class ComposerDraftStorageAccountingAdapter
    implements StorageAccountingAdapter {
  const ComposerDraftStorageAccountingAdapter({
    required Future<Database> Function() databaseProvider,
  }) : _databaseProvider = databaseProvider;

  final Future<Database> Function() _databaseProvider;

  @override
  StorageBucket get bucket => StorageBucket.composerDraft;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final db = await _databaseProvider();
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS draft_count,
        COALESCE(SUM(LENGTH(CAST(snapshot_json AS BLOB))), 0) AS payload_bytes
      FROM ${ComposerDraftLocalDb.draftsTable}
    ''');
    final count = (rows.single['draft_count'] as num?)?.toInt() ?? 0;
    final bytes = (rows.single['payload_bytes'] as num?)?.toInt() ?? 0;
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: bytes,
      clearable: count > 0,
      slices: [
        if (bytes > 0)
          StorageUsageSlice(
            id: 'composer_draft:sqlite',
            labelRef: StorageUsageLabelRef(
              kind: StorageUsageLabelKind.composerDraft,
              code: 'composer_draft',
              count: count,
            ),
            bytes: bytes,
            protected: false,
          ),
      ],
    );
  }
}

class DownloadStorageAccountingAdapter implements StorageAccountingAdapter {
  const DownloadStorageAccountingAdapter({
    required DownloadStorageService storageService,
    required StorageRootAccessGate storageRootAccessGate,
  }) : _storageService = storageService,
       _storageRootAccessGate = storageRootAccessGate;

  final DownloadStorageService _storageService;
  final StorageRootAccessGate _storageRootAccessGate;

  @override
  StorageBucket get bucket => StorageBucket.download;

  @override
  Future<StorageUsageSection> calculateUsage() {
    return _storageRootAccessGate.runWithAccess(_calculateUsage);
  }

  Future<StorageUsageSection> _calculateUsage() async {
    final root = await _storageService.prepareRoot();
    final comics = await _directoryBytes(io.Directory(root.comicsPath));
    final novels = await _directoryBytes(io.Directory(root.novelsPath));
    final favorites = await _fileBytes(io.File(root.favoritesJsonPath));
    final total = comics + novels + favorites;
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: total,
      clearable: false,
      slices: [
        if (comics > 0)
          StorageUsageSlice(
            id: 'download:comics',
            labelRef: const StorageUsageLabelRef(
              kind: StorageUsageLabelKind.downloadKind,
              code: 'comics',
            ),
            bytes: comics,
            protected: true,
          ),
        if (novels > 0)
          StorageUsageSlice(
            id: 'download:novels',
            labelRef: const StorageUsageLabelRef(
              kind: StorageUsageLabelKind.downloadKind,
              code: 'novels',
            ),
            bytes: novels,
            protected: true,
          ),
        if (favorites > 0)
          StorageUsageSlice(
            id: 'download:favorites_snapshot',
            labelRef: const StorageUsageLabelRef(
              kind: StorageUsageLabelKind.downloadKind,
              code: 'favorites_snapshot',
            ),
            bytes: favorites,
            protected: true,
          ),
      ],
    );
  }
}

class LibraryMetadataStorageAccountingAdapter
    implements StorageAccountingAdapter {
  const LibraryMetadataStorageAccountingAdapter({
    Future<Database>? databaseFuture,
    Future<String>? databasePathFuture,
  }) : _databaseFuture = databaseFuture,
       _databasePathFuture = databasePathFuture;

  final Future<Database>? _databaseFuture;
  final Future<String>? _databasePathFuture;

  @override
  StorageBucket get bucket => StorageBucket.libraryMetadata;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final counts = await _loadCounts();
    final dbBytes = await _databaseFileBytes();
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: dbBytes,
      clearable: false,
      slices: [
        if (dbBytes > 0)
          StorageUsageSlice(
            id: 'library_metadata:sqlite',
            labelRef: const StorageUsageLabelRef(
              kind: StorageUsageLabelKind.database,
              code: 'library_metadata',
            ),
            bytes: dbBytes,
            protected: true,
          ),
        ...counts.entries.where((entry) => entry.value > 0).map((entry) {
          return StorageUsageSlice(
            id: 'library_metadata:${entry.key}',
            labelRef: StorageUsageLabelRef(
              kind: StorageUsageLabelKind.libraryKind,
              code: entry.key,
              count: entry.value,
            ),
            bytes: 0,
            protected: true,
          );
        }),
      ],
    );
  }

  Future<Map<String, int>> _loadCounts() async {
    final db = await (_databaseFuture ?? ComicLocalDb.open());
    final tables = <String, String>{
      'comics': ComicLocalDb.comicsTable,
      'comic_episodes': ComicLocalDb.episodesTable,
      'novels': ComicLocalDb.worksTable,
      'novel_episodes': ComicLocalDb.workEpisodesTable,
      'favorites': ComicLocalDb.favoriteThreadsTable,
      'library_work_state': ComicLocalDb.libraryWorkStateTable,
      'library_episode_state': ComicLocalDb.libraryEpisodeStateTable,
    };
    final result = <String, int>{};
    for (final entry in tables.entries) {
      try {
        final rows = await db.rawQuery(
          'SELECT COUNT(*) AS count FROM ${entry.value}',
        );
        result[entry.key] = rows.first['count'] as int? ?? 0;
      } catch (_) {
        result[entry.key] = 0;
      }
    }
    return result;
  }

  Future<int> _databaseFileBytes() async {
    final path =
        await (_databasePathFuture ??
            (() async =>
                p.join(await getDatabasesPath(), ComicLocalDb.dbName))());
    final file = io.File(path);
    if (!await file.exists()) {
      return 0;
    }
    return file.length();
  }
}

class HistoryStorageAccountingAdapter implements StorageAccountingAdapter {
  const HistoryStorageAccountingAdapter({
    Future<Database>? databaseFuture,
    Future<Database> Function()? databaseProvider,
    Future<String>? databasePathFuture,
  }) : _databaseFuture = databaseFuture,
       _databaseProvider = databaseProvider,
       _databasePathFuture = databasePathFuture;

  final Future<Database>? _databaseFuture;
  final Future<Database> Function()? _databaseProvider;
  final Future<String>? _databasePathFuture;

  @override
  StorageBucket get bucket => StorageBucket.history;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final count = await _loadEntryCount();
    final bytes = await _databaseFileBytes();
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: bytes,
      clearable: false,
      slices: <StorageUsageSlice>[
        if (bytes > 0)
          StorageUsageSlice(
            id: 'history:sqlite',
            labelRef: const StorageUsageLabelRef(
              kind: StorageUsageLabelKind.database,
              code: 'history',
            ),
            bytes: bytes,
            protected: true,
          ),
        StorageUsageSlice(
          id: 'history:entries',
          labelRef: StorageUsageLabelRef(
            kind: StorageUsageLabelKind.historyKind,
            code: 'entries',
            count: count,
          ),
          bytes: 0,
          protected: true,
        ),
      ],
    );
  }

  Future<int> _loadEntryCount() async {
    try {
      final db =
          await (_databaseProvider?.call() ??
              _databaseFuture ??
              HistoryLocalDb.open());
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM ${HistoryLocalDb.entriesTable}',
      );
      return rows.first['count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _databaseFileBytes() async {
    final path =
        await (_databasePathFuture ??
            (() async =>
                p.join(await getDatabasesPath(), HistoryLocalDb.dbName))());
    var bytes = 0;
    for (final suffix in const <String>['', '-wal', '-shm']) {
      final file = io.File('$path$suffix');
      if (await file.exists()) {
        bytes += await file.length();
      }
    }
    return bytes;
  }
}

Future<int> _directoryBytes(io.Directory directory) async {
  if (!await directory.exists()) {
    return 0;
  }
  var total = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is io.File) {
      total += await _fileBytes(entity);
    }
  }
  return total;
}

Future<int> _fileBytes(io.File file) async {
  if (!await file.exists()) {
    return 0;
  }
  return file.length();
}
