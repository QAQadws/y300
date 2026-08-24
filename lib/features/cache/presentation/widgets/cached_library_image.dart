import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/delayed_image_loading_overlay.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';

enum CachedImageRemoteDisplayPolicy { eager, afterCacheWrite }

/// Binds an explicit cache request to [LibraryCachedImage].
///
/// Business layers still own cache-key and role decisions.  This widget only
/// performs the shared "ensure cached, then prefer local file" presentation
/// flow so UI surfaces do not reimplement cache service orchestration.
class CachedLibraryImage extends ConsumerStatefulWidget {
  const CachedLibraryImage({
    super.key,
    required this.request,
    required this.fit,
    this.width,
    this.height,
    this.preferredLocalPath,
    this.decodeDisplaySize,
    required this.placeholder,
    this.errorPlaceholder,
    this.referer,
    this.onImageResolved,
    this.onImageFailed,
    this.onLocalPathResolved,
    this.imageProviderOverride,
    this.remoteImageProviderOverride,
    this.showDelayedLoadingIndicator = false,
    this.loadingIndicatorDelay = const Duration(milliseconds: 300),
    this.loadingIndicatorColor,
    this.fadeInDuration = Duration.zero,
    this.remoteDisplayPolicy = CachedImageRemoteDisplayPolicy.eager,
    this.retryToken = 0,
  });

  final ImageCacheRequest? request;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String? preferredLocalPath;
  final Size? decodeDisplaySize;
  final Widget placeholder;
  final Widget? errorPlaceholder;
  final String? referer;
  final ValueChanged<Size>? onImageResolved;
  final VoidCallback? onImageFailed;
  final ValueChanged<String>? onLocalPathResolved;
  @visibleForTesting
  final ImageProvider? imageProviderOverride;
  @visibleForTesting
  final ImageProvider? remoteImageProviderOverride;
  final bool showDelayedLoadingIndicator;
  final Duration loadingIndicatorDelay;
  final Color? loadingIndicatorColor;

  /// Optional first-frame transition. It remains disabled by default so each
  /// business surface can opt in without changing shared image behavior.
  final Duration fadeInDuration;

  /// Controls whether a cache miss may display a direct network image while
  /// the persistent cache write is still running.
  final CachedImageRemoteDisplayPolicy remoteDisplayPolicy;

  /// 重试代次。自增会重跑一次"缓存查询 → ensureCached → 远端兜底"整条流程，
  /// 并透传给 [LibraryCachedImage] 重建解码；失败可能出在其中任一段。
  final int retryToken;

  @override
  ConsumerState<CachedLibraryImage> createState() => _CachedLibraryImageState();
}

