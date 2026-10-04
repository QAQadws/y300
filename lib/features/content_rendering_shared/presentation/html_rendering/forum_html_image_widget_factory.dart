import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../contracts/forum_html_display_image.dart';
import '../contracts/forum_html_image_host.dart';
import 'forum_html_prepared_render_document.dart';
import 'forum_html_render_callbacks.dart';
import '../services/forum_html_image_viewport_coordinator.dart';

typedef ForumHtmlImageFactoryBinding = ({
  ForumHtmlImageHost host,
  ForumHtmlImageViewportCoordinator? viewport,
});

Widget _clipMedia(Widget child) => ClipRRect(
  borderRadius: const BorderRadius.all(Radius.circular(4)),
  clipBehavior: Clip.antiAlias,
  child: child,
);

/// A fresh factory is required for each HTML body: image numbering is local.
class ForumHtmlImageWidgetFactory extends WidgetFactory {
  ForumHtmlImageWidgetFactory({
    required this.binding,
    this.onImageResolved,
    this.onTapImageRequest,
    this.onImageLayoutShift,
    this.onBodyBuilt,
    this.readableImageKeyPrefix,
  });

  final ValueListenable<ForumHtmlImageFactoryBinding> binding;
  final VoidCallback? onBodyBuilt;
  final ValueChanged<Size>? onImageResolved;
  final void Function(ForumHtmlImageRequest request)? onTapImageRequest;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final String? readableImageKeyPrefix;
  var _nextImageIndex = 0;

  @override
  Widget buildBodyWidget(BuildContext context, Widget child) {
    final body = super.buildBodyWidget(context, child);
    onBodyBuilt?.call();
    return body;
  }

  @override
  Widget? buildImageWidget(BuildTree tree, ImageSource src) {
    final url = src.url.trim();
    if (url.startsWith('asset:') ||
        url.startsWith('data:image/') ||
        url.startsWith('file:')) {
      return _fallback(tree, src);
    }
    final resolved = urlFull(url);
    final uri = resolved == null ? null : Uri.tryParse(resolved);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return _fallback(tree, src);
    }
    final isSticker = _isSticker(resolved!);
    final readableIndex = _readableIndex(tree);
    final imageIndex = isSticker ? null : readableIndex ?? _nextImageIndex++;
    final htmlSize = _explicitSize(src);
    return ValueListenableBuilder<ForumHtmlImageFactoryBinding>(
      valueListenable: binding,
      builder: (context, binding, child) {
        final host = binding.host;
        final image = host.resolveImage(
          url: uri,
          imageIndex: imageIndex,
          isSticker: isSticker,
          htmlSize: htmlSize,
        );
        if (image == null) {
          return _fallback(tree, src) ?? const SizedBox.shrink();
        }
        return _wrapTap(
          _ForumHtmlImageView(
            host: host,
            image: image,
            onImageResolved: onImageResolved,
            onImageLayoutShift: onImageLayoutShift,
            viewportCoordinator: isSticker ? null : binding.viewport,
          ),
          image: image,
          src: src,
          element: tree.element,
          readableIndex: readableIndex,
          isSticker: isSticker,
        );
      },
    );
  }

  Widget? _fallback(BuildTree tree, ImageSource src) {
    final fallback = super.buildImageWidget(tree, src);
    return fallback == null ? null : _clipMedia(fallback);
  }

  Widget _wrapTap(
    Widget child, {
    required ForumHtmlDisplayImage image,
    required ImageSource src,
    required html_dom.Element element,
    required int? readableIndex,
    required bool isSticker,
  }) {
    final callback = onTapImageRequest;
    if (callback == null) return child;
    return GestureDetector(
      key: readableIndex == null
          ? null
          : Key(
              '${readableImageKeyPrefix ?? 'thread-post-html-first-readable-image'}-$readableIndex',
            ),
      behavior: HitTestBehavior.opaque,
      onTap: () => callback(
        ForumHtmlImageRequest(
          url: image.sourceUrl,
          alt: src.image?.alt,
          title: src.image?.title,
          width: src.width,
          height: src.height,
          isSticker: isSticker,
          attachmentId: _attachmentIdFromElement(element),
          readableIndex: readableIndex,
          cacheKey: image.cacheKey,
        ),
      ),
      child: child,
    );
  }

  int? _readableIndex(BuildTree tree) {
    final raw = tree.element.attributes[forumHtmlReadableImageIndexAttribute];
    final parsed = int.tryParse(raw?.trim() ?? '');
    return parsed == null || parsed < 0 ? null : parsed;
  }

  Size? _explicitSize(ImageSource src) {
    final width = src.width;
    final height = src.height;
    if (width == null || height == null) return null;
    final size = Size(width, height);
    return _validSize(size) ? size : null;
  }

  bool _isSticker(String url) =>
      url.contains('/static/image/smiley/') ||
      url.contains('static/image/smiley/');

  String? _attachmentIdFromElement(html_dom.Element element) {
    final aimgMatch = RegExp(r'^aimg_(\d+)$').firstMatch(element.id);
    if (aimgMatch != null) return aimgMatch.group(1);
    final aid = element.attributes['aid']?.trim();
    if (aid != null && aid.isNotEmpty) return aid;
    final src = DefaultForumImageSourcePipeline.firstDomImageSourceFromElement(
      element,
      domAttributes: const [
        'zoomfile',
        'file',
        'data-original',
        'data-src',
        'src',
      ],
    );
    if (src == null) return null;
    return RegExp(r'aimg[_=/-](\d+)').firstMatch(src)?.group(1) ??
        RegExp(r'(?:aid|attachmentid)=(\d+)').firstMatch(src)?.group(1);
  }
}

