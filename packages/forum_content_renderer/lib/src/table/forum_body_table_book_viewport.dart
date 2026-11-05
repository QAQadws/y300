import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

import '../pagination/forum_body_prepared_text_fragment.dart';
import '../pagination/forum_body_text_page_preparation.dart';
import 'forum_body_table_preparation.dart';

typedef ForumBodyTableSliceBuilder =
    Widget Function(
      BuildContext context,
      ForumBodyTableAreaLayout area,
      int page,
      List<ForumBodyPreparedTextFragment> fragments,
    );

typedef ForumBodyTableVisibleSlice = ({
  ForumBodyTableAreaLayout area,
  int page,
  Rect bounds,
  List<ForumBodyPreparedTextFragment> fragments,
});

/// One settled, mounted window in table coordinates. Its fragments are
/// borrowed; asynchronous consumers must recheck [isCurrent] before use.
final class ForumBodyTableVisibleWindow {
  const ForumBodyTableVisibleWindow._(
    this.layout,
    this.bounds,
    this.slices,
    this.hasUserScrolled,
    this._isCurrent,
  );

  final ForumBodyTableLayout layout;
  final Rect bounds;
  final List<ForumBodyTableVisibleSlice> slices;
  final bool hasUserScrolled;
  final bool Function() _isCurrent;

  bool get isCurrent => !layout.isClosed && _isCurrent();
}

/// A book-page viewport over one already composed table. Controllers are
/// borrowed from the mounted page. Visible slices are owned here, including
/// during preparation; a builder borrows them to paint the same source pages.
final class ForumBodyTableBookViewport extends StatefulWidget {
  const ForumBodyTableBookViewport({
    super.key,
    required this.layout,
    required this.horizontalController,
    required this.verticalController,
    required this.buildSlice,
    required this.onFailure,
    this.onReadyChanged,
    this.onWindowChanged,
  });

  final ForumBodyTableLayout layout;
  final ScrollController horizontalController;
  final ScrollController verticalController;
  final ForumBodyTableSliceBuilder buildSlice;
  final void Function(Object error, StackTrace stackTrace) onFailure;

  /// True after all slices intersecting the current viewport have mounted.
  /// This is presentation readiness, not source or image coverage.
  final ValueChanged<bool>? onReadyChanged;

  /// A settled window after its slices have mounted, or null while moving or
  /// waiting for the newly visible slices. This does not confirm reading.
  final ValueChanged<ForumBodyTableVisibleWindow?>? onWindowChanged;

  @override
  State<ForumBodyTableBookViewport> createState() => _TableBookViewportState();
}

typedef _Slice = ({ForumBodyTableAreaLayout area, int page});

final class _TableBookViewportState extends State<ForumBodyTableBookViewport> {
  static const _physics = AlwaysScrollableScrollPhysics(
    parent: ClampingScrollPhysics(),
  );

