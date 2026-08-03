import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/composer_shared/data/local/composer_draft_local_db.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_draft_snapshot_codec.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_cache_storage.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_draft_attachment_sanitizer.dart';

typedef ComposerDraftDatabaseProvider = Future<Database> Function();

class SqfliteComposerDraftRepository
    implements ComposerDraftRepository, ComposerDraftAttachmentInvalidator {
  SqfliteComposerDraftRepository({
    required ComposerDraftDatabaseProvider databaseProvider,
    ComposerDraftSnapshotJsonCodec codec =
        const ComposerDraftSnapshotJsonCodec(),
    ComposerDraftAttachmentSanitizer sanitizer =
        const ComposerDraftAttachmentSanitizer(),
    ComposerUploadCacheStorage cacheStorage =
        const NoopComposerUploadCacheStorage(),
    DateTime Function()? now,
  }) : _databaseProvider = databaseProvider,
       _codec = codec,
       _sanitizer = sanitizer,
       _cacheStorage = cacheStorage,
       _now = now ?? DateTime.now;

  final ComposerDraftDatabaseProvider _databaseProvider;
  final ComposerDraftSnapshotJsonCodec _codec;
  final ComposerDraftAttachmentSanitizer _sanitizer;
  final ComposerUploadCacheStorage _cacheStorage;
  final DateTime Function() _now;

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      ComposerDraftLocalDb.draftsTable,
      where: 'storage_key = ?',
      whereArgs: <Object>[identity.storageKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _loadSanitizedRow(db, rows.single, expectedIdentity: identity);
  }

  @override
  Future<void> saveDraft(ComposerDraftSnapshot draft) async {
    final sanitized = _sanitizeSnapshot(draft);
    await _deleteCacheFiles(sanitized.cacheCleanupAttachments);
    if (sanitized.snapshot.isEmpty) {
      await deleteDraft(draft.identity);
      return;
    }
    await _write(await _databaseProvider(), sanitized.snapshot);
  }

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      ComposerDraftLocalDb.draftsTable,
      columns: const <String>['snapshot_json'],
      where: 'storage_key = ?',
      whereArgs: <Object>[identity.storageKey],
      limit: 1,
    );
    await db.delete(
      ComposerDraftLocalDb.draftsTable,
      where: 'storage_key = ?',
      whereArgs: <Object>[identity.storageKey],
    );
    if (rows.isNotEmpty) {
      final draft = _decodeRow(rows.single);
      if (draft != null) {
        await _deleteCacheFiles(draft.imageAttachments);
      }
    }
  }

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      ComposerDraftLocalDb.draftsTable,
      orderBy: 'updated_at DESC, storage_key ASC',
    );
    final cutoff = _now().subtract(maxAge);
    final valid = <ComposerDraftSnapshot>[];
    var removedCount = 0;
    var sanitizedCount = 0;
    var removedAttachmentCount = 0;
    var deletedCacheFileCount = 0;
    var failedCount = 0;

    for (final row in rows) {
      try {
        final decoded = _decodeRow(row);
        if (decoded == null ||
            decoded.identity.storageKey != row['storage_key']) {
          await _deleteRow(db, row['storage_key'] as String);
          removedCount += 1;
          continue;
        }
        final sanitized = _sanitizeSnapshot(decoded);
        removedAttachmentCount += sanitized.removedAttachments.length;
        deletedCacheFileCount += await _deleteCacheFiles(
          sanitized.cacheCleanupAttachments,
        );
        final draft = sanitized.snapshot;
        if (draft.isEmpty || draft.updatedAt.isBefore(cutoff)) {
          deletedCacheFileCount += await _deleteCacheFiles(
            draft.imageAttachments,
          );
          await _deleteRow(db, decoded.identity.storageKey);
          removedCount += 1;
          continue;
        }
        if (sanitized.changed) {
          sanitizedCount += 1;
          await _write(db, draft);
        }
        valid.add(draft);
      } catch (_) {
        failedCount += 1;
      }
    }

    final normalizedMaxCount = maxCount < 0 ? 0 : maxCount;
    for (final draft in valid.skip(normalizedMaxCount)) {
      deletedCacheFileCount += await _deleteCacheFiles(draft.imageAttachments);
      await _deleteRow(db, draft.identity.storageKey);
      removedCount += 1;
    }
    final keptCount = valid.length > normalizedMaxCount
        ? normalizedMaxCount
        : valid.length;
    return ComposerDraftPruneResult(
      removedCount: removedCount,
      keptCount: keptCount,
      sanitizedCount: sanitizedCount,
      removedAttachmentCount: removedAttachmentCount,
      deletedCacheFileCount: deletedCacheFileCount,
      failedCount: failedCount,
    );
  }

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      ComposerDraftLocalDb.draftsTable,
      where: 'fid = ? AND tid = ? AND kind IN (?, ?)',
      whereArgs: <Object>[
        fid,
        tid,
        ComposerDraftKind.threadReply.name,
        ComposerDraftKind.postReply.name,
      ],
      orderBy: 'updated_at DESC, storage_key ASC',
    );
    final drafts = <ComposerDraftSnapshot>[];
    for (final row in rows) {
      final expectedKey = row['storage_key'] as String;
      final draft = await _loadSanitizedRow(db, row);
      if (draft == null ||
          draft.identity.storageKey != expectedKey ||
          draft.identity.fid != fid ||
          draft.identity.tid != tid) {
        continue;
      }
      drafts.add(draft);
    }
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return drafts;
  }

  @override
  Future<ComposerDraftAttachmentInvalidationResult> invalidateAttachmentAids({
    required Set<String> aids,
    ComposerDraftIdentity? identity,
  }) async {
    final normalizedAids = aids
        .map((aid) => aid.trim())
        .where((aid) => aid.isNotEmpty)
        .toSet();
    if (normalizedAids.isEmpty) {
      return const ComposerDraftAttachmentInvalidationResult();
    }
    final db = await _databaseProvider();
    final writeResult = await db.transaction<_DraftInvalidationWriteResult>((
      transaction,
    ) async {
      final rows = await transaction.query(
        ComposerDraftLocalDb.draftsTable,
        where: identity == null ? null : 'storage_key = ?',
        whereArgs: identity == null ? null : <Object>[identity.storageKey],
        orderBy: 'updated_at DESC, storage_key ASC',
      );
      var affectedDraftCount = 0;
      var removedAttachmentCount = 0;
      ComposerDraftSnapshot? updatedDraft;
      final cacheCleanup = <ComposerImageAttachment>[];

      for (final row in rows) {
        final decoded = _decodeRow(row);
        final storageKey = row['storage_key'] as String?;
        if (decoded == null ||
            storageKey == null ||
            decoded.identity.storageKey != storageKey) {
          if (storageKey != null) {
            await _deleteRow(transaction, storageKey);
          }
          continue;
        }
        final sanitized = _sanitizeSnapshot(decoded);
        cacheCleanup.addAll(sanitized.cacheCleanupAttachments);
        final removed = <ComposerImageAttachment>[];
        final kept = <ComposerImageAttachment>[];
        for (final attachment in sanitized.snapshot.imageAttachments) {
          final aid = attachment.aid?.trim();
          if (aid != null && normalizedAids.contains(aid)) {
            removed.add(attachment);
          } else {
            kept.add(attachment);
          }
        }
        cacheCleanup.addAll(removed);
        final next = ComposerDraftSnapshot(
          identity: sanitized.snapshot.identity,
          message: sanitized.snapshot.message,
          subject: sanitized.snapshot.subject,
          extras: sanitized.snapshot.extras,
          useSignature: sanitized.snapshot.useSignature,
          updatedAt: sanitized.snapshot.updatedAt,
          imageAttachments: kept,
        );
        final changed = sanitized.changed || removed.isNotEmpty;
        if (removed.isNotEmpty) {
          affectedDraftCount += 1;
          removedAttachmentCount += removed.length;
        }
        if (changed) {
          if (next.isEmpty) {
            await _deleteRow(transaction, storageKey);
          } else {
            await _write(transaction, next);
          }
        }
        if (identity != null) {
          updatedDraft = next.isEmpty ? null : next;
        }
      }
      return _DraftInvalidationWriteResult(
        affectedDraftCount: affectedDraftCount,
        removedAttachmentCount: removedAttachmentCount,
        cacheCleanupAttachments: cacheCleanup,
        updatedDraft: updatedDraft,
      );
    });
    final deletedCacheFileCount = await _deleteCacheFiles(
      writeResult.cacheCleanupAttachments,
    );
    return ComposerDraftAttachmentInvalidationResult(
      affectedDraftCount: writeResult.affectedDraftCount,
      removedAttachmentCount: writeResult.removedAttachmentCount,
      deletedCacheFileCount: deletedCacheFileCount,
      updatedDraft: writeResult.updatedDraft,
    );
  }

  Future<ComposerDraftSnapshot?> _loadSanitizedRow(
    Database db,
    Map<String, Object?> row, {
    ComposerDraftIdentity? expectedIdentity,
  }) async {
    final decoded = _decodeRow(row);
    final storageKey = row['storage_key'] as String?;
    if (decoded == null ||
        storageKey == null ||
        decoded.identity.storageKey != storageKey ||
        (expectedIdentity != null && decoded.identity != expectedIdentity)) {
      if (storageKey != null) {
        await _deleteRow(db, storageKey);
      }
      return null;
    }
    final sanitized = _sanitizeSnapshot(decoded);
    await _deleteCacheFiles(sanitized.cacheCleanupAttachments);
    if (sanitized.snapshot.isEmpty) {
      await _deleteRow(db, storageKey);
      return null;
    }
    if (sanitized.changed) {
      await _write(db, sanitized.snapshot);
    }
    return sanitized.snapshot;
  }

  ComposerDraftSnapshot? _decodeRow(Map<String, Object?> row) {
    final raw = row['snapshot_json'];
    return raw is String ? _codec.decode(raw) : null;
  }

  Future<void> _write(DatabaseExecutor db, ComposerDraftSnapshot draft) {
    return db.insert(
      ComposerDraftLocalDb.draftsTable,
      <String, Object?>{
        'storage_key': draft.identity.storageKey,
        'kind': draft.identity.kind.name,
        'fid': draft.identity.fid,
        'tid': draft.identity.tid,
        'snapshot_json': jsonEncode(_codec.encode(draft)),
        'updated_at': draft.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _deleteRow(DatabaseExecutor db, String storageKey) {
    return db.delete(
      ComposerDraftLocalDb.draftsTable,
      where: 'storage_key = ?',
      whereArgs: <Object>[storageKey],
    );
  }

  _SanitizedDraftSnapshot _sanitizeSnapshot(ComposerDraftSnapshot snapshot) {
    final result = _sanitizer.sanitize(
      message: snapshot.message,
      imageAttachments: snapshot.imageAttachments,
      now: _now(),
    );
    return _SanitizedDraftSnapshot(
      snapshot: ComposerDraftSnapshot(
        identity: snapshot.identity,
        message: result.message,
        subject: snapshot.subject,
        extras: snapshot.extras,
        useSignature: snapshot.useSignature,
        updatedAt: snapshot.updatedAt,
        imageAttachments: result.imageAttachments,
      ),
      removedAttachments: result.removedAttachments,
      expiredCacheAttachments: result.expiredCacheAttachments,
    );
  }

  Future<int> _deleteCacheFiles(
    List<ComposerImageAttachment> attachments,
  ) async {
    var deleted = 0;
    for (final attachment in attachments) {
      try {
        if (await _cacheStorage.deleteCachePathIfOwned(attachment.cachePath)) {
          deleted += 1;
        }
      } catch (_) {
        // Cache cleanup failure must not discard a valid draft snapshot.
      }
    }
    return deleted;
  }
}

class _SanitizedDraftSnapshot {
  const _SanitizedDraftSnapshot({
    required this.snapshot,
    required this.removedAttachments,
    required this.expiredCacheAttachments,
  });

  final ComposerDraftSnapshot snapshot;
  final List<ComposerImageAttachment> removedAttachments;
  final List<ComposerImageAttachment> expiredCacheAttachments;

  List<ComposerImageAttachment> get cacheCleanupAttachments =>
      <ComposerImageAttachment>[
        ...removedAttachments,
        ...expiredCacheAttachments,
      ];

  bool get changed =>
      removedAttachments.isNotEmpty || expiredCacheAttachments.isNotEmpty;
}

class _DraftInvalidationWriteResult {
  const _DraftInvalidationWriteResult({
    required this.affectedDraftCount,
    required this.removedAttachmentCount,
    required this.cacheCleanupAttachments,
    required this.updatedDraft,
  });

  final int affectedDraftCount;
  final int removedAttachmentCount;
  final List<ComposerImageAttachment> cacheCleanupAttachments;
  final ComposerDraftSnapshot? updatedDraft;
}
