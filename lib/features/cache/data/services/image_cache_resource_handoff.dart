import 'package:y300/features/cache/domain/models/image_cache_models.dart';

/// No file/provider/context is held; managed mutations and source owner changes
/// retire this optional fast path synchronously. The normal read path recovers
/// files removed externally after validation.
final class ValidatedImageCacheResourceHandoff
    implements ImageCacheResourceHandoff {
  ValidatedImageCacheResourceHandoff({
    required this.request,
    required this.result,
    required bool Function() isCurrent,
    required void Function() recordAccess,
    Duration Function()? elapsed,
    Duration lifetime = const Duration(seconds: 2),
  }) : _isCurrent = isCurrent,
       _recordAccess = recordAccess,
       _elapsed = elapsed ?? _monotonicClock(),
       _lifetime = lifetime;

  final ImageCacheRequest request;
  final CachedImageResult result;
  final bool Function() _isCurrent;
  final void Function() _recordAccess;
  final Duration Function() _elapsed;
  final Duration _lifetime;
  bool _used = false;
  bool _invalid = false;

  @override
  bool get isCurrent => !_invalid && _isCurrent();

  @override
  CachedImageResult? take(ImageCacheRequest next) {
    if (_used || !isCurrent || _elapsed() >= _lifetime) return null;
    _used = true;
    if (request.cacheKey != next.cacheKey ||
        request.sourceUrl != next.sourceUrl ||
        request.referer != next.referer ||
        request.ownerType != next.ownerType ||
        request.ownerId != next.ownerId ||
        request.role != next.role ||
        request.episodeId != next.episodeId ||
        request.imageIndex != next.imageIndex ||
        request.effectiveRetentionClass != next.effectiveRetentionClass ||
        request.protected != next.protected) {
      return null;
    }
    _recordAccess();
    return result;
  }

  @override
  void invalidate() => _invalid = true;

  static Duration Function() _monotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }
}
