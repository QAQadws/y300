import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart' show RenderBox, ScrollDirection;
import 'package:flutter/widgets.dart';

import '../pagination/forum_body_prepared_text_fragment.dart';
import '../pagination/forum_body_text_page_binding.dart';
import '../pagination/forum_body_text_page_composer.dart';
import '../pagination/forum_body_text_page_preparation.dart';
import '../pagination/forum_body_text_page_session.dart';
import '../services/forum_body_scroll_geometry.dart';
import 'forum_body_table_preparation.dart';

typedef ForumBodyTableSliceBuilder =
    Widget Function(
      BuildContext context,
      ForumBodyTableAreaLayout area,
      int page,
      List<ForumBodyPreparedTextFragment> fragments,
    );

/// Leaf geometry remains in the outer table's coordinates. [clip] includes
/// every ancestor viewport without changing the measured surface's origin.
typedef ForumBodyTableVisibleSlice = ({
  ForumBodyTableAreaLayout area,
  int page,
  Rect bounds,
  Rect clip,
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

/// A measured cell slice transfers to its first mounted table viewport.
final class ForumBodyTablePreparedSlice {
  ForumBodyTablePreparedSlice({
    required this.area,
    required this.page,
    required List<ForumBodyPreparedTextFragment> fragments,
  }) : _fragments = List.unmodifiable(fragments);

  final ForumBodyTableAreaLayout area;
  final int page;
  List<ForumBodyPreparedTextFragment>? _fragments;
  bool get isPending => _fragments != null;

  List<ForumBodyPreparedTextFragment>? _take(ForumBodyTableLayout layout) {
    final fragments = _fragments;
    if (fragments == null) return null;
    if (layout.isClosed ||
        (!layout.cells.contains(area) && !layout.captions.contains(area)) ||
        !area.ownsPreparedFragments(fragments)) {
      throw StateError('Prepared table slice belongs to a different layout');
    }
    final snapshot = area.snapshot;
    validateForumBodyPreparedTextPageBinding(
      snapshot: snapshot,
      pageIndex: page,
      layoutId: snapshot.layoutId,
      fragments: fragments,
    );
    _fragments = null;
    return fragments;
  }

  void close() {
    final fragments = _fragments;
    _fragments = null;
    if (fragments == null) return;
    for (final fragment in fragments) {
      fragment.close();
    }
  }
}

/// A book-page viewport over one already composed table. Controllers are
/// borrowed from the mounted page. Visible slices are owned here, including
/// during preparation; a builder borrows them to paint the same source pages.
final class ForumBodyTableBookViewport extends _ForumBodyTableViewport {
  const ForumBodyTableBookViewport({
    super.key,
    required super.layout,
    required super.horizontalController,
    required this.verticalController,
    required super.buildSlice,
    required super.onFailure,
    super.onReadyChanged,
    super.onWindowChanged,
  });

  @override
  final ScrollController verticalController;
}

/// A table in a continuous document. The enclosing viewport owns vertical
/// scrolling; the table borrows a horizontal controller only when it overflows.
final class ForumBodyTableFlowViewport extends _ForumBodyTableViewport {
  const ForumBodyTableFlowViewport({
    super.key,
    required super.layout,
    required super.horizontalController,
    required super.buildSlice,
    required super.onFailure,
    super.onReadyChanged,
    super.onWindowChanged,
    this.initialSlice,
  });

  final ForumBodyTablePreparedSlice? initialSlice;

  /// The mounted portion of a settled viewport, even while other cells
  /// prepare. It may contain only the slice transferred for restoration.
  static ForumBodyTableVisibleWindow? borrowPaintedWindow(
    BuildContext viewport,
  ) {
    if (viewport is! StatefulElement) return null;
    final state = viewport.state;
    if (state is! _TableViewportState) return null;
    return state._borrowPaintedWindow();
  }

  @override
  ScrollController? get verticalController => null;
}

abstract class _ForumBodyTableViewport extends StatefulWidget {
  const _ForumBodyTableViewport({
    super.key,
    required this.layout,
    required this.horizontalController,
    required this.buildSlice,
    required this.onFailure,
    this.onReadyChanged,
    this.onWindowChanged,
  });

  final ForumBodyTableLayout layout;
  final ScrollController horizontalController;
  ScrollController? get verticalController;
  final ForumBodyTableSliceBuilder buildSlice;
  final void Function(Object error, StackTrace stackTrace) onFailure;

  /// True after all slices intersecting the current viewport have mounted.
  /// This is presentation readiness, not source or image coverage.
  final ValueChanged<bool>? onReadyChanged;

  /// A settled window after its slices have mounted, or null while moving or
  /// waiting for the newly visible slices. This does not confirm reading.
  final ValueChanged<ForumBodyTableVisibleWindow?>? onWindowChanged;

  @override
  State<_ForumBodyTableViewport> createState() => _TableViewportState();
}

typedef _Slice = ({ForumBodyTableAreaLayout area, int page});

final class _NestedTable {
  _NestedTable(this.area, this.page, this.frame, this.lease)
    : horizontal = ScrollController(
        initialScrollOffset: area.flowTableOffset(page, frame.path) ?? 0,
      ) {
    horizontal.addListener(_rememberOffset);
  }
  final ForumBodyTableAreaLayout area;
  final int page;
  final ForumBodyTextPageTable frame;
  final ForumBodyTablePageLease lease;
  final ScrollController horizontal;
  final key = GlobalKey();
  bool ready = false;
  ForumBodyTableVisibleWindow? window;

  void _rememberOffset() {
    if (lease.isActive && horizontal.hasClients) {
      area.setFlowTableOffset(page, frame.path, horizontal.offset);
    }
  }

  void close() {
    _rememberOffset();
    horizontal.dispose();
    lease.close();
  }
}

final class _TableViewportState extends State<_ForumBodyTableViewport> {
  static const _physics = AlwaysScrollableScrollPhysics(
    parent: ClampingScrollPhysics(),
  );

  final _ready = <_Slice, List<ForumBodyPreparedTextFragment>>{};
  final _nested = <_Slice, List<_NestedTable>>{};
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
  GlobalKey? _flowBoxKey;
  ScrollPosition? _outerPosition;

  @override
  void initState() {
    super.initState();
    _adoptInitialSlice();
    _listen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.verticalController != null) return;
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (identical(position, _outerPosition)) return;
    _unlistenOuter();
    _outerPosition = position;
    position?.addListener(_scrollChanged);
    position?.isScrollingNotifier.addListener(_scrollChanged);
    _scrollChanged();
  }

  @override
  void didUpdateWidget(covariant _ForumBodyTableViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout ||
        oldWidget.horizontalController != widget.horizontalController ||
        oldWidget.verticalController != widget.verticalController) {
      _unlisten(oldWidget);
      _clear();
      _adoptInitialSlice();
      _listen();
    }
  }

  void _adoptInitialSlice() {
    final table = widget;
    if (table is! ForumBodyTableFlowViewport) return;
    final seed = table.initialSlice;
    final fragments = seed?._take(table.layout);
    if (fragments != null) {
      final slice = (area: seed!.area, page: seed.page);
      try {
        _nested[slice] = _openNested(slice);
        _ready[slice] = fragments;
      } catch (_) {
        _release(fragments);
        rethrow;
      }
    }
  }

  List<_NestedTable> _openNested(_Slice slice) {
    final result = <_NestedTable>[];
    try {
      for (final frame in slice.area.snapshot[slice.page].tableFrames) {
        final lease = slice.area.acquireTablePage(slice.page, path: frame.path);
        if (lease == null) throw StateError('Missing nested table layout');
        result.add(_NestedTable(slice.area, slice.page, frame, lease));
      }
      return result;
    } catch (_) {
      for (final table in result) {
        table.close();
      }
      rethrow;
    }
  }

  void _listen() {
    widget.horizontalController.addListener(_scrollChanged);
    widget.verticalController?.addListener(_scrollChanged);
    _budget = widget.layout.layoutBudgetChanges.listen((_) {
      if (_waiting || widget.layout.isClosed) {
        _waiting = false;
        _schedule();
      }
    }, onDone: _schedule);
    _schedule();
  }

  void _unlisten(_ForumBodyTableViewport config) {
    config.horizontalController.removeListener(_scrollChanged);
    config.verticalController?.removeListener(_scrollChanged);
    unawaited(_budget?.cancel());
  }

  void _unlistenOuter() {
    _outerPosition?.removeListener(_scrollChanged);
    _outerPosition?.isScrollingNotifier.removeListener(_scrollChanged);
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
    final window = _currentBounds() ?? Rect.zero;
    if (window != _window) _updateWindow(window);
    final ready =
        !window.isEmpty &&
        _visible.every(
          (slice) =>
              _ready.containsKey(slice) &&
              (_nested[slice] ?? const <_NestedTable>[]).every(
                (table) =>
                    !table.frame.bounds
                        .shift(_sliceBounds(slice).topLeft)
                        .overlaps(window) ||
                    (table.ready && table.window?.isCurrent == true),
              ),
        );
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
        late final List<_NestedTable> nested;
        try {
          nested = _openNested(slice);
        } catch (_) {
          _release(fragments);
          rethrow;
        }
        _stopWork();
        setState(() {
          _ready[slice] = fragments;
          _nested[slice] = nested;
        });
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
    if (v == null) return _flowBounds();
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

  Rect? _flowBounds() {
    final box = _flowBoxKey?.currentContext?.findRenderObject();
    if (box is! RenderBox) return null;
    final clip = forumBodyVisibleBoxClip(box, _outerPosition);
    if (clip == null || clip.isEmpty) return clip;
    final horizontal = widget.horizontalController;
    return horizontal.hasClients && horizontal.position.hasPixels
        ? clip.shift(Offset(horizontal.offset, 0))
        : clip;
  }

  bool get _scrolling {
    final h = widget.horizontalController;
    final v = widget.verticalController;
    final vertical = v?.hasClients == true ? v!.position : _outerPosition;
    return (h.hasClients && h.position.isScrollingNotifier.value) ||
        (vertical?.isScrollingNotifier.value ?? false);
  }

  ForumBodyTableVisibleWindow? _borrowPaintedWindow() {
    final published = _publishedWindow;
    if (published?.isCurrent == true) return published;
    final bounds = _currentBounds();
    if (bounds == null || bounds.isEmpty || _scrolling) return null;
    final revision = _scrollRevision;
    final layout = widget.layout;
    final visible = _collectSlices(bounds);
    if (visible.slices.isEmpty) return null;
    return ForumBodyTableVisibleWindow._(
      layout,
      bounds,
      visible.slices,
      false,
      () =>
          mounted &&
          identical(widget.layout, layout) &&
          revision == _scrollRevision &&
          _currentBounds() == bounds &&
          !_scrolling &&
          visible.isCurrent(),
    );
  }

  ({
    List<ForumBodyTableVisibleSlice> slices,
    bool hasUserScrolled,
    bool Function() isCurrent,
  })
  _collectSlices(Rect bounds) {
    final slices = <ForumBodyTableVisibleSlice>[];
    final roots = <_Slice, List<ForumBodyPreparedTextFragment>>{};
    final children = <ForumBodyTableVisibleWindow>[];
    var hasUserScrolled = false;
    for (final slice in _slicesIn(bounds)) {
      final fragments = _ready[slice];
      if (fragments == null) continue;
      roots[slice] = fragments;
      final rect = _sliceBounds(slice), clip = rect.intersect(bounds);
      if (fragments.isNotEmpty) {
        slices.add((
          area: slice.area,
          page: slice.page,
          bounds: rect,
          clip: clip,
          fragments: fragments,
        ));
      }
      for (final table in _nested[slice] ?? const <_NestedTable>[]) {
        final context = table.key.currentContext;
        final window = table.window?.isCurrent == true
            ? table.window
            : context == null
            ? null
            : ForumBodyTableFlowViewport.borrowPaintedWindow(context);
        if (window == null || !window.isCurrent) continue;
        children.add(window);
        hasUserScrolled |= window.hasUserScrolled;
        final origin =
            rect.topLeft +
            table.frame.bounds.topLeft -
            Offset(
              table.horizontal.hasClients ? table.horizontal.offset : 0,
              0,
            );
        final nestedClip = clip.intersect(window.bounds.shift(origin));
        for (final leaf in window.slices) {
          final shown = leaf.clip.shift(origin).intersect(nestedClip);
          if (shown.isEmpty) continue;
          slices.add((
            area: leaf.area,
            page: leaf.page,
            bounds: leaf.bounds.shift(origin),
            clip: shown,
            fragments: leaf.fragments,
          ));
        }
      }
    }
    return (
      slices: List.unmodifiable(slices),
      hasUserScrolled: hasUserScrolled,
      isCurrent: () =>
          roots.entries.every(
            (entry) => identical(_ready[entry.key], entry.value),
          ) &&
          children.every((window) => window.isCurrent),
    );
  }

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
    final visible = _collectSlices(bounds);
    final userOrigin = _userScrollOrigin;
    _userScrollOrigin = null;
    late final ForumBodyTableVisibleWindow window;
    window = ForumBodyTableVisibleWindow._(
      layout,
      bounds,
      visible.slices,
      visible.hasUserScrolled ||
          (userOrigin != null &&
              (widget.verticalController == null
                  ? userOrigin.left != bounds.left
                  : userOrigin.topLeft != bounds.topLeft)),
      () =>
          mounted &&
          identical(widget.layout, layout) &&
          revision == _scrollRevision &&
          identical(_publishedWindow, window) &&
          _currentBounds() == bounds &&
          visible.isCurrent() &&
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
    _visible = window.isEmpty ? const {} : _slicesIn(window).toSet();
    if (!_visible.contains(_working)) _stopWork();
    _failed.retainAll(_visible);
    final offscreen = _ready.keys.where((s) => !_visible.contains(s)).toList();
    if (offscreen.isEmpty) return;
    setState(() {
      for (final slice in offscreen) {
        for (final table in _nested.remove(slice) ?? const <_NestedTable>[]) {
          table.close();
        }
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
    for (final tables in _nested.values) {
      for (final table in tables) {
        table.close();
      }
    }
    _nested.clear();
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
        assert(constraints.hasBoundedWidth);
        _schedule();
        final vertical = widget.verticalController;
        if (vertical == null) {
          final overflows =
              layout.size.width - constraints.maxWidth >
              precisionErrorTolerance;
          final content = SizedBox(
            width: overflows ? layout.size.width : constraints.maxWidth,
            height: layout.size.height,
            child: _tableSurface(),
          );
          return ForumBodyCompositionObserver(
            key: _flowBoxKey ??= GlobalKey(),
            onComposited: () {
              if (mounted && (_flowBounds() ?? Rect.zero) != _window) {
                _schedule();
              }
            },
            child: overflows
                ? _horizontal(context, content, const ClampingScrollPhysics())
                : content,
          );
        }
        assert(constraints.hasBoundedHeight);
        return _horizontal(
          context,
          SizedBox(
            width: math.max(constraints.maxWidth, layout.size.width),
            child: SingleChildScrollView(
              controller: vertical,
              primary: false,
              physics: _physics,
              child: SizedBox(
                height: math.max(constraints.maxHeight, layout.size.height),
                child: _tableSurface(),
              ),
            ),
          ),
          _physics,
        );
      },
    );
  }

  Widget _horizontal(
    BuildContext context,
    Widget child,
    ScrollPhysics physics,
  ) => NotificationListener<ScrollNotification>(
    onNotification: _onScroll,
    child: SingleChildScrollView(
      controller: widget.horizontalController,
      primary: false,
      scrollDirection: Axis.horizontal,
      reverse: Directionality.of(context) == TextDirection.rtl,
      physics: physics,
      child: child,
    ),
  );

  Widget _tableSurface() => CustomPaint(
    painter: _TableBackgrounds(widget.layout),
    child: Stack(
      children: [
        for (final entry in _ready.entries)
          Positioned(
            key: ValueKey(entry.key),
            left: _sliceBounds(entry.key).left,
            top: _sliceBounds(entry.key).top,
            // Rect subtraction can round fractional image extents. The
            // surface must receive the original published dimensions exactly.
            width: entry.key.area.snapshot.width,
            height: entry.key.area.snapshot[entry.key.page].usedHeight,
            child: widget.buildSlice(
              context,
              entry.key.area,
              entry.key.page,
              entry.value,
            ),
          ),
        for (final entry in _nested.entries)
          for (final table in entry.value)
            Positioned.fromRect(
              rect: table.frame.bounds.shift(_sliceBounds(entry.key).topLeft),
              child: ForumBodyTableFlowViewport(
                key: table.key,
                layout: table.lease.layout,
                horizontalController: table.horizontal,
                buildSlice: widget.buildSlice,
                onFailure: (error, stack) {
                  if (_ownsNested(entry.key, table)) {
                    widget.onFailure(error, stack);
                  }
                },
                onReadyChanged: (ready) {
                  if (!_ownsNested(entry.key, table)) {
                    return;
                  }
                  table.ready = ready;
                  _schedule();
                },
                onWindowChanged: (window) {
                  if (!_ownsNested(entry.key, table)) {
                    return;
                  }
                  table.window = window;
                  _scrollRevision++;
                  _schedule();
                },
              ),
            ),
      ],
    ),
  );

  bool _ownsNested(_Slice slice, _NestedTable table) =>
      mounted &&
      table.lease.isActive &&
      _nested[slice]?.contains(table) == true;

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
    _unlistenOuter();
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
