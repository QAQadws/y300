import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';

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
    required this.placeholder,
    this.errorPlaceholder,
    this.headerBuilder,
    this.onImageResolved,
    this.onImageFailed,
    this.imageProviderOverride,
    this.remoteImageProviderOverride,
  });

  final ImageCacheRequest? request;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget placeholder;
  final Widget? errorPlaceholder;
  final ImageRequestHeaderBuilder? headerBuilder;
  final ValueChanged<Size>? onImageResolved;
  final VoidCallback? onImageFailed;
  @visibleForTesting
  final ImageProvider? imageProviderOverride;
  @visibleForTesting
  final ImageProvider? remoteImageProviderOverride;

  @override
  ConsumerState<CachedLibraryImage> createState() => _CachedLibraryImageState();
}

class _CachedLibraryImageState extends ConsumerState<CachedLibraryImage> {
  String? _localPath;
  bool _allowRemoteFallback = false;
  bool _displayedRemoteImage = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _restartCacheFlow();
  }

  @override
  void didUpdateWidget(covariant CachedLibraryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProviderOverride != widget.imageProviderOverride) {
      _restartCacheFlow();
      return;
    }
    if (oldWidget.request?.cacheKey != widget.request?.cacheKey ||
        oldWidget.request?.sourceUrl != widget.request?.sourceUrl) {
      _restartCacheFlow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final generation = _generation;
    return LibraryCachedImage(
      localPath: _localPath,
      imageUrl: _allowRemoteFallback ? request?.sourceUrl : null,
      imageProviderOverride: widget.imageProviderOverride,
      remoteImageProviderOverride: widget.remoteImageProviderOverride,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      placeholder: widget.placeholder,
      errorPlaceholder: widget.errorPlaceholder,
      headerBuilder: widget.headerBuilder,
      onImageResolved: (size) =>
          _handleImageResolved(request, size, generation),
      onRemoteImageResolved: () => _handleRemoteImageResolved(generation),
      onImageFailed: widget.onImageFailed,
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
    if (widget.imageProviderOverride != null) {
      return;
    }
    final request = widget.request;
    if (request == null) {
      return;
    }
    if (request.cacheKey.trim().isEmpty) {
      _allowRemoteFallback = true;
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
      setState(() {
        _localPath = cached!.localPath;
        _allowRemoteFallback = false;
      });
      return;
    }

    setState(() {
      _allowRemoteFallback = true;
    });

    final result = await service.ensureCached(request);
    if (!_isActive(generation) || !_hasUsableLocalPath(result)) {
      return;
    }
    if (_displayedRemoteImage) {
      return;
    }
    setState(() {
      _localPath = result.localPath;
      _allowRemoteFallback = false;
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
}
