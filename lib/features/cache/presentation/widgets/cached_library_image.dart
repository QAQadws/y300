import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
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

  @override
  ConsumerState<CachedLibraryImage> createState() => _CachedLibraryImageState();
}

class _CachedLibraryImageState extends ConsumerState<CachedLibraryImage> {
  String? _localPath;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.imageProviderOverride == null) {
      _ensureCached();
    }
  }

  @override
  void didUpdateWidget(covariant CachedLibraryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProviderOverride != widget.imageProviderOverride) {
      _localPath = null;
      if (widget.imageProviderOverride == null) {
        _ensureCached();
      }
      return;
    }
    if (oldWidget.request?.cacheKey != widget.request?.cacheKey ||
        oldWidget.request?.sourceUrl != widget.request?.sourceUrl) {
      _localPath = null;
      if (widget.imageProviderOverride == null) {
        _ensureCached();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return LibraryCachedImage(
      localPath: _localPath,
      imageUrl: request?.sourceUrl,
      imageProviderOverride: widget.imageProviderOverride,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      placeholder: widget.placeholder,
      errorPlaceholder: widget.errorPlaceholder,
      headerBuilder: widget.headerBuilder,
      onImageResolved: (size) => _handleImageResolved(request, size),
      onImageFailed: widget.onImageFailed,
    );
  }

  void _handleImageResolved(ImageCacheRequest? request, Size size) {
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

  void _ensureCached() {
    if (widget.imageProviderOverride != null) {
      return;
    }
    final request = widget.request;
    if (request == null || request.cacheKey.trim().isEmpty) {
      return;
    }
    final generation = ++_generation;
    unawaited(
      ref.read(imageCacheServiceProvider).ensureCached(request).then((result) {
        if (!mounted || generation != _generation || !result.success) {
          return;
        }
        setState(() {
          _localPath = result.localPath;
        });
      }),
    );
  }
}
