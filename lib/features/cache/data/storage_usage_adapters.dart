import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/data/image_cache_repository.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/composer_shared/data/shared_preferences_composer_draft_repository.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

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
            label: _imageGroupLabel(group),
            bytes: group.bytes,
            protected: group.protected,
          );
        })
        .where((slice) => slice.bytes > 0)
        .toList(growable: false);
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.bytes);
    return StorageUsageSection(
      bucket: bucket,
      label: bucket.label,
      bytes: total,
      clearable: slices.any((slice) => !slice.protected),
      slices: slices,
    );
  }

  String _imageGroupLabel(ImageCacheUsageGroup group) {
    final role = switch (group.role) {
      'cover' => '封面',
      'custom_cover' => '自定义封面',
      'comic_page' => '漫画页',
      'novel_inline' => '小说正文图',
      'thread_inline' => '帖子图片',
      'thread_attachment' => '帖子附件图',
      'avatar' => '头像',
      'remote_smiley' => '表情图片',
      'forum_head_image' => '论坛头图',
      'forum_icon' => '论坛图标',
      'blog_inline' => '日志图片',
      _ => group.role.isEmpty ? '未分类图片' : group.role,
    };
    final retention = switch (group.retentionClass) {
      'ephemeral' => '',
      'recent_reader' => '（最近阅读）',
      'sticky' => '（低淘汰）',
      'protected' => '（受保护）',
      'downloaded' => '（已下载）',
      _ => group.retentionClass.isEmpty ? '' : '（${group.retentionClass}）',
    };
    if (retention.isNotEmpty) {
      return '$role$retention';
    }
    return group.protected ? '$role（受保护）' : role;
  }
}

class ComposerDraftStorageAccountingAdapter
    implements StorageAccountingAdapter {
  const ComposerDraftStorageAccountingAdapter({
    SharedPreferences? sharedPreferences,
  }) : _sharedPreferences = sharedPreferences;

  final SharedPreferences? _sharedPreferences;

  @override
  StorageBucket get bucket => StorageBucket.composerDraft;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final prefs = _sharedPreferences ?? await SharedPreferences.getInstance();
    var bytes = 0;
    var count = 0;
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(
        SharedPreferencesComposerDraftRepository.draftKeyPrefix,
      )) {
        continue;
      }
      count += 1;
      bytes += _roughUtf8Bytes(key);
      final value = prefs.getString(key);
      if (value != null) {
        bytes += _roughUtf8Bytes(value);
      }
    }
    return StorageUsageSection(
      bucket: bucket,
      label: bucket.label,
      bytes: bytes,
      clearable: count > 0,
      slices: [
        if (bytes > 0)
          StorageUsageSlice(
            id: 'composer_draft:prefs',
            label: '发帖/回复草稿（$count）',
            bytes: bytes,
            protected: false,
          ),
      ],
    );
  }

  int _roughUtf8Bytes(String value) {
    return utf8.encode(value).length;
  }
}

class DownloadStorageAccountingAdapter implements StorageAccountingAdapter {
  const DownloadStorageAccountingAdapter({
    required DownloadStorageService storageService,
  }) : _storageService = storageService;

  final DownloadStorageService _storageService;

  @override
  StorageBucket get bucket => StorageBucket.download;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final root = await _storageService.prepareRoot();
    final comics = await _directoryBytes(io.Directory(root.comicsPath));
    final novels = await _directoryBytes(io.Directory(root.novelsPath));
    final favorites = await _fileBytes(io.File(root.favoritesJsonPath));
    final total = comics + novels + favorites;
    return StorageUsageSection(
      bucket: bucket,
      label: bucket.label,
      bytes: total,
      clearable: false,
      slices: [
        if (comics > 0)
          StorageUsageSlice(
            id: 'download:comics',
            label: '漫画下载',
            bytes: comics,
            protected: true,
          ),
        if (novels > 0)
          StorageUsageSlice(
            id: 'download:novels',
            label: '小说下载',
            bytes: novels,
            protected: true,
          ),
        if (favorites > 0)
          StorageUsageSlice(
            id: 'download:favorites_snapshot',
            label: '收藏快照',
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
      label: bucket.label,
      bytes: dbBytes,
      clearable: false,
      slices: [
        if (dbBytes > 0)
          StorageUsageSlice(
            id: 'library_metadata:sqlite',
            label: '本地数据库',
            bytes: dbBytes,
            protected: true,
          ),
        ...counts.entries.where((entry) => entry.value > 0).map((entry) {
          return StorageUsageSlice(
            id: 'library_metadata:${entry.key}',
            label: _countLabel(entry.key, entry.value),
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

  String _countLabel(String key, int count) {
    final label = switch (key) {
      'comics' => '漫画作品',
      'comic_episodes' => '漫画章节',
      'novels' => '小说作品',
      'novel_episodes' => '小说章节',
      'favorites' => '收藏帖子',
      'library_work_state' => '作品状态',
      'library_episode_state' => '章节状态',
      _ => key,
    };
    return '$label：$count';
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
