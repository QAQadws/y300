import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart' show GrowthDirection, SliverConstraints;
import 'package:flutter/widgets.dart';

import '../pagination/forum_body_prepared_text_fragment.dart';
import '../pagination/forum_body_text_page_composer.dart';
import '../pagination/forum_body_text_page_preparation.dart';
import '../pagination/forum_body_text_page_session.dart';
import '../table/forum_body_table_viewport.dart';

typedef ForumBodyFlowSliceBuilder =
    Widget Function(
      BuildContext context,
      ForumBodyTextPageSnapshot snapshot,
      int slice,
      List<ForumBodyPreparedTextFragment> fragments,
    );

/// Presents an append-only prefix from a native body session in a downward
/// scrolling document. The host drives and owns the source session. The sliver
/// reserves the measured prefix extent and materializes only intersecting
/// slices. Use compact-height native surfaces in [buildSlice].
final class ForumBodyFlowSliver extends StatefulWidget {
  const ForumBodyFlowSliver({
    super.key,
    required this.session,
    required this.prefix,
    required this.buildSlice,
    required this.onFailure,
    this.onReadyChanged,
    this.onTableWindowChanged,
  });

  final ForumBodyTextPageSession session;
  final ForumBodyTextPageSnapshot prefix;
  final ForumBodyFlowSliceBuilder buildSlice;
  final void Function(Object error, StackTrace stackTrace) onFailure;
  final ValueChanged<bool>? onReadyChanged;
  final void Function(int slice, ForumBodyTableVisibleWindow? window)?
  onTableWindowChanged;

  @override
  State<ForumBodyFlowSliver> createState() => _ForumBodyFlowSliverState();
}

final class _ForumBodyFlowSliverState extends State<ForumBodyFlowSliver> {
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

  double get _extent => _ends.lastOrNull ?? 0;
  double _top(int index) => index == 0 ? 0 : _ends[index - 1];

  @override
  void initState() {
    super.initState();
    _updatePrefix();
    _listen();
  }

  @override
  void didUpdateWidget(covariant ForumBodyFlowSliver oldWidget) {
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
    if (_working case final index? when !_intersects(index)) _stopWork();
    final offscreen = _ready.keys
        .where((index) => !_intersects(index))
        .toList();
    if (offscreen.isNotEmpty) {
      setState(() {
        for (final index in offscreen) {
          _ready.remove(index)!.close();
          _readyTables.remove(index);
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
    _reportReady(ready && _fits);
    final index = _working ?? missing;
    if (!mounted || _waiting || index == null) return;
    _working = index;
    try {
      if (widget.prefix[index].table != null) {
        final table = session.acquireTablePage(index)!;
        final controller = ScrollController(
          initialScrollOffset: _tableOffsets[index] ?? 0,
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

  void _updateVisible(SliverConstraints constraints) {
    if (constraints.axisDirection != AxisDirection.down ||
        constraints.growthDirection != GrowthDirection.forward) {
      throw StateError('Flowing body requires a downward viewport');
    }
    final fits =
        (constraints.crossAxisExtent - widget.prefix.width).abs() <=
        precisionErrorTolerance;
    if (_fits != fits) {
      _fits = fits;
      _schedule();
    }
    final start = constraints.scrollOffset;
    final end = math.min(_extent, start + constraints.remainingPaintExtent);
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
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      _updateVisible(constraints);
      final body = Stack(
        children: [
          for (final entry in _ready.entries)
            Positioned(
              key: ObjectKey(entry.value),
              top: _top(entry.key),
              left: 0,
              right: 0,
              height: widget.prefix[entry.key].usedHeight,
              child: _slice(context, entry.key, entry.value),
            ),
        ],
      );
      return SliverToBoxAdapter(
        child: SizedBox(
          height: _extent,
          child: ClipRect(
            // A resize can temporarily retain an older measured prefix.
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: widget.prefix.width,
              maxWidth: widget.prefix.width,
              child: body,
            ),
          ),
        ),
      );
    },
  );

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
    _unlisten();
    _clear();
    super.dispose();
  }
}

final class _FlowDelivery {
  const _FlowDelivery(this.fragments, [this.table, this.horizontal]);
  final List<ForumBodyPreparedTextFragment> fragments;
  final ForumBodyTablePageLease? table;
  final ScrollController? horizontal;

  void close() {
    horizontal?.dispose();
    table?.close();
    for (final fragment in fragments) {
      fragment.close();
    }
  }
}
