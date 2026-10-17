import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../html_rendering/forum_html_prepared_render_document.dart';
import 'forum_html_image_viewport_geometry.dart';

typedef _ImageIdentity = ({int index, String cacheKey, String url});

/// Reveals an already mounted readable image without preparing other images.
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

  /// Aligns the image's leading edge within the supplied scroll viewport.
  ///
  /// The caller should keep its covering reader route visible until this
  /// completes. Corrections are bounded to three layout frames. No dimensions,
  /// downloads, persistent positions, or image providers are retained here.
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
    if (!current() || scrollController.positions.length != 1) return false;
    final position = scrollController.position;
    final originalPixels = position.pixels;
    var moved = false;

    bool available() =>
        current() &&
        scrollController.positions.length == 1 &&
        identical(scrollController.position, position);

    void rollback() {
      if (!moved || !available() || !position.hasContentDimensions) return;
      scrollController.jumpTo(
        originalPixels
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    }

    for (var frame = 0; frame < 3; frame++) {
      if (!available()) return false;
      final target = _targetPixels(key, position);
      if (target == null) {
        rollback();
        return false;
      }
      if ((position.pixels - target).abs() > 0.5) {
        moved = true;
        scrollController.jumpTo(target);
      }
      // Layout and previously queued image-height compensation can both run
      // after the first jump. Recheck the real anchor before uncovering it.
      await WidgetsBinding.instance.endOfFrame;
      if (!available()) return false;
      final corrected = _targetPixels(key, position);
      if (corrected == null) {
        rollback();
        return false;
      }
      if ((position.pixels - corrected).abs() <= 0.5) return true;
    }
    rollback();
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
    final viewport = forumHtmlImageViewportFor(box, position);
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
