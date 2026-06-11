import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/composer_shared/data/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/composer_draft_snapshot_codec.dart';
import 'package:y300/features/composer_shared/data/composer_upload_cache_storage.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_draft_attachment_sanitizer.dart';

/// 基于 SharedPreferences 的草稿持久化。
///
/// 存储 key 前缀沿用 `reply_draft.` 是为了不丢已有草稿；后续如果需要把发帖
/// 草稿放进同一个命名空间，再统一迁移。
class SharedPreferencesComposerDraftRepository
    implements ComposerDraftRepository {
  SharedPreferencesComposerDraftRepository({
    SharedPreferences? sharedPreferences,
    ComposerDraftSnapshotJsonCodec codec = const ComposerDraftSnapshotJsonCodec(),
    ComposerDraftAttachmentSanitizer sanitizer =
        const ComposerDraftAttachmentSanitizer(),
    ComposerUploadCacheStorage cacheStorage =
        const NoopComposerUploadCacheStorage(),
    DateTime Function()? now,
  })  : _sharedPreferences = sharedPreferences,
        _codec = codec,
        _sanitizer = sanitizer,
        _cacheStorage = cacheStorage,
        _now = now ?? DateTime.now;

  static const String draftKeyPrefix = 'reply_draft.';
  static const String _keyPrefix = draftKeyPrefix;

  final SharedPreferences? _sharedPreferences;
  final ComposerDraftSnapshotJsonCodec _codec;
  final ComposerDraftAttachmentSanitizer _sanitizer;
  final ComposerUploadCacheStorage _cacheStorage;
  final DateTime Function() _now;

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async {
    final prefs = await _prefs();
    final key = _prefsKey(identity);
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return _loadSanitizedSnapshot(
      prefs: prefs,
      key: key,
      raw: raw,
    );
  }

  @override
  Future<void> saveDraft(ComposerDraftSnapshot draft) async {
    final sanitized = _sanitizeSnapshot(draft);
    await _deleteRemovedCacheFiles(sanitized.removedAttachments);
    if (sanitized.snapshot.isEmpty) {
      await deleteDraft(draft.identity);
      return;
    }

    final prefs = await _prefs();
    await prefs.setString(
      _prefsKey(sanitized.snapshot.identity),
      jsonEncode(_codec.encode(sanitized.snapshot)),
    );
  }

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {
    final prefs = await _prefs();
    final key = _prefsKey(identity);
    await _deleteDraftCacheFiles(prefs.getString(key));
    await prefs.remove(key);
  }

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
    final prefs = await _prefs();
    final now = _now();
    final cutoff = now.subtract(maxAge);
    final validEntries = <_DraftEntry>[];
    var removedCount = 0;

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_keyPrefix)) {
        continue;
      }
      final raw = prefs.getString(key);
      final draft = raw == null
          ? null
          : await _loadSanitizedSnapshot(
              prefs: prefs,
              key: key,
              raw: raw,
              pruneEmpty: false,
            );
      if (draft == null || draft.isEmpty || draft.updatedAt.isBefore(cutoff)) {
        await _deleteRemovedCacheFiles(draft?.imageAttachments ?? const []);
        await prefs.remove(key);
        removedCount += 1;
        continue;
      }
      validEntries.add(_DraftEntry(key: key, draft: draft));
    }

    validEntries.sort(
      (a, b) => b.draft.updatedAt.compareTo(a.draft.updatedAt),
    );
    final normalizedMaxCount = maxCount < 0 ? 0 : maxCount;
    final overflow = validEntries.skip(normalizedMaxCount);
    for (final entry in overflow) {
      await _deleteRemovedCacheFiles(entry.draft.imageAttachments);
      await prefs.remove(entry.key);
      removedCount += 1;
    }

    final keptCount = validEntries.length > normalizedMaxCount
        ? normalizedMaxCount
        : validEntries.length;
    return ComposerDraftPruneResult(
      removedCount: removedCount,
      keptCount: keptCount,
    );
  }

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    final prefs = await _prefs();
    final threadKey = _prefsKey(
      ComposerDraftIdentity.thread(fid: fid, tid: tid),
    );
    final postKeyPrefix = '${_keyPrefix}post:$fid:$tid:';
    final drafts = <ComposerDraftSnapshot>[];

    for (final key in prefs.getKeys()) {
      if (key != threadKey && !key.startsWith(postKeyPrefix)) {
        continue;
      }
      final raw = prefs.getString(key);
      if (raw == null) {
        continue;
      }
      final draft = await _loadSanitizedSnapshot(
        prefs: prefs,
        key: key,
        raw: raw,
      );
      if (draft == null ||
          draft.identity.fid != fid ||
          draft.identity.tid != tid) {
        continue;
      }
      drafts.add(draft);
    }

    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return drafts;
  }

  Future<SharedPreferences> _prefs() async {
    final sharedPreferences = _sharedPreferences;
    if (sharedPreferences != null) {
      return sharedPreferences;
    }
    return SharedPreferences.getInstance();
  }

  String _prefsKey(ComposerDraftIdentity identity) {
    return '$_keyPrefix${identity.storageKey}';
  }

  Future<ComposerDraftSnapshot?> _loadSanitizedSnapshot({
    required SharedPreferences prefs,
    required String key,
    required String raw,
    bool pruneEmpty = true,
  }) async {
    final decoded = _codec.decode(raw);
    if (decoded == null) {
      return null;
    }
    final sanitized = _sanitizeSnapshot(decoded);
    await _deleteRemovedCacheFiles(sanitized.removedAttachments);
    if (sanitized.snapshot.isEmpty && pruneEmpty) {
      await prefs.remove(key);
      return null;
    }
    if (sanitized.changed) {
      if (sanitized.snapshot.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(
          key,
          jsonEncode(_codec.encode(sanitized.snapshot)),
        );
      }
    }
    return sanitized.snapshot;
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
        useSignature: snapshot.useSignature,
        updatedAt: snapshot.updatedAt,
        imageAttachments: result.imageAttachments,
      ),
      removedAttachments: result.removedAttachments,
    );
  }

  Future<void> _deleteRemovedCacheFiles(
    List<ComposerImageAttachment> attachments,
  ) async {
    for (final attachment in attachments) {
      try {
        await _cacheStorage.deleteCachePathIfOwned(attachment.cachePath);
      } catch (_) {
        // 草稿清理不能因为缓存文件删除失败而丢失保存/恢复主流程。
      }
    }
  }

  Future<void> _deleteDraftCacheFiles(String? raw) async {
    if (raw == null) {
      return;
    }
    final snapshot = _codec.decode(raw);
    if (snapshot == null) {
      return;
    }
    await _deleteRemovedCacheFiles(snapshot.imageAttachments);
  }
}

class _DraftEntry {
  const _DraftEntry({
    required this.key,
    required this.draft,
  });

  final String key;
  final ComposerDraftSnapshot draft;
}

class _SanitizedDraftSnapshot {
  const _SanitizedDraftSnapshot({
    required this.snapshot,
    required this.removedAttachments,
  });

  final ComposerDraftSnapshot snapshot;
  final List<ComposerImageAttachment> removedAttachments;

  bool get changed {
    return removedAttachments.isNotEmpty;
  }
}
