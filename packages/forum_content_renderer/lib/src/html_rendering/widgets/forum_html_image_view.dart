import 'dart:async';

import 'package:flutter/material.dart';

import '../../contracts/forum_html_display_image.dart';
import '../../contracts/forum_html_image_host.dart';
import '../../contracts/forum_html_image_predecode_host.dart';
import '../../helpers/forum_html_image_presentation.dart';
import '../../services/forum_html_image_viewport_coordinator.dart';
import '../forum_html_render_callbacks.dart';
import 'forum_html_block_image_frame.dart';

/// Displays one Host-resolved image without parsing HTML or creating requests.
/// The same binding and callback generations protect standalone native bodies
/// and the HTML factory from late dimensions, decoded sizes and frame events.
class ForumHtmlImageView extends StatefulWidget {
  const ForumHtmlImageView({
    super.key,
    required this.host,
    required this.image,
    this.initialInlineSize,
    this.rememberInlineSize,
    this.onImageResolved,
    this.onImageLayoutShift,
    this.viewportCoordinator,
    this.fit,
    this.onImageDisplayChanged,
    this.onImageLayoutResolved,
  });

  final ForumHtmlImageHost host;
  final ForumHtmlDisplayImage image;
  final Size? initialInlineSize;
  final ValueChanged<Size>? rememberInlineSize;
  final ValueChanged<Size>? onImageResolved;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final ForumHtmlImageViewportCoordinator? viewportCoordinator;

  /// Native fixed-page frames use contain; HTML keeps its existing fit policy.
  final BoxFit? fit;
  final ValueChanged<bool>? onImageDisplayChanged;

  /// Current accepted dimension metadata, separate from rendered pixels.
  /// Fixed-page consumers may prepare a new layout without resizing this page.
  final ValueChanged<ForumHtmlImageLayout>? onImageLayoutResolved;

  @override
  State<ForumHtmlImageView> createState() => _ForumHtmlImageViewState();
}

class _ForumHtmlImageViewState extends State<ForumHtmlImageView> {
  ForumHtmlImageLayout? _cachedLayout;
  ForumHtmlImageLayout? _initialInlineLayout;
  Size? _intrinsicSize;
  bool _hasResolvedImageSize = false;
  bool _firstFrameRendered = false;
  bool _inlineDisplaySettled = false;
  int _bindingRevision = 0;
  int _callbackRevision = 0;
  int _retryToken = 0;
  ForumHtmlImageViewportHandle? _viewportHandle;
  ForumHtmlImageViewportMode? _lastMode;
  ForumHtmlImageViewportWork? _prefetchToken;
  Object? _prefetchIdentity;
  Size _displaySize = Size.zero;
  bool _workConfigurationScheduled = false;
  bool _dimensionPromotionScheduled = false;
  bool _dimensionRetryUsed = false;
  int _dimensionLookupsPending = 0;
  ForumHtmlImageDimensionPriority _dimensionPriority =
      ForumHtmlImageDimensionPriority.background;

  ForumHtmlImageLayout get _layout =>
      _cachedLayout ?? _initialInlineLayout ?? widget.image.initialLayout;

  void _restoreInlineLayout() {
    if (!widget.image.isSticker || widget.image.htmlSize != null) {
      _initialInlineLayout = null;
      return;
    }
    final size =
        widget.image.initialLayout.displaySize ?? widget.initialInlineSize;
    _initialInlineLayout = size != null && forumHtmlValidImageSize(size)
        ? ForumHtmlImageLayout(displaySize: size, aspectRatio: size.aspectRatio)
        : null;
  }

  @override
  void initState() {
    super.initState();
    _restoreInlineLayout();
    _viewportHandle = widget.viewportCoordinator?.register();
    _loadDimensions();
  }

