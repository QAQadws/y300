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
import 'forum_html_block_decorator.dart';
import 'forum_html_paragraph_metrics.dart';
import 'widgets/forum_html_block_image_frame.dart';
import 'widgets/forum_html_image_paint_observer.dart';
import '../services/forum_html_image_viewport_coordinator.dart';
import '../services/forum_html_image_anchor_controller.dart';
import '../services/forum_html_body_presentation.dart';
import '../services/forum_html_image_binding.dart';

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
    this.bodyPresentationFor,
    this.textAlignFor,
    this.onImageResolved,
    this.onTapImageRequest,
    this.onImageLayoutShift,
    this.onBodyBuilt,
    this.readableImageKeyPrefix,
    this.hasTrailingContentFor,
    this.decorateBlock,
    this.blockDecorationEnabled,
  });

  final ValueListenable<ForumHtmlImageFactoryBinding> binding;
  final ForumHtmlBodyPresentation? Function()? bodyPresentationFor;
  final TextAlign? Function()? textAlignFor;
  final VoidCallback? onBodyBuilt;
  final ValueChanged<Size>? onImageResolved;
  final void Function(ForumHtmlImageRequest request)? onTapImageRequest;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final String? readableImageKeyPrefix;
  final bool Function()? hasTrailingContentFor;
  final Widget Function(Widget child)? decorateBlock;
  final bool Function()? blockDecorationEnabled;
  var _nextImageIndex = 0;

  @override
  void parse(BuildTree tree) {
    super.parse(tree);
    final decorate = decorateBlock;
    if (decorate == null ||
        blockDecorationEnabled?.call() == false ||
        !ForumHtmlBlockDecorationPolicy.isBlock(tree.element) ||
        ForumHtmlBlockDecorationPolicy.hasBlockAncestor(tree.element)) {
      return;
    }
    tree.register(
      BuildOp.v2(
        onRenderedBlock: (_, block) {
          if (block is WidgetPlaceholder) {
            block.wrapWith((_, child) => decorate(child));
          }
        },
      ),
    );
  }

  @override
  Widget? buildText(
    BuildTree tree,
    InheritedProperties resolved,
    InlineSpan text,
  ) {
    var child = super.buildText(tree, resolved, text);
    final decorate = decorateBlock;
    if (child == null ||
        decorate == null ||
        blockDecorationEnabled?.call() == false) {
      return child;
    }
    if (!ForumHtmlBlockDecorationPolicy.isAtomic(tree.element) &&
        !ForumHtmlBlockDecorationPolicy.hasAtomicAncestor(tree.element) &&
        text.toPlainText(includeSemanticsLabels: false).contains('\n')) {
      child = ForumHtmlParagraphMetrics(child: child);
    }
    if (ForumHtmlBlockDecorationPolicy.isBlock(tree.element) ||
        ForumHtmlBlockDecorationPolicy.hasBlockAncestor(tree.element)) {
      return child;
    }
    // Unwrapped body text, including inline images, is one intact paragraph.
    return decorate(child);
  }

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
      // fwfh caches this widget per DOM image. A table can insert/remove a
      // scroll wrapper during width measurement, so its image binding must
      // survive reparenting. Each DOM slot owns a key, including repeated URLs.
      key: _hasTableAncestor(tree.element) ? GlobalKey() : null,
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
        final presentation = isSticker ? bodyPresentationFor?.call() : null;
        final child = _ForumHtmlImageView(
          observationIdentity: binding.viewport?.visibilityObserver == null
              ? image.identity
              : (
                  binding.sourceId,
                  readableIndex ?? _occurrencePath(tree.element),
                  image.identity,
                ),
          host: host,
          image: image,
          initialInlineSize: presentation?.inlineImageSizeFor(image.identity),
          rememberInlineSize: presentation == null
              ? null
              : (size) =>
                    presentation.recordInlineImageSize(image.identity, size),
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

  bool _hasTableAncestor(html_dom.Element element) {
    for (var parent = element.parent; parent != null; parent = parent.parent) {
      if (parent.localName == 'table') return true;
    }
    return false;
  }

  String _occurrencePath(html_dom.Element element) {
    final indices = <int>[];
    for (var node = element; node.parent != null; node = node.parent!) {
      indices.add(node.parent!.nodes.indexOf(node));
    }
    return indices.reversed.join('/');
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
    required this.observationIdentity,
    required this.host,
    required this.image,
    this.initialInlineSize,
    this.rememberInlineSize,
    this.onImageResolved,
    this.onImageLayoutShift,
    this.viewportCoordinator,
  });

  final ForumHtmlImageHost host;
  final Object observationIdentity;
  final ForumHtmlDisplayImage image;
  final Size? initialInlineSize;
  final ValueChanged<Size>? rememberInlineSize;
  final ValueChanged<Size>? onImageResolved;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final ForumHtmlImageViewportCoordinator? viewportCoordinator;

  @override
  State<_ForumHtmlImageView> createState() => _ForumHtmlImageViewState();
}

