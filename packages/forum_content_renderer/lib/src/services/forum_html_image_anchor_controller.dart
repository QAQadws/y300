import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../html_rendering/forum_html_prepared_render_document.dart';
import 'forum_body_scroll_geometry.dart';

typedef _ImageIdentity = ({int index, String cacheKey, String url});

typedef ForumHtmlOffscreenImageReveal =
    Future<bool> Function(
      int index,
      ScrollPosition position,
      bool Function() isCurrent,
      Future<bool> Function(double offset, bool Function() layoutIsCurrent)
      revealAt,
    );
typedef _OffscreenLayout = ({
  ForumHtmlOffscreenImageReveal reveal,
  bool Function() isCurrent,
});

/// Reveals a readable image after verifying its mounted source and slot.
///
/// One controller belongs to one root HTML body. Nested folds share its root
/// sequence; missing or closed-fold anchors leave the existing position alone.
final class ForumHtmlImageAnchorController {
  final _anchors = <_ImageIdentity, _ForumHtmlImageAnchorState>{};
  List<_ImageIdentity> _entries = const [];
  Set<_ImageIdentity> _entrySet = const {};
  String? _sourceId;
  Object _bindingIdentity = Object();
  int _revealGeneration = 0;
  bool _disposed = false;
  _OffscreenLayout? _offscreenLayout;

  /// A renderer binding marker, changed when the readable sequence changes.
  Object get bindingIdentity => _bindingIdentity;

  /// The renderer owns sequence binding; callers only request image reveals.
  void bindSequence(ForumHtmlReadableImageSequence sequence) {
    if (_disposed) return;
    final entries = [
      for (final entry in sequence.entries)
        (index: entry.index, cacheKey: entry.cacheKey, url: entry.url),
    ];
    if (_sourceId == sequence.sourceId && listEquals(_entries, entries)) return;
    _sourceId = sequence.sourceId;
    _entries = entries;
    _entrySet = entries.toSet();
    _bindingIdentity = Object();
    _revealGeneration++;
    _anchors.clear();
  }

  /// Installs the current layout's bounded offscreen locator. Its offset is
  /// a hint to mount the target. Only the real image anchor can confirm it.
  VoidCallback attachOffscreenReveal(
    ForumHtmlOffscreenImageReveal reveal, {
    required bool Function() isCurrent,
  }) {
    if (_disposed) return () {};
    final layout = _offscreenLayout = (reveal: reveal, isCurrent: isCurrent);
    return () {
      if (_offscreenLayout == layout) _offscreenLayout = null;
    };
  }

  /// Aligns the image's leading edge within the supplied scroll viewport.
  ///
  /// The caller should keep its covering reader route visible until this
  /// completes. Exact corrections are bounded to three layout frames.
  Future<bool> revealImage({
    required int index,
    required String cacheKey,
    required String url,
    required ScrollController scrollController,
    required bool Function() isCurrent,
  }) async {
    final generation = ++_revealGeneration;
    final binding = _bindingIdentity;
    bool current() =>
        !_disposed &&
        generation == _revealGeneration &&
        identical(binding, _bindingIdentity) &&
        isCurrent();
    final key = (index: index, cacheKey: cacheKey, url: url);
    if (!current() ||
        !_entrySet.contains(key) ||
        scrollController.positions.length != 1) {
      return false;
    }
    final position = scrollController.position;
    final originalPixels = position.pixels;
    var moved = false;

    bool available() =>
        current() &&
        scrollController.positions.length == 1 &&
        identical(scrollController.position, position);

    void move(double target) {
      final pixels = target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((position.pixels - pixels).abs() <= 0.5) return;
      moved = true;
      scrollController.jumpTo(pixels);
    }

    Future<bool> align(bool Function() valid, {bool inFlow = false}) async {
      for (var frame = 0; frame < 3; frame++) {
        if (!valid()) return false;
        final target = _targetPixels(key, position);
        if (target == null) return false;
        if (inFlow) _showInTable(key, move: true);
        move(target);
        // Check again after layout and any queued image-height compensation.
        await _nextFrame();
        if (!valid()) return false;
        final corrected = _targetPixels(key, position);
        if (corrected == null) return false;
        if ((position.pixels - corrected).abs() <= 0.5 &&
            (!inFlow || _showInTable(key, move: false))) {
          return true;
        }
      }
      return false;
    }

    var aligned = false;
    try {
      final layout = _offscreenLayout;
      bool locating() =>
          available() &&
          _offscreenLayout == layout &&
          (layout?.isCurrent() ?? true);
      if (!locating()) return false;
      if (_targetPixels(key, position) != null &&
          (layout == null || _showInTable(key, move: false))) {
        return aligned = await align(locating);
      }
      if (layout == null) return false;
      await layout.reveal(index, position, locating, (
        offset,
        layoutIsCurrent,
      ) async {
        bool valid() => locating() && layoutIsCurrent();
        if (!offset.isFinite || !valid() || !position.hasContentDimensions) {
          return false;
        }
        move(offset);
        for (var frame = 0; frame < 40 && valid(); frame++) {
          if (_targetPixels(key, position) != null) {
            return aligned = await align(valid, inFlow: true);
          }
          await _nextFrame();
        }
        return false;
      });
      return aligned;
    } finally {
      if (!aligned && moved && available() && position.hasContentDimensions) {
        move(originalPixels);
      }
    }
  }

