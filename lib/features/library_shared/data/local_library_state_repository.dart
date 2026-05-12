import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';

/// 基于 SQLite 的统一状态仓储实现。
class LocalLibraryStateRepository implements LibraryStateRepository {
  LocalLibraryStateRepository(this._dbFuture);

  final Future<Database> _dbFuture;

  @override
  Future<void> upsertWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
    String? lastReadEpisodeId,
    DateTime? lastReadAt,
    DateTime? checkUpdatedAt,
    DateTime? fetchedUpdatedAt,
    String? introText,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final contentType = _moduleKeyToContentType(moduleKey);
    final old = await getWorkState(moduleKey: moduleKey, workId: workId);
    await db.insert(
      ComicLocalDb.libraryWorkStateTable,
      <String, Object?>{
        'content_type': contentType,
        'work_id': workId,
        'last_read_episode_id': lastReadEpisodeId ?? old?.lastReadEpisodeId,
        'last_read_at': lastReadAt?.millisecondsSinceEpoch ?? old?.lastReadAt?.millisecondsSinceEpoch,
        'check_updated_at':
            checkUpdatedAt?.millisecondsSinceEpoch ?? old?.checkUpdatedAt?.millisecondsSinceEpoch,
        'fetched_updated_at':
            fetchedUpdatedAt?.millisecondsSinceEpoch ?? old?.fetchedUpdatedAt?.millisecondsSinceEpoch,
        'intro_text': introText ?? old?.introText,
        'created_at': old?.createdAt.millisecondsSinceEpoch ?? now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.libraryWorkStateTable,
      where: 'content_type = ? AND work_id = ?',
      whereArgs: <Object>[
        _moduleKeyToContentType(moduleKey),
        workId,
      ],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return LibraryWorkState(
      moduleKey: moduleKey,
      workId: row['work_id'] as String,
      lastReadEpisodeId: row['last_read_episode_id'] as String?,
      lastReadAt: _toDateTime(row['last_read_at']),
      checkUpdatedAt: _toDateTime(row['check_updated_at']),
      fetchedUpdatedAt: _toDateTime(row['fetched_updated_at']),
      introText: row['intro_text'] as String?,
      createdAt: _toDateTime(row['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _toDateTime(row['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  Future<void> upsertEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
    required String workId,
    bool? isRead,
    bool? isDownloaded,
    bool? isBookmarked,
    DateTime? readAt,
    DateTime? downloadedAt,
  }) async {
    final db = await _dbFuture;
    final old = await getEpisodeState(moduleKey: moduleKey, episodeId: episodeId);
    final nextRead = isRead ?? old?.isRead ?? false;
    final nextDownloaded = isDownloaded ?? old?.isDownloaded ?? false;
    final nextBookmarked = isBookmarked ?? old?.isBookmarked ?? false;
    final nextReadAt = isRead == false
        ? null
        : readAt?.millisecondsSinceEpoch ?? old?.readAt?.millisecondsSinceEpoch;

    await db.insert(
      ComicLocalDb.libraryEpisodeStateTable,
      <String, Object?>{
        'content_type': _moduleKeyToContentType(moduleKey),
        'episode_id': episodeId,
        'work_id': workId,
        'is_read': nextRead ? 1 : 0,
        'is_downloaded': nextDownloaded ? 1 : 0,
        'is_bookmarked': nextBookmarked ? 1 : 0,
        'read_at': nextReadAt,
        'downloaded_at':
            downloadedAt?.millisecondsSinceEpoch ?? old?.downloadedAt?.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.libraryEpisodeStateTable,
      where: 'content_type = ? AND episode_id = ?',
      whereArgs: <Object>[
        _moduleKeyToContentType(moduleKey),
        episodeId,
      ],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return LibraryEpisodeState(
      moduleKey: moduleKey,
      episodeId: row['episode_id'] as String,
      workId: row['work_id'] as String,
      isRead: (row['is_read'] as int? ?? 0) == 1,
      isDownloaded: (row['is_downloaded'] as int? ?? 0) == 1,
      isBookmarked: (row['is_bookmarked'] as int? ?? 0) == 1,
      readAt: _toDateTime(row['read_at']),
      downloadedAt: _toDateTime(row['downloaded_at']),
    );
  }

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM ${ComicLocalDb.libraryEpisodeStateTable}
      WHERE content_type = ? AND work_id = ? AND is_read = 0
      ''',
      <Object>[
        _moduleKeyToContentType(moduleKey),
        workId,
      ],
    );
    return rows.first['count'] as int? ?? 0;
  }

  @override
  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM ${ComicLocalDb.libraryEpisodeStateTable}
      WHERE content_type = ? AND work_id = ? AND is_read = 1
      ''',
      <Object>[
        _moduleKeyToContentType(moduleKey),
        workId,
      ],
    );
    return rows.first['count'] as int? ?? 0;
  }

  @override
  Future<int> countDownloadedEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM ${ComicLocalDb.libraryEpisodeStateTable}
      WHERE content_type = ? AND work_id = ? AND is_downloaded = 1
      ''',
      <Object>[
        _moduleKeyToContentType(moduleKey),
        workId,
      ],
    );
    return rows.first['count'] as int? ?? 0;
  }

  @override
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {
    final db = await _dbFuture;
    await db.insert(
      ComicLocalDb.libraryDisplaySettingsTable,
      <String, Object?>{
        'module_key': _moduleKeyToContentType(moduleKey),
        'display_mode': _displayModeToDbValue(displayMode),
        'grid_columns': _normalizeGridColumns(gridColumns),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.libraryDisplaySettingsTable,
      where: 'module_key = ?',
      whereArgs: <Object>[_moduleKeyToContentType(moduleKey)],
      limit: 1,
    );
    if (rows.isEmpty) {
      return LibraryModuleDisplaySettings(
        moduleKey: moduleKey,
        displayMode: defaultDisplayMode,
        gridColumns: 3,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
    final row = rows.first;
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: _displayModeFromDbValue(row['display_mode'] as String?),
      gridColumns: _normalizeGridColumns(row['grid_columns'] as int? ?? 3),
      updatedAt: _toDateTime(row['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  Future<String> createTag({required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('标签名称不能为空');
    }
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tagId = 'tag_$now${Random().nextInt(1000)}';
    await db.insert(
      ComicLocalDb.libraryTagsTable,
      <String, Object?>{
        'tag_id': tagId,
        'name': trimmed,
        'created_at': now,
      },
    );
    return tagId;
  }

  @override
  Future<List<LibraryTag>> getTags() async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.libraryTagsTable,
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (row) => LibraryTag(
            tagId: row['tag_id'] as String,
            name: row['name'] as String,
            createdAt: _toDateTime(row['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> renameTag({
    required String tagId,
    required String newName,
  }) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('标签名称不能为空');
    }
    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.libraryTagsTable,
      <String, Object?>{'name': trimmed},
      where: 'tag_id = ?',
      whereArgs: <Object>[tagId],
    );
  }

  @override
  Future<void> deleteTag({required String tagId}) async {
    final db = await _dbFuture;
    await db.transaction((txn) async {
      await txn.delete(
        ComicLocalDb.libraryWorkTagsTable,
        where: 'tag_id = ?',
        whereArgs: <Object>[tagId],
      );
      await txn.delete(
        ComicLocalDb.libraryTagsTable,
        where: 'tag_id = ?',
        whereArgs: <Object>[tagId],
      );
    });
  }

  @override
  Future<void> bindTagToWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {
    final db = await _dbFuture;
    await db.insert(
      ComicLocalDb.libraryWorkTagsTable,
      <String, Object?>{
        'content_type': _moduleKeyToContentType(moduleKey),
        'work_id': workId,
        'tag_id': tagId,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> unbindTagFromWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {
    final db = await _dbFuture;
    await db.delete(
      ComicLocalDb.libraryWorkTagsTable,
      where: 'content_type = ? AND work_id = ? AND tag_id = ?',
      whereArgs: <Object>[
        _moduleKeyToContentType(moduleKey),
        workId,
        tagId,
      ],
    );
  }

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT t.tag_id, t.name, t.created_at
      FROM ${ComicLocalDb.libraryWorkTagsTable} wt
      INNER JOIN ${ComicLocalDb.libraryTagsTable} t
        ON t.tag_id = wt.tag_id
      WHERE wt.content_type = ? AND wt.work_id = ?
      ORDER BY t.created_at ASC
      ''',
      <Object>[
        _moduleKeyToContentType(moduleKey),
        workId,
      ],
    );
    return rows
        .map(
          (row) => LibraryTag(
            tagId: row['tag_id'] as String,
            name: row['name'] as String,
            createdAt: _toDateTime(row['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT 1
      FROM ${ComicLocalDb.libraryWorkTagsTable}
      WHERE content_type = ? AND work_id = ?
      LIMIT 1
      ''',
      <Object>[
        _moduleKeyToContentType(moduleKey),
        workId,
      ],
    );
    return rows.isNotEmpty;
  }

  String _moduleKeyToContentType(LibraryModuleKey key) {
    switch (key) {
      case LibraryModuleKey.comic:
        return 'comic';
      case LibraryModuleKey.novel:
        return 'novel';
      case LibraryModuleKey.favorite:
        return 'favorite';
    }
  }

  LibraryDisplayMode _displayModeFromDbValue(String? value) {
    if (value == 'list') {
      return LibraryDisplayMode.list;
    }
    return LibraryDisplayMode.grid;
  }

  String _displayModeToDbValue(LibraryDisplayMode mode) {
    switch (mode) {
      case LibraryDisplayMode.grid:
        return 'grid';
      case LibraryDisplayMode.list:
        return 'list';
    }
  }

  int _normalizeGridColumns(int value) {
    if (value < 1) {
      return 1;
    }
    if (value > 3) {
      return 3;
    }
    return value;
  }

  DateTime? _toDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }
}