class _ForumHtmlImageViewState extends State<_ForumHtmlImageView> {
  ForumHtmlImageLayout? _cachedLayout;
  ForumHtmlImageLayout? _initialInlineLayout;
  Size? _intrinsicSize;
  bool _hasResolvedImageSize = false;
  late final ForumHtmlImageBinding _binding;
  ForumHtmlImageViewportHandle? get _viewportHandle => _binding.viewportHandle;
  Size _displaySize = Size.zero;
  bool _workConfigurationScheduled = false;
  bool _dimensionPromotionScheduled = false;

  ForumHtmlImageLayout get _layout =>
      _cachedLayout ?? _initialInlineLayout ?? widget.image.initialLayout;

  void _restoreInlineLayout() {
    if (!widget.image.isSticker || widget.image.htmlSize != null) {
      _initialInlineLayout = null;
      return;
    }
    final size =
        widget.image.initialLayout.displaySize ?? widget.initialInlineSize;
    _initialInlineLayout = size != null && _validSize(size)
        ? ForumHtmlImageLayout(displaySize: size, aspectRatio: size.aspectRatio)
        : null;
  }

  @override
  void initState() {
    super.initState();
    _restoreInlineLayout();
    _binding = ForumHtmlImageBinding(
      host: widget.host,
      image: widget.image,
      viewport: widget.viewportCoordinator,
      observationIdentity: widget.observationIdentity,
    );
    unawaited(_loadDimensions());
  }

  @override
  void didUpdateWidget(covariant _ForumHtmlImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bindingChanged = _binding.update(
      host: widget.host,
      image: widget.image,
      viewport: widget.viewportCoordinator,
      observationIdentity: widget.observationIdentity,
    );
    if (bindingChanged) {
      _cachedLayout = null;
      _intrinsicSize = null;
      _hasResolvedImageSize = false;
      _restoreInlineLayout();
      unawaited(_loadDimensions());
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = _viewportHandle;
    if (handle == null) return _buildImage();
    return _buildBlockImage(
      LayoutBuilder(
        builder: (context, constraints) {
          _scheduleWorkConfiguration();
          handle.bind(context);
          return ValueListenableBuilder<ForumHtmlImageViewportMode>(
            valueListenable: handle,
            builder: (context, mode, child) {
              _scheduleDimensionPromotion();
              if (mode == ForumHtmlImageViewportMode.prefetch ||
                  mode == ForumHtmlImageViewportMode.predecode) {
                _binding.prepareImage(
                  context: context,
                  displaySize: _displaySize,
                  pixelRatio: MediaQuery.devicePixelRatioOf(context),
                );
              } else {
                _binding.cancelPreparation();
              }
              return mode.keepsImageMounted
                  ? TickerMode(
                      enabled: mode == ForumHtmlImageViewportMode.display,
                      child: _buildImageContent(),
                    )
                  : const _ImageSurface();
            },
          );
        },
      ),
    );
  }

  void _scheduleWorkConfiguration() {
    if (_workConfigurationScheduled) return;
    _workConfigurationScheduled = true;
    // Tables measure a cell at multiple widths in one frame. Only its final
    // laid-out width can invalidate decode work; provisional constraints would
    // repeatedly reset a visible image to dormant before it can mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _workConfigurationScheduled = false;
      if (!mounted) return;
      final handle = _viewportHandle;
      final box = context.findRenderObject();
      if (handle == null ||
          box is! RenderBox ||
          !box.attached ||
          !box.hasSize) {
        return;
      }
      // Read the current binding after layout, including any Host/viewport
      // replacement during this frame, rather than configuring a retired one.
      _displaySize = box.size;
      _binding.configureWork(
        displaySize: _displaySize,
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    });
  }

  Widget _buildImage() {
    final image = _buildImageContent();
    if (!widget.image.isSticker) return _buildBlockImage(image);
    final size = _layout.displaySize;
    return _clipMedia(
      size == null
          ? image
          : SizedBox(width: size.width, height: size.height, child: image),
    );
  }

  Widget _buildBlockImage(Widget child) => ForumHtmlBlockImageFrame(
    aspectRatio: _layout.aspectRatio ?? 0.7,
    // LayoutBuilder's build scope also relayouts on mode changes. Keep it inside
    // the tight clip so content changes do not invalidate surrounding tables.
    child: _clipMedia(
      _viewportHandle?.observesVisibility == true
          ? ForumHtmlImagePaintObserver(
              onPaint: _binding.reportPaintedFrame,
              child: child,
            )
          : child,
    ),
  );

