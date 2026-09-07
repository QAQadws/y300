import 'package:flutter/widgets.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';

abstract interface class ForumImagePrecacheService {
  Future<ForumImagePrecacheResult> ensureDiskCached(ForumImageLoadSpec spec);

  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  });
}

/// Optional lifecycle-aware extension used by page and reader schedulers.
///
/// Cancelling a scope prevents queued decode work and stale UI updates. A
/// download that already reached the transport may still finish and populate
/// the shared disk cache.
abstract interface class ScopedForumImagePrecacheService {
  Future<ForumImagePrecacheResult> ensureDiskCachedScoped(
    ForumImageLoadSpec spec, {
    required ForumImageWorkScope scope,
  });

  Future<ForumImagePrecacheResult> precacheDecodedScoped({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    required ForumImageWorkScope scope,
    Size? expectedDisplaySize,
  });
}

abstract interface class ForumImageWorkScope {
  bool get isActive;
}

final class ForumImageWorkToken implements ForumImageWorkScope {
  bool _cancelled = false;

  @override
  bool get isActive => !_cancelled;

  void cancel() {
    _cancelled = true;
  }
}

class ForumImagePrecacheResult {
  const ForumImagePrecacheResult({
    required this.success,
    this.fromDiskCache = false,
    this.decoded = false,
    this.diskCacheAttempted = false,
    this.decodePrecacheAttempted = false,
    this.cacheKey,
    this.localPath,
    this.error,
    this.failureReason,
  });

  final bool success;
  final bool fromDiskCache;
  final bool decoded;
  final bool diskCacheAttempted;
  final bool decodePrecacheAttempted;
  final String? cacheKey;
  final String? localPath;
  final Object? error;
  final String? failureReason;

  static ForumImagePrecacheResult failed(
    Object error, {
    String? failureReason,
    bool diskCacheAttempted = false,
    bool decodePrecacheAttempted = false,
  }) {
    return ForumImagePrecacheResult(
      success: false,
      error: error,
      failureReason: failureReason ?? error.runtimeType.toString(),
      diskCacheAttempted: diskCacheAttempted,
      decodePrecacheAttempted: decodePrecacheAttempted,
    );
  }

  static const ForumImagePrecacheResult cancelled = ForumImagePrecacheResult(
    success: false,
    failureReason: 'cancelled_before_decode',
  );
}
