import 'dart:async';
import 'dart:math' as math;

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
  });

  final ForumBodyTableLayout layout;
  final ScrollController horizontalController;
  final ScrollController verticalController;
  final ForumBodyTableSliceBuilder buildSlice;
  final void Function(Object error, StackTrace stackTrace) onFailure;

  /// True after all slices intersecting the current viewport have mounted.
  /// This is presentation readiness, not source or image coverage.
  final ValueChanged<bool>? onReadyChanged;

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
    widget.horizontalController.addListener(_schedule);
    widget.verticalController.addListener(_schedule);
    _budget = widget.layout.layoutBudgetChanges.listen((_) {
      if (_waiting || widget.layout.isClosed) {
        _waiting = false;
        _schedule();
      }
    }, onDone: _schedule);
    _schedule();
  }

  void _unlisten(ForumBodyTableBookViewport config) {
    config.horizontalController.removeListener(_schedule);
    config.verticalController.removeListener(_schedule);
    unawaited(_budget?.cancel());
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
      return;
    }
    final h = widget.horizontalController;
    final v = widget.verticalController;
    if (!h.hasClients ||
        !v.hasClients ||
        !h.position.hasContentDimensions ||
        !v.position.hasContentDimensions) {
      return;
    }
    final window = Rect.fromLTWH(
      h.offset,
      v.offset,
      h.position.viewportDimension,
      v.position.viewportDimension,
    );
    if (window != _window) _updateWindow(window);
    _reportReady(_visible.every(_ready.containsKey));
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
    for (final fragments in _ready.values) {
      _release(fragments);
    }
    _ready.clear();
    _failed.clear();
    _visible = const {};
    _window = null;
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
        return SingleChildScrollView(
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