  Widget _buildImageContent() {
    final lease = _binding.displayLease;
    final sticker = widget.image.isSticker;
    final size = _layout.displaySize;
    void firstFrameRendered() {
      if (_binding.reportFirstFrame(lease)) {
        if (!sticker) _reportRenderedFrame();
      }
    }

    void failed() {
      _binding.reportFailure(lease);
    }

    return widget.host.buildImage(
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
              if (lease.isActive) _retryImage();
            },
      showDelayedLoadingIndicator: !sticker,
      onImageResolved: (size) {
        if (!mounted || !lease.isActive) return;
        widget.onImageResolved?.call(size);
        if (!mounted || !lease.isActive) return;
        if (sticker) {
          if (_validSize(size)) {
            _intrinsicSize = size;
            _hasResolvedImageSize = true;
            widget.rememberInlineSize?.call(size);
          }
          return;
        }
        widget.host.onBlockImageResolved(widget.image, size);
        if (!mounted || !lease.isActive) return;
        _intrinsicSize = _validSize(size) ? size : null;
        _hasResolvedImageSize = _intrinsicSize != null;
        _reportRenderedFrame();
        _promoteDecodedSize(size);
      },
      onFirstFrameRendered: firstFrameRendered,
      onImageFailed: failed,
      waitForCacheWrite: !sticker,
      retryToken: _binding.retryToken,
    );
  }

  void _reportRenderedFrame() {
    if (!_binding.firstFrameRendered || !_binding.canDisplay) return;
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
    _binding.reportRetainAdmission(admission);
  }

  @override
  void dispose() {
    _binding.dispose();
    super.dispose();
  }

  void _retryImage() {
    if (!mounted) return;
    setState(_binding.retry);
  }

  void _scheduleDimensionPromotion() {
    if (_dimensionPromotionScheduled ||
        !_binding.canPromoteDimensions ||
        _intrinsicSize != null ||
        _cachedLayout != null) {
      return;
    }
    _dimensionPromotionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dimensionPromotionScheduled = false;
      if (!mounted || _intrinsicSize != null || _cachedLayout != null) {
        return;
      }
      final priority = _binding.takeDimensionPromotion();
      if (priority == null) return;
      unawaited(_loadDimensions(priority: priority));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _loadDimensions({
    ForumHtmlImageDimensionPriority? priority,
  }) async {
    if (widget.image.htmlSize != null ||
        widget.image.cacheKey.trim().isEmpty ||
        (widget.image.isSticker && _initialInlineLayout != null)) {
      return;
    }
    final image = widget.image;
    final host = widget.host;
    final result = await _binding.loadDimensions(priority: priority);
    if (!mounted || !result.isCurrent) return;
    final dimensions = result.dimensions;
    if (dimensions == null) {
      if (!_binding.hasPendingDimensions) _scheduleDimensionPromotion();
      return;
    }
    // Once a smiley is displayed, keep its natural inline layout. A late cache
    // hint must not resize it again; decoded sizes still seed the next mount.
    if (_hasResolvedImageSize ||
        (image.isSticker && _binding.inlineDisplaySettled)) {
      return;
    }
    if (image.isSticker && _validSize(dimensions.size)) {
      widget.rememberInlineSize?.call(dimensions.size);
      if (!mounted || !result.isCurrent) return;
    }
    if (_intrinsicSize == dimensions.size &&
        _cachedLayout == dimensions.layout) {
      return;
    }
    if (!image.isSticker) host.onBlockImageResolved(image, dimensions.size);
    if (!mounted || !result.isCurrent || _hasResolvedImageSize) {
      return;
    }
    _intrinsicSize = _validSize(dimensions.size) ? dimensions.size : null;
    _reportRenderedFrame();
    if (_cachedLayout != dimensions.layout) {
      final current = _layout.aspectRatio;
      final next = dimensions.layout.aspectRatio;
      // Dormant images still own a layout frame. Its corrected height can
      // move visible text even while the pixel provider is not mounted.
      if (_layout.isFallback &&
          current != null &&
          current.isFinite &&
          current > 0 &&
          next != null &&
          next.isFinite &&
          next > 0 &&
          (next - current).abs() / current >= 0.05) {
        final shift = _layoutShift(decoded: next, current: current);
        if (shift != null) widget.onImageLayoutShift?.call(shift);
      }
      if (!mounted || !result.isCurrent || _hasResolvedImageSize) {
        return;
      }
      setState(() => _cachedLayout = dimensions.layout);
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
