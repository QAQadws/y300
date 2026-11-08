import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'forum_native_body_flow_input.dart';

/// Active navigation work, not an LRU: only one request owns these sources and
/// display leases. Completed reusable values remain in the page's normal cache.
final class ForumNativeBodyFlowPreloads extends ChangeNotifier {
  final _bound =
      <Object, ({Object owner, ForumNativeBodyPreparedSource body})>{};
  final _demands = <Object, _FlowDemand>{};
  Object? _ticket;
  bool _closed = false;

  void begin(Object ticket) {
    cancel();
    if (!_closed) _ticket = ticket;
  }

  bool isCurrent(Object ticket) => !_closed && identical(_ticket, ticket);

  void cancel([Object? ticket]) {
    if (ticket != null && !identical(ticket, _ticket)) return;
    _ticket = null;
    for (final demand in _demands.values.toList()) {
      demand.close();
    }
    _demands.clear();
  }

  ForumNativeBodyPreparedSource? peek(Object identity) {
    final demand = _demands[identity];
    final body = demand?.isCurrent() == true
        ? demand?.body
        : _bound[identity]?.body;
    return body != null && !body.source.isClosed && !body.source.isStopped
        ? body
        : null;
  }

  void bind(Object owner, ForumNativeBodyPreparedSource body) {
    if (_closed) return;
    final identity = body.input.preparationIdentity;
    if (identity != null) _bound[identity] = (owner: owner, body: body);
  }

  bool release(Object owner, ForumNativeBodyPreparedSource body) {
    final identity = body.input.preparationIdentity;
    if (identical(_bound[identity]?.owner, owner)) _bound.remove(identity);
    final demand = _demands[identity];
    // Extent correction may recycle a just-built target before first paint.
    return demand != null &&
        !demand.borrowed &&
        demand.isCurrent() &&
        identical(demand.body, body);
  }

  /// Transfers an active source and independent view handles only after the
  /// exact resolved layout matches. A borrowed mounted source stays mounted.
  ({
    ForumNativeBodyPreparedSource body,
    List<ForumBodyFlowPreparedSlice> slices,
  })?
  take(ForumNativeBodyFlowInput input, {ForumBodyFlowSource? mountedSource}) {
    final demand = _demands[input.preparationIdentity];
    if (demand == null ||
        !demand.isCurrent() ||
        !demand.ready ||
        !demand.body!.input.matches(input)) {
      return null;
    }
    if (demand.borrowed && !identical(demand.body!.source, mountedSource)) {
      return null;
    }
    if (!demand.borrowed &&
        mountedSource != null &&
        !identical(demand.body!.source, mountedSource)) {
      return null;
    }
    final slices = demand.slices;
    if (slices.isEmpty && (!demand.transferred || mountedSource != null)) {
      return null;
    }
    demand.slices = [];
    demand.transferred = true;
    return (body: demand.body!, slices: slices);
  }

  Future<bool> prepare({
    required Object ticket,
    required ForumNativeBodyFlowInput input,
    required bool bottom,
    required double extent,
  }) async {
    if (!isCurrent(ticket) || input.preparationIdentity == null) return false;
    final identity = input.preparationIdentity!;
    _demands.remove(identity)?.close();
    final bound = _bound[identity]?.body;
    final borrowed = bound != null && bound.input.matches(input);
    final demand = _FlowDemand(
      current: () => isCurrent(ticket),
      isBound: (body) => identical(_bound[identity]?.body, body),
      borrowed: borrowed,
      body: borrowed ? bound : null,
    );
    _demands[identity] = demand;
    try {
      if (!borrowed) {
        final opening = input.open(isCurrent: demand.isCurrent);
        final body = opening is ForumNativeBodyPreparedSource
            ? opening
            : await opening;
        if (!demand.isCurrent()) {
          body.close();
          return false;
        }
        demand.body = body;
      }
      final source = demand.body!.source;
      source.start();
      await demand.waitForPrefix(bottom: bottom, extent: extent);
      if (!borrowed) source.suspend();
      await demand.prepareWindow(bottom: bottom, extent: extent);
      demand.guard();
      demand.ready = true;
      notifyListeners();
      return true;
    } catch (_) {
      demand.close();
      if (identical(_demands[identity], demand)) _demands.remove(identity);
      return false;
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    cancel();
    _bound.clear();
    super.dispose();
  }
}

final class ForumNativeBodyFlowPreloadScope
    extends InheritedNotifier<ForumNativeBodyFlowPreloads> {
  const ForumNativeBodyFlowPreloadScope({
    super.key,
    required ForumNativeBodyFlowPreloads controller,
    required super.child,
  }) : super(notifier: controller);

  static ForumNativeBodyFlowPreloads? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ForumNativeBodyFlowPreloadScope>()
      ?.notifier;
}

final class _FlowDemand {
  _FlowDemand({
    required this.current,
    required this.isBound,
    required this.borrowed,
    this.body,
  });
  final bool Function() current;
  final bool Function(ForumNativeBodyPreparedSource body) isBound;
  final bool borrowed;
  ForumNativeBodyPreparedSource? body;
  bool _closed = false, transferred = false, ready = false;
  Completer<void>? _prefixWait;
  VoidCallback? _prefixListener;
  final _jobs = <ForumBodyTextPagePreparation>{};
  final _held = <ForumBodyPreparedTextFragment>[];
  List<ForumBodyFlowPreparedSlice> slices = [];