  @override
  void didUpdateWidget(covariant ForumHtmlImageView oldWidget) {
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
      _hasResolvedImageSize = false;
      _firstFrameRendered = false;
      widget.onImageDisplayChanged?.call(false);
      _inlineDisplaySettled = false;
      _restoreInlineLayout();
      _dimensionRetryUsed = false;
      _dimensionLookupsPending = 0;
      _dimensionPriority = ForumHtmlImageDimensionPriority.background;
      _loadDimensions();
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
      final width = _displaySize.width;
      handle.configureWork(
        identity: (
          widget.host,
          widget.image.identity,
          // Intrinsic-height recovery must not retire a width-bound frame.
          width,
          MediaQuery.devicePixelRatioOf(context),
        ),
        canPredecode:
            widget.host is ForumHtmlImagePredecodeHost &&
            width.isFinite &&
            width > 0,
      );
    });
  }

  bool _acceptCallback(int revision) =>
      mounted &&
      revision == _callbackRevision &&
      (_viewportHandle == null || _viewportHandle!.value.keepsImageMounted);

  Widget _buildImage() {
    final image = _buildImageContent();
    if (!widget.image.isSticker) return _buildBlockImage(image);
    final size = _layout.displaySize;
    return forumHtmlClipImage(
      size == null
          ? image
          : SizedBox(width: size.width, height: size.height, child: image),
    );
  }

  Widget _buildBlockImage(Widget child) => ForumHtmlBlockImageFrame(
    aspectRatio: _layout.aspectRatio ?? 0.7,
    // LayoutBuilder's build scope also relayouts on mode changes. Keep it inside
    // the tight clip so content changes do not invalidate surrounding tables.
    child: forumHtmlClipImage(child),
  );

  Widget _buildImageContent() {
    final revision = _callbackRevision;
    final sticker = widget.image.isSticker;
    final size = _layout.displaySize;
    void firstFrameRendered() {
      if (_acceptCallback(revision)) {
        _firstFrameRendered = true;
        _inlineDisplaySettled = true;
        if (!sticker) _reportRenderedFrame();
        if (_acceptCallback(revision)) widget.onImageDisplayChanged?.call(true);
      }
    }

    void failed() {
      if (_acceptCallback(revision)) {
        _firstFrameRendered = false;
        _inlineDisplaySettled = true;
        _viewportHandle?.reportImageFailed();
        widget.onImageDisplayChanged?.call(false);
      }
    }

    return widget.host.buildImage(
      image: widget.image,
      fit: widget.fit ?? (sticker ? BoxFit.contain : BoxFit.fitWidth),
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
        if (!_acceptCallback(revision)) return;
        if (sticker) {
          if (forumHtmlValidImageSize(size)) {
            _intrinsicSize = size;
            _hasResolvedImageSize = true;
            widget.rememberInlineSize?.call(size);
            if (_acceptCallback(revision)) {
              // Metadata can seed a new fixed layout without resizing the
              // current inline image. Explicit author dimensions still win.
              widget.onImageLayoutResolved?.call(
                widget.image.htmlSize == null
                    ? ForumHtmlImageLayout(
                        displaySize: size,
                        aspectRatio: size.aspectRatio,
                      )
                    : _layout,
              );
            }
          }
          return;
        }
        widget.host.onBlockImageResolved(widget.image, size);
        if (!_acceptCallback(revision)) return;
        _intrinsicSize = forumHtmlValidImageSize(size) ? size : null;
        _hasResolvedImageSize = _intrinsicSize != null;
        _reportRenderedFrame();
        _promoteDecodedSize(size);
        if (_acceptCallback(revision) && forumHtmlValidImageSize(size)) {
          widget.onImageLayoutResolved?.call(
            _inlineNaturalLayout(
              size,
              widget.image.htmlSize == null
                  ? ForumHtmlImageLayout(aspectRatio: size.aspectRatio)
                  : _layout,
            ),
          );
        }
      },
      onFirstFrameRendered: firstFrameRendered,
      onImageFailed: failed,
      waitForCacheWrite: !sticker,
      retryToken: _retryToken,
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

  ForumHtmlImageLayout _inlineNaturalLayout(
    Size size,
    ForumHtmlImageLayout otherwise,
  ) =>
      !widget.image.isSticker &&
          widget.initialInlineSize != null &&
          forumHtmlValidImageSize(size)
      ? ForumHtmlImageLayout(displaySize: size, aspectRatio: size.aspectRatio)
      : otherwise;

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
    final token = handle.tryBeginWork();
    if (token == null) return;
    _prefetchIdentity = identity;
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
    widget.onImageDisplayChanged?.call(false);
    _viewportHandle?.reportLoadStarted();
    setState(() => _retryToken++);
  }

  void _scheduleDimensionPromotion() {
    if (_dimensionPromotionScheduled ||
        _viewportHandle == null ||
        _viewportHandle!.value == ForumHtmlImageViewportMode.dormant ||
        widget.host is! ForumHtmlImageDimensionPriorityHost ||
        widget.image.isSticker ||
        widget.image.htmlSize != null ||
        _intrinsicSize != null ||
        _cachedLayout != null ||
        (_dimensionRetryUsed && _dimensionLookupsPending == 0)) {
      return;
    }
    _dimensionPromotionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dimensionPromotionScheduled = false;
      if (!mounted ||
          widget.host is! ForumHtmlImageDimensionPriorityHost ||
          widget.image.isSticker ||
          widget.image.htmlSize != null ||
          _intrinsicSize != null ||
          _cachedLayout != null) {
        return;
      }
      // Read the current binding and window after layout. A pending lookup is
      // joined/promoted without spending the one fresh missing-hint retry.
      final priority = switch (_viewportHandle?.value) {
        ForumHtmlImageViewportMode.display =>
          ForumHtmlImageDimensionPriority.visible,
        ForumHtmlImageViewportMode.retained ||
        ForumHtmlImageViewportMode.prefetch ||
        ForumHtmlImageViewportMode.predecode =>
          ForumHtmlImageDimensionPriority.nearby,
        _ => null,
      };
      if (priority == null) return;
      if (_dimensionLookupsPending > 0) {
        if (priority.index <= _dimensionPriority.index) return;
      } else {
        if (_dimensionRetryUsed) return;
        _dimensionRetryUsed = true;
      }
      if (priority.index > _dimensionPriority.index) {
        _dimensionPriority = priority;
      }
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
    final revision = _bindingRevision;
    final image = widget.image;
    final host = widget.host;
    _dimensionLookupsPending++;
    ({Size size, ForumHtmlImageLayout layout})? dimensions;
    try {
      dimensions =
          priority != null && host is ForumHtmlImageDimensionPriorityHost
          ? await (host as ForumHtmlImageDimensionPriorityHost)
                .loadDimensionsWithPriority(image, priority: priority)
          : await host.loadDimensions(image);
    } catch (_) {
      // Cached dimensions are optional hints; a cache race must not stop display.
      return;
    } finally {
      if (mounted && revision == _bindingRevision) {
        _dimensionLookupsPending--;
        if (dimensions == null && _dimensionLookupsPending == 0) {
          // A joined request can still be displaced or miss. Only the current
          // viewport may request one fresh read; a second miss cannot loop.
          _scheduleDimensionPromotion();
        }
      }
    }
    // Once a smiley is displayed, keep its natural inline layout. A late cache
    // hint must not resize it again; decoded sizes still seed the next mount.
    if (!mounted ||
        revision != _bindingRevision ||
        dimensions == null ||
        _hasResolvedImageSize ||
        (image.isSticker && _inlineDisplaySettled)) {
      return;
    }
    if (image.isSticker && forumHtmlValidImageSize(dimensions.size)) {
      widget.rememberInlineSize?.call(dimensions.size);
    }
    if (_intrinsicSize == dimensions.size &&
        _cachedLayout == dimensions.layout) {
      return;
    }
    if (!image.isSticker) host.onBlockImageResolved(image, dimensions.size);
    if (!mounted || revision != _bindingRevision || _hasResolvedImageSize) {
      return;
    }
    _intrinsicSize = forumHtmlValidImageSize(dimensions.size)
        ? dimensions.size
        : null;
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
      if (!mounted || revision != _bindingRevision || _hasResolvedImageSize) {
        return;
      }
      setState(() => _cachedLayout = dimensions!.layout);
    }
    if (mounted && revision == _bindingRevision) {
      widget.onImageLayoutResolved?.call(
        _inlineNaturalLayout(dimensions.size, _layout),
      );
    }
  }

  void _promoteDecodedSize(Size size) {
    if (widget.image.htmlSize != null ||
        !_layout.isFallback ||
        !forumHtmlValidImageSize(size)) {
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
    if (!forumHtmlValidImageSize(oldSize) ||
        !newHeight.isFinite ||
        newHeight <= 0) {
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
