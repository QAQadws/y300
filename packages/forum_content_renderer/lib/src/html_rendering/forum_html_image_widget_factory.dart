import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../contracts/forum_html_display_image.dart';
import '../contracts/forum_html_image_host.dart';
import '../contracts/forum_html_image_predecode_host.dart';
import 'forum_html_prepared_render_document.dart';
import 'forum_html_render_callbacks.dart';
import '../services/forum_html_image_viewport_coordinator.dart';
import '../services/forum_html_image_anchor_controller.dart';

typedef ForumHtmlImageFactoryBinding = ({
  ForumHtmlImageHost? host,
  ForumHtmlImageViewportCoordinator? viewport,
  bool handlesImageTap,
  ForumHtmlImageAnchorController? imageAnchors,
  Object? imageAnchorRevision,
  String sourceId,
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
    this.textAlignFor,
    this.onImageResolved,
    this.onTapImageRequest,
    this.onImageLayoutShift,
    this.onBodyBuilt,
    this.readableImageKeyPrefix,
    this.hasTrailingContentFor,
  });

  final ValueListenable<ForumHtmlImageFactoryBinding> binding;
  final TextAlign? Function()? textAlignFor;
  final VoidCallback? onBodyBuilt;
  final ValueChanged<Size>? onImageResolved;
  final void Function(ForumHtmlImageRequest request)? onTapImageRequest;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final String? readableImageKeyPrefix;
  final bool Function()? hasTrailingContentFor;
  var _nextImageIndex = 0;

  @override
  Iterable<dynamic> getDependencies(BuildContext context) {
    final alignment = textAlignFor?.call();
    return [...super.getDependencies(context), ?alignment];
  }

  @override
  Widget buildBodyWidget(BuildContext context, Widget child) {
    if (hasTrailingContentFor?.call() == true && child is Column) {
      // fwfh trims the root trailing margin. An interior display fragment must
      // retain that real CSS margin, so put a zero-size flow item after it.
      child = Column(
        mainAxisSize: child.mainAxisSize,
        mainAxisAlignment: child.mainAxisAlignment,
        crossAxisAlignment: child.crossAxisAlignment,
        textDirection: child.textDirection,
        verticalDirection: child.verticalDirection,
        textBaseline: child.textBaseline,
        children: [...child.children, const SizedBox.shrink()],
      );
    }
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
        if (host == null) {
          return _fallback(tree, src) ?? const SizedBox.shrink();
        }
        final image = host.resolveImage(
          url: uri,
          imageIndex: imageIndex,
          isSticker: isSticker,
          htmlSize: htmlSize,
        );
        if (image == null) {
          return _fallback(tree, src) ?? const SizedBox.shrink();
        }
        final child = _ForumHtmlImageView(
          host: host,
          image: image,
          onImageResolved: onImageResolved,
          onImageLayoutShift: onImageLayoutShift,
          viewportCoordinator: isSticker ? null : binding.viewport,
        );
        return _wrapTap(
          child,
          enabled: binding.handlesImageTap,
          image: image,
          src: src,
          element: tree.element,
          readableIndex: readableIndex,
          isSticker: isSticker,
          binding: binding,
        );
      },
    );
  }

  Widget? _fallback(BuildTree tree, ImageSource src) {
    final fallback = super.buildImageWidget(tree, src);
    if (fallback == null) return null;
    return ValueListenableBuilder<ForumHtmlImageFactoryBinding>(
      valueListenable: binding,
      child: _clipMedia(fallback),
      builder: (context, binding, child) => _wrapTap(
        child!,
        enabled: binding.handlesImageTap,
        src: src,
        element: tree.element,
        readableIndex: _readableIndex(tree),
        isSticker: _isSticker(urlFull(src.url) ?? src.url),
        binding: binding,
      ),
    );
  }

  Widget _wrapTap(
    Widget child, {
    required bool enabled,
    ForumHtmlDisplayImage? image,
    required ImageSource src,
    required html_dom.Element element,
    required int? readableIndex,
    required bool isSticker,
    required ForumHtmlImageFactoryBinding binding,
  }) {
    final callback = onTapImageRequest;
    final gesture = GestureDetector(
      key: readableIndex == null
          ? null
          : Key(
              '${readableImageKeyPrefix ?? 'thread-post-html-first-readable-image'}-$readableIndex',
            ),
      behavior: HitTestBehavior.opaque,
      onTap: !enabled || callback == null
          ? null
          : () => callback(
              ForumHtmlImageRequest(
                url: image?.sourceUrl ?? urlFull(src.url) ?? src.url,
                alt: src.image?.alt,
                title: src.image?.title,
                width: src.width,
                height: src.height,
                isSticker: isSticker,
                attachmentId: _attachmentIdFromElement(element),
                readableIndex: readableIndex,
                cacheKey: image?.cacheKey,
              ),
            ),
      child: child,
    );
    final anchors = binding.imageAnchors;
    if (image == null || readableIndex == null || isSticker) {
      return gesture;
    }
    return ForumHtmlImageAnchor(
      controller: anchors,
      sourceId: binding.sourceId,
      index: readableIndex,
      cacheKey: image.cacheKey,
      url: image.sourceUrl,
      child: gesture,
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
  Size? _intrinsicSize;
  bool _firstFrameRendered = false;
  int _bindingRevision = 0;
  int _callbackRevision = 0;
  int _retryToken = 0;
  ForumHtmlImageViewportHandle? _viewportHandle;
  ForumHtmlImageViewportMode? _lastMode;
  ForumHtmlImageViewportWork? _prefetchToken;
  Object? _prefetchIdentity;
  Size _displaySize = Size.zero;

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
      _intrinsicSize = null;
      _firstFrameRendered = false;
      _loadDimensions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = _viewportHandle;
    if (handle == null) return _buildImage();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        _displaySize = Size(width, width / (_layout.aspectRatio ?? 0.7));
        handle.configureWork(
          identity: (
            widget.host,
            widget.image.identity,
            // Block images decode by width. Intrinsic-height recovery only
            // changes layout and must not retire an already displayed frame.
            width,
            MediaQuery.devicePixelRatioOf(context),
          ),
          canPredecode:
              widget.host is ForumHtmlImagePredecodeHost &&
              width.isFinite &&
              width > 0,
        );
        handle.bind(context);
        return ValueListenableBuilder<ForumHtmlImageViewportMode>(
          valueListenable: handle,
          builder: (context, mode, child) {
            if (_lastMode != mode) {
              if (_lastMode?.keepsImageMounted != mode.keepsImageMounted) {
                _callbackRevision++;
                if (!mode.keepsImageMounted) _firstFrameRendered = false;
              }
              _lastMode = mode;
            }
            if (mode == ForumHtmlImageViewportMode.prefetch ||
                mode == ForumHtmlImageViewportMode.predecode) {
              _schedulePrefetch();
            } else {
              _cancelPrefetch();
            }
            return mode.keepsImageMounted
                ? TickerMode(
                    enabled: mode == ForumHtmlImageViewportMode.display,
                    child: _buildImage(),
                  )
                : _clipMedia(
                    AspectRatio(
                      aspectRatio: _layout.aspectRatio ?? 0.7,
                      child: const _ImageSurface(),
                    ),
                  );
          },
        );
      },
    );
  }

  bool _acceptCallback(int revision) =>
      mounted &&
      revision == _callbackRevision &&
      (_viewportHandle == null || _viewportHandle!.value.keepsImageMounted);

  Widget _buildImage() {
    final revision = _callbackRevision;
    final sticker = widget.image.isSticker;
    final size = _layout.displaySize;
    void firstFrameRendered() {
      if (_acceptCallback(revision)) {
        _firstFrameRendered = true;
        _reportRenderedFrame();
      }
    }

    void failed() {
      if (_acceptCallback(revision)) {
        _firstFrameRendered = false;
        _viewportHandle?.reportImageFailed();
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
        if (!_acceptCallback(revision)) return;
        _intrinsicSize = _validSize(size) ? size : null;
        _reportRenderedFrame();
        _promoteDecodedSize(size);
      },
      onFirstFrameRendered: sticker ? null : firstFrameRendered,
      onImageFailed: sticker ? null : failed,
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

  void _reportRenderedFrame() {
    if (!_firstFrameRendered || !_acceptCallback(_callbackRevision)) return;
    final host = widget.host;
    final size = _intrinsicSize;
    // An optional predecode may already have admitted this frame. Missing
    // display metadata leaves that decision intact until its probe completes.
    final admission = host is ForumHtmlImagePredecodeHost && size != null
        ? (host as ForumHtmlImagePredecodeHost).canRetainDisplayedImage(
            image: widget.image,
            intrinsicSize: size,
            displaySize: _displaySize,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            maxDecodedBytes: _viewportHandle?.maxDecodedBytes ?? 0,
          )
        : null;
    _viewportHandle?.reportFirstFrameRendered(canRetain: admission);
  }

  void _schedulePrefetch() {
    final handle = _viewportHandle!;
    final mode = handle.value;
    final identity = (
      widget.host,
      widget.image.identity,
      mode,
      _displaySize.width,
      MediaQuery.devicePixelRatioOf(context),
    );
    if (_prefetchIdentity == identity) return;
    _cancelPrefetch();
    _prefetchIdentity = identity;
    final token = handle.beginWork();
    _prefetchToken = token;
    final host = widget.host;
    final image = widget.image;
    final displaySize = _displaySize;
    final maxDecodedBytes = handle.maxDecodedBytes;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && token.isActive && _prefetchIdentity == identity) {
        unawaited(_prefetch(host, image, token, displaySize, maxDecodedBytes));
      } else {
        token.complete(ForumHtmlImagePreparationOutcome.cancelled);
      }
    });
  }

  Future<void> _prefetch(
    ForumHtmlImageHost host,
    ForumHtmlDisplayImage image,
    ForumHtmlImageViewportWork scope,
    Size displaySize,
    int maxDecodedBytes,
  ) async {
    var outcome = ForumHtmlImagePreparationOutcome.failed;
    try {
      if (scope.mode == ForumHtmlImageViewportMode.predecode &&
          host is ForumHtmlImagePredecodeHost) {
        outcome = await (host as ForumHtmlImagePredecodeHost).predecodeImage(
          image: image,
          context: context,
          displaySize: displaySize,
          scope: scope,
          maxDecodedBytes: maxDecodedBytes,
        );
      } else {
        await host.prefetchDisk(image, scope: scope);
        outcome = ForumHtmlImagePreparationOutcome.diskOnly;
      }
    } catch (_) {
      // Look-ahead is optional; display owns its failure and retry UI.
    } finally {
      scope.complete(outcome);
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
    _firstFrameRendered = false;
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
    _intrinsicSize = _validSize(dimensions.size) ? dimensions.size : null;
    _reportRenderedFrame();
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