  bool isCurrent() =>
      !_closed &&
      current() &&
      body?.source.isClosed != true &&
      body?.source.isStopped != true &&
      body?.input.cache.isClosed != true &&
      body?.input.presentation?.isActive != false;
  void guard() {
    if (!isCurrent()) throw const ForumBodyFlowPreparationCancelled();
  }

  Future<void> waitForPrefix({required bool bottom, required double extent}) {
    final source = body!.source;
    final done = _prefixWait = Completer<void>();
    var measured = 0;
    var height = 0.0;
    void check() {
      if (done.isCompleted) return;
      final error = source.error;
      if (!isCurrent() || error != null) {
        done.completeError(error ?? const ForumBodyFlowPreparationCancelled());
      } else {
        final prefix = source.prefix;
        if (prefix == null) return;
        while (measured < prefix.length) {
          height += prefix[measured++].usedHeight;
        }
        if (prefix.isComplete || (!bottom && height >= extent)) done.complete();
      }
    }

    _prefixListener = check;
    source.addListener(check);
    check();
    return done.future.whenComplete(() {
      source.removeListener(check);
      if (identical(_prefixListener, check)) _prefixListener = null;
    });
  }

  Future<List<ForumBodyPreparedTextFragment>> _prepare(
    ForumBodyTextPagePreparation job,
  ) async {
    _jobs.add(job);
    try {
      guard();
      final result = await body!.source.prepare(job);
      if (!isCurrent()) {
        for (final fragment in result) {
          fragment.close();
        }
        guard();
      }
      return result;
    } finally {
      _jobs.remove(job);
      job.close();
    }
  }

  Future<List<ForumBodyPreparedTextFragment>> _pair(
    ForumBodyTextPagePreparation Function() open,
  ) async {
    // Pin the warmed pictures through navigation. A visible range moving past
    // an injected copy can release it without evicting the target's glyphs.
    _held.addAll(await _prepare(open()));
    return _prepare(open());
  }

  Future<void> prepareWindow({
    required bool bottom,
    required double extent,
  }) async {
    guard();
    final source = body!.source, session = body!.source.session!;
    final prefix = source.prefix!;
    final height = prefix.fold<double>(0, (sum, page) => sum + page.usedHeight);
    final window = Rect.fromLTWH(
      0,
      bottom ? math.max(0, height - extent) : 0,
      prefix.width,
      math.min(extent, height),
    );
    var top = 0.0;
    for (var index = 0; index < prefix.length; index++) {
      final page = prefix[index];
      final bounds = Rect.fromLTWH(0, top, prefix.width, page.usedHeight);
      top += page.usedHeight;
      if (!bounds.overlaps(window)) continue;
      final fragments = await _pair(() => session.openPagePreparation(index));
      final tables = <ForumBodyTablePreparedSlice>[];
      var accepted = false;
      try {
        for (final frame in page.tableFrames) {
          final clip = window
              .shift(Offset(0, -bounds.top))
              .intersect(frame.bounds);
          if (clip.isEmpty) continue;
          final layout = session.tableLayoutForPage(index, path: frame.path)!;
          final offset = session.flowTableOffset(index, frame.path) ?? 0;
          await _table(
            layout,
            clip.shift(-frame.bounds.topLeft + Offset(offset, 0)),
            tables,
          );
        }
        guard();
        slices.add(
          ForumBodyFlowPreparedSlice(
            session: session,
            index: index,
            fragments: fragments,
            tableSlices: tables,
          ),
        );
        accepted = true;
      } finally {
        if (!accepted) {
          for (final fragment in fragments) {
            fragment.close();
          }
          for (final slice in tables) {
            slice.close();
          }
        }
      }
    }
  }

  Future<void> _table(
    ForumBodyTableLayout layout,
    Rect bounds,
    List<ForumBodyTablePreparedSlice> result,
  ) async {
    for (final slice in layout.slicesIn(bounds)) {
      guard();
      final fragments = await _pair(
        () => slice.area.openPagePreparation(slice.page),
      );
      result.add(
        ForumBodyTablePreparedSlice(
          area: slice.area,
          page: slice.page,
          fragments: fragments,
        ),
      );
      final origin =
          slice.area.contentBounds.topLeft +
          Offset(0, slice.area.pageTop(slice.page));
      for (final frame in slice.area.snapshot[slice.page].tableFrames) {
        final clip = bounds.shift(-origin).intersect(frame.bounds);
        if (clip.isEmpty) continue;
        final nested = slice.area.tableLayoutForPage(
          slice.page,
          path: frame.path,
        )!;
        final offset = slice.area.flowTableOffset(slice.page, frame.path) ?? 0;
        await _table(
          nested,
          clip.shift(-frame.bounds.topLeft + Offset(offset, 0)),
          result,
        );
      }
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final source = body?.source;
    final listener = _prefixListener;
    if (listener != null) source?.removeListener(listener);
    final waiting = _prefixWait;
    if (waiting != null && !waiting.isCompleted) {
      waiting.completeError(const ForumBodyFlowPreparationCancelled());
    }
    for (final job in _jobs.toList()) {
      source?.cancelPreparation(job);
    }
    for (final slice in slices) {
      slice.close();
    }
    slices = [];
    for (final fragment in _held) {
      fragment.close();
    }
    _held.clear();
    if (!borrowed && body != null && !isBound(body!)) source?.close();
  }
}
