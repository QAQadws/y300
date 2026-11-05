import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart'
    show GrowthDirection, RenderBox, RenderProxySliver, SliverConstraints;
import 'package:flutter/widgets.dart';

import '../pagination/forum_body_prepared_text_fragment.dart';
import '../pagination/forum_body_text_page_binding.dart';
import '../pagination/forum_body_text_page_composer.dart';
import '../pagination/forum_body_text_page_preparation.dart';
import '../pagination/forum_body_text_page_session.dart';
import '../services/forum_body_scroll_geometry.dart';
import '../services/forum_html_image_anchor_controller.dart';
import '../table/forum_body_table_viewport.dart';

part 'forum_body_flow_image_reveal.dart';

typedef ForumBodyFlowSliceBuilder =
    Widget Function(
      BuildContext context,
      ForumBodyTextPageSnapshot snapshot,
      int slice,
      List<ForumBodyPreparedTextFragment> fragments,
    );

typedef ForumBodyFlowVisibleSlice = ({
  int index,
  double top,
  List<ForumBodyPreparedTextFragment> fragments,
});

/// The currently mounted non-table slices and their clip in body coordinates.
/// The window borrows deliveries. Check [isCurrent] after each asynchronous
/// wait and before accepting a result from any of its fragments.
final class ForumBodyFlowTextWindow {
  const ForumBodyFlowTextWindow._(
    this.snapshot,
    this.bounds,
    this.slices,
    this._isCurrent,
  );

  final ForumBodyTextPageSnapshot snapshot;
  final Rect bounds;
  final List<ForumBodyFlowVisibleSlice> slices;
  final bool Function() _isCurrent;

  bool get isCurrent => _isCurrent();
}

/// Presents an append-only prefix from a native body session in a downward
/// scrolling document. The host drives and owns the source session. The sliver
/// reserves the measured prefix extent and materializes only intersecting
/// slices. Use compact-height native surfaces in [buildSlice].
final class ForumBodyFlowSliver extends _ForumBodyFlow {
  const ForumBodyFlowSliver({
    super.key,
    required super.session,
    required super.prefix,
    required super.buildSlice,
    required super.onFailure,
    super.isCurrentLayout,
    super.onReadyChanged,
    super.onTableWindowChanged,
    super.onFloatedTableWindowChanged,
    super.initialTableOffset,
  });

  /// Applies a measured offset to a table in the current sliver delivery.
  /// An offscreen table uses the same offset when its viewport mounts.
  static bool setTableOffset(
    GlobalKey key, {
    required ForumBodyTextPageSession session,
    required int slice,
    required String path,
    required double offset,
  }) {
    final state = key.currentState;
    if (state is! _ForumBodyFlowState || state.widget is! ForumBodyFlowSliver) {
      return false;
    }
    final flow = state.widget;
    if (!flow.isCurrentLayout ||
        !state._fits ||
        !identical(session, flow.session) ||
        session.isClosed ||
        session.isLayoutOwnerRetired ||
        !offset.isFinite ||
        offset < 0 ||
        slice < 0 ||
        slice >= flow.prefix.length ||
        !flow.prefix[slice].tableFrames.any((frame) => frame.path == path)) {
      return false;
    }
    state._setTableOffset((slice, path), offset);
    return true;
  }
}

/// The same flowing body as a lazy list child. Its measured extent belongs to
/// the outer list, and only physically visible slices acquire paint leases.
final class ForumBodyFlowBox extends _ForumBodyFlow {
  const ForumBodyFlowBox({
    super.key,
    required super.session,
    required super.prefix,
    required super.buildSlice,
    required super.onFailure,
    super.isCurrentLayout,
    super.onReadyChanged,
    super.onTableWindowChanged,
    super.onFloatedTableWindowChanged,
    super.initialTableOffset,
    this.imageAnchorController,
    this.imagePathForIndex,
    this.initialSlice,
    this.initialTableSlice,
  });

  final ForumHtmlImageAnchorController? imageAnchorController;
  final String? Function(int index)? imagePathForIndex;
  final ForumBodyFlowPreparedSlice? initialSlice;
  final ({int index, ForumBodyTablePreparedSlice slice})? initialTableSlice;

  /// Borrow the currently painted box, including a retained predecessor while
  /// a replacement is being prepared at the same width.
  static ForumBodyFlowTextWindow? borrowPaintedTextWindow(GlobalKey key) {
    final state = key.currentState;
    return state is _ForumBodyFlowState && state.widget is ForumBodyFlowBox
        ? state._borrowPaintedBox()
        : null;
  }
}