  final _ready = <_Slice, List<ForumBodyPreparedTextFragment>>{};
  final _failed = <_Slice>{};
  Set<_Slice> _visible = const {};
  Rect? _window;
  Rect? _userScrollOrigin;
  ForumBodyTableVisibleWindow? _publishedWindow;
  int _scrollRevision = 0;
  _Slice? _working;
  ForumBodyTextPagePreparation? _preparation;
  StreamSubscription<int>? _budget;
  bool _waiting = false;
  bool _scheduled = false;
  bool _reportedReady = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant ForumBodyTableBookViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout ||
        oldWidget.horizontalController != widget.horizontalController ||
        oldWidget.verticalController != widget.verticalController) {
      _unlisten(oldWidget);
      _clear();
      _listen();
    }
  }

  void _listen() {
    widget.horizontalController.addListener(_scrollChanged);
    widget.verticalController.addListener(_scrollChanged);
    _budget = widget.layout.layoutBudgetChanges.listen((_) {
      if (_waiting || widget.layout.isClosed) {
        _waiting = false;
        _schedule();
      }
    }, onDone: _schedule);
    _schedule();
  }

  void _unlisten(ForumBodyTableBookViewport config) {
    config.horizontalController.removeListener(_scrollChanged);
    config.verticalController.removeListener(_scrollChanged);
    unawaited(_budget?.cancel());
  }

  void _scrollChanged() {
    _scrollRevision++;
    _schedule();
  }

  bool _onScroll(ScrollNotification notification) {
    if ((notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle) ||
        (notification is ScrollStartNotification &&
            notification.dragDetails != null)) {
      _userScrollOrigin ??= _window;
    }
    if (notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _scrollChanged();
    }
    return false;
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _advance();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _advance() {
    if (widget.layout.isClosed) {
      if (_ready.isNotEmpty) {
        setState(_clear);
      } else {
        _clear();
      }
      _reportReady(false);
      _publishWindow(null);
      return;
    }
    final window = _currentBounds();
    if (window == null) return;
    if (window != _window) _updateWindow(window);
    final ready = _visible.every(_ready.containsKey);
    _reportReady(ready);
    _publishWindow(ready && !_scrolling ? window : null);
    if (!mounted || _waiting) return;
    final slice = _working ?? _nextSlice();
    if (slice == null) return;
    _working = slice;
    try {
      final preparation = _preparation ??= slice.area.openPagePreparation(
        slice.page,
      );
      final step = preparation.advance(maxFragments: 1, maxParts: 8);
      _waiting = step.waitingForLayoutBudget;
      if (step.isReady) {
        final fragments = preparation.takeFragments();
        _stopWork();
        setState(() => _ready[slice] = fragments);
      }
      if (!_waiting) _schedule();
    } catch (error, stackTrace) {
      _stopWork();
      _failed.add(slice);
      if (!widget.layout.isClosed) {
        widget.onFailure(error, stackTrace);
        _schedule();
      }
    }
  }

  Rect? _currentBounds() {
    final h = widget.horizontalController;
    final v = widget.verticalController;
    if (!h.hasClients ||
        !v.hasClients ||
        !h.position.hasContentDimensions ||
        !v.position.hasContentDimensions) {
      return null;
    }
    return Rect.fromLTWH(
      h.offset,
      v.offset,
      h.position.viewportDimension,
      v.position.viewportDimension,
    );
  }

  bool get _scrolling =>
      widget.horizontalController.position.isScrollingNotifier.value ||
      widget.verticalController.position.isScrollingNotifier.value;

  void _publishWindow(Rect? bounds) {
    final onChanged = widget.onWindowChanged;
    if (onChanged == null) return;
    if (bounds == null) {
      if (_publishedWindow == null) return;
      _publishedWindow = null;
      onChanged(null);
      return;
    }
    if (_publishedWindow?.isCurrent == true) return;
    final revision = _scrollRevision;
    final layout = widget.layout;
    final userOrigin = _userScrollOrigin;
    _userScrollOrigin = null;
    late final ForumBodyTableVisibleWindow window;
    window = ForumBodyTableVisibleWindow._(
      layout,
      bounds,
      List.unmodifiable([
        for (final slice in _visible)
          (
            area: slice.area,
            page: slice.page,
            bounds: _sliceBounds(slice),
            fragments: _ready[slice]!,
          ),
      ]),
      userOrigin != null && userOrigin.topLeft != bounds.topLeft,
      () =>
          mounted &&
          identical(widget.layout, layout) &&
          revision == _scrollRevision &&
          identical(_publishedWindow, window) &&
          _currentBounds() == bounds &&
          !_scrolling,
    );
    _publishedWindow = window;
    onChanged(window);
  }

  void _reportReady(bool value) {
    if (value == _reportedReady) return;
    _reportedReady = value;
    widget.onReadyChanged?.call(value);
  }

  _Slice? _nextSlice() {
    for (final slice in _visible) {
      if (!_ready.containsKey(slice) && !_failed.contains(slice)) return slice;
    }
    return null;
  }

  void _updateWindow(Rect window) {
    _window = window;
    _visible = _slicesIn(window).toSet();
    if (!_visible.contains(_working)) _stopWork();
    _failed.retainAll(_visible);
    final offscreen = _ready.keys.where((s) => !_visible.contains(s)).toList();
    if (offscreen.isEmpty) return;
    setState(() {
      for (final slice in offscreen) {
        _release(_ready.remove(slice)!);
      }
    });
  }

  Iterable<_Slice> _slicesIn(Rect window) sync* {
    final layout = widget.layout;
    for (final area in layout.captions.followedBy(layout.cells)) {
      if (!area.contentBounds.overlaps(window)) continue;
      final snapshot = area.snapshot;
      var start = 0;
      var end = snapshot.length;
      // Skip all slices whose occupied bottom is above the visible region.
      while (start < end) {
        final mid = (start + end) ~/ 2;
        final bottom =
            area.contentBounds.top +
            area.pageTop(mid) +
            snapshot[mid].usedHeight;
        if (bottom <= window.top) {
          start = mid + 1;
        } else {
          end = mid;
        }
      }
      for (var page = start; page < snapshot.length; page++) {
        final top = area.contentBounds.top + area.pageTop(page);
        if (top >= window.bottom) break;
        if (snapshot[page].usedHeight > 0) yield (area: area, page: page);
      }
    }
  }

  void _stopWork() {
    _preparation?.close();
    _preparation = null;
    _working = null;
    _waiting = false;
  }

  void _clear() {
    _stopWork();
    _scrollRevision++;
    for (final fragments in _ready.values) {
      _release(fragments);
    }
    _ready.clear();
    _failed.clear();
    _visible = const {};
    _window = null;
    _userScrollOrigin = null;
  }

  void _release(List<ForumBodyPreparedTextFragment> fragments) {
    for (final fragment in fragments) {
      fragment.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    if (layout.isClosed) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        assert(constraints.hasBoundedWidth && constraints.hasBoundedHeight);
        _schedule();
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SingleChildScrollView(
            controller: widget.horizontalController,
            primary: false,
            scrollDirection: Axis.horizontal,
            reverse: Directionality.of(context) == TextDirection.rtl,
            physics: _physics,
            child: SizedBox(
              width: math.max(constraints.maxWidth, layout.size.width),
              child: SingleChildScrollView(
                controller: widget.verticalController,
                primary: false,
                physics: _physics,
                child: SizedBox(
                  height: math.max(constraints.maxHeight, layout.size.height),
                  child: CustomPaint(
                    painter: _TableBackgrounds(layout),
                    child: Stack(
                      children: [
                        for (final entry in _ready.entries)
                          Positioned.fromRect(
                            key: ValueKey(entry.key),
                            rect: _sliceBounds(entry.key),
                            child: widget.buildSlice(
                              context,
                              entry.key.area,
                              entry.key.page,
                              entry.value,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Rect _sliceBounds(_Slice slice) {
    final area = slice.area;
    return Rect.fromLTWH(
      area.contentBounds.left,
      area.contentBounds.top + area.pageTop(slice.page),
      area.contentBounds.width,
      area.snapshot[slice.page].usedHeight,
    );
  }

  @override
  void dispose() {
    _unlisten(widget);
    _clear();
    super.dispose();
  }
}

final class _TableBackgrounds extends CustomPainter {
  const _TableBackgrounds(this.layout);
  final ForumBodyTableLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    if (layout.background case final color?) {
      canvas.drawRect(Offset.zero & layout.size, fill..color = color);
    }
    for (final (index, color) in layout.rowBackgrounds.indexed) {
      if (color != null) {
        canvas.drawRect(
          layout.geometry.rowBounds(index).shift(Offset(0, layout.gridTop)),
          fill..color = color,
        );
      }
    }
    for (final area in layout.cells.followedBy(layout.captions)) {
      if (area.background case final color?) {
        canvas.drawRect(area.bounds, fill..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TableBackgrounds oldDelegate) =>
      oldDelegate.layout != layout;
}
