import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_layout_hint_resolver.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';

class ForumHtmlCachedImageWidgetFactory extends WidgetFactory {
  ForumHtmlCachedImageWidgetFactory({
    required this.threadId,
    this.imageHeaderBuilder,
    this.imageCacheOwnerId,
    this.onImageResolved,
    ForumImageRequestResolver? imageRequestResolver,
    this.imageDimensionIndex,
    ForumImageLayoutHintResolver? layoutHintResolver,
  }) : imageRequestResolver =
           imageRequestResolver ?? const DefaultForumImageRequestResolver(),
       layoutHintResolver =
           layoutHintResolver ?? const ForumImageLayoutHintResolver();

  final String threadId;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String? imageCacheOwnerId;
  final ValueChanged<Size>? onImageResolved;
  final ForumImageRequestResolver imageRequestResolver;
  final ForumImageDimensionIndex? imageDimensionIndex;
  final ForumImageLayoutHintResolver layoutHintResolver;
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
    final explicitSize = _explicitSize(src);
    final spec = ForumImageLoadSpec(
      kind: isSticker
          ? ForumImageKind.remoteSmiley
          : ForumImageKind.threadInline,
      url: uri,
      ownerId: isSticker ? null : _cacheOwnerId(),
      imageIndex: imageIndex,
      htmlWidth: explicitSize?.width,
      htmlHeight: explicitSize?.height,
    );
    final request = imageRequestResolver.resolveCacheRequest(spec);
    if (request == null) {
      return super.buildImageWidget(tree, src);
    }
    if (isSticker) {
      return _ForumHtmlCachedStickerImageView(
        spec: spec,
        request: request,
        imageHeaderBuilder: imageHeaderBuilder,
        onImageResolved: onImageResolved,
        initialHint: layoutHintResolver.resolve(spec: spec),
        dimensionIndex: imageDimensionIndex,
        layoutHintResolver: layoutHintResolver,
      );
    }

    return _ForumHtmlCachedBlockImageView(
      spec: spec,
      request: request,
      imageHeaderBuilder: imageHeaderBuilder,
      onImageResolved: onImageResolved,
      initialHint: layoutHintResolver.resolve(spec: spec),
      dimensionIndex: imageDimensionIndex,
      layoutHintResolver: layoutHintResolver,
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

  bool _isForumStickerImage(String url) {
    return url.contains('/static/image/smiley/') ||
        url.contains('static/image/smiley/');
  }
}

class _ForumHtmlCachedBlockImageView extends ConsumerStatefulWidget {
  const _ForumHtmlCachedBlockImageView({
    required this.spec,
    required this.request,
    required this.imageHeaderBuilder,
    required this.onImageResolved,
    required this.initialHint,
    required this.dimensionIndex,
    required this.layoutHintResolver,
  });

  final ForumImageLoadSpec spec;
  final ImageCacheRequest request;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<Size>? onImageResolved;
  final ForumImageLayoutHint initialHint;
  final ForumImageDimensionIndex? dimensionIndex;
  final ForumImageLayoutHintResolver layoutHintResolver;