bool _validSize(Size size) =>
    size.width.isFinite &&
    size.height.isFinite &&
    size.width > 0 &&
    size.height > 0;

class _ForumHtmlImageView extends StatefulWidget {
  const _ForumHtmlImageView({
    required this.host,
    required this.image,
    this.onImageResolved,
    this.onImageLayoutShift,
    this.viewportCoordinator,
  });

  final ForumHtmlImageHost host;
  final ForumHtmlDisplayImage image;
  final ValueChanged<Size>? onImageResolved;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final ForumHtmlImageViewportCoordinator? viewportCoordinator;

  @override
  State<_ForumHtmlImageView> createState() => _ForumHtmlImageViewState();
}

class _ForumHtmlImageViewState extends State<_ForumHtmlImageView> {
  ForumHtmlImageLayout? _cachedLayout;
  int _bindingRevision = 0;
  int _callbackRevision = 0;
  int _retryToken = 0;
  ForumHtmlImageViewportHandle? _viewportHandle;
  ForumHtmlImageViewportMode? _lastMode;
  ForumHtmlImageWorkToken? _prefetchToken;
  Object? _prefetchIdentity;

  ForumHtmlImageLayout get _layout =>
      _cachedLayout ?? widget.image.initialLayout;

  @override
  void initState() {
    super.initState();
    _viewportHandle = widget.viewportCoordinator?.register();
    _loadDimensions();
  }

