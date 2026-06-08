import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/reply/data/reply_draft_snapshot_codec.dart';
import 'package:y300/features/reply/data/reply_upload_cache_storage.dart';
import 'package:y300/features/reply/data/shared_preferences_reply_draft_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/reply_draft_attachment_sanitizer.dart';

abstract class ReplyDraftAttachmentMaintenanceService {
  Future<ReplyDraftAttachmentMaintenanceResult> maintain();
}

class ReplyDraftAttachmentMaintenanceResult {
  const ReplyDraftAttachmentMaintenanceResult({
    required this.scannedDraftCount,
    required this.sanitizedDraftCount,
    required this.deletedDraftCount,
    required this.removedAttachmentCount,
    required this.deletedCacheFileCount,
    required this.failedDraftCount,
  });

  final int scannedDraftCount;
  final int sanitizedDraftCount;
  final int deletedDraftCount;
  final int removedAttachmentCount;
  final int deletedCacheFileCount;
  final int failedDraftCount;
}

class SharedPreferencesReplyDraftAttachmentMaintenanceService
    implements ReplyDraftAttachmentMaintenanceService {
  SharedPreferencesReplyDraftAttachmentMaintenanceService({
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

  final SharedPreferences? _sharedPreferences;
  final ReplyDraftSnapshotJsonCodec _codec;
  final ReplyDraftAttachmentSanitizer _sanitizer;
  final ReplyUploadCacheStorage _cacheStorage;
  final DateTime Function() _now;

  @override
  Future<ReplyDraftAttachmentMaintenanceResult> maintain() async {
    try {
      final prefs = await _prefs();
      var scannedDraftCount = 0;
      var sanitizedDraftCount = 0;
      var deletedDraftCount = 0;
      var removedAttachmentCount = 0;
      var deletedCacheFileCount = 0;
      var failedDraftCount = 0;

      for (final key in prefs.getKeys()) {
        if (!key.startsWith(
          SharedPreferencesReplyDraftRepository.draftKeyPrefix,
        )) {
          continue;
        }
        scannedDraftCount += 1;
        try {
          final raw = prefs.getString(key);
          final draft = raw == null ? null : _codec.decode(raw);
          if (draft == null) {
            await prefs.remove(key);
            deletedDraftCount += 1;
            continue;
          }

          final sanitized = _sanitizeSnapshot(draft);
          if (!sanitized.changed) {
            continue;
          }
          sanitizedDraftCount += 1;
          removedAttachmentCount += sanitized.removedAttachments.length;
          deletedCacheFileCount += await _deleteRemovedCacheFiles(
            sanitized.removedAttachments,
          );
          if (sanitized.snapshot.isEmpty) {
            await prefs.remove(key);
            deletedDraftCount += 1;
          } else {
            await prefs.setString(
              key,
              jsonEncode(_codec.encode(sanitized.snapshot)),
            );
          }
        } catch (_) {
          failedDraftCount += 1;
        }
      }

      return ReplyDraftAttachmentMaintenanceResult(
        scannedDraftCount: scannedDraftCount,
        sanitizedDraftCount: sanitizedDraftCount,
        deletedDraftCount: deletedDraftCount,
        removedAttachmentCount: removedAttachmentCount,
        deletedCacheFileCount: deletedCacheFileCount,
        failedDraftCount: failedDraftCount,
      );
    } catch (_) {
      return const ReplyDraftAttachmentMaintenanceResult(
        scannedDraftCount: 0,
        sanitizedDraftCount: 0,
        deletedDraftCount: 0,
        removedAttachmentCount: 0,
        deletedCacheFileCount: 0,
        failedDraftCount: 1,
      );
    }
  }

  Future<SharedPreferences> _prefs() async {
    final sharedPreferences = _sharedPreferences;
    if (sharedPreferences != null) {
      return sharedPreferences;
    }
    return SharedPreferences.getInstance();
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

  Future<int> _deleteRemovedCacheFiles(
    List<ReplyImageAttachment> attachments,
  ) async {
    var deletedCount = 0;
    for (final attachment in attachments) {
      if (await _cacheStorage.deleteCachePathIfOwned(attachment.cachePath)) {
        deletedCount += 1;
      }
    }
    return deletedCount;
  }
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
