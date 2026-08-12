import 'dart:async';
import 'dart:io' as io;

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/data/local/comic_cover_store.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_local_models.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';

class ComicDuplicateMergeStore {
  ComicDuplicateMergeStore(
    this._dbFuture, {
    required ComicCoverStore coverStore,
    required LibraryCoverStore libraryCoverStore,
  }) : _coverStore = coverStore,
       _libraryCoverStore = libraryCoverStore;

  final Future<Database> _dbFuture;
  final ComicCoverStore _coverStore;
  final LibraryCoverStore _libraryCoverStore;
  static Future<void> _exclusiveTail = Future<void>.value();
  static int _operationSequence = 0;

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
  }) {
    return _exclusive(() => _mergeDuplicateGroup(comicIds: comicIds));
  }

  Future<ComicDuplicateMergeResult> _mergeDuplicateGroup({
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

    await _recoverPendingCoverMerges();
    for (var attempt = 0; attempt < 2; attempt += 1) {
      final db = await _dbFuture;
      final comics = await _loadComicRecords(db, normalizedIds);
      if (comics.length <= 1) {
        return ComicDuplicateMergeResult.unchanged(
          targetComicId: comics.isEmpty
              ? normalizedIds.first
              : comics.first.comicId,
        );
      }

      final target = chooseDuplicateMergeTarget(comics);
      final plan = await _buildCoverMergePlan(comics: comics, target: target);
      final journalCreated = await db.transaction<bool>((txn) async {
        final current = await _loadComicRecords(txn, normalizedIds);
        if (!_sameCoverSnapshot(comics, current)) {
          return false;
        }
        await _insertMergeJournal(txn, plan);
        return true;
      });
      if (!journalCreated) {
        continue;
      }

      try {
        await _prepareCoverAssets(plan);
      } catch (_) {
        await _rollbackPreparingOperation(plan);
        rethrow;
      }

      ComicDuplicateMergeResult? result;
      try {
        result = await db.transaction<ComicDuplicateMergeResult?>((txn) async {
          final current = await _loadComicRecords(txn, normalizedIds);
          if (!_sameCoverSnapshot(comics, current)) {
            return null;
          }
          return _commitMerge(txn, comics: current, plan: plan);
        });
      } catch (_) {
        await _rollbackPreparingOperation(plan);
        rethrow;
      }
      if (result == null) {
        await _rollbackPreparingOperation(plan);
        continue;
      }
      try {
        await _cleanupCommittedOperation(plan.operationId);
      } catch (_) {
        // The database merge is already durable. Leave the committed journal
        // for startup or the next merge to finish the idempotent cleanup.
      }
      return result;
    }
    throw StateError('Duplicate comics changed repeatedly during merge');
  }

  Future<ComicDuplicateMergeResult> _commitMerge(
    Transaction txn, {
    required List<ComicRecord> comics,
    required _CoverMergePlan plan,
  }) async {
    final target = comics.firstWhere(
      (comic) => comic.comicId == plan.targetComicId,
    );
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
      sourceCover: plan.source.finalBundle,
      customCover: plan.custom.finalBundle,
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

    await _updateCoverMigrationMarkers(txn, plan);
    await txn.update(
      ComicLocalDb.comicCoverMergeOperationsTable,
      <String, Object?>{
        'state': _MergeJournalState.databaseCommitted,
        'updated_at': now,
      },
      where: 'operation_id = ?',
      whereArgs: <Object>[plan.operationId],
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
  }

  Future<List<ComicRecord>> _loadComicRecords(
    DatabaseExecutor txn,
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

  Future<void> recoverPendingCoverMerges() {
    return _exclusive(_recoverPendingCoverMerges);
  }

  Future<void> _recoverPendingCoverMerges() async {
    final db = await _dbFuture;
    final operations = await db.query(
      ComicLocalDb.comicCoverMergeOperationsTable,
      orderBy: 'created_at ASC, operation_id ASC',
    );
    for (final operation in operations) {
      final operationId = operation['operation_id'] as String;
      final state = operation['state'] as String;
      if (state == _MergeJournalState.preparing) {
        await _rollbackPreparingOperationById(operationId);
      } else if (state == _MergeJournalState.databaseCommitted) {
        await _cleanupCommittedOperation(operationId);
      } else {
        throw StateError('Unknown comic cover merge state: $state');
      }
    }
  }

  Future<_CoverMergePlan> _buildCoverMergePlan({
    required List<ComicRecord> comics,
    required ComicRecord target,
  }) async {
    final source = await _selectCover(
      comics: comics,
      target: target,
      kind: LibraryCoverAssetKind.source,
    );
    final custom = await _selectCover(
      comics: comics,
      target: target,
      kind: LibraryCoverAssetKind.custom,
    );
    final now = DateTime.now().microsecondsSinceEpoch;
    final sequence = _operationSequence++;
    return _CoverMergePlan(
      operationId: 'comic-cover-merge-$now-$sequence',
      targetComicId: target.comicId,
      sourceComicIds: comics
          .map((comic) => comic.comicId)
          .where((comicId) => comicId != target.comicId)
          .toSet(),
      source: source,
      custom: custom,
    );
  }

  Future<_CoverSelection> _selectCover({
    required List<ComicRecord> comics,
    required ComicRecord target,
    required LibraryCoverAssetKind kind,
  }) async {
    final bundles = comics
        .map((comic) => _CoverBundle.fromComic(comic, kind: kind))
        .toList(growable: false);
    final availability = <String, _CoverAvailability>{};
    for (final bundle in bundles) {
      availability[bundle.ownerComicId] = await _coverAvailability(bundle);
    }
    if (kind == LibraryCoverAssetKind.custom) {
      final invalid = bundles
          .where((bundle) {
            return bundle.hasIdentity &&
                availability[bundle.ownerComicId] == _CoverAvailability.invalid;
          })
          .toList(growable: false);
      if (invalid.isNotEmpty) {
        throw StateError(
          'Custom cover cannot be recovered for ${invalid.first.ownerComicId}',
        );
      }
    }

    final targetBundle = bundles.firstWhere(
      (bundle) => bundle.ownerComicId == target.comicId,
    );
    _CoverBundle? winner;
    if (availability[target.comicId]?.isAvailable ?? false) {
      winner = targetBundle;
    } else {
      final candidates =
          bundles
              .where(
                (bundle) =>
                    bundle.ownerComicId != target.comicId &&
                    (availability[bundle.ownerComicId]?.isAvailable ?? false),
              )
              .toList(growable: true)
            ..sort(_compareCoverCandidates);
      winner = candidates.isEmpty ? null : candidates.first;
    }
    if (winner == null) {
      return _CoverSelection.empty(kind);
    }
    final winnerAvailability = availability[winner.ownerComicId]!;
    final mode = winnerAvailability == _CoverAvailability.installed
        ? _CoverTransferMode.installed
        : _CoverTransferMode.remote;
    if (winner.ownerComicId == target.comicId) {
      return _CoverSelection.retained(winner, mode: mode);
    }
    final targetRevision =
        (targetBundle.revision < 0 ? 0 : targetBundle.revision) + 1;
    final targetAsset = LibraryCoverAssetRef(
      assetId: _assetId(comicId: target.comicId, kind: kind),
      revision: targetRevision,
      kind: kind,
      sourceUrl: winner.sourceUrl,
    );
    return _CoverSelection.transferred(
      source: winner,
      finalBundle: winner.reowned(
        ownerComicId: target.comicId,
        revision: targetRevision,
        // A valid legacy file has already been copied into the Store. When
        // the asset is URL-only, any legacy path here is stale by definition.
        // Neither case should make the target depend on the old owner path.
        clearLegacyPath: true,
      ),
      targetAsset: targetAsset,
      mode: mode,
    );
  }

  Future<_CoverAvailability> _coverAvailability(_CoverBundle bundle) async {
    if (!bundle.hasIdentity) {
      return _CoverAvailability.absent;
    }
    if (await (await _libraryCoverStore.fileFor(bundle.asset)).exists()) {
      return _CoverAvailability.installed;
    }
    final legacyPath = bundle.legacyPath;
    if (legacyPath != null && await io.File(legacyPath).exists()) {
      return _CoverAvailability.installed;
    }
    if (bundle.sourceUrl != null) {
      return _CoverAvailability.remote;
    }
    return _CoverAvailability.invalid;
  }

  int _compareCoverCandidates(_CoverBundle left, _CoverBundle right) {
    final metadataOrder = (right.metadataUpdatedAt ?? -1).compareTo(
      left.metadataUpdatedAt ?? -1,
    );
    if (metadataOrder != 0) {
      return metadataOrder;
    }
    final createdOrder = right.createdAt.compareTo(left.createdAt);
    if (createdOrder != 0) {
      return createdOrder;
    }
    return left.ownerComicId.compareTo(right.ownerComicId);
  }

  Future<void> _insertMergeJournal(
    Transaction txn,
    _CoverMergePlan plan,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await txn
        .insert(ComicLocalDb.comicCoverMergeOperationsTable, <String, Object?>{
          'operation_id': plan.operationId,
          'target_comic_id': plan.targetComicId,
          'state': _MergeJournalState.preparing,
          'created_at': now,
          'updated_at': now,
        });
    for (final sourceComicId in plan.sourceComicIds) {
      await txn.insert(
        ComicLocalDb.comicCoverMergeMembersTable,
        <String, Object?>{
          'operation_id': plan.operationId,
          'source_comic_id': sourceComicId,
        },
      );
    }
    for (final selection in plan.journaledSelections) {
      final source = selection.source ?? selection.finalBundle!;
      final target = selection.targetAsset ?? selection.finalBundle!.asset;
      await txn
          .insert(ComicLocalDb.comicCoverMergeAssetsTable, <String, Object?>{
            'operation_id': plan.operationId,
            'kind': selection.kind.name,
            'source_comic_id': source.ownerComicId,
            'source_asset_id': source.asset.assetId,
            'source_revision': source.revision,
            'target_asset_id': target.assetId,
            'target_revision': target.revision,
            'mode': selection.mode,
          });
    }
  }

  Future<void> _prepareCoverAssets(_CoverMergePlan plan) async {
    for (final selection in plan.transfers) {
      if (selection.mode != _CoverTransferMode.installed) {
        continue;
      }
      final targetAsset = selection.targetAsset!;
      await _libraryCoverStore.invalidate(targetAsset);
      final source = selection.source!;
      final sourceFile = await _libraryCoverStore.fileFor(source.asset);
      final sourcePath = await sourceFile.exists()
          ? sourceFile.path
          : source.legacyPath;
      if (sourcePath == null || !await io.File(sourcePath).exists()) {
        throw StateError(
          'Cover disappeared while preparing ${source.ownerComicId}',
        );
      }
      await _libraryCoverStore.installLocalFile(
        asset: targetAsset,
        sourcePath: sourcePath,
      );
    }
  }

  bool _sameCoverSnapshot(
    List<ComicRecord> expected,
    List<ComicRecord> actual,
  ) {
    if (expected.length != actual.length) {
      return false;
    }
    final actualById = <String, ComicRecord>{
      for (final comic in actual) comic.comicId: comic,
    };
    for (final comic in expected) {
      final current = actualById[comic.comicId];
      if (current == null || !_sameComicCoverSnapshot(comic, current)) {
        return false;
      }
    }
    return true;
  }

  bool _sameComicCoverSnapshot(ComicRecord left, ComicRecord right) {
    return left.comicId == right.comicId &&
        left.updatedAt == right.updatedAt &&
        left.metadataUpdatedAt == right.metadataUpdatedAt &&
        left.coverImageUrl == right.coverImageUrl &&
        left.coverLocalPath == right.coverLocalPath &&
        left.coverRevision == right.coverRevision &&
        left.customCoverImageUrl == right.customCoverImageUrl &&
        left.customCoverLocalPath == right.customCoverLocalPath &&
        left.customCoverRevision == right.customCoverRevision &&
        left.customCoverSourceEpisodeId == right.customCoverSourceEpisodeId &&
        left.customCoverSourceImageIndex == right.customCoverSourceImageIndex &&
        left.customCoverSourceImageUrl == right.customCoverSourceImageUrl &&
        left.customCoverFocusX == right.customCoverFocusX &&
        left.customCoverFocusY == right.customCoverFocusY;
  }

  Future<void> _rollbackPreparingOperation(_CoverMergePlan plan) async {
    await _rollbackPreparingOperationById(plan.operationId);
  }

  Future<void> _rollbackPreparingOperationById(String operationId) async {
    final db = await _dbFuture;
    final assets = await db.query(
      ComicLocalDb.comicCoverMergeAssetsTable,
      where: 'operation_id = ?',
      whereArgs: <Object>[operationId],
    );
    for (final row in assets) {
      final target = _journalTargetAsset(row);
      if (!await _isTargetRevisionReferenced(target)) {
        await _libraryCoverStore.invalidate(target);
      }
    }
    await db.delete(
      ComicLocalDb.comicCoverMergeOperationsTable,
      where: 'operation_id = ? AND state = ?',
      whereArgs: <Object>[operationId, _MergeJournalState.preparing],
    );
  }

  Future<bool> _isTargetRevisionReferenced(LibraryCoverAssetRef asset) async {
    final db = await _dbFuture;
    final ownerId = _comicIdFromAssetId(asset.assetId);
    final column = asset.kind == LibraryCoverAssetKind.custom
        ? 'custom_cover_revision'
        : 'cover_revision';
    final rows = await db.query(
      ComicLocalDb.comicsTable,
      columns: <String>[column],
      where: 'comic_id = ?',
      whereArgs: <Object>[ownerId],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single[column] == asset.revision;
  }

  Future<void> _cleanupCommittedOperation(String operationId) async {
    final db = await _dbFuture;
    final operations = await db.query(
      ComicLocalDb.comicCoverMergeOperationsTable,
      where: 'operation_id = ? AND state = ?',
      whereArgs: <Object>[operationId, _MergeJournalState.databaseCommitted],
      limit: 1,
    );
    if (operations.isEmpty) {
      return;
    }
    final members = await db.query(
      ComicLocalDb.comicCoverMergeMembersTable,
      columns: const <String>['source_comic_id'],
      where: 'operation_id = ?',
      whereArgs: <Object>[operationId],
    );
    for (final row in members) {
      final comicId = row['source_comic_id'] as String;
      await _libraryCoverStore.deleteAsset(
        _assetId(comicId: comicId, kind: LibraryCoverAssetKind.source),
      );
      await _libraryCoverStore.deleteAsset(
        _assetId(comicId: comicId, kind: LibraryCoverAssetKind.custom),
      );
    }
    final assets = await db.query(
      ComicLocalDb.comicCoverMergeAssetsTable,
      where: 'operation_id = ?',
      whereArgs: <Object>[operationId],
    );
    for (final row in assets) {
      await _libraryCoverStore.deleteOlderRevisions(_journalTargetAsset(row));
    }
    await db.delete(
      ComicLocalDb.comicCoverMergeOperationsTable,
      where: 'operation_id = ? AND state = ?',
      whereArgs: <Object>[operationId, _MergeJournalState.databaseCommitted],
    );
  }

  Future<void> _updateCoverMigrationMarkers(
    Transaction txn,
    _CoverMergePlan plan,
  ) async {
    for (final sourceComicId in plan.sourceComicIds) {
      for (final kind in LibraryCoverAssetKind.values) {
        await txn.delete(
          ComicLocalDb.libraryCoverMigrationsTable,
          where: 'asset_id = ?',
          whereArgs: <Object>[_assetId(comicId: sourceComicId, kind: kind)],
        );
      }
    }
    for (final selection in <_CoverSelection>[plan.source, plan.custom]) {
      final finalBundle = selection.finalBundle;
      final targetAssetId = _assetId(
        comicId: plan.targetComicId,
        kind: selection.kind,
      );
      if (finalBundle == null || finalBundle.revision <= 0) {
        await txn.delete(
          ComicLocalDb.libraryCoverMigrationsTable,
          where: 'asset_id = ?',
          whereArgs: <Object>[targetAssetId],
        );
        continue;
      }
      await txn.delete(
        ComicLocalDb.libraryCoverMigrationsTable,
        where: 'asset_id = ? AND revision != ?',
        whereArgs: <Object>[targetAssetId, finalBundle.revision],
      );
    }
    for (final selection in plan.transfers) {
      final target = selection.targetAsset!;
      await txn.insert(
        ComicLocalDb.libraryCoverMigrationsTable,
        <String, Object?>{
          'asset_id': target.assetId,
          'revision': target.revision,
          'kind': selection.mode,
          'completed_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  LibraryCoverAssetRef _journalTargetAsset(Map<String, Object?> row) {
    return LibraryCoverAssetRef(
      assetId: row['target_asset_id'] as String,
      revision: row['target_revision'] as int,
      kind: _parseKind(row['kind'] as String),
    );
  }

  LibraryCoverAssetKind _parseKind(String value) {
    return value == LibraryCoverAssetKind.custom.name
        ? LibraryCoverAssetKind.custom
        : LibraryCoverAssetKind.source;
  }

  String _assetId({
    required String comicId,
    required LibraryCoverAssetKind kind,
  }) {
    return kind == LibraryCoverAssetKind.custom
        ? LibraryCoverAssetIds.custom(ownerType: 'comic', ownerId: comicId)
        : LibraryCoverAssetIds.source(ownerType: 'comic', ownerId: comicId);
  }

  String _comicIdFromAssetId(String assetId) {
    const prefix = 'comic/';
    final suffix = assetId.endsWith('/custom') ? '/custom' : '/source';
    if (!assetId.startsWith(prefix) || !assetId.endsWith(suffix)) {
      throw StateError('Unexpected comic cover asset id: $assetId');
    }
    return assetId.substring(prefix.length, assetId.length - suffix.length);
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final previous = _exclusiveTail;
    final released = Completer<void>();
    _exclusiveTail = released.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        released.complete();
      }
    }();
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
    if (customTitle !=
        _normalizeNullable(existing['custom_episode_title'] as String?)) {
      update['custom_episode_title'] = customTitle;
    }
    final displayTitle = resolveEpisodeDisplayTitle(
      customEpisodeTitle: customTitle,
      sourceEpisodeTitle: sourceTitle,
    );
    if (displayTitle !=
        _normalizeNullable(existing['episode_title'] as String?)) {
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
    required _CoverBundle? sourceCover,
    required _CoverBundle? customCover,
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
        'cover_image_url': sourceCover?.sourceUrl,
        'cover_local_path': sourceCover?.committedLegacyPath,
        'cover_revision': sourceCover?.revision ?? 0,
        'custom_cover_image_url': customCover?.sourceUrl,
        'custom_cover_local_path': customCover?.committedLegacyPath,
        'custom_cover_revision': customCover?.revision ?? 0,
        'custom_cover_source_episode_id': _remapMergedEpisodeId(
          customCover?.sourceEpisodeId,
          targetComicId: target.comicId,
        ),
        'custom_cover_source_image_index': customCover?.sourceImageIndex,
        'custom_cover_source_image_url': customCover?.sourceImageUrl,
        'custom_cover_focus_x': customCover?.focusX,
        'custom_cover_focus_y': customCover?.focusY,
        'metadata_updated_at': now,
        'updated_at': now,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[target.comicId],
    );
    // The source-cover URL trigger maintains revisions for ordinary writes.
    // Reassert the merge plan's exact revisions so corrupted negative legacy
    // values are normalized according to max(oldRevision, 0) + 1 as well.
    await txn.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{
        'cover_revision': sourceCover?.revision ?? 0,
        'custom_cover_revision': customCover?.revision ?? 0,
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

abstract final class _MergeJournalState {
  static const String preparing = 'preparing';
  static const String databaseCommitted = 'database_committed';
}

abstract final class _CoverTransferMode {
  static const String installed = 'installed';
  static const String remote = 'remote';
}

enum _CoverAvailability { absent, installed, remote, invalid }

extension on _CoverAvailability {
  bool get isAvailable =>
      this == _CoverAvailability.installed || this == _CoverAvailability.remote;
}

class _CoverMergePlan {
  const _CoverMergePlan({
    required this.operationId,
    required this.targetComicId,
    required this.sourceComicIds,
    required this.source,
    required this.custom,
  });

  final String operationId;
  final String targetComicId;
  final Set<String> sourceComicIds;
  final _CoverSelection source;
  final _CoverSelection custom;

  Iterable<_CoverSelection> get transfers sync* {
    if (source.isTransfer) {
      yield source;
    }
    if (custom.isTransfer) {
      yield custom;
    }
  }

  Iterable<_CoverSelection> get journaledSelections sync* {
    if (source.finalBundle != null) {
      yield source;
    }
    if (custom.finalBundle != null) {
      yield custom;
    }
  }
}

class _CoverSelection {
  const _CoverSelection._({
    required this.kind,
    required this.finalBundle,
    required this.source,
    required this.targetAsset,
    required this.mode,
  });

  const _CoverSelection.empty(LibraryCoverAssetKind kind)
    : this._(
        kind: kind,
        finalBundle: null,
        source: null,
        targetAsset: null,
        mode: null,
      );

  factory _CoverSelection.retained(
    _CoverBundle bundle, {
    required String mode,
  }) {
    return _CoverSelection._(
      kind: bundle.kind,
      finalBundle: bundle,
      source: null,
      targetAsset: bundle.asset,
      mode: mode,
    );
  }

  factory _CoverSelection.transferred({
    required _CoverBundle source,
    required _CoverBundle finalBundle,
    required LibraryCoverAssetRef targetAsset,
    required String mode,
  }) {
    return _CoverSelection._(
      kind: finalBundle.kind,
      finalBundle: finalBundle,
      source: source,
      targetAsset: targetAsset,
      mode: mode,
    );
  }

  final LibraryCoverAssetKind kind;
  final _CoverBundle? finalBundle;
  final _CoverBundle? source;
  final LibraryCoverAssetRef? targetAsset;
  final String? mode;

  bool get isTransfer =>
      source != null && source!.ownerComicId != finalBundle?.ownerComicId;
}

class _CoverBundle {
  const _CoverBundle({
    required this.ownerComicId,
    required this.kind,
    required this.revision,
    required this.sourceUrl,
    required this.legacyPath,
    required this.sourceEpisodeId,
    required this.sourceImageIndex,
    required this.sourceImageUrl,
    required this.focusX,
    required this.focusY,
    required this.metadataUpdatedAt,
    required this.createdAt,
  });

  factory _CoverBundle.fromComic(
    ComicRecord comic, {
    required LibraryCoverAssetKind kind,
  }) {
    final custom = kind == LibraryCoverAssetKind.custom;
    return _CoverBundle(
      ownerComicId: comic.comicId,
      kind: kind,
      revision: custom ? comic.customCoverRevision : comic.coverRevision,
      sourceUrl: _text(
        custom ? comic.customCoverImageUrl : comic.coverImageUrl,
      ),
      legacyPath: _text(
        custom ? comic.customCoverLocalPath : comic.coverLocalPath,
      ),
      sourceEpisodeId: custom ? comic.customCoverSourceEpisodeId : null,
      sourceImageIndex: custom ? comic.customCoverSourceImageIndex : null,
      sourceImageUrl: custom ? comic.customCoverSourceImageUrl : null,
      focusX: custom ? comic.customCoverFocusX : null,
      focusY: custom ? comic.customCoverFocusY : null,
      metadataUpdatedAt: comic.metadataUpdatedAt,
      createdAt: comic.createdAt,
    );
  }

  final String ownerComicId;
  final LibraryCoverAssetKind kind;
  final int revision;
  final String? sourceUrl;
  final String? legacyPath;
  final String? sourceEpisodeId;
  final int? sourceImageIndex;
  final String? sourceImageUrl;
  final double? focusX;
  final double? focusY;
  final int? metadataUpdatedAt;
  final int createdAt;

  bool get hasIdentity =>
      revision > 0 || sourceUrl != null || legacyPath != null;

  String? get committedLegacyPath => legacyPath;

  LibraryCoverAssetRef get asset => LibraryCoverAssetRef(
    assetId: kind == LibraryCoverAssetKind.custom
        ? LibraryCoverAssetIds.custom(ownerType: 'comic', ownerId: ownerComicId)
        : LibraryCoverAssetIds.source(
            ownerType: 'comic',
            ownerId: ownerComicId,
          ),
    revision: revision > 0 ? revision : 1,
    kind: kind,
    sourceUrl: sourceUrl,
    legacyLocalPath: legacyPath,
  );

  _CoverBundle reowned({
    required String ownerComicId,
    required int revision,
    required bool clearLegacyPath,
  }) {
    return _CoverBundle(
      ownerComicId: ownerComicId,
      kind: kind,
      revision: revision,
      sourceUrl: sourceUrl,
      legacyPath: clearLegacyPath ? null : legacyPath,
      sourceEpisodeId: sourceEpisodeId,
      sourceImageIndex: sourceImageIndex,
      sourceImageUrl: sourceImageUrl,
      focusX: focusX,
      focusY: focusY,
      metadataUpdatedAt: metadataUpdatedAt,
      createdAt: createdAt,
    );
  }

  static String? _text(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
