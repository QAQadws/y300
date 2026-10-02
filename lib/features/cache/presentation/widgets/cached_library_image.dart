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
    this.localFileFallbackPredicate,
    this.localFileFallback,
    this.decodeDisplaySize,
    required this.placeholder,
    this.errorPlaceholder,
    this.referer,
    this.onImageResolved,
    this.onImageFailed,
    this.onFirstFrameRendered,
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

  /// Selects [localFileFallback] before a cached or preferred file is decoded.
  /// Pair with [CachedImageRemoteDisplayPolicy.afterCacheWrite] when remote
  /// content must also wait for this check. Inspection failures keep the usual
  /// image path, including its decode-failure diagnostics.
  final Future<bool> Function(String localPath)? localFileFallbackPredicate;
  final Widget? localFileFallback;
  final Size? decodeDisplaySize;
  final Widget placeholder;
  final Widget? errorPlaceholder;
  final String? referer;
  final ValueChanged<Size>? onImageResolved;
  final VoidCallback? onImageFailed;
  final ValueChanged<LibraryImageFrameSource>? onFirstFrameRendered;
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
  bool _remoteProviderStarted = false;
  bool _cacheWriteFailed = false;
  bool _useLocalFileFallback = false;
  bool _displaySettled = false;
  bool _firstFrameRendered = false;
  bool _settledRebuildScheduled = false;
  String? _dimensionLocalPath;
  int? _knownImageWidth;
  int? _knownImageHeight;
  String? _cacheReadyLocalPath;
  String? _scheduledDimensionIdentity;
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
        oldWidget.localFileFallbackPredicate !=
            widget.localFileFallbackPredicate ||
        oldWidget.remoteDisplayPolicy != widget.remoteDisplayPolicy ||
        oldWidget.retryToken != widget.retryToken) {
      _restartCacheFlow();
      return;
    }
    if (oldWidget.onImageResolved == null && widget.onImageResolved != null) {
      _scheduleDimensionProbe(widget.request, _generation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final generation = _generation;
    if (_localPath == null && _allowRemoteFallback) {
      _remoteProviderStarted = true;
    }
    return DelayedImageLoadingOverlay(
      loadIdentity: generation,
      isLoading: !_displaySettled,
      enabled: widget.showDelayedLoadingIndicator,
      delay: widget.loadingIndicatorDelay,
      color: widget.loadingIndicatorColor,
      isLoadActive: (loadIdentity) =>
          mounted && loadIdentity == _generation && !_displaySettled,
      child: _useLocalFileFallback
          ? widget.localFileFallback ??
                widget.errorPlaceholder ??
                widget.placeholder
          : _cacheWriteFailed
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
              onFirstFrameRendered: (source) =>
                  _handleFirstFrameRendered(request, source, generation),
              onLocalImageDecodeFailed: (error, stackTrace) =>
                  _handleLocalImageDecodeFailed(
                    request,
                    error,
                    stackTrace,
                    generation,
                  ),
              onImageFailed: () => _handleImageFailed(generation),
            ),
    );
  }

  void _handleFirstFrameRendered(
    ImageCacheRequest? request,
    LibraryImageFrameSource source,
    int generation,
  ) {
    if (generation != _generation || _useLocalFileFallback) {
      return;
    }
    _firstFrameRendered = true;
    if (source == LibraryImageFrameSource.remote) {
      _displayedRemoteImage = true;
    }
    _markDisplaySettled(generation);
    widget.onFirstFrameRendered?.call(source);
    _scheduleDimensionProbe(request, generation);
  }

  void _handleImageFailed(int generation) {
    if (generation != _generation || _useLocalFileFallback) {
      return;
    }
    final cacheReadyLocalPath = _cacheReadyLocalPath?.trim();
    if (_localPath == null &&
        _remoteProviderStarted &&
        cacheReadyLocalPath != null &&
        cacheReadyLocalPath.isNotEmpty) {
      setState(() {
        _localPath = cacheReadyLocalPath;
        _allowRemoteFallback = false;
        _remoteProviderStarted = false;
      });
      return;
    }
    _markDisplaySettled(generation);
    widget.onImageFailed?.call();
  }

  void _handleLocalImageDecodeFailed(
    ImageCacheRequest? request,
    Object error,
    StackTrace? stackTrace,
    int generation,
  ) {
    if (generation != _generation || request == null) {
      return;
    }
    final service = ref.read(imageCacheServiceProvider);
    if (service is ImageCacheDecodeFailureReporter) {
      final reporter = service as ImageCacheDecodeFailureReporter;
      reporter.reportDecodeFailure(
        request: request,
        error: error,
        stackTrace: stackTrace,
      );
    }
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
    _remoteProviderStarted = false;
    _cacheWriteFailed = false;
    _useLocalFileFallback = false;
    _displaySettled = !_hasDisplaySource;
    _firstFrameRendered = false;
    _settledRebuildScheduled = false;
    _dimensionLocalPath = null;
    _knownImageWidth = null;
    _knownImageHeight = null;
    _cacheReadyLocalPath = null;
    _scheduledDimensionIdentity = null;
    final preferredLocalPath = widget.preferredLocalPath?.trim();
    if (widget.imageProviderOverride != null) {
      _dimensionLocalPath = preferredLocalPath;
      return;
    }
    final request = widget.request;
    if (request == null) {
      return;
    }
    if (preferredLocalPath != null && preferredLocalPath.isNotEmpty) {
      if (widget.localFileFallbackPredicate == null) {
        _dimensionLocalPath = preferredLocalPath;
        _localPath = preferredLocalPath;
        _allowRemoteFallback = true;
      } else {
        unawaited(_resolvePreferredLocalImage(preferredLocalPath, _generation));
      }
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

  Future<void> _resolvePreferredLocalImage(
    String localPath,
    int generation,
  ) async {
    final useFallback = await _resolveLocalFileFallback(localPath, generation);
    if (!_isActive(generation) || useFallback) return;
    setState(() {
      _dimensionLocalPath = localPath;
      _localPath = localPath;
      _allowRemoteFallback = true;
    });
  }

  Future<bool> _resolveLocalFileFallback(
    String localPath,
    int generation,
  ) async {
    final predicate = widget.localFileFallbackPredicate;
    if (predicate == null) return false;
    var useFallback = false;
    try {
      useFallback = await predicate(localPath);
    } catch (_) {
      // An optional content check must not hide a real image-loading failure.
    }
    if (!_isActive(generation) || !useFallback) return false;
    setState(() {
      _useLocalFileFallback = true;
      _displaySettled = true;
      _localPath = null;
      _allowRemoteFallback = false;
      _remoteProviderStarted = false;
      _cacheReadyLocalPath = null;
      _dimensionLocalPath = null;
      _knownImageWidth = null;
      _knownImageHeight = null;
      _scheduledDimensionIdentity = null;
    });
    return true;
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
      if (widget.localFileFallbackPredicate != null) {
        final useFallback = await _resolveLocalFileFallback(
          cachedLocalPath,
          generation,
        );
        if (!_isActive(generation) || useFallback) return;
      }
      widget.onLocalPathResolved?.call(cachedLocalPath);
      _dimensionLocalPath = cachedLocalPath;
      _knownImageWidth = cached?.width;
      _knownImageHeight = cached?.height;
      _cacheReadyLocalPath = cachedLocalPath;
      _scheduleDimensionProbe(request, generation);
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
    if (widget.localFileFallbackPredicate != null) {
      final useFallback = await _resolveLocalFileFallback(
        result.localPath!.trim(),
        generation,
      );
      if (!_isActive(generation) || useFallback) return;
    }
    widget.onLocalPathResolved?.call(result.localPath!.trim());
    _dimensionLocalPath = result.localPath!.trim();
    _knownImageWidth = result.width;
    _knownImageHeight = result.height;
    _cacheReadyLocalPath = result.localPath!.trim();
    _scheduleDimensionProbe(request, generation);
    if (_displayedRemoteImage || _remoteProviderStarted) {
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

  void _scheduleDimensionProbe(ImageCacheRequest? request, int generation) {
    final callback = widget.onImageResolved;
    final localPath = _dimensionLocalPath?.trim();
    final cacheKey = request?.cacheKey.trim();
    if (_useLocalFileFallback ||
        callback == null ||
        localPath == null ||
        localPath.isEmpty ||
        cacheKey == null ||
        cacheKey.isEmpty) {
      return;
    }
    final identity = '$cacheKey\u0000$localPath';
    if (_scheduledDimensionIdentity == identity) {
      return;
    }
    final knownWidth = _knownImageWidth;
    final knownHeight = _knownImageHeight;
    if (knownWidth != null &&
        knownHeight != null &&
        knownWidth > 0 &&
        knownHeight > 0) {
      _scheduledDimensionIdentity = identity;
      callback(Size(knownWidth.toDouble(), knownHeight.toDouble()));
      return;
    }
    // Missing metadata still waits for the displayed provider's first frame.
    // This prevents a hidden or failed image from starting a second file task.
    if (!_firstFrameRendered) {
      return;
    }
    _scheduledDimensionIdentity = identity;
    final probe = ref.read(encodedImageDimensionProbeProvider);
    unawaited(
      probe
          .probe(cacheKey: cacheKey, localPath: localPath)
          .then((size) {
            if (!_isActive(generation) ||
                _scheduledDimensionIdentity != identity ||
                _dimensionLocalPath?.trim() != localPath ||
                widget.request?.cacheKey.trim() != cacheKey) {
              return;
            }
            final service = ref.read(imageCacheServiceProvider);
            if (service is ImageCacheDimensionRecorder) {
              final recorder = service as ImageCacheDimensionRecorder;
              unawaited(_recordDimensions(recorder, cacheKey, size));
            }
            widget.onImageResolved?.call(size);
          })
          .catchError((Object _, StackTrace _) {
            // Intrinsic dimensions only improve layout hints. Display success
            // and its loading state are independent from metadata failures.
          }),
    );
  }
}