/// Transfers an already prepared non-table slice to its first flow view.
/// The caller closes it if publication is cancelled before the view takes it.
final class ForumBodyFlowPreparedSlice {
  ForumBodyFlowPreparedSlice({
    required this.session,
    required this.index,
    required List<ForumBodyPreparedTextFragment> fragments,
  }) : _fragments = List.unmodifiable(fragments);

  final ForumBodyTextPageSession session;
  final int index;
  List<ForumBodyPreparedTextFragment>? _fragments;

  List<ForumBodyPreparedTextFragment>? _take(_ForumBodyFlow flow) {
    final fragments = _fragments;
    if (fragments == null) return null;
    if (!identical(session, flow.session) ||
        index < 0 ||
        index >= flow.prefix.length ||
        flow.prefix[index].table != null ||
        !session.ownsPreparedFragments(fragments)) {
      throw StateError('Prepared flow slice belongs to a different layout');
    }
    validateForumBodyPreparedTextPageBinding(
      snapshot: flow.prefix,
      pageIndex: index,
      layoutId: flow.prefix.layoutId,
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

abstract class _ForumBodyFlow extends StatefulWidget {
  const _ForumBodyFlow({
    super.key,
    required this.session,
    required this.prefix,
    required this.buildSlice,
    required this.onFailure,
    this.isCurrentLayout = true,
    this.onReadyChanged,
    this.onTableWindowChanged,
    this.onFloatedTableWindowChanged,
    this.initialTableOffset,
  });

  final ForumBodyTextPageSession session;
  final ForumBodyTextPageSnapshot prefix;
  final ForumBodyFlowSliceBuilder buildSlice;
  final void Function(Object error, StackTrace stackTrace) onFailure;
  final bool isCurrentLayout;
  final ValueChanged<bool>? onReadyChanged;
  final void Function(int slice, ForumBodyTableVisibleWindow? window)?
  onTableWindowChanged;
  final void Function(
    int slice,
    ForumBodyTextPageTable frame,
    ForumBodyTableVisibleWindow? window,
  )?
  onFloatedTableWindowChanged;

  /// A one-time, measured horizontal offset for a table in this layout. Once
  /// mounted, the viewport's actual scrolling position takes precedence.
  final ({int slice, double offset})? initialTableOffset;

  @override
  State<StatefulWidget> createState() => _ForumBodyFlowState();
}

final class _ForumBodyFlowState extends State<_ForumBodyFlow> {
  final _ends = <double>[];
  final _ready = <int, _FlowDelivery>{};
  final _failed = <int>{};
  ({int start, int end}) _visible = (start: 0, end: 0);
  ({double start, double end}) _clip = (start: 0, end: 0);
  StreamSubscription<int>? _budget;
  StreamSubscription<void>? _retirement;
  ForumBodyTextPagePreparation? _preparation;
  int? _working;
  bool _waiting = false;
  bool _scheduled = false;
  bool _reportedReady = false;
  bool _fits = true;
  GlobalKey? _boxKey;
  ScrollPosition? _outerPosition;
  VoidCallback? _detachImageLocator;
  ({int slice, Object request})? _imageReveal;

  double get _extent => _ends.lastOrNull ?? 0;
  double _top(int index) => index == 0 ? 0 : _ends[index - 1];

  @override
  void initState() {
    super.initState();
    _updatePrefix();
    _adoptInitialSlice();
    _listen();
    _bindImageLocator();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget is! ForumBodyFlowBox) return;
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (identical(position, _outerPosition)) return;
    _outerPosition?.removeListener(_schedule);
    _outerPosition = position;
    position?.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _ForumBodyFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget is ForumBodyFlowBox &&
        (!identical(oldWidget.session, widget.session) ||
            (oldWidget as ForumBodyFlowBox).imageAnchorController !=
                (widget as ForumBodyFlowBox).imageAnchorController)) {
      _bindImageLocator();
    }
    if (!identical(oldWidget.session, widget.session)) {
      _unlisten();
      _clear();
      _ends.clear();
      _imageReveal = null;
      _visible = (start: 0, end: 0);
      _listen();
    } else if (oldWidget.prefix.isNotEmpty &&
        (widget.prefix.length < oldWidget.prefix.length ||
            !identical(
              widget.prefix[oldWidget.prefix.length - 1],
              oldWidget.prefix.last,
            ))) {
      throw StateError('Flowing body prefix changed');
    }
    _updatePrefix();
    if (!identical(oldWidget.session, widget.session)) _adoptInitialSlice();
    _schedule();
  }

  void _adoptInitialSlice() {
    final flow = widget;
    if (flow is! ForumBodyFlowBox) return;
    final seed = flow.initialSlice;
    final fragments = seed?._take(flow);
    if (fragments != null) {
      _ready[seed!.index] = _makeDelivery(seed.index, fragments);
    }
    final table = flow.initialTableSlice;
    if (table != null &&
        table.slice.isPending &&
        !_ready.containsKey(table.index) &&
        flow.prefix[table.index].fragments.isEmpty) {
      _ready[table.index] = _makeDelivery(table.index, const []);
    }
  }

  void _updatePrefix() {
    final prefix = widget.prefix;
    final session = widget.session;
    final current = session.snapshot;
    if (session.tableExtent != ForumBodyTableExtent.natural ||
        prefix.identity != current.identity ||
        prefix.layoutId != current.layoutId ||
        prefix.length > current.length ||
        (prefix.isNotEmpty &&
            !identical(prefix.last, current[prefix.length - 1]))) {
      throw StateError('Flowing body requires its native session prefix');
    }
    for (var index = _ends.length; index < prefix.length; index++) {
      _ends.add(_extent + prefix[index].usedHeight);
    }
  }

  void _listen() {
    _budget = widget.session.layoutBudgetChanges.listen((_) {
      if (_waiting || widget.session.isLayoutOwnerRetired) {
        _waiting = false;
        _schedule();
      }
    }, onDone: _schedule);
    _retirement = widget.session.retirement.listen((_) => _schedule());
  }

  void _unlisten() {
    unawaited(_budget?.cancel());
    unawaited(_retirement?.cancel());
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

  bool _intersects(int index) =>
      index >= _visible.start &&
      index < _visible.end &&
      _ends[index] > _top(index);

  void _advance() {
    final session = widget.session;
    if (session.isClosed || session.isLayoutOwnerRetired) {
      if (_ready.isNotEmpty) {
        setState(_clear);
      } else {
        _clear();
      }
      _reportReady(false);
      return;
    }
    if (widget is ForumBodyFlowBox) _updateBoxVisible();
    if (_working case final index? when !_intersects(index)) _stopWork();
    final target = _imageReveal?.slice;
    final targetPending =
        target != null &&
        _intersects(target) &&
        !_ready.containsKey(target) &&
        !_failed.contains(target);
    if (targetPending && _working != null && _working != target) _stopWork();
    final offscreen = _ready.keys
        .where((index) => !_intersects(index))
        .toList();
    if (offscreen.isNotEmpty) {
      setState(() {
        for (final index in offscreen) {
          final delivery = _ready.remove(index)!;
          delivery.close();
          for (final table in delivery.tables) {
            _reportTableWindow(index, table.frame, null);
          }
        }
      });
    }
    _failed.removeWhere((index) => !_intersects(index));
    int? missing;
    var ready = _visible.start < _visible.end;
    for (var index = _visible.start; index < _visible.end; index++) {
      if (!_intersects(index)) continue;
      final delivery = _ready[index];
      if (delivery == null) {
        ready = false;
        if (!_failed.contains(index)) missing ??= index;
      } else if (delivery.tables.any(
        (table) => !table.ready && _tableIntersects(index, table.frame),
      )) {
        ready = false;
      }
    }
    _reportReady(ready && _fits && widget.isCurrentLayout);
    final index = _working ?? (targetPending ? target : missing);
    if (!mounted || _waiting || index == null) return;
    _working = index;
    try {
      if (widget.prefix[index].table != null) {
        _deliver(index, _makeDelivery(index, const []));
      } else {
        final work = _preparation ??= session.openPagePreparation(index);
        final steps = index == target ? 6 : 1;
        final clock = steps > 1 ? (Stopwatch()..start()) : null;
        for (var step = 0; step < steps; step++) {
          final progress = work.advance(maxFragments: 1, maxParts: 8);
          _waiting = progress.waitingForLayoutBudget;
          if (progress.isReady) {
            _deliver(index, _makeDelivery(index, work.takeFragments()));
            break;
          }
          if (_waiting || (clock?.elapsedMicroseconds ?? 0) >= 2000) break;
        }
      }
    } catch (error, stackTrace) {
      _stopWork();
      _failed.add(index);
      if (!session.isClosed && !session.isLayoutOwnerRetired) {
        widget.onFailure(error, stackTrace);
      }
    }
    if (!_waiting) _schedule();
  }

  _FlowDelivery _makeDelivery(
    int index,
    List<ForumBodyPreparedTextFragment> fragments,
  ) {
    final page = widget.prefix[index];
    final delivery = _FlowDelivery(fragments);
    try {
      for (final frame in page.tableFrames) {
        delivery.tables.add(_tableDelivery(index, frame));
      }
      return delivery;
    } catch (_) {
      delivery.close();
      rethrow;
    }
  }

  _FlowTableDelivery _tableDelivery(int index, ForumBodyTextPageTable frame) {
    final initial = widget.initialTableOffset;
    final session = widget.session;
    final offset =
        session.flowTableOffset(index, frame.path) ??
        (initial?.slice == index &&
                widget.prefix[index].table?.path == frame.path
            ? initial!.offset
            : 0.0);
    if (!offset.isFinite || offset < 0) {
      throw ArgumentError.value(offset, 'initialTableOffset');
    }
    final table = session.acquireTablePage(index, path: frame.path)!;
    final controller = ScrollController(
      initialScrollOffset: offset,
      keepScrollOffset: false,
    );
    controller.addListener(() {
      if (table.isActive && controller.hasClients) {
        final position = controller.position;
        if (position.hasContentDimensions) {
          session.setFlowTableOffset(
            index,
            frame.path,
            position.pixels.clamp(0.0, position.maxScrollExtent),
          );
        }
      }
    });
    return _FlowTableDelivery(frame, table, controller);
  }

  bool _tableIntersects(int index, ForumBodyTextPageTable frame) {
    final top = _top(index);
    return frame.bounds.height > 0 &&
        top + frame.bounds.top < _clip.end &&
        top + frame.bounds.bottom > _clip.start;
  }

  void _reportTableWindow(
    int index,
    ForumBodyTextPageTable frame,
    ForumBodyTableVisibleWindow? window,
  ) {
    if (widget.prefix[index].table?.path == frame.path) {
      widget.onTableWindowChanged?.call(index, window);
    } else {
      widget.onFloatedTableWindowChanged?.call(index, frame, window);
    }
  }

  void _deliver(int index, _FlowDelivery delivery) {
    _stopWork();
    setState(() => _ready[index] = delivery);
  }

  void _reportReady(bool ready) {
    if (_reportedReady == ready) return;
    _reportedReady = ready;
    widget.onReadyChanged?.call(ready);
  }

  void _stopWork() {
    _preparation?.close();
    _preparation = null;
    _working = null;
    _waiting = false;
  }

  void _clear() {
    _stopWork();
    for (final delivery in _ready.values) {
      delivery.close();
    }
    _ready.clear();
    _failed.clear();
  }

  void _updateSliverVisible(SliverConstraints constraints) {
    if (constraints.axisDirection != AxisDirection.down ||
        constraints.growthDirection != GrowthDirection.forward) {
      throw StateError('Flowing body requires a downward viewport');
    }
    final start = constraints.scrollOffset;
    _updateVisible(
      constraints.crossAxisExtent,
      start,
      start + constraints.remainingPaintExtent,
    );
  }

  void _updateBoxVisible() {
    final box = _boxKey?.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      final clip = forumBodyVisibleBoxClip(box, _outerPosition) ?? Rect.zero;
      _updateVisible(box.size.width, clip.top, clip.bottom);
    } else {
      _updateVisible(0, 0, 0);
    }
  }

  void _updateVisible(double width, double start, double viewportEnd) {
    final fits = (width - widget.prefix.width).abs() <= precisionErrorTolerance;
    if (_fits != fits) {
      _fits = fits;
      _schedule();
    }
    final end = math.min(_extent, viewportEnd);
    final clip = (start: start, end: end);
    if (_clip != clip) {
      _clip = clip;
      if (_ready.values.any((delivery) => delivery.tables.isNotEmpty)) {
        _schedule();
      }
    }
    final next = start >= end
        ? (start: 0, end: 0)
        : (
            start: _firstEnd(start, strictlyAfter: true),
            end: _firstEnd(end, strictlyAfter: false) + 1,
          );
    if (_visible != next) {
      _visible = next;
      _schedule();
    }
  }

  int _firstEnd(double offset, {required bool strictlyAfter}) {
    var low = 0, high = _ends.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_ends[mid] < offset || (strictlyAfter && _ends[mid] == offset)) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  @override
  Widget build(BuildContext context) {
    if (widget is ForumBodyFlowBox) {
      _schedule();
      return ForumBodyCompositionObserver(
        key: _boxKey ??= GlobalKey(),
        onComposited: _updateBoxVisible,
        child: _buildBody(context),
      );
    }
    return _FlowExtentBoundary(
      width: widget.prefix.width,
      complete: widget.prefix.isComplete && widget.isCurrentLayout,
      borrowTextWindow: _borrowTextWindow,
      child: SliverLayoutBuilder(
        builder: (context, constraints) {
          _updateSliverVisible(constraints);
          return SliverToBoxAdapter(child: _buildBody(context));
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) => SizedBox(
    height: _extent,
    child: ClipRect(
      // A resize can temporarily retain an older measured prefix.
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: widget.prefix.width,
        maxWidth: widget.prefix.width,
        child: Stack(
          children: [
            for (final entry in _ready.entries)
              Positioned(
                key: entry.value.mountKey,
                top: _top(entry.key),
                left: 0,
                right: 0,
                height: widget.prefix[entry.key].usedHeight,
                child: _slice(context, entry.key, entry.value),
              ),
          ],
        ),
      ),
    ),
  );

  ForumBodyFlowTextWindow? _borrowPaintedBox() {
    final box = _boxKey?.currentContext?.findRenderObject();
    final position = _outerPosition;
    if (box is! RenderBox || position == null) return null;
    final clip = forumBodyVisibleBoxClip(box, position);
    if (clip == null || clip.isEmpty) return null;
    return _borrowTextWindow(
      clip,
      () =>
          identical(position, _outerPosition) &&
          forumBodyVisibleBoxClip(box, position) == clip,
      allowRetained: true,
    );
  }

  ForumBodyFlowTextWindow? _borrowTextWindow(
    Rect bounds,
    bool Function() stillLaidOut, {
    bool allowRetained = false,
  }) {
    final session = widget.session;
    if (!_fits ||
        (!widget.isCurrentLayout && !allowRetained) ||
        session.isClosed ||
        session.isLayoutOwnerRetired) {
      return null;
    }
    final prefix = widget.prefix;
    final slices = <ForumBodyFlowVisibleSlice>[];
    final deliveries = <int, _FlowDelivery>{};
    for (var index = _visible.start; index < _visible.end; index++) {
      final delivery = _ready[index];
      if (delivery == null ||
          delivery.fragments.isEmpty ||
          !delivery.isMounted) {
        continue;
      }
      final top = _top(index);
      if (top >= bounds.bottom || _ends[index] <= bounds.top) continue;
      deliveries[index] = delivery;
      slices.add((index: index, top: top, fragments: delivery.fragments));
    }
    if (slices.isEmpty) return null;
    return ForumBodyFlowTextWindow._(
      prefix,
      bounds,
      List.unmodifiable(slices),
      () =>
          mounted &&
          (widget.isCurrentLayout || allowRetained) &&
          identical(widget.session, session) &&
          !session.isClosed &&
          !session.isLayoutOwnerRetired &&
          stillLaidOut() &&
          deliveries.entries.every(
            (entry) =>
                identical(_ready[entry.key], entry.value) &&
                entry.value.isMounted,
          ),
    );
  }

  Widget _slice(BuildContext context, int index, _FlowDelivery delivery) {
    final prefix = widget.prefix;
    final surface = widget.buildSlice(
      context,
      prefix,
      index,
      delivery.fragments,
    );
    if (delivery.tables.isEmpty) return surface;
    return Stack(
      fit: StackFit.expand,
      children: [
        surface,
        for (final table in delivery.tables) _tableView(index, delivery, table),
      ],
    );
  }

  Widget _tableView(
    int index,
    _FlowDelivery delivery,
    _FlowTableDelivery table,
  ) {
    final flow = widget;
    final initial = flow is ForumBodyFlowBox ? flow.initialTableSlice : null;
    final frame = table.frame;
    final dedicated = widget.prefix[index].table?.path == frame.path;
    final layout = table.lease.layout;
    final seed = initial?.index == index && initial!.slice.isPending
        ? initial.slice
        : null;
    final reportsWindow = dedicated
        ? widget.onTableWindowChanged != null
        : widget.onFloatedTableWindowChanged != null;
    return Positioned.fromRect(
      key: ValueKey(frame.path),
      rect: frame.bounds,
      child: ForumBodyTableFlowViewport(
        layout: layout,
        horizontalController: table.horizontal,
        initialSlice:
            seed != null &&
                (layout.cells.contains(seed.area) ||
                    layout.captions.contains(seed.area))
            ? seed
            : null,
        onFailure: (error, stack) {
          if (identical(_ready[index], delivery)) {
            widget.onFailure(error, stack);
          }
        },
        onReadyChanged: (ready) {
          if (!identical(_ready[index], delivery)) return;
          table.ready = ready;
          _schedule();
        },
        onWindowChanged: !reportsWindow
            ? null
            : (window) {
                if (_fits && identical(_ready[index], delivery)) {
                  _reportTableWindow(index, frame, window);
                }
              },
        buildSlice: (context, area, page, fragments) =>
            widget.buildSlice(context, area.snapshot, page, fragments),
      ),
    );
  }

  @override
  void dispose() {
    _detachImageLocator?.call();
    _outerPosition?.removeListener(_schedule);
    _unlisten();
    _clear();
    super.dispose();
  }
}

final class _FlowExtentBoundary extends SingleChildRenderObjectWidget {
  const _FlowExtentBoundary({
    required this.width,
    required this.complete,
    required this.borrowTextWindow,
    required super.child,
  });

  final double width;
  final bool complete;
  final _BorrowTextWindow borrowTextWindow;

  @override
  RenderForumBodyFlowBoundary createRenderObject(BuildContext context) =>
      RenderForumBodyFlowBoundary._(width, complete, borrowTextWindow);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderForumBodyFlowBoundary renderObject,
  ) => renderObject._update(width, complete, borrowTextWindow);
}

typedef _BorrowTextWindow =
    ForumBodyFlowTextWindow? Function(Rect bounds, bool Function() isCurrent);

/// Exposes the terminal extent laid out by [ForumBodyFlowSliver]. An append-only
/// prefix has an exact extent of its own but is not necessarily the whole body.
final class RenderForumBodyFlowBoundary extends RenderProxySliver {
  RenderForumBodyFlowBoundary._(
    this._width,
    this._complete,
    this._borrowTextWindow,
  );

  double _width;
  bool _complete;
  _BorrowTextWindow _borrowTextWindow;
  bool _finalBoundaryKnown = false;

  bool get finalBoundaryKnown => _finalBoundaryKnown;

  /// Borrow the visible mounted deliveries after layout.
  ForumBodyFlowTextWindow? borrowTextWindow() {
    final laidOut = geometry;
    if (!attached || laidOut == null || laidOut.paintExtent <= 0) return null;
    final viewport = constraints;
    if ((viewport.crossAxisExtent - _width).abs() > precisionErrorTolerance) {
      return null;
    }
    return _borrowTextWindow(
      Rect.fromLTWH(0, viewport.scrollOffset, _width, laidOut.paintExtent),
      () =>
          attached &&
          constraints == viewport &&
          geometry?.paintExtent == laidOut.paintExtent,
    );
  }

  void _update(
    double width,
    bool complete,
    _BorrowTextWindow borrowTextWindow,
  ) {
    _borrowTextWindow = borrowTextWindow;
    if (_width == width && _complete == complete) return;
    _width = width;
    _complete = complete;
    _finalBoundaryKnown = false;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    _finalBoundaryKnown =
        _complete &&
        (constraints.crossAxisExtent - _width).abs() <=
            precisionErrorTolerance &&
        geometry?.scrollExtent.isFinite == true;
  }
}

final class _FlowDelivery {
  _FlowDelivery(this.fragments);
  final List<ForumBodyPreparedTextFragment> fragments;
  final tables = <_FlowTableDelivery>[];
  final mountKey = GlobalKey();

  bool get isMounted {
    final render = mountKey.currentContext?.findRenderObject();
    return render is RenderBox &&
        render.attached &&
        render.hasSize &&
        fragments.every((fragment) => fragment.isActive);
  }

  void close() {
    for (final table in tables) {
      table.horizontal.dispose();
      table.lease.close();
    }
    for (final fragment in fragments) {
      fragment.close();
    }
  }
}

final class _FlowTableDelivery {
  _FlowTableDelivery(this.frame, this.lease, this.horizontal);
  final ForumBodyTextPageTable frame;
  final ForumBodyTablePageLease lease;
  final ScrollController horizontal;
  bool ready = false;
}