  Future<void> _nextFrame() {
    WidgetsBinding.instance.ensureVisualUpdate();
    return WidgetsBinding.instance.endOfFrame;
  }

  bool _showInTable(_ImageIdentity key, {required bool move}) {
    final anchor = _anchors[key];
    if (anchor == null || !anchor.mounted) return false;
    final position = Scrollable.maybeOf(
      anchor.context,
      axis: Axis.horizontal,
    )?.position;
    if (position == null) return true;
    final box = anchor.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !position.hasContentDimensions) {
      return false;
    }
    final viewport = forumBodyViewportForPosition(box, position);
    if (viewport == null) return false;
    final clip = MatrixUtils.transformRect(
      viewport.getTransformTo(box),
      viewport.paintBounds,
    );
    if (clip.isFinite && clip.left < box.size.width && clip.right > 0) {
      return true;
    }
    if (move) {
      final offset = viewport.getOffsetToReveal(box, 0).offset;
      if (offset.isFinite) {
        position.jumpTo(
          offset.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      }
    }
    return false;
  }

  double? _targetPixels(_ImageIdentity key, ScrollPosition position) {
    final anchor = _anchors[key];
    if (anchor == null ||
        !anchor.mounted ||
        !position.hasContentDimensions ||
        !identical(
          Scrollable.maybeOf(anchor.context, axis: position.axis)?.position,
          position,
        )) {
      return null;
    }
    final box = anchor.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final viewport = forumBodyViewportForPosition(box, position);
    if (viewport == null) return null;
    final target = viewport.getOffsetToReveal(box, 0).offset;
    if (!target.isFinite) return null;
    return target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  void _register(_ForumHtmlImageAnchorState anchor) {
    final widget = anchor.widget;
    if (_disposed ||
        widget.sourceId != _sourceId ||
        !_entrySet.contains(widget._identity)) {
      return;
    }
    _anchors[widget._identity] = anchor;
  }

  void _unregister(_ForumHtmlImageAnchorState anchor, _ImageIdentity key) {
    if (identical(_anchors[key], anchor)) _anchors.remove(key);
  }

  void dispose() {
    _disposed = true;
    _revealGeneration++;
    _anchors.clear();
    _entries = const [];
    _entrySet = const {};
    _sourceId = null;
    _offscreenLayout = null;
  }
}

/// Internal renderer wrapper. Its handle exists only while the image mounts.
class ForumHtmlImageAnchor extends StatefulWidget {
  const ForumHtmlImageAnchor({
    super.key,
    required this.controller,
    required this.sourceId,
    required this.index,
    required this.cacheKey,
    required this.url,
    required this.child,
  });

  final ForumHtmlImageAnchorController? controller;
  final String sourceId;
  final int index;
  final String cacheKey;
  final String url;
  final Widget child;

  _ImageIdentity get _identity => (index: index, cacheKey: cacheKey, url: url);

  @override
  State<ForumHtmlImageAnchor> createState() => _ForumHtmlImageAnchorState();
}

class _ForumHtmlImageAnchorState extends State<ForumHtmlImageAnchor> {
  @override
  void initState() {
    super.initState();
    widget.controller?._register(this);
  }

  @override
  void didUpdateWidget(covariant ForumHtmlImageAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.controller?._unregister(this, oldWidget._identity);
    widget.controller?._register(this);
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.controller?._unregister(this, widget._identity);
    super.dispose();
  }
}
