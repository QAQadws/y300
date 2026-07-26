import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/data/local/comic_cover_store.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_local_models.dart';

class ComicDuplicateMergeStore {
  ComicDuplicateMergeStore(
    this._dbFuture, {
    required ComicCoverStore coverStore,
  }) : _coverStore = coverStore;

  final Future<Database> _dbFuture;
  final ComicCoverStore _coverStore;

  Future<List<ComicDuplicateGroup>> findDuplicateGroups({
    String? comicId,
  }) async {
    final db = await _dbFuture;
    final normalizedComicId = _normalizeNullable(comicId);
    final rows = await db.rawQuery('''
      SELECT comic_id, source_tid
      FROM ${ComicLocalDb.episodesTable}
      UNION ALL
      SELECT comic_id, source_tid
      FROM ${ComicLocalDb.comicsTable}
      ''');
    if (rows.isEmpty) {
      return const <ComicDuplicateGroup>[];
    }

    final comicIdsByTid = <String, Set<String>>{};
    final tidsByComicId = <String, Set<String>>{};
    for (final row in rows) {
      final rowComicId = _normalizeNullable(row['comic_id'] as String?);
      final sourceTid = _normalizeNullable(row['source_tid'] as String?);
      if (rowComicId == null || sourceTid == null) {
        continue;
      }
      comicIdsByTid.putIfAbsent(sourceTid, () => <String>{}).add(rowComicId);
      tidsByComicId.putIfAbsent(rowComicId, () => <String>{}).add(sourceTid);
    }

    final candidateComicIds = normalizedComicId == null
        ? tidsByComicId.keys.toSet()
        : <String>{normalizedComicId};
    final visited = <String>{};
    final groups = <ComicDuplicateGroup>[];
    for (final startComicId in candidateComicIds) {
      if (!tidsByComicId.containsKey(startComicId) ||
          visited.contains(startComicId)) {
        continue;
      }
      final groupComicIds = <String>{};
      final groupTids = <String>{};
      final queue = <String>[startComicId];
      visited.add(startComicId);
      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        groupComicIds.add(current);
        for (final tid in tidsByComicId[current] ?? const <String>{}) {
          groupTids.add(tid);
          for (final neighbor in comicIdsByTid[tid] ?? const <String>{}) {
            if (visited.add(neighbor)) {
              queue.add(neighbor);
            }
          }
        }
      }
      if (groupComicIds.length > 1) {
        groups.add(
          ComicDuplicateGroup(
            comicIds: Set<String>.unmodifiable(groupComicIds),
            sharedTids: Set<String>.unmodifiable(
              groupTids.where((tid) => (comicIdsByTid[tid]?.length ?? 0) > 1),
            ),
          ),
        );
      }
    }
    return groups;
  }

  Future<ComicDuplicateMergeResult> mergeDuplicateGroup({
    required Set<String> comicIds,
  }) async {
    final normalizedIds = comicIds
        .map(_normalizeNullable)
        .whereType<String>()
        .toSet();
    if (normalizedIds.length <= 1) {
      return ComicDuplicateMergeResult.unchanged(
        targetComicId: normalizedIds.isEmpty ? '' : normalizedIds.first,
      );
    }

    final db = await _dbFuture;
    return db.transaction<ComicDuplicateMergeResult>((txn) async {
      final comics = await _loadComicRecords(txn, normalizedIds);
      if (comics.length <= 1) {
        return ComicDuplicateMergeResult.unchanged(
          targetComicId: comics.isEmpty
              ? normalizedIds.first
              : comics.first.comicId,
        );
      }

      final target = chooseDuplicateMergeTarget(comics);
      final sourceIds = comics
          .map((comic) => comic.comicId)
          .where((id) => id != target.comicId)
          .toSet();
      var movedEpisodeCount = 0;
      for (final sourceComicId in sourceIds) {
        movedEpisodeCount += await mergeSourceComicIntoTarget(
          txn,
          sourceComicId: sourceComicId,
          targetComicId: target.comicId,
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await _updateMergedComicMetadata(
        txn,
        target: target,
        sources: comics
            .where((comic) => sourceIds.contains(comic.comicId))
            .toList(growable: false),
        now: now,
      );
      await _updateMergedComicEpisodeOrder(txn, comicId: target.comicId);
      await _moveShelfRowsToTarget(
        txn,
        sourceComicIds: sourceIds,
        targetComicId: target.comicId,
      );
      await _moveExternalComicReferencesToTarget(
        txn,
        sourceComicIds: sourceIds,
        targetComicId: target.comicId,
      );
      await txn.delete(
        ComicLocalDb.comicsTable,
        where: _whereIn('comic_id', sourceIds.length),
        whereArgs: sourceIds.toList(growable: false),
      );

      return ComicDuplicateMergeResult(
        targetComicId: target.comicId,
        targetTitle: _shortestDisplayTitle(comics),
        mergedComicIds: Set<String>.unmodifiable(sourceIds),
        replacements: Map<String, String>.unmodifiable(<String, String>{
          for (final sourceComicId in sourceIds) sourceComicId: target.comicId,
        }),
        movedEpisodeCount: movedEpisodeCount,
      );
    });
  }

  Future<List<ComicRecord>> _loadComicRecords(
    Transaction txn,
    Set<String> comicIds,
  ) async {
    if (comicIds.isEmpty) {
      return const <ComicRecord>[];
    }
    final rows = await txn.query(
      ComicLocalDb.comicsTable,
      where: _whereIn('comic_id', comicIds.length),
      whereArgs: comicIds.toList(growable: false),
    );
    return rows.map(ComicRecord.fromMap).toList(growable: false);
  }

  ComicRecord chooseDuplicateMergeTarget(List<ComicRecord> comics) {
    final sorted = comics.toList(growable: false)
      ..sort((a, b) {
        final titleOrder = _titleLength(
          a.title,
        ).compareTo(_titleLength(b.title));
        if (titleOrder != 0) {
          return titleOrder;
        }
        final createdOrder = a.createdAt.compareTo(b.createdAt);
        if (createdOrder != 0) {
          return createdOrder;
        }
        return a.comicId.compareTo(b.comicId);
      });
    return sorted.first;
  }

  String _shortestDisplayTitle(List<ComicRecord> comics) {
    return chooseDuplicateMergeTarget(comics).title;
  }

  int _titleLength(String title) {
    final trimmed = title.trim();
    return trimmed.isEmpty ? 1 << 30 : trimmed.runes.length;
  }

  Future<int> mergeSourceComicIntoTarget(
    Transaction txn, {
    required String sourceComicId,
    required String targetComicId,
  }) async {
    final sourceEpisodes = await txn.query(
      ComicLocalDb.episodesTable,
      where: 'comic_id = ?',
      whereArgs: <Object>[sourceComicId],
      orderBy: 'order_index ASC, episode_id ASC',
    );
    var moved = 0;
    for (final row in sourceEpisodes) {
      final sourceEpisodeId = row['episode_id'] as String;
      final sourceTid = row['source_tid'] as String;
      final targetEpisodeId = '$targetComicId:$sourceTid';
      final existingRows = await txn.query(
        ComicLocalDb.episodesTable,
        where: 'episode_id = ?',
        whereArgs: <Object>[targetEpisodeId],
        limit: 1,
      );

      if (existingRows.isEmpty) {
        await txn.insert(ComicLocalDb.episodesTable, <String, Object?>{
          ...row,
          'episode_id': targetEpisodeId,
          'comic_id': targetComicId,
        });
        await _mergeEpisodeStateIntoTarget(
          txn,
          sourceEpisodeId: sourceEpisodeId,
          targetEpisodeId: targetEpisodeId,
          targetComicId: targetComicId,
        );
        await _moveEpisodeChildrenToTarget(
          txn,
          sourceEpisodeId: sourceEpisodeId,
          targetEpisodeId: targetEpisodeId,
          targetComicId: targetComicId,
          moveEpisodeState: false,
        );
        await txn.delete(
          ComicLocalDb.episodesTable,
          where: 'episode_id = ?',
          whereArgs: <Object>[sourceEpisodeId],
        );
        moved++;
      } else {
        await _preferEpisodeMetadata(
          txn,
          existing: existingRows.first,
          incoming: row,
        );
        await _mergeEpisodeStateIntoTarget(
          txn,
          sourceEpisodeId: sourceEpisodeId,
          targetEpisodeId: targetEpisodeId,
          targetComicId: targetComicId,
        );
        await _moveEpisodeChildrenToTarget(
          txn,
          sourceEpisodeId: sourceEpisodeId,
          targetEpisodeId: targetEpisodeId,
          targetComicId: targetComicId,
          moveEpisodeState: false,
        );
        await txn.delete(
          ComicLocalDb.episodesTable,
          where: 'episode_id = ?',
          whereArgs: <Object>[sourceEpisodeId],
        );
      }
    }
    return moved;
  }

  Future<void> _preferEpisodeMetadata(
    Transaction txn, {
    required Map<String, Object?> existing,
    required Map<String, Object?> incoming,
  }) async {
    final existingSourceTitle = _normalizeNullable(
      existing['source_episode_title'] as String?,
    );
    final incomingSourceTitle = _normalizeNullable(
      incoming['source_episode_title'] as String?,
    );
    final existingUrl = _normalizeNullable(existing['source_url'] as String?);
    final incomingUrl = _normalizeNullable(incoming['source_url'] as String?);
    final update = <String, Object?>{};
    // 沿用“信息量更大的来源名胜出”，但只作用在来源列上。
    final sourceTitle =
        (incomingSourceTitle != null &&
            (existingSourceTitle == null ||
                incomingSourceTitle.length > existingSourceTitle.length))
        ? incomingSourceTitle
        : existingSourceTitle;
    if (sourceTitle != existingSourceTitle) {
      update['source_episode_title'] = sourceTitle;
    }
    // 重命名是用户意图，两侧取其一保留；来源名换了也要重算展示名。
    final customTitle =
        _normalizeNullable(existing['custom_episode_title'] as String?) ??
        _normalizeNullable(incoming['custom_episode_title'] as String?);
    if (customTitle != _normalizeNullable(
      existing['custom_episode_title'] as String?,
    )) {
      update['custom_episode_title'] = customTitle;
    }
    final displayTitle = resolveEpisodeDisplayTitle(
      customEpisodeTitle: customTitle,
      sourceEpisodeTitle: sourceTitle,
    );
    if (displayTitle != _normalizeNullable(existing['episode_title'] as String?)) {
      update['episode_title'] = displayTitle;
    }
    if (incomingUrl != null && (existingUrl == null || existingUrl.isEmpty)) {
      update['source_url'] = incomingUrl;
    }
    final publishTimeText =
        _normalizeNullable(existing['publish_time_text'] as String?) ??
        _normalizeNullable(incoming['publish_time_text'] as String?);
    if (publishTimeText != null) {
      update['publish_time_text'] = publishTimeText;
    }
    // A parsed source wins over a manual-only copy: once either side is
    // parse-discovered the chapter comes back on every refresh, so keeping it
    // removable would promise a deletion that cannot hold.
    final existingIsManual = (existing['is_manual'] as int? ?? 0) == 1;
    final incomingIsManual = (incoming['is_manual'] as int? ?? 0) == 1;
    if (existingIsManual && !incomingIsManual) {
      update['is_manual'] = 0;
    }
    // Hidden is user intent and must survive a merge from either side.
    final isHidden =
        (existing['is_hidden'] as int? ?? 0) == 1 ||
        (incoming['is_hidden'] as int? ?? 0) == 1;
    if (isHidden) {
      update['is_hidden'] = 1;
    }
    if (update.isEmpty) {
      return;
    }
    await txn.update(
      ComicLocalDb.episodesTable,
      update,
      where: 'episode_id = ?',
      whereArgs: <Object>[existing['episode_id'] as String],
    );
  }

  Future<void> _moveEpisodeChildrenToTarget(
    Transaction txn, {
    required String sourceEpisodeId,
    required String targetEpisodeId,
    required String targetComicId,
    bool moveEpisodeState = true,
  }) async {
    // Only reparent images if the target episode has none yet. When both
    // episodes are from the same source thread, their image lists are
    // identical — keeping the target's copy and discarding the source's
    // avoids duplicates. The source images are removed by cascade when the
    // source episode row is deleted at the end of mergeSourceComicIntoTarget.
    final targetImageCount =
        (await txn.rawQuery(
              'SELECT COUNT(*) AS c FROM ${ComicLocalDb.episodeImagesTable} WHERE episode_id = ?',
              <Object>[targetEpisodeId],
            )).first['c']
            as int? ??
        0;
    if (targetImageCount == 0) {
      await txn.update(
        ComicLocalDb.episodeImagesTable,
        <String, Object?>{
          'episode_id': targetEpisodeId,
          'stable_cache_key': null,
        },
        where: 'episode_id = ?',
        whereArgs: <Object>[sourceEpisodeId],
      );
    }
    await txn.update(
      ComicLocalDb.readingProgressTable,
      <String, Object?>{'episode_id': targetEpisodeId},
      where: 'episode_id = ?',
      whereArgs: <Object>[sourceEpisodeId],
    );
    await txn.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{'last_read_episode_id': targetEpisodeId},
      where: 'last_read_episode_id = ?',
      whereArgs: <Object>[sourceEpisodeId],
    );
    await txn.update(
      ComicLocalDb.libraryWorkStateTable,
      <String, Object?>{'last_read_episode_id': targetEpisodeId},
      where: 'content_type = ? AND last_read_episode_id = ?',
      whereArgs: <Object>['comic', sourceEpisodeId],
    );
    if (!moveEpisodeState) {
      return;
    }
    await txn.update(
      ComicLocalDb.libraryEpisodeStateTable,
      <String, Object?>{
        'episode_id': targetEpisodeId,
        'work_id': targetComicId,
      },
      where: 'content_type = ? AND episode_id = ?',
      whereArgs: <Object>['comic', sourceEpisodeId],
    );
  }

  Future<void> _mergeEpisodeStateIntoTarget(
    Transaction txn, {
    required String sourceEpisodeId,
    required String targetEpisodeId,
    required String targetComicId,
  }) async {
    final sourceRows = await txn.query(
      ComicLocalDb.libraryEpisodeStateTable,
      where: 'content_type = ? AND episode_id = ?',
      whereArgs: <Object>['comic', sourceEpisodeId],
      limit: 1,
    );
    if (sourceRows.isEmpty) {
      return;
    }
    final source = sourceRows.first;
    final targetRows = await txn.query(
      ComicLocalDb.libraryEpisodeStateTable,
      where: 'content_type = ? AND episode_id = ?',
      whereArgs: <Object>['comic', targetEpisodeId],
      limit: 1,
    );
    if (targetRows.isEmpty) {
      await txn.update(
        ComicLocalDb.libraryEpisodeStateTable,
        <String, Object?>{
          'episode_id': targetEpisodeId,
          'work_id': targetComicId,
        },
        where: 'content_type = ? AND episode_id = ?',
        whereArgs: <Object>['comic', sourceEpisodeId],
      );
      return;
    }

    final target = targetRows.first;
    await txn.update(
      ComicLocalDb.libraryEpisodeStateTable,
      <String, Object?>{
        'work_id': targetComicId,
        'is_read': _maxInt(target['is_read'], source['is_read']),
        'is_downloaded': _maxInt(
          target['is_downloaded'],
          source['is_downloaded'],
        ),
        'is_bookmarked': _maxInt(
          target['is_bookmarked'],
          source['is_bookmarked'],
        ),
        'read_at': _maxNullableInt(target['read_at'], source['read_at']),
        'downloaded_at': _maxNullableInt(
          target['downloaded_at'],
          source['downloaded_at'],
        ),
      },
      where: 'content_type = ? AND episode_id = ?',
      whereArgs: <Object>['comic', targetEpisodeId],
    );
    await txn.delete(
      ComicLocalDb.libraryEpisodeStateTable,
      where: 'content_type = ? AND episode_id = ?',
      whereArgs: <Object>['comic', sourceEpisodeId],
    );
  }

  Future<void> _updateMergedComicMetadata(
    Transaction txn, {
    required ComicRecord target,
    required List<ComicRecord> sources,
    required int now,
  }) async {
    final all = <ComicRecord>[target, ...sources];
    final shortestTitle = _shortestDisplayTitle(all);
    await txn.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{
        'title': shortestTitle,
        'source_title': _firstNormalized(<String?>[
          shortestTitle,
          target.sourceTitle,
          for (final source in sources) source.sourceTitle,
        ]),
        'custom_title': null,
        'custom_search_title': _firstNormalized(<String?>[
          target.customSearchTitle,
          for (final source in sources) source.customSearchTitle,
        ]),
        'author': _firstNormalized(<String?>[
          target.author,
          for (final source in sources) source.author,
        ]),
        'source_author': _firstNormalized(<String?>[
          target.sourceAuthor,
          for (final source in sources) source.sourceAuthor,
        ]),
        'translation_group': _firstNormalized(<String?>[
          target.translationGroup,
          for (final source in sources) source.translationGroup,
        ]),
        'source_translation_group': _firstNormalized(<String?>[
          target.sourceTranslationGroup,
          for (final source in sources) source.sourceTranslationGroup,
        ]),
        'cover_image_url': _firstNormalized(<String?>[
          target.coverImageUrl,
          for (final source in sources) source.coverImageUrl,
        ]),
        'custom_cover_image_url': _firstNormalized(<String?>[
          target.customCoverImageUrl,
          for (final source in sources) source.customCoverImageUrl,
        ]),
        'cover_local_path': _firstNormalized(<String?>[
          target.coverLocalPath,
          for (final source in sources) source.coverLocalPath,
        ]),
        'custom_cover_local_path': _firstNormalized(<String?>[
          target.customCoverLocalPath,
          for (final source in sources) source.customCoverLocalPath,
        ]),
        'custom_cover_source_episode_id': _remapMergedEpisodeId(
          _firstNormalized(<String?>[
            target.customCoverSourceEpisodeId,
            for (final source in sources) source.customCoverSourceEpisodeId,
          ]),
          targetComicId: target.comicId,
        ),
        'custom_cover_source_image_index': _firstInt(<int?>[
          target.customCoverSourceImageIndex,
          for (final source in sources) source.customCoverSourceImageIndex,
        ]),
        'custom_cover_source_image_url': _firstNormalized(<String?>[
          target.customCoverSourceImageUrl,
          for (final source in sources) source.customCoverSourceImageUrl,
        ]),
        'metadata_updated_at': now,
        'updated_at': now,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[target.comicId],
    );
  }

  String? _remapMergedEpisodeId(
    String? episodeId, {
    required String targetComicId,
  }) {
    final normalized = _normalizeNullable(episodeId);
    if (normalized == null) {
      return null;
    }
    final lastColon = normalized.lastIndexOf(':');
    if (lastColon <= 0 || lastColon == normalized.length - 1) {
      return normalized;
    }
    final sourceTid = normalized.substring(lastColon + 1);
    return '$targetComicId:$sourceTid';
  }

  Future<void> _updateMergedComicEpisodeOrder(
    Transaction txn, {
    required String comicId,
  }) async {
    final rows = await txn.query(
      ComicLocalDb.episodesTable,
      columns: const <String>['episode_id', 'source_tid', 'order_index'],
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
    final ordered = rows.toList(growable: true)
      ..sort(_coverStore.compareEpisodeRowsByFirstTid);
    for (var index = 0; index < ordered.length; index++) {
      await txn.update(
        ComicLocalDb.episodesTable,
        <String, Object?>{'order_index': index},
        where: 'episode_id = ?',
        whereArgs: <Object>[ordered[index]['episode_id'] as String],
      );
    }
  }

  Future<void> _moveShelfRowsToTarget(
    Transaction txn, {
    required Set<String> sourceComicIds,
    required String targetComicId,
  }) async {
    if (sourceComicIds.isEmpty) {
      return;
    }
    final rows = await txn.query(
      ComicLocalDb.shelfItemsTable,
      where: _whereIn('comic_id', sourceComicIds.length),
      whereArgs: sourceComicIds.toList(growable: false),
      orderBy: 'added_at ASC, sort_order ASC',
    );
    for (final row in rows) {
      final categoryId = row['category_id'] as String;
      final existing = await txn.query(
        ComicLocalDb.shelfItemsTable,
        columns: const <String>['id'],
        where: 'category_id = ? AND comic_id = ?',
        whereArgs: <Object>[categoryId, targetComicId],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert(
          ComicLocalDb.shelfItemsTable,
          <String, Object?>{
            'category_id': categoryId,
            'comic_id': targetComicId,
            'added_at': row['added_at'],
            'sort_order': row['sort_order'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    await txn.delete(
      ComicLocalDb.shelfItemsTable,
      where: _whereIn('comic_id', sourceComicIds.length),
      whereArgs: sourceComicIds.toList(growable: false),
    );
  }

  Future<void> _moveExternalComicReferencesToTarget(
    Transaction txn, {
    required Set<String> sourceComicIds,
    required String targetComicId,
  }) async {
    if (sourceComicIds.isEmpty) {
      return;
    }
    final args = sourceComicIds.toList(growable: false);
    final where = _whereIn('work_id', sourceComicIds.length);
    await _mergeWorkStateRowsToTarget(
      txn,
      sourceComicIds: sourceComicIds,
      targetComicId: targetComicId,
    );
    await _mergeWorkTagsToTarget(
      txn,
      sourceComicIds: sourceComicIds,
      targetComicId: targetComicId,
    );
    await txn.update(
      ComicLocalDb.favoriteThreadsTable,
      <String, Object?>{'work_id': targetComicId},
      where: where,
      whereArgs: args,
    );
    await _mergeCachedImagesToTarget(
      txn,
      sourceComicIds: sourceComicIds,
      targetComicId: targetComicId,
    );
    await txn.update(
      ComicLocalDb.comicSearchRefreshQueueTable,
      <String, Object?>{'comic_id': targetComicId},
      where: _whereIn('comic_id', sourceComicIds.length),
      whereArgs: args,
    );
    await _mergeReadingProgressToTarget(
      txn,
      sourceComicIds: sourceComicIds,
      targetComicId: targetComicId,
    );
  }

  Future<void> _mergeCachedImagesToTarget(
    Transaction txn, {
    required Set<String> sourceComicIds,
    required String targetComicId,
  }) async {
    final args = sourceComicIds.toList(growable: false);
    await txn.update(
      ComicLocalDb.cachedImagesTable,
      <String, Object?>{'owner_id': targetComicId},
      where: 'owner_type = ? AND ${_whereIn('owner_id', args.length)}',
      whereArgs: <Object>['comic', ...args],
    );
  }

  Future<void> _mergeWorkStateRowsToTarget(
    Transaction txn, {
    required Set<String> sourceComicIds,
    required String targetComicId,
  }) async {
    final args = sourceComicIds.toList(growable: false);
    final rows = await txn.query(
      ComicLocalDb.libraryWorkStateTable,
      where: 'content_type = ? AND ${_whereIn('work_id', args.length + 1)}',
      whereArgs: <Object>['comic', targetComicId, ...args],
    );
    if (rows.isEmpty) {
      return;
    }

    Map<String, Object?>? target;
    for (final row in rows) {
      if (row['work_id'] == targetComicId) {
        target = row;
        break;
      }
    }
    target ??= <String, Object?>{
      'content_type': 'comic',
      'work_id': targetComicId,
      'created_at': rows
          .map((row) => row['created_at'])
          .whereType<int>()
          .fold<int>(
            DateTime.now().millisecondsSinceEpoch,
            (minValue, value) => value < minValue ? value : minValue,
          ),
      'updated_at': 0,
    };
    final Map<String, Object?> targetRow = target;

    String? pickFirst(String column) {
      final value = _firstObject(<Object?>[
        targetRow[column],
        for (final row in rows)
          if (row['work_id'] != targetComicId) row[column],
      ]);
      return value is String ? _normalizeNullable(value) : null;
    }

    int? pickLatest(String column) {
      Object? latest = targetRow[column];
      for (final row in rows) {
        if (row['work_id'] == targetComicId) {
          continue;
        }
        latest = _maxNullableInt(latest, row[column]);
      }
      return latest is int ? latest : null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await txn.insert(
      ComicLocalDb.libraryWorkStateTable,
      <String, Object?>{
        'content_type': 'comic',
        'work_id': targetComicId,
        'last_read_episode_id': pickFirst('last_read_episode_id'),
        'last_read_at': pickLatest('last_read_at'),
        'check_updated_at': pickLatest('check_updated_at'),
        'fetched_updated_at': pickLatest('fetched_updated_at'),
        'intro_text': pickFirst('intro_text'),
        'created_at': targetRow['created_at'] as int? ?? now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await txn.delete(
      ComicLocalDb.libraryWorkStateTable,
      where: 'content_type = ? AND ${_whereIn('work_id', args.length)}',
      whereArgs: <Object>['comic', ...args],
    );
  }

  Future<void> _mergeWorkTagsToTarget(
    Transaction txn, {
    required Set<String> sourceComicIds,
    required String targetComicId,
  }) async {
    final args = sourceComicIds.toList(growable: false);
    final tagRows = await txn.query(
      ComicLocalDb.libraryWorkTagsTable,
      columns: const <String>['tag_id'],
      where: 'content_type = ? AND ${_whereIn('work_id', args.length)}',
      whereArgs: <Object>['comic', ...args],
    );
    for (final row in tagRows) {
      final tagId = row['tag_id'] as String?;
      if (tagId == null || tagId.trim().isEmpty) {
        continue;
      }
      await txn.insert(
        ComicLocalDb.libraryWorkTagsTable,
        <String, Object?>{
          'content_type': 'comic',
          'work_id': targetComicId,
          'tag_id': tagId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await txn.delete(
      ComicLocalDb.libraryWorkTagsTable,
      where: 'content_type = ? AND ${_whereIn('work_id', args.length)}',
      whereArgs: <Object>['comic', ...args],
    );
  }

  Future<void> _mergeReadingProgressToTarget(
    Transaction txn, {
    required Set<String> sourceComicIds,
    required String targetComicId,
  }) async {
    final args = sourceComicIds.toList(growable: false);
    final rows = await txn.query(
      ComicLocalDb.readingProgressTable,
      where: _whereIn('comic_id', args.length + 1),
      whereArgs: <Object>[targetComicId, ...args],
      orderBy: 'updated_at DESC, rowid DESC',
    );
    if (rows.isEmpty) {
      return;
    }
    final latestByEpisodeId = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final episodeId = row['episode_id'] as String;
      latestByEpisodeId.putIfAbsent(episodeId, () => row);
    }
    for (final winner in latestByEpisodeId.values) {
      await txn.insert(
        ComicLocalDb.readingProgressTable,
        <String, Object?>{...winner, 'comic_id': targetComicId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await txn.delete(
      ComicLocalDb.readingProgressTable,
      where: _whereIn('comic_id', args.length),
      whereArgs: args,
    );
  }

  Object? _firstObject(Iterable<Object?> values) {
    for (final value in values) {
      if (value is String && value.trim().isEmpty) {
        continue;
      }
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  int? _firstInt(Iterable<int?> values) {
    for (final value in values) {
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  int _maxInt(Object? a, Object? b) {
    final left = a is int ? a : 0;
    final right = b is int ? b : 0;
    return left > right ? left : right;
  }

  int? _maxNullableInt(Object? a, Object? b) {
    final left = a is int ? a : null;
    final right = b is int ? b : null;
    if (left == null) {
      return right;
    }
    if (right == null) {
      return left;
    }
    return left > right ? left : right;
  }

  String _whereIn(String column, int count) {
    if (count <= 0) {
      throw ArgumentError('IN condition requires at least one value');
    }
    return '$column IN (${List<String>.filled(count, '?').join(', ')})';
  }

  String? _firstNormalized(Iterable<String?> values) {
    for (final value in values) {
      final normalized = _normalizeNullable(value);
      if (normalized != null) {
        return normalized;
      }
    }
    return null;
  }

  String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
