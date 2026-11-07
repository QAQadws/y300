part of 'forum_body_inline_font_frame_plan.dart';

enum _FramePhase {
  parent,
  isolation,
  allocation,
  paint,
  rows,
  ready,
  transferred,
  closed,
}

/// Joins the existing natural, isolated, allocated and paint-reference workers.
/// The owner/cache and one caller work budget govern the whole transaction.
/// Numeric preparation never warms paint, records a picture or prepares children.
final class ForumBodyInlineFontFramePreparation {
  ForumBodyInlineFontFramePreparation({
    required ForumBodyInlinePlanInput input,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _cache = cache,
       _ensureOwner = ensureOwner,
       _additionalOwned = additionalOwnedLeases {
    try {
      _guard();
      if (input.layoutMode != ForumBodyParagraphLayoutMode.wrap) {
        throw ArgumentError('Font-frame planning requires wrapping text');
      }
      _parentWork = ForumBodyInlineEmphasisParentPreparation(
        input: input,
        cache: cache,
        textScaler: textScaler,
        ensureOwner: _guard,
        additionalOwnedLeases: _callerOwned,
      );
    } catch (_) {
      close();
      rethrow;
    }
  }

  /// Uses the same bounded source preparation as normal mixed text. The raw
  /// input constructor lets an existing admission retain its prepared source.
  ForumBodyInlineFontFramePreparation.fromFlow({
    required ForumBodyInlineFlowContent input,
    required double width,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _cache = cache,
       _ensureOwner = ensureOwner,
       _additionalOwned = additionalOwnedLeases {
    try {
      _guard();
      if (input.layoutMode != ForumBodyParagraphLayoutMode.wrap) {
        throw ArgumentError('Font-frame planning requires wrapping text');
      }
      _parentWork = ForumBodyInlineEmphasisParentPreparation.fromFlow(
        input: input,
        width: width,
        cache: cache,
        textScaler: textScaler,
        ensureOwner: _guard,
        additionalOwnedLeases: _callerOwned,
      );
    } catch (_) {
      close();
      rethrow;
    }
  }
  ForumBodyInlinePlanInput? _input;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyInlineEmphasisParentPreparation? _parentWork;
  ForumBodyInlineEmphasisIsolationPreparation? _isolationWork;
  ForumBodyInlineEmphasisRowAllocationPreparation? _allocationWork;
  ForumBodyInlineEmphasisPaintPreparation? _paintWork;
  ForumBodyInlineEmphasisParentMetrics? _parentMetrics;
  ForumBodyInlineEmphasisRowAllocation? _allocation;
  ForumBodyInlineParagraphLease? _natural, _isolated;
  ForumBodyInlineEmphasisPaintBinding? _paint;
  List<ForumBodyParagraphLine> _lines = [];
  List<List<ForumBodyTextPictureCommand>> _commands = [];
  List<int> _commandPrefix = [0];
  ForumBodyInlineFontFramePlan? _result;
  int _row = 0;
  bool _operating = false, _cacheMiss = false;
  var _phase = _FramePhase.parent;
  bool get isReady => _phase == _FramePhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    if (_natural != null) yield _natural!;
    if (_isolated != null) yield _isolated!;
    if (_parentWork != null) yield* _parentWork!.nativeLeases;
    if (_isolationWork != null) yield* _isolationWork!.nativeLeases;
    if (_paintWork != null) yield* _paintWork!.nativeLeases;
    if (_paint != null) yield* _paint!.nativeLeases;
  }

  Iterable<ForumBodyNativeParagraphLease> _callerOwned() {
    final values =
        _additionalOwned?.call() ?? const <ForumBodyNativeParagraphLease>[];
    _guard();
    return values;
  }

  Iterable<ForumBodyNativeParagraphLease> _paintPrefix() sync* {
    yield* _callerOwned();
    yield _natural!; // The isolated source is already owned by the paint worker.
  }

  ({int partsPrepared, bool waitingForLayoutBudget, bool isReady}) advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Font-frame planning is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      if (isReady) throw StateError('Font-frame plan is already ready');
      _cacheMiss = false;
      final cache = _cache!, builds = cache.layoutBuildCount;
      while (!isReady && used < maxParts && cache.layoutBuildCount == builds) {
        switch (_phase) {
          case _FramePhase.parent:
            final work = _parentWork!;
            final step = work.advance(
              maxParts: maxParts - used,
              cachedOnly: cachedOnly,
            );
            used += step.partsPrepared;
            _cacheMiss = work.cacheMiss;
            if (step.waitingForLayoutBudget || work.cacheMiss) {
              return (
                partsPrepared: used,
                waitingForLayoutBudget: step.waitingForLayoutBudget,
                isReady: false,
              );
            }
            if (!work.isReady) break;
            final ready = work.takeMeasurement();
            _parentWork = null;
            _input = ready.source;
            _parentMetrics = ready.metrics;
            _natural = ready.parent;
            _isolationWork = ForumBodyInlineEmphasisIsolationPreparation(
              metrics: ready.metrics,
              natural: ready.parent,
              cache: cache,
              ensureOwner: _guard,
              additionalOwnedLeases: _callerOwned,
            );
            _phase = _FramePhase.isolation;
          case _FramePhase.isolation:
            final work = _isolationWork!;
            final step = work.advance(
              maxParts: maxParts - used,
              cachedOnly: cachedOnly,
            );
            used += step.partsPrepared;
            _cacheMiss = work.cacheMiss;
            if (step.waitingForLayoutBudget || work.cacheMiss) {
              return (
                partsPrepared: used,
                waitingForLayoutBudget: step.waitingForLayoutBudget,
                isReady: false,
              );
            }
            if (!work.isReady) break;
            final ready = work.takeMeasurement();
            _isolationWork = null;
            _isolated = ready.parent;
            _allocationWork = ForumBodyInlineEmphasisRowAllocationPreparation(
              input: ready.metrics,
              natural: _natural!,
              isolated: ready.parent,
              ensureOwner: _guard,
            );
            _phase = _FramePhase.allocation;
          case _FramePhase.allocation:
            used += _allocationWork!.advance(maxParts: maxParts - used);
            if (!_allocationWork!.isReady) break;
            final allocation = _allocation = _allocationWork!.takeAllocation();
            _allocationWork = null;
            _paintWork = ForumBodyInlineEmphasisPaintPreparation(
              allocation: allocation,
              source: _isolated!,
              cache: cache,
              expectedTextScaler: _parentMetrics!.textScaler,
              ensureOwner: _guard,
              ensureVisibleOwner: _ensureOwner!,
              additionalOwnedLeases: _paintPrefix,
              preparePaint: false,
            );
            _phase = _FramePhase.paint;
          case _FramePhase.paint:
            final work = _paintWork!;
            final step = work.advance(
              maxParts: maxParts - used,
              cachedOnly: cachedOnly,
            );
            used += step.partsPrepared;
            _cacheMiss = work.cacheMiss;
            if (step.waitingForLayoutBudget || work.cacheMiss) {
              return (
                partsPrepared: used,
                waitingForLayoutBudget: step.waitingForLayoutBudget,
                isReady: false,
              );
            }
            if (!work.isReady) break;
            _paint = work.takeBinding();
            _paintWork = null;
            _phase = _FramePhase.rows;
          case _FramePhase.rows:
            if (_row < _allocation!.rows.length) {
              final commands = <ForumBodyTextPictureCommand>[];
              const layers = [
                ForumBodyParagraphPaintLayer.background,
                ForumBodyParagraphPaintLayer.foreground,
                ForumBodyParagraphPaintLayer.decoration,
              ];
              for (var i = 0; i < layers.length; i++) {
                final row = ForumBodyInlinePaintRowView.phase(
                  parent: _paint!.phases[i],
                  reference: _paint!.view.reference,
                  lineIndex: _row,
                  layer: layers[i],
                  ensureOwner: _guard,
                );
                if (!row.selector.isEmpty) {
                  commands.add(
                    ForumBodyTextPictureCommand.fromInlineRow(row, Offset.zero),
                  );
                }
              }
              _lines.add(_allocation!.rows[_row].line);
              _commands.add(List.unmodifiable(commands));
              _commandPrefix.add(_commandPrefix.last + commands.length);
              _row++;
            } else {
              _result = ForumBodyInlineFontFramePlan._(
                _input!,
                _allocation!,
                _paint!.view.reference,
                _lines,
                _commands,
                _commandPrefix,
              );
              _lines = [];
              _commands = [];
              _commandPrefix = [0];
              _phase = _FramePhase.ready;
            }
            used++;
          case _FramePhase.ready:
          case _FramePhase.transferred:
          case _FramePhase.closed:
            throw StateError('Font-frame planning is not active');
        }
        _guard();
      }
      return (
        partsPrepared: used,
        waitingForLayoutBudget: false,
        isReady: isReady,
      );
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyInlineFontFrameMeasurement takeMeasurement() {
    if (_operating) throw StateError('Font-frame planning is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Font-frame planning is incomplete');
      final result = ForumBodyInlineFontFrameMeasurement._(
        _result!,
        _natural!,
        _isolated!,
        _paint!,
      );
      _natural = null;
      _isolated = null;
      _paint = null;
      _phase = _FramePhase.transferred;
      _drop();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyInlineFontFramePlan takePlan() {
    final cache = _cache;
    final ensureOwner = _ensureOwner;
    final measurement = takeMeasurement();
    measurement.close();
    ensureOwner!();
    if (cache!.isClosed) {
      throw StateError('Font-frame owner retired on release');
    }
    return measurement.plan;
  }

  void _guard() {
    if (_phase == _FramePhase.closed || _phase == _FramePhase.transferred) {
      throw StateError('Font-frame planning is retired');
    }
    _ensureOwner!();
    if (_phase == _FramePhase.closed ||
        _phase == _FramePhase.transferred ||
        _cache!.isClosed ||
        (_natural != null && !_cache!.ownsLease(_natural!)) ||
        (_isolated != null && !_cache!.ownsLease(_isolated!)) ||
        (_paint != null && _paint!.phases.any((p) => !_cache!.ownsLease(p)))) {
      throw StateError('Font-frame owner is retired');
    }
  }

  void close() {
    if (_phase == _FramePhase.closed || _phase == _FramePhase.transferred) {
      return;
    }
    _phase = _FramePhase.closed;
    try {
      _parentWork?.close();
      _isolationWork?.close();
      _allocationWork?.close();
      _paintWork?.close();
      _paint?.close();
    } finally {
      try {
        _isolated?.release();
      } finally {
        _natural?.release();
        _drop();
      }
    }
  }

  void _drop() {
    _parentWork = null;
    _isolationWork = null;
    _allocationWork = null;
    _paintWork = null;
    _parentMetrics = null;
    _input = null;
    _allocation = null;
    _paint = null;
    _natural = null;
    _isolated = null;
    _result = null;
    _cache = null;
    _ensureOwner = null;
    _additionalOwned = null;
    _lines = [];
    _commands = [];
    _commandPrefix = [0];
  }
}
