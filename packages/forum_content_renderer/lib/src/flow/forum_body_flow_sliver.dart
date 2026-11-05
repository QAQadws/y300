import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart'
    show GrowthDirection, RenderBox, RenderProxySliver, SliverConstraints;
import 'package:flutter/widgets.dart';

import '../pagination/forum_body_prepared_text_fragment.dart';
import '../pagination/forum_body_text_page_composer.dart';
import '../pagination/forum_body_text_page_preparation.dart';
import '../pagination/forum_body_text_page_session.dart';
import '../services/forum_body_scroll_geometry.dart';
import '../table/forum_body_table_viewport.dart';

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
    super.initialTableOffset,
  });
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
  });
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

  /// A one-time, measured horizontal offset for a table in this layout. Once
  /// mounted, the viewport's actual scrolling position takes precedence.
  final ({int slice, double offset})? initialTableOffset;

  @override
  State<StatefulWidget> createState() => _ForumBodyFlowState();
}

final class _ForumBodyFlowState extends State<_ForumBodyFlow> {
  final _ends = <double>[];
  final _ready = <int, _FlowDelivery>{};
  final _readyTables = <int>{};
  final _failed = <int>{};
  final _tableOffsets = <int, double>{};
  ({int start, int end}) _visible = (start: 0, end: 0);
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

  double get _extent => _ends.lastOrNull ?? 0;
  double _top(int index) => index == 0 ? 0 : _ends[index - 1];

  @override
  void initState() {
    super.initState();
    _updatePrefix();
    _listen();
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
    if (!identical(oldWidget.session, widget.session)) {
      _unlisten();
      _clear();
      _ends.clear();
      _tableOffsets.clear();
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
    _schedule();
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
    final offscreen = _ready.keys
        .where((index) => !_intersects(index))
        .toList();
    if (offscreen.isNotEmpty) {
      setState(() {
        for (final index in offscreen) {
          final delivery = _ready.remove(index)!;
          delivery.close();
          _readyTables.remove(index);
          if (delivery.table != null) {
            widget.onTableWindowChanged?.call(index, null);
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
      } else if (delivery.table != null && !_readyTables.contains(index)) {
        ready = false;
      }
    }
    _reportReady(ready && _fits && widget.isCurrentLayout);
    final index = _working ?? missing;
    if (!mounted || _waiting || index == null) return;
    _working = index;
    try {
      if (widget.prefix[index].table != null) {
        final initial = widget.initialTableOffset;
        final offset =
            _tableOffsets[index] ??
            (initial?.slice == index ? initial!.offset : 0.0);
        if (!offset.isFinite || offset < 0) {
          throw ArgumentError.value(offset, 'initialTableOffset');
        }
        final table = session.acquireTablePage(index)!;
        final controller = ScrollController(
          initialScrollOffset: offset,
          keepScrollOffset: false,
        );
        controller.addListener(() {
          if (controller.hasClients) _tableOffsets[index] = controller.offset;
        });
        _deliver(index, _FlowDelivery(const [], table, controller));
      } else {
        final work = _preparation ??= session.openPagePreparation(index);
        final step = work.advance(maxFragments: 1, maxParts: 8);
        _waiting = step.waitingForLayoutBudget;
        if (step.isReady) {
          _deliver(index, _FlowDelivery(work.takeFragments()));
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
    _readyTables.clear();
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

  ForumBodyFlowTextWindow? _borrowTextWindow(
    Rect bounds,
    bool Function() stillLaidOut,
  ) {
    final session = widget.session;
    if (!_fits ||
        !widget.isCurrentLayout ||
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
          delivery.table != null ||
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
          widget.isCurrentLayout &&
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
    final lease = delivery.table;
    if (lease == null) return surface;
    return Stack(
      fit: StackFit.expand,
      children: [
        surface,
        Positioned.fromRect(
          rect: prefix[index].table!.bounds,
          child: ForumBodyTableFlowViewport(
            layout: lease.layout,
            horizontalController: delivery.horizontal!,
            onFailure: (error, stack) {
              if (identical(_ready[index], delivery)) {
                widget.onFailure(error, stack);
              }
            },
            onReadyChanged: (ready) {
              if (!identical(_ready[index], delivery)) return;
              if (ready) {
                _readyTables.add(index);
              } else {
                _readyTables.remove(index);
              }
              _schedule();
            },
            onWindowChanged: widget.onTableWindowChanged == null
                ? null
                : (window) {
                    if (_fits && identical(_ready[index], delivery)) {
                      widget.onTableWindowChanged?.call(index, window);
                    }
                  },
            buildSlice: (context, area, page, fragments) =>
                widget.buildSlice(context, area.snapshot, page, fragments),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
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
  _FlowDelivery(this.fragments, [this.table, this.horizontal]);
  final List<ForumBodyPreparedTextFragment> fragments;
  final ForumBodyTablePageLease? table;
  final ScrollController? horizontal;
  final mountKey = GlobalKey();

  bool get isMounted {
    final render = mountKey.currentContext?.findRenderObject();
    return render is RenderBox &&
        render.attached &&
        render.hasSize &&
        fragments.every((fragment) => fragment.isActive);
  }

  void close() {
    horizontal?.dispose();
    table?.close();
    for (final fragment in fragments) {
      fragment.close();
    }
  }
}
