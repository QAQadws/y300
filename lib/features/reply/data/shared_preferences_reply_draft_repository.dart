import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/reply/data/reply_draft_repository.dart';
import 'package:y300/features/reply/data/reply_draft_snapshot_codec.dart';
import 'package:y300/features/reply/data/reply_upload_cache_storage.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/reply_draft_attachment_sanitizer.dart';

class SharedPreferencesReplyDraftRepository implements ReplyDraftRepository {
  SharedPreferencesReplyDraftRepository({
    SharedPreferences? sharedPreferences,
    ReplyDraftSnapshotJsonCodec codec = const ReplyDraftSnapshotJsonCodec(),
    ReplyDraftAttachmentSanitizer sanitizer =
        const ReplyDraftAttachmentSanitizer(),
    ReplyUploadCacheStorage cacheStorage =
        const NoopReplyUploadCacheStorage(),
    DateTime Function()? now,
  })  : _sharedPreferences = sharedPreferences,
        _codec = codec,
        _sanitizer = sanitizer,
        _cacheStorage = cacheStorage,
        _now = now ?? DateTime.now;

  static const String draftKeyPrefix = 'reply_draft.';
  static const String _keyPrefix = draftKeyPrefix;

  final SharedPreferences? _sharedPreferences;
  final ReplyDraftSnapshotJsonCodec _codec;
  final ReplyDraftAttachmentSanitizer _sanitizer;
  final ReplyUploadCacheStorage _cacheStorage;
  final DateTime Function() _now;

  @override
  Future<ReplyDraftSnapshot?> loadDraft(ReplyDraftIdentity identity) async {
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
  Future<void> saveDraft(ReplyDraftSnapshot draft) async {
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
  Future<void> deleteDraft(ReplyDraftIdentity identity) async {
    final prefs = await _prefs();
    final key = _prefsKey(identity);
    await _deleteDraftCacheFiles(prefs.getString(key));
    await prefs.remove(key);
  }

  @override
  Future<ReplyDraftPruneResult> pruneDrafts({
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
    return ReplyDraftPruneResult(
      removedCount: removedCount,
      keptCount: keptCount,
    );
  }

  @override
  Future<List<ReplyDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    final prefs = await _prefs();
    final threadKey = _prefsKey(
      ReplyDraftIdentity.thread(fid: fid, tid: tid),
    );
    final postKeyPrefix = '${_keyPrefix}post:$fid:$tid:';
    final drafts = <ReplyDraftSnapshot>[];

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

  String _prefsKey(ReplyDraftIdentity identity) {
    return '$_keyPrefix${identity.storageKey}';
  }

  Future<ReplyDraftSnapshot?> _loadSanitizedSnapshot({
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

  _SanitizedDraftSnapshot _sanitizeSnapshot(ReplyDraftSnapshot snapshot) {
    final result = _sanitizer.sanitize(
      message: snapshot.message,
      imageAttachments: snapshot.imageAttachments,
      now: _now(),
    );
    return _SanitizedDraftSnapshot(
      snapshot: ReplyDraftSnapshot(
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
    List<ReplyImageAttachment> attachments,
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
  final ReplyDraftSnapshot draft;
}

class _SanitizedDraftSnapshot {
  const _SanitizedDraftSnapshot({
    required this.snapshot,
    required this.removedAttachments,
  });

  final ReplyDraftSnapshot snapshot;
  final List<ReplyImageAttachment> removedAttachments;

  bool get changed {
    return removedAttachments.isNotEmpty;
  }
}
