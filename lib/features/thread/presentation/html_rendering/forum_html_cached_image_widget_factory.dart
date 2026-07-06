import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';

class ForumHtmlCachedImageWidgetFactory extends WidgetFactory {
  ForumHtmlCachedImageWidgetFactory({
    required this.threadId,
    this.imageHeaderBuilder,
    this.imageCacheOwnerId,
    this.onImageResolved,
  });

  final String threadId;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String? imageCacheOwnerId;
  final ValueChanged<Size>? onImageResolved;
  static const double _fallbackImageAspectRatio = 0.7;
  var _nextImageIndex = 0;

  @override
  Widget? buildImageWidget(BuildTree tree, ImageSource src) {
    final url = src.url.trim();
    if (url.startsWith('asset:') ||
        url.startsWith('data:image/') ||
        url.startsWith('file:')) {
      return super.buildImageWidget(tree, src);
    }

    final resolved = urlFull(url);
    final uri = resolved == null ? null : Uri.tryParse(resolved);
    if (resolved == null ||
        uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return super.buildImageWidget(tree, src);
    }

    final isSticker = _isForumStickerImage(resolved);
    final imageIndex = isSticker ? null : _nextImageIndex++;
    final request = isSticker
        ? ForumImageCacheRequests.remoteSmiley(url: resolved)
        : ForumImageCacheRequests.threadInline(
            tid: _cacheOwnerId(),
            url: resolved,
            imageIndex: imageIndex,
          );
    final explicitSize = _explicitSize(src);
    if (isSticker) {
      return _ForumHtmlCachedStickerImageView(
        request: request,
        explicitSize: explicitSize,
        imageHeaderBuilder: imageHeaderBuilder,
        onImageResolved: onImageResolved,
      );
    }

    final image = CachedLibraryImage(
      request: request,
      fit: BoxFit.fitWidth,
      width: explicitSize?.width,
      height: explicitSize?.height,
      placeholder: const _ForumHtmlImageLoadingPlaceholder(
        delay: Duration(milliseconds: 350),
      ),
      errorPlaceholder: const _ForumHtmlImageErrorPlaceholder(
        icon: Icons.broken_image_outlined,
      ),
      headerBuilder: imageHeaderBuilder,
      onImageResolved: onImageResolved,
    );

    return AspectRatio(
      aspectRatio: _imageAspectRatio(explicitSize),
      child: image,
    );
  }

  String _cacheOwnerId() {
    final owner = imageCacheOwnerId?.trim();
    if (owner != null && owner.isNotEmpty) {
      return owner;
    }
    final tid = threadId.trim();
    return tid.isEmpty ? 'unknown' : tid;
  }

  Size? _explicitSize(ImageSource src) {
    final width = src.width;
    final height = src.height;
    if (width != null &&
        height != null &&
        width.isFinite &&
        height.isFinite &&
        width > 0 &&
        height > 0) {
      return Size(width, height);
    }
    return null;
  }

  double _imageAspectRatio(Size? explicitSize) {
    if (explicitSize == null) {
      return _fallbackImageAspectRatio;
    }
    final ratio = explicitSize.width / explicitSize.height;
    return ratio.isFinite && ratio > 0 ? ratio : _fallbackImageAspectRatio;
  }

  bool _isForumStickerImage(String url) {
    return url.contains('/static/image/smiley/') ||
        url.contains('static/image/smiley/');
  }
}

class _ForumHtmlCachedStickerImageView extends ConsumerStatefulWidget {
  const _ForumHtmlCachedStickerImageView({
    required this.request,
    required this.explicitSize,
    required this.imageHeaderBuilder,
    required this.onImageResolved,
  });

  final ImageCacheRequest request;
  final Size? explicitSize;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<Size>? onImageResolved;

  @override
  ConsumerState<_ForumHtmlCachedStickerImageView> createState() =>
      _ForumHtmlCachedStickerImageViewState();
}

class _ForumHtmlCachedStickerImageViewState
    extends ConsumerState<_ForumHtmlCachedStickerImageView> {
  Size? _cachedSize;
  String? _loadedCacheKey;

  @override
  void initState() {
    super.initState();
    _loadCachedSize();
  }

  @override
  void didUpdateWidget(covariant _ForumHtmlCachedStickerImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.cacheKey != widget.request.cacheKey ||
        oldWidget.explicitSize != widget.explicitSize) {
      _cachedSize = null;
      _loadedCacheKey = null;
      _loadCachedSize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.explicitSize ?? _cachedSize;
    final child = CachedLibraryImage(
      request: widget.request,
      fit: BoxFit.contain,
      width: size?.width,
      height: size?.height,
      placeholder: const SizedBox.shrink(),
      errorPlaceholder: Icon(
        Icons.image_not_supported_outlined,
        size: (size?.shortestSide ?? 14).clamp(12, 18).toDouble(),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      headerBuilder: widget.imageHeaderBuilder,
      onImageResolved: widget.onImageResolved,
    );
    if (size == null) {
      return child;
    }
    return SizedBox(width: size.width, height: size.height, child: child);
  }

  Future<void> _loadCachedSize() async {
    if (widget.explicitSize != null) {
      return;
    }
    final cacheKey = widget.request.cacheKey.trim();
    if (cacheKey.isEmpty || _loadedCacheKey == cacheKey) {
      return;
    }
    _loadedCacheKey = cacheKey;
    final result = await ref
        .read(imageCacheServiceProvider)
        .getCached(cacheKey);
    if (!mounted || _loadedCacheKey != cacheKey || result == null) {
      return;
    }
    final width = result.width;
    final height = result.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return;
    }
    final next = Size(width.toDouble(), height.toDouble());
    if (_cachedSize == next || widget.explicitSize != null) {
      return;
    }
    setState(() {
      _cachedSize = next;
    });
  }
}

class _ForumHtmlImageLoadingPlaceholder extends StatefulWidget {
  const _ForumHtmlImageLoadingPlaceholder({required this.delay});

  final Duration delay;

  @override
  State<_ForumHtmlImageLoadingPlaceholder> createState() =>
      _ForumHtmlImageLoadingPlaceholderState();
}

class _ForumHtmlImageLoadingPlaceholderState
    extends State<_ForumHtmlImageLoadingPlaceholder> {
  Timer? _timer;
  bool _showSpinner = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showSpinner = true;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ForumHtmlImageSurface(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: _showSpinner
            ? SizedBox(
                key: const Key('forum-html-image-loading-spinner'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : const SizedBox.shrink(key: ValueKey('forum-html-image-idle')),
      ),
    );
  }
}

class _ForumHtmlImageErrorPlaceholder extends StatelessWidget {
  const _ForumHtmlImageErrorPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _ForumHtmlImageSurface(
      child: Icon(
        icon,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ForumHtmlImageSurface extends StatelessWidget {
  const _ForumHtmlImageSurface({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
      child: child,
    );
  }
}