class _CachedLibraryImageState extends ConsumerState<CachedLibraryImage> {
  String? _localPath;
  bool _allowRemoteFallback = false;
  bool _displayedRemoteImage = false;
  bool _cacheWriteFailed = false;
  bool _displaySettled = false;
  bool _settledRebuildScheduled = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _restartCacheFlow();
  }

  @override
  void didUpdateWidget(covariant CachedLibraryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProviderOverride != widget.imageProviderOverride ||
        oldWidget.remoteImageProviderOverride !=
            widget.remoteImageProviderOverride ||
        oldWidget.referer != widget.referer) {
      _restartCacheFlow();
      return;
    }
    if (oldWidget.request?.cacheKey != widget.request?.cacheKey ||
        oldWidget.request?.sourceUrl != widget.request?.sourceUrl ||
        oldWidget.preferredLocalPath != widget.preferredLocalPath ||
        oldWidget.remoteDisplayPolicy != widget.remoteDisplayPolicy ||
        oldWidget.retryToken != widget.retryToken) {
      _restartCacheFlow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final generation = _generation;
    return DelayedImageLoadingOverlay(
      loadIdentity: generation,
      isLoading: !_displaySettled,
      enabled: widget.showDelayedLoadingIndicator,
      delay: widget.loadingIndicatorDelay,
      color: widget.loadingIndicatorColor,
      isLoadActive: (loadIdentity) =>
          mounted && loadIdentity == _generation && !_displaySettled,
      child: _cacheWriteFailed
          ? widget.errorPlaceholder ?? widget.placeholder
          : LibraryCachedImage(
              localPath: _localPath,
              imageUrl: _allowRemoteFallback ? request?.sourceUrl : null,
              cacheKey: request?.cacheKey,
              referer: widget.referer ?? request?.referer,
              imageProviderOverride: widget.imageProviderOverride,
              remoteImageProviderOverride: widget.remoteImageProviderOverride,
              fit: widget.fit,
              width: widget.width,
              height: widget.height,
              decodeDisplaySize: widget.decodeDisplaySize,
              placeholder: widget.placeholder,
              errorPlaceholder: widget.errorPlaceholder,
              fadeInDuration: widget.fadeInDuration,
              retryToken: widget.retryToken,
              onImageResolved: (size) =>
                  _handleImageResolved(request, size, generation),
              onRemoteImageResolved: () =>
                  _handleRemoteImageResolved(generation),
              onImageFailed: () => _handleImageFailed(generation),
            ),
    );
  }

  void _handleImageResolved(
    ImageCacheRequest? request,
    Size size,
    int generation,
  ) {
    if (generation != _generation) {
      return;
    }
    _markDisplaySettled(generation);
    final cacheKey = request?.cacheKey.trim();
    if (cacheKey != null && cacheKey.isNotEmpty) {
      final service = ref.read(imageCacheServiceProvider);
      if (service is ImageCacheDimensionRecorder) {
        final recorder = service as ImageCacheDimensionRecorder;
        unawaited(_recordDimensions(recorder, cacheKey, size));
      }
    }
    widget.onImageResolved?.call(size);
  }

  void _handleRemoteImageResolved(int generation) {
    if (generation != _generation) {
      return;
    }
    _displayedRemoteImage = true;
    _markDisplaySettled(generation);
  }

  void _handleImageFailed(int generation) {
    if (generation != _generation) {
      return;
    }
    _markDisplaySettled(generation);
    widget.onImageFailed?.call();
  }

  void _markDisplaySettled(int generation) {
    if (generation != _generation || _displaySettled) {
      return;
    }
    _displaySettled = true;
    if (_settledRebuildScheduled) {
      return;
    }
    _settledRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _settledRebuildScheduled = false;
      });
    });
  }

  Future<void> _recordDimensions(
    ImageCacheDimensionRecorder service,
    String cacheKey,
    Size size,
  ) async {
    try {
      await service.recordResolvedDimensions(cacheKey: cacheKey, size: size);
    } catch (_) {
      // Image size metadata only improves future layout hints; display should
      // never fail because persisting the hint failed.
    }
  }

  void _restartCacheFlow() {
    _generation += 1;
    _localPath = null;
    _allowRemoteFallback = false;
    _displayedRemoteImage = false;
    _cacheWriteFailed = false;
    _displaySettled = !_hasDisplaySource;
    _settledRebuildScheduled = false;
    if (widget.imageProviderOverride != null) {
      return;
    }
    final request = widget.request;
    if (request == null) {
      return;
    }
    final preferredLocalPath = widget.preferredLocalPath?.trim();
    if (preferredLocalPath != null && preferredLocalPath.isNotEmpty) {
      _localPath = preferredLocalPath;
      _allowRemoteFallback = true;
      return;
    }
    if (request.cacheKey.trim().isEmpty) {
      if (widget.remoteDisplayPolicy == CachedImageRemoteDisplayPolicy.eager) {
        _allowRemoteFallback = true;
      } else {
        _scheduleCacheFailure(_generation);
      }
      return;
    }
    unawaited(_resolveCachedImage(request, _generation));
  }

  Future<void> _resolveCachedImage(
    ImageCacheRequest request,
    int generation,
  ) async {
    final service = ref.read(imageCacheServiceProvider);
    final cached = await service.getCached(request.cacheKey);
    if (!_isActive(generation)) {
      return;
    }
    if (_hasUsableLocalPath(cached)) {
      final cachedLocalPath = cached?.localPath?.trim();
      if (cachedLocalPath == null || cachedLocalPath.isEmpty) {
        return;
      }
      widget.onLocalPathResolved?.call(cachedLocalPath);
      setState(() {
        _localPath = cachedLocalPath;
        _allowRemoteFallback = false;
      });
      return;
    }

    if (widget.remoteDisplayPolicy == CachedImageRemoteDisplayPolicy.eager) {
      setState(() {
        _allowRemoteFallback = true;
      });
    }

    final result = await service.ensureCached(request);
    if (!_isActive(generation)) {
      return;
    }
    if (!_hasUsableLocalPath(result)) {
      if (widget.remoteDisplayPolicy ==
          CachedImageRemoteDisplayPolicy.afterCacheWrite) {
        setState(() {
          _cacheWriteFailed = true;
        });
        _handleImageFailed(generation);
      }
      return;
    }
    widget.onLocalPathResolved?.call(result.localPath!.trim());
    if (_displayedRemoteImage) {
      return;
    }
    setState(() {
      _localPath = result.localPath;
      _allowRemoteFallback = false;
    });
  }

  void _scheduleCacheFailure(int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isActive(generation)) {
        setState(() {
          _cacheWriteFailed = true;
        });
        _handleImageFailed(generation);
      }
    });
  }

  bool _isActive(int generation) {
    return mounted && generation == _generation;
  }

  bool _hasUsableLocalPath(CachedImageResult? result) {
    final localPath = result?.localPath?.trim();
    return result != null &&
        result.success &&
        localPath != null &&
        localPath.isNotEmpty;
  }

  bool get _hasDisplaySource {
    final preferredLocalPath = widget.preferredLocalPath?.trim();
    return widget.imageProviderOverride != null ||
        widget.request != null ||
        (preferredLocalPath != null && preferredLocalPath.isNotEmpty);
  }
}
