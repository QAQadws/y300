import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_layout_hint_resolver.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/cache/presentation/widgets/image_retry_placeholder.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';

const _forumHtmlInlineMediaBorderRadius = BorderRadius.all(Radius.circular(4));

Widget _clipForumHtmlInlineMedia(Widget child) {
  return ClipRRect(
    borderRadius: _forumHtmlInlineMediaBorderRadius,
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class ForumHtmlCachedImageWidgetFactory extends WidgetFactory {
  ForumHtmlCachedImageWidgetFactory({
    required this.threadId,
    this.imageHeaderBuilder,
    this.imageCacheOwnerId,
    this.onImageResolved,
    this.onTapImageRequest,
    this.onImageLayoutShift,
    this.readableImageKeyPrefix,
    this.contentImageKind = ForumImageKind.threadInline,
    ForumImageRequestResolver? imageRequestResolver,
    this.imageDimensionIndex,
    this.fallbackAspectRatioFor,
    this.onBlockImageResolved,
    ForumImageLayoutHintResolver? layoutHintResolver,
  }) : imageRequestResolver =
           imageRequestResolver ?? const DefaultForumImageRequestResolver(),
       layoutHintResolver =
           layoutHintResolver ?? const ForumImageLayoutHintResolver();

  final String threadId;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String? imageCacheOwnerId;
  final ValueChanged<Size>? onImageResolved;
  final void Function(ForumHtmlImageRequest request)? onTapImageRequest;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final String? readableImageKeyPrefix;
  final ForumImageKind contentImageKind;
  final ForumImageRequestResolver imageRequestResolver;
  final ForumImageDimensionIndex? imageDimensionIndex;
  final double? Function(ForumImageLoadSpec spec, ImageCacheRequest request)?
  fallbackAspectRatioFor;
  final void Function(
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  )?
  onBlockImageResolved;
  final ForumImageLayoutHintResolver layoutHintResolver;
  var _nextImageIndex = 0;

  @override
  Widget? buildImageWidget(BuildTree tree, ImageSource src) {
    final url = src.url.trim();
    if (url.startsWith('asset:') ||
        url.startsWith('data:image/') ||
        url.startsWith('file:')) {
      return _buildFallbackImageWidget(tree, src);
    }

    final resolved = urlFull(url);
    final uri = resolved == null ? null : Uri.tryParse(resolved);
    if (resolved == null ||
        uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return _buildFallbackImageWidget(tree, src);
    }

    final isSticker = _isForumStickerImage(resolved);
    final readableIndex = _readableIndex(tree);
    final imageIndex = isSticker ? null : readableIndex ?? _nextImageIndex++;
    final explicitSize = _explicitSize(src);
    final spec = ForumImageLoadSpec(
      kind: isSticker ? ForumImageKind.remoteSmiley : contentImageKind,
      url: uri,
      ownerId: isSticker ? null : _cacheOwnerId(),
      imageIndex: imageIndex,
      htmlWidth: explicitSize?.width,
      htmlHeight: explicitSize?.height,
    );
    final request = imageRequestResolver.resolveCacheRequest(spec);
    if (request == null) {
      return _buildFallbackImageWidget(tree, src);
    }
    if (isSticker) {
      return _wrapTap(
        _ForumHtmlCachedStickerImageView(
          spec: spec,
          request: request,
          imageHeaderBuilder: imageHeaderBuilder,
          onImageResolved: onImageResolved,
          initialHint: layoutHintResolver.resolve(spec: spec),
          dimensionIndex: imageDimensionIndex,
          layoutHintResolver: layoutHintResolver,
        ),
        spec: spec,
        request: request,
        src: src,
        element: tree.element,
        readableIndex: readableIndex,
        isSticker: true,
      );
    }

    return _wrapTap(
      _ForumHtmlCachedBlockImageView(
        spec: spec,
        request: request,
        imageHeaderBuilder: imageHeaderBuilder,
        onImageResolved: onImageResolved,
        onBlockImageResolved: onBlockImageResolved,
        onImageLayoutShift: onImageLayoutShift,
        initialHint: _resolveInitialBlockHint(spec, request),
        dimensionIndex: imageDimensionIndex,
        layoutHintResolver: layoutHintResolver,
      ),
      spec: spec,
      request: request,
      src: src,
      element: tree.element,
      readableIndex: readableIndex,
      isSticker: false,
    );
  }

  Widget? _buildFallbackImageWidget(BuildTree tree, ImageSource src) {
    final fallback = super.buildImageWidget(tree, src);
    return fallback == null ? null : _clipForumHtmlInlineMedia(fallback);
  }

  ForumImageLayoutHint _resolveInitialBlockHint(
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
  ) {
    final base = layoutHintResolver.resolve(spec: spec);
    if (base.layoutMode != ForumImageLayoutMode.blockWithFallbackAspectRatio) {
      return base;
    }
    final learnedAspectRatio = fallbackAspectRatioFor?.call(spec, request);
    if (learnedAspectRatio == null ||
        !learnedAspectRatio.isFinite ||
        learnedAspectRatio <= 0) {
      return base;
    }
    return ForumImageLayoutHint(
      layoutMode: ForumImageLayoutMode.blockWithFallbackAspectRatio,
      aspectRatio: learnedAspectRatio,
    );
  }

  Widget _wrapTap(
    Widget child, {
    required ForumImageLoadSpec spec,
    required ImageCacheRequest request,
    required ImageSource src,
    required html_dom.Element element,
    required int? readableIndex,
    required bool isSticker,
  }) {
    final callback = onTapImageRequest;
    if (callback == null) {
      return child;
    }
    return GestureDetector(
      key: readableIndex == null
          ? null
          : Key(
              '${readableImageKeyPrefix ?? 'thread-post-html-first-readable-image'}-$readableIndex',
            ),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        callback(
          ForumHtmlImageRequest(
            url: spec.sourceUrl,
            alt: src.image?.alt,
            title: src.image?.title,
            width: src.width,
            height: src.height,
            isSticker: isSticker,
            attachmentId: _attachmentIdFromElement(element),
            readableIndex: readableIndex,
            cacheKey: request.cacheKey,
            kind: spec.kind,
          ),
        );
      },
      child: child,
    );
  }

  int? _readableIndex(BuildTree tree) {
    final raw = tree.element.attributes[forumHtmlReadableImageIndexAttribute];
    final parsed = int.tryParse(raw?.trim() ?? '');
    if (parsed == null || parsed < 0) {
      return null;
    }
    return parsed;
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

  String? _attachmentIdFromElement(html_dom.Element element) {
    final id = element.id;
    final aimgMatch = RegExp(r'^aimg_(\d+)$').firstMatch(id);
    if (aimgMatch != null) {
      return aimgMatch.group(1);
    }
    final aid = element.attributes['aid']?.trim();
    if (aid != null && aid.isNotEmpty) {
      return aid;
    }
    final src = DefaultForumImageSourcePipeline.firstDomImageSourceFromElement(
      element,
      domAttributes: const <String>[
        'zoomfile',
        'file',
        'data-original',
        'data-src',
        'src',
      ],
    );
    return src == null ? null : _attachmentIdFromUrl(src);
  }

  String? _attachmentIdFromUrl(String url) {
    final aimgMatch = RegExp(r'aimg[_=/-](\d+)').firstMatch(url);
    if (aimgMatch != null) {
      return aimgMatch.group(1);
    }
    final aidMatch = RegExp(r'(?:aid|attachmentid)=(\d+)').firstMatch(url);
    return aidMatch?.group(1);
  }
}

class _ForumHtmlCachedBlockImageView extends ConsumerStatefulWidget {
  const _ForumHtmlCachedBlockImageView({
    required this.spec,
    required this.request,
    required this.imageHeaderBuilder,
    required this.onImageResolved,
    required this.onBlockImageResolved,
    required this.onImageLayoutShift,
    required this.initialHint,
    required this.dimensionIndex,
    required this.layoutHintResolver,
  });

  final ForumImageLoadSpec spec;
  final ImageCacheRequest request;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<Size>? onImageResolved;
  final void Function(
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  )?
  onBlockImageResolved;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final ForumImageLayoutHint initialHint;
  final ForumImageDimensionIndex? dimensionIndex;
  final ForumImageLayoutHintResolver layoutHintResolver;

  @override
  ConsumerState<_ForumHtmlCachedBlockImageView> createState() =>
      _ForumHtmlCachedBlockImageViewState();
}

class _ForumHtmlCachedBlockImageViewState
    extends ConsumerState<_ForumHtmlCachedBlockImageView> {
  static const double _decodedAspectRatioPromotionThreshold = 0.05;

  ForumImageLayoutHint? _cachedHint;
  String? _loadedCacheKey;
  int _retryToken = 0;

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
      placeholder: const _ForumHtmlImageSurface(),
      errorPlaceholder: _ForumHtmlImageErrorPlaceholder(
        cacheKey: widget.request.cacheKey,
        onRetry: _retryImage,
      ),
      showDelayedLoadingIndicator: true,
      headerBuilder: widget.imageHeaderBuilder,
      onImageResolved: _handleImageResolved,
      retryToken: _retryToken,
    );
    return _clipForumHtmlInlineMedia(
      AspectRatio(aspectRatio: hint.aspectRatio ?? 0.7, child: image),
    );
  }

  void _retryImage() {
    setState(() {
      _retryToken += 1;
    });
  }

  void _handleImageResolved(Size size) {
    widget.onImageResolved?.call(size);
    widget.onBlockImageResolved?.call(widget.spec, widget.request, size);
    _promoteFallbackLayoutFromDecodedSize(size);
  }

  void _promoteFallbackLayoutFromDecodedSize(Size size) {
    if (!mounted || ForumImageDimensions.fromHtmlSpec(widget.spec) != null) {
      return;
    }
    final hint = _hint;
    if (hint.layoutMode != ForumImageLayoutMode.blockWithFallbackAspectRatio) {
      return;
    }
    final decoded = ForumImageDimensions.fromValues(
      width: size.width,
      height: size.height,
      source: ForumImageDimensionSource.decodedImage,
    );
    final currentAspectRatio = hint.aspectRatio;
    final decodedAspectRatio = decoded?.aspectRatio;
    if (decoded == null ||
        currentAspectRatio == null ||
        !currentAspectRatio.isFinite ||
        currentAspectRatio <= 0 ||
        decodedAspectRatio == null ||
        !decodedAspectRatio.isFinite ||
        decodedAspectRatio <= 0) {
      return;
    }
    final relativeDelta =
        (decodedAspectRatio - currentAspectRatio).abs() / currentAspectRatio;
    if (relativeDelta >= _decodedAspectRatioPromotionThreshold) {
      final shift = _layoutShiftFromDecodedAspectRatio(
        decodedAspectRatio: decodedAspectRatio,
        currentAspectRatio: currentAspectRatio,
      );
      if (shift != null) {
        widget.onImageLayoutShift?.call(shift);
      }
    }
    setState(() {
      _cachedHint = ForumImageLayoutHint(
        layoutMode: ForumImageLayoutMode.blockWithKnownAspectRatio,
        dimensionSource: ForumImageDimensionSource.decodedImage,
        aspectRatio: decodedAspectRatio,
      );
    });
  }

  ForumHtmlImageLayoutShift? _layoutShiftFromDecodedAspectRatio({
    required double decodedAspectRatio,
    required double currentAspectRatio,
  }) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final oldSize = renderObject.size;
    if (!oldSize.width.isFinite ||
        !oldSize.height.isFinite ||
        oldSize.width <= 0 ||
        oldSize.height <= 0) {
      return null;
    }
    final newHeight = oldSize.width / decodedAspectRatio;
    if (!newHeight.isFinite || newHeight <= 0) {
      return null;
    }
    final oldTopLeft = renderObject.localToGlobal(Offset.zero);
    return ForumHtmlImageLayoutShift(
      sourceUrl: widget.spec.sourceUrl,
      cacheKey: widget.request.cacheKey,
      oldGlobalRect: oldTopLeft & oldSize,
      oldSize: oldSize,
      newSize: Size(oldSize.width, newHeight),
      oldAspectRatio: currentAspectRatio,
      newAspectRatio: decodedAspectRatio,
    );
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
    final media = size == null
        ? child
        : SizedBox(width: size.width, height: size.height, child: child);
    return _clipForumHtmlInlineMedia(media);
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

class _ForumHtmlImageErrorPlaceholder extends StatelessWidget {
  const _ForumHtmlImageErrorPlaceholder({
    required this.cacheKey,
    required this.onRetry,
  });

  final String cacheKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // 正文内联图的失败位受宽高比约束，高度可能只剩几十像素，密度由占位自行降级。
    return _ForumHtmlImageSurface(
      child: ImageRetryPlaceholder(
        onRetry: onRetry,
        retryButtonKey: ValueKey<String>('thread-post-image-retry-$cacheKey'),
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