  @override
  ConsumerState<_ForumHtmlCachedBlockImageView> createState() =>
      _ForumHtmlCachedBlockImageViewState();
}

class _ForumHtmlCachedBlockImageViewState
    extends ConsumerState<_ForumHtmlCachedBlockImageView> {
  ForumImageLayoutHint? _cachedHint;
  String? _loadedCacheKey;

  ForumImageLayoutHint get _hint => _cachedHint ?? widget.initialHint;

  @override
  void initState() {
    super.initState();
    _loadCachedDimensions();
  }

  @override
  void didUpdateWidget(covariant _ForumHtmlCachedBlockImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.cacheKey != widget.request.cacheKey ||
        oldWidget.spec.htmlWidth != widget.spec.htmlWidth ||
        oldWidget.spec.htmlHeight != widget.spec.htmlHeight) {
      _cachedHint = null;
      _loadedCacheKey = null;
      _loadCachedDimensions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = _hint;
    final image = CachedLibraryImage(
      request: widget.request,
      fit: BoxFit.fitWidth,
      placeholder: const _ForumHtmlImageLoadingPlaceholder(
        delay: Duration(milliseconds: 350),
      ),
      errorPlaceholder: const _ForumHtmlImageErrorPlaceholder(
        icon: Icons.broken_image_outlined,
      ),
      headerBuilder: widget.imageHeaderBuilder,
      onImageResolved: widget.onImageResolved,
    );
    return AspectRatio(aspectRatio: hint.aspectRatio ?? 0.7, child: image);
  }

  Future<void> _loadCachedDimensions() async {
    if (ForumImageDimensions.fromHtmlSpec(widget.spec) != null) {
      return;
    }
    final cacheKey = widget.request.cacheKey.trim();
    if (cacheKey.isEmpty || _loadedCacheKey == cacheKey) {
      return;
    }
    _loadedCacheKey = cacheKey;
    final ForumImageDimensionIndex index =
        widget.dimensionIndex ?? ref.read(forumImageDimensionIndexProvider);
    final dimensions = await index.getBySpec(widget.spec);
    if (!mounted || _loadedCacheKey != cacheKey || dimensions == null) {
      return;
    }
    final next = widget.layoutHintResolver.resolve(
      spec: widget.spec,
      cacheDimensions: dimensions,
    );
    if (_cachedHint == next) {
      return;
    }
    setState(() {
      _cachedHint = next;
    });
  }
}

class _ForumHtmlCachedStickerImageView extends ConsumerStatefulWidget {
  const _ForumHtmlCachedStickerImageView({
    required this.spec,
    required this.request,
    required this.imageHeaderBuilder,
    required this.onImageResolved,
    required this.initialHint,
    required this.dimensionIndex,
    required this.layoutHintResolver,
  });

  final ForumImageLoadSpec spec;
  final ImageCacheRequest request;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<Size>? onImageResolved;
  final ForumImageLayoutHint initialHint;
  final ForumImageDimensionIndex? dimensionIndex;
  final ForumImageLayoutHintResolver layoutHintResolver;

  @override
  ConsumerState<_ForumHtmlCachedStickerImageView> createState() =>
      _ForumHtmlCachedStickerImageViewState();
}

class _ForumHtmlCachedStickerImageViewState
    extends ConsumerState<_ForumHtmlCachedStickerImageView> {
  ForumImageLayoutHint? _cachedHint;
  String? _loadedCacheKey;

  ForumImageLayoutHint get _hint => _cachedHint ?? widget.initialHint;

  @override
  void initState() {
    super.initState();
    _loadCachedSize();
  }

  @override
  void didUpdateWidget(covariant _ForumHtmlCachedStickerImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.cacheKey != widget.request.cacheKey ||
        oldWidget.spec.htmlWidth != widget.spec.htmlWidth ||
        oldWidget.spec.htmlHeight != widget.spec.htmlHeight) {
      _cachedHint = null;
      _loadedCacheKey = null;
      _loadCachedSize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = _hint.displaySize;
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
    if (ForumImageDimensions.fromHtmlSpec(widget.spec) != null) {
      return;
    }
    final cacheKey = widget.request.cacheKey.trim();
    if (cacheKey.isEmpty || _loadedCacheKey == cacheKey) {
      return;
    }
    _loadedCacheKey = cacheKey;
    final ForumImageDimensionIndex index =
        widget.dimensionIndex ?? ref.read(forumImageDimensionIndexProvider);
    final dimensions = await index.getBySpec(widget.spec);
    if (!mounted || _loadedCacheKey != cacheKey || dimensions == null) {
      return;
    }
    final next = widget.layoutHintResolver.resolve(
      spec: widget.spec,
      cacheDimensions: dimensions,
    );
    if (_cachedHint == next) {
      return;
    }
    setState(() {
      _cachedHint = next;
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