  @override
  void didUpdateWidget(covariant _ForumHtmlImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final coordinatorChanged = !identical(
      oldWidget.viewportCoordinator,
      widget.viewportCoordinator,
    );
    if (coordinatorChanged) {
      _viewportHandle?.dispose();
      _viewportHandle = widget.viewportCoordinator?.register();
      _lastMode = null;
      _callbackRevision++;
      _cancelPrefetch();
    }
    final bindingChanged =
        oldWidget.image.identity != widget.image.identity ||
        oldWidget.image.htmlSize != widget.image.htmlSize ||
        oldWidget.image.isSticker != widget.image.isSticker ||
        !identical(oldWidget.host, widget.host);
    if (bindingChanged) {
      _bindingRevision++;
      _callbackRevision++;
      _viewportHandle?.reportLoadStarted();
      _cancelPrefetch();
      _cachedLayout = null;
      _loadDimensions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = _viewportHandle;
    handle?.bind(context);
    if (handle == null) return _buildImage();
    return ValueListenableBuilder<ForumHtmlImageViewportMode>(
      valueListenable: handle,
      builder: (context, mode, child) {
        if (_lastMode != mode) {
          _lastMode = mode;
          _callbackRevision++;
        }
        if (mode == ForumHtmlImageViewportMode.prefetch) {
          _schedulePrefetch();
        } else if (mode == ForumHtmlImageViewportMode.dormant) {
          _cancelPrefetch();
        }
        return mode == ForumHtmlImageViewportMode.display
            ? _buildImage()
            : _clipMedia(
                AspectRatio(
                  aspectRatio: _layout.aspectRatio ?? 0.7,
                  child: const _ImageSurface(),
                ),
              );
      },
    );
  }

  bool _acceptCallback(int revision) =>
      mounted &&
      revision == _callbackRevision &&
      (_viewportHandle == null ||
          _viewportHandle!.value == ForumHtmlImageViewportMode.display);

  Widget _buildImage() {
    final revision = _callbackRevision;
    final sticker = widget.image.isSticker;
    final size = _layout.displaySize;
    void settle() {
      if (_acceptCallback(revision)) {
        _viewportHandle?.reportFirstFrameSettled();
      }
    }

    final image = widget.host.buildImage(
      image: widget.image,
      fit: sticker ? BoxFit.contain : BoxFit.fitWidth,
      width: sticker ? size?.width : null,
      height: sticker ? size?.height : null,
      placeholder: sticker ? const SizedBox.shrink() : const _ImageSurface(),
      errorPlaceholder: sticker
          ? Icon(
              Icons.image_not_supported_outlined,
              size: (size?.shortestSide ?? 14).clamp(12, 18).toDouble(),
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )
          : null,
      onRetry: sticker
          ? null
          : () {
              if (_acceptCallback(revision)) _retryImage();
            },
      showDelayedLoadingIndicator: !sticker,
      onImageResolved: (size) {
        if (!_acceptCallback(revision)) return;
        widget.onImageResolved?.call(size);
        if (!_acceptCallback(revision) || sticker) return;
        widget.host.onBlockImageResolved(widget.image, size);
        if (_acceptCallback(revision)) _promoteDecodedSize(size);
      },
      onFirstFrameRendered: sticker ? null : settle,
      onImageFailed: sticker ? null : settle,
      waitForCacheWrite: !sticker,
      retryToken: _retryToken,
    );
    return _clipMedia(
      sticker
          ? size == null
                ? image
                : SizedBox(width: size.width, height: size.height, child: image)
          : AspectRatio(aspectRatio: _layout.aspectRatio ?? 0.7, child: image),
    );
  }

  void _schedulePrefetch() {
    final identity = widget.image.identity;
    if (_prefetchIdentity == identity) return;
    _cancelPrefetch();
    _prefetchIdentity = identity;
    final token = ForumHtmlImageWorkToken();
    _prefetchToken = token;
    final host = widget.host;
    final image = widget.image;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && token.isActive && _prefetchIdentity == identity) {
        unawaited(_prefetch(host, image, token));
      }
    });
  }

  Future<void> _prefetch(
    ForumHtmlImageHost host,
    ForumHtmlDisplayImage image,
    ForumHtmlImageWorkScope scope,
  ) async {
    try {
      await host.prefetchDisk(image, scope: scope);
    } catch (_) {
      // Look-ahead is optional; display owns its failure and retry UI.
    }
  }

  void _cancelPrefetch() {
    _prefetchToken?.cancel();
    _prefetchToken = null;
    _prefetchIdentity = null;
  }

  @override
  void dispose() {
    _bindingRevision++;
    _callbackRevision++;
    _cancelPrefetch();
    _viewportHandle?.dispose();
    super.dispose();
  }

  void _retryImage() {
    if (!mounted) return;
    _callbackRevision++;
    _viewportHandle?.reportLoadStarted();
    setState(() => _retryToken++);
  }

  Future<void> _loadDimensions() async {
    if (widget.image.htmlSize != null || widget.image.cacheKey.trim().isEmpty) {
      return;
    }
    final revision = _bindingRevision;
    final image = widget.image;
    final host = widget.host;
    ({Size size, ForumHtmlImageLayout layout})? dimensions;
    try {
      dimensions = await host.loadDimensions(image);
    } catch (_) {
      // Cached dimensions are optional hints; a cache race must not stop display.
      return;
    }
    if (!mounted || revision != _bindingRevision || dimensions == null) return;
    if (!image.isSticker) host.onBlockImageResolved(image, dimensions.size);
    if (!mounted || revision != _bindingRevision) return;
    if (_cachedLayout != dimensions.layout) {
      setState(() => _cachedLayout = dimensions!.layout);
    }
  }

  void _promoteDecodedSize(Size size) {
    if (widget.image.htmlSize != null ||
        !_layout.isFallback ||
        !_validSize(size)) {
      return;
    }
    final current = _layout.aspectRatio;
    final decoded = size.aspectRatio;
    if (current == null ||
        !current.isFinite ||
        current <= 0 ||
        !decoded.isFinite ||
        decoded <= 0) {
      return;
    }
    if ((decoded - current).abs() / current >= 0.05) {
      final shift = _layoutShift(decoded: decoded, current: current);
      if (shift != null) widget.onImageLayoutShift?.call(shift);
    }
    if (mounted) {
      setState(
        () => _cachedLayout = ForumHtmlImageLayout(aspectRatio: decoded),
      );
    }
  }

  ForumHtmlImageLayoutShift? _layoutShift({
    required double decoded,
    required double current,
  }) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final oldSize = renderObject.size;
    final newHeight = oldSize.width / decoded;
    if (!_validSize(oldSize) || !newHeight.isFinite || newHeight <= 0) {
      return null;
    }
    return ForumHtmlImageLayoutShift(
      sourceUrl: widget.image.sourceUrl,
      cacheKey: widget.image.cacheKey,
      oldGlobalRect: renderObject.localToGlobal(Offset.zero) & oldSize,
      oldSize: oldSize,
      newSize: Size(oldSize.width, newHeight),
      oldAspectRatio: current,
      newAspectRatio: decoded,
    );
  }
}

class _ImageSurface extends StatelessWidget {
  const _ImageSurface();

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    color: Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
  );
}
