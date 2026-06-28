import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/composer_shared/data/services/composer_draft_snapshot_codec.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_cache_storage.dart';
import 'package:y300/features/composer_shared/data/repositories/shared_preferences_composer_draft_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_draft_attachment_sanitizer.dart';

abstract class ComposerDraftAttachmentMaintenanceService {
  Future<ComposerDraftAttachmentMaintenanceResult> maintain();
}

class ComposerDraftAttachmentMaintenanceResult {
  const ComposerDraftAttachmentMaintenanceResult({
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

/// 启动时跑一次的"草稿维护"任务，把过期附件清理掉，避免本地草稿越积越大。
/// 与 [SharedPreferencesComposerDraftRepository] 共用同一份 codec 与 sanitizer。
class SharedPreferencesComposerDraftAttachmentMaintenanceService
    implements ComposerDraftAttachmentMaintenanceService {
  SharedPreferencesComposerDraftAttachmentMaintenanceService({
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

  final SharedPreferences? _sharedPreferences;
  final ComposerDraftSnapshotJsonCodec _codec;
  final ComposerDraftAttachmentSanitizer _sanitizer;
  final ComposerUploadCacheStorage _cacheStorage;
  final DateTime Function() _now;

  @override
  Future<ComposerDraftAttachmentMaintenanceResult> maintain() async {
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
          SharedPreferencesComposerDraftRepository.draftKeyPrefix,
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

      return ComposerDraftAttachmentMaintenanceResult(
        scannedDraftCount: scannedDraftCount,
        sanitizedDraftCount: sanitizedDraftCount,
        deletedDraftCount: deletedDraftCount,
        removedAttachmentCount: removedAttachmentCount,
        deletedCacheFileCount: deletedCacheFileCount,
        failedDraftCount: failedDraftCount,
      );
    } catch (_) {
      return const ComposerDraftAttachmentMaintenanceResult(
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
    );
  }

  Future<int> _deleteRemovedCacheFiles(
    List<ComposerImageAttachment> attachments,
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

  final ComposerDraftSnapshot snapshot;
  final List<ComposerImageAttachment> removedAttachments;

  bool get changed {
    return removedAttachments.isNotEmpty;
  }
}
