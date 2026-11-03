part of 'forum_body_emphasis_line_layout.dart';

final class _EmphasisNativeBinding {
  _EmphasisNativeBinding(this.base, this.row, this.marks);
  ForumBodyParagraphLease? base;
  ForumBodyParagraphRowView? row;
  final List<ForumBodyEmphasisMarkLease> marks;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    if (base?.isActive == true) yield base!;
    yield* marks.where((m) => m.isActive);
  }

  void close() {
    final source = base;
    base = null;
    row = null;
    try {
      for (final mark in marks) {
        mark.release();
      }
    } finally {
      marks.clear();
      source?.release();
    }
  }
}

enum _AllocatedPhase {
  scales,
  prefix,
  probe,
  bind,
  acquirePhase,
  frames,
  group,
  physical,
  verify,
  commands,
  scene,
  releaseParents,
  releaseMarks,
  publish,
  ready,
  transferred,
  closed,
}

/// Rebinds an allocated numeric plan to actual source/phase/marker fonts in the
/// SAME reading cache. Native acquisition and final scene recording use existing
/// transactions; each advance stops after at most one native shape OR recording.
final class ForumBodyEmphasisAllocatedPreparation {
  ForumBodyEmphasisAllocatedPreparation({
    required ForumBodyEmphasisRowInput input,
    required ForumBodyEmphasisRowAllocation allocation,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    required double width,
    required TextScaler expectedTextScaler,
    ForumBodyEmphasisAllocatedSceneInput? plannedSceneInput,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _allocation = allocation,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _callerScaler = expectedTextScaler,
       _additionalOwned = additionalOwnedLeases,
       _expectedScene = plannedSceneInput {
    try {
      _guard();
      if (!identical(input, allocation.source.rowInput) ||
          (plannedSceneInput != null &&
              !identical(plannedSceneInput.allocation, allocation)) ||
          width != allocation.source.requestWidth ||
          allocation.rows.isEmpty ||
          allocation.rows.length > 64 ||
          allocation.marks.length > 512) {
        ForumBodyEmphasisLinePreparation._mismatch();
      }
      _scales = allocation.source.effectiveScales.entries.iterator;
      _slots = allocation.nativeFootprint.iterator;
      _phaseRequests = [
        for (final content in [
          allocation.paintInput.background,
          allocation.paintInput.foreground,
          allocation.paintInput.decoration,
        ])
          ForumBodyTextRequest.paragraph(
            content,
            rowIsolationPitch: allocation.reference.rowIsolationPitch,
          ),
      ];
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  ForumBodyEmphasisRowAllocation? _allocation;
  ForumBodyEmphasisAllocatedSceneInput? _expectedScene;
  bool _sceneProbed = false;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  TextScaler? _callerScaler;
  Iterator<MapEntry<double, double>>? _scales;
  Iterator<ForumBodyNativeRequestSlot>? _slots;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  bool _prefixStarted = false;
  ForumBodyParagraphBudgetProbe? _probe;
  ForumBodyEmphasisLinePreparation? _binder;
  _EmphasisNativeBinding? _binding;
  List<ForumBodyTextRequest> _phaseRequests = const [];
  ForumBodyTextRequestPreparation? _pending;
  final _parents = <ForumBodyParagraphLease>[];
  final _groups = <ForumBodyParagraphRowView>[];
  final _strips = <List<ForumBodyParagraphPhysicalLineSelector>>[];
  ForumBodyParagraphLineFramePreparation? _frameJob;
  ForumBodyParagraphLineFrames? _frames;
  ForumBodyParagraphRowPreparation? _groupJob;
  ForumBodyParagraphPhysicalLinePreparation? _physicalJob;
  _AllocatedSceneCommands? _commandJob;
  ForumBodyTextPicturePreparation? _sceneJob;
  ForumBodyTextPictureLease? _picture;
  ForumBodyEmphasisAllocatedLayout? _result;
  var _phase = _AllocatedPhase.scales;
  int _layer = 0, _verify = 0, _release = 0;
  bool _operating = false, _cacheMiss = false;
  bool get isReady => _phase == _AllocatedPhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    if (_binder != null) yield* _binder!.nativeLeases;
    yield* _owned;
    if (_pending != null) yield* _pending!.nativeLeases;
    if (_sceneJob != null) yield* _sceneJob!.nativeLeases;
    if (_picture?.isActive == true) yield _picture!;
    if (_result != null) yield* _result!.nativeLeases;
  }

  Iterable<ForumBodyNativeParagraphLease> get _owned sync* {
    if (_binding != null) yield* _binding!.nativeLeases;
    yield* _parents.where((p) => p.isActive);
  }

  Iterable<ForumBodyNativeParagraphLease> _otherOwned() sync* {
    final extra =
        _additionalOwned?.call() ?? const <ForumBodyNativeParagraphLease>[];
    _guard();
    yield* extra;
    yield* _owned;
  }

  ForumBodyEmphasisLineStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) {
      throw StateError('Allocated emphasis preparation is reentrant');
    }
    _operating = true;
    var used = 0;
    final cache = _cache;
    final builds = cache?.layoutBuildCount ?? 0,
        recordings = cache?.pictureBuildCount ?? 0;
    ForumBodyEmphasisLineStep step([bool waiting = false]) => (
      partsPrepared: used,
      nativeLayoutsBuilt: (cache?.layoutBuildCount ?? builds) - builds,
      picturesRecorded: (cache?.pictureBuildCount ?? recordings) - recordings,
      waitingForLayoutBudget: waiting,
    );
    try {
      _guard();
      _cacheMiss = false;
      while (used < maxParts &&
          !isReady &&
          cache!.layoutBuildCount == builds &&
          cache.pictureBuildCount == recordings) {
        _guard();
        final plan = _allocation!, source = plan.source;
        switch (_phase) {
          case _AllocatedPhase.scales:
            if (_scales!.moveNext()) {
              final sample = _scales!.current,
                  actual = _callerScaler!.scale(_scales!.current.key);
              _guard();
              if (actual != sample.value ||
                  !actual.isFinite ||
                  actual <= 0 ||
                  actual > 4096) {
                ForumBodyEmphasisLinePreparation._mismatch();
              }
            } else {
              _scales = null;
              _callerScaler = null;
              _probe = cache.createBudgetProbe();
              _phase = _AllocatedPhase.prefix;
            }
          case _AllocatedPhase.prefix:
            if (!_prefixStarted) {
              final prefix =
                  _additionalOwned?.call() ??
                  const <ForumBodyNativeParagraphLease>[];
              _guard();
              _prefix = prefix.iterator;
              _prefixStarted = true;
            } else if (_prefix!.moveNext()) {
              _guard();
              _probe!.includeLease(_prefix!.current);
            } else {
              _prefix = null;
              _phase = _AllocatedPhase.probe;
            }
          case _AllocatedPhase.probe:
            if (_slots!.moveNext()) {
              final slot = _slots!.current;
              slot.request.includeBudget(
                _probe!,
                width: slot.width,
                textScaler: source.textScaler,
                minimumLineCount: slot.minimumLineCount,
              );
            } else if (!_sceneProbed && _expectedScene != null) {
              _expectedScene!.includeBudget(_probe!);
              _sceneProbed = true;
            } else {
              _probe!.close();
              _probe = null;
              _slots = null;
              _binder = ForumBodyEmphasisLinePreparation._work(
                input: source.input,
                rowInput: source.rowInput,
                cache: cache,
                ensureOwner: _guard,
                width: source.requestWidth,
                textScaler: source.textScaler,
                measureOnly: true,
                bindOnly: true,
                metrics: source,
                baseRequest: source.baseRequest,
                additionalOwnedLeases: _otherOwned,
              );
              _phase = _AllocatedPhase.bind;
            }
          case _AllocatedPhase.bind:
            final work = _binder!.advance(maxParts: 1, cachedOnly: cachedOnly);
            if (work.waitingForLayoutBudget || _binder!.cacheMiss) {
              _cacheMiss = _binder!.cacheMiss;
              used += work.partsPrepared;
              return step(work.waitingForLayoutBudget);
            }
            if (_binder!.isReady) {
              _binding = _binder!._takeBinding();
              _binder = null;
              _verifyParent(_binding!.base!);
              _phase = _AllocatedPhase.acquirePhase;
            }
          case _AllocatedPhase.acquirePhase:
            _pending ??= ForumBodyTextRequestPreparation(
              cache: cache,
              request: _phaseRequests[_layer],
              ensureOwner: _guard,
              preparePaint: true,
              textScaler: source.textScaler,
              width: source.requestWidth,
              additionalOwnedLeases: _otherOwned,
            );
            final work = _pending!.advance(cachedOnly: cachedOnly);
            if (work.waiting || work.cacheMiss) {
              _cacheMiss = work.cacheMiss;
              used += work.units;
              return step(work.waiting);
            }
            if (_pending!.isReady) {
              final parent = _pending!.takeLease() as ForumBodyParagraphLease;
              _parents.add(parent);
              _pending = null;
              _verifyParent(parent);
              _frameJob = ForumBodyParagraphLineFramePreparation(
                parent: parent,
                ensureOwner: _guard,
              );
              _phase = _AllocatedPhase.frames;
            }
          case _AllocatedPhase.frames:
            _frameJob!.advance(maxParts: 1);
            if (_frameJob!.isReady) {
              _frames = _frameJob!.takeFrames();
              _frameJob = null;
              if (_frames!.nativeAlphabeticBaseline !=
                  plan.isolatedAlphabeticBaseline) {
                ForumBodyEmphasisLinePreparation._mismatch();
              }
              _groupJob = ForumBodyParagraphRowPreparation(
                parent: _parents.last,
                startLine: source.rowInput!.row.selector.startLine,
                ensureOwner: _guard,
              );
              _phase = _AllocatedPhase.group;
            }
          case _AllocatedPhase.group:
            _groupJob!.advance(maxParts: 1);
            if (_groupJob!.isReady) {
              final metrics = _groupJob!.takeMetrics();
              _groupJob = null;
              final expected = source.rowInput!.row;
              if (metrics.selector != expected.selector ||
                  metrics.startUtf16 != expected.startUtf16 ||
                  metrics.endUtf16 != expected.endUtf16 ||
                  metrics.fontBounds != expected.fontBounds) {
                ForumBodyEmphasisLinePreparation._mismatch();
              }
              final view = ForumBodyParagraphRowView.bind(
                parent: _parents.last,
                metrics: metrics,
                ensureOwner: _guard,
              );
              _groups.add(view);
              _physicalJob = ForumBodyParagraphPhysicalLinePreparation(
                group: view,
                frames: _frames!,
                ensureOwner: _guard,
              );
              _phase = _AllocatedPhase.physical;
            }
          case _AllocatedPhase.physical:
            _physicalJob!.advance(maxParts: 1);
            if (_physicalJob!.isReady) {
              _strips.add(_physicalJob!.takeSelectors());
              _physicalJob = null;
              _verify = 0;
              if (_strips.last.length != plan.rows.length) {
                ForumBodyEmphasisLinePreparation._mismatch();
              }
              _phase = _AllocatedPhase.verify;
            }
          case _AllocatedPhase.verify:
            if (_verify < plan.rows.length) {
              final index = _verify++,
                  expected = plan.rows[index].physicalLine,
                  actual = _strips.last[index];
              final absolute = actual.lineIndex;
              if (actual.selector != expected.selector ||
                  actual.fontBounds != expected.fontBounds ||
                  !_samePhaseLine(
                    _frames!.lines[absolute],
                    plan.reference.isolatedLines[absolute],
                  )) {
                ForumBodyEmphasisLinePreparation._mismatch();
              }
            } else {
              _frames = null;
              _layer++;
              _phase = _layer < 3
                  ? _AllocatedPhase.acquirePhase
                  : _AllocatedPhase.commands;
            }
          case _AllocatedPhase.commands:
            _commandJob ??= _AllocatedSceneCommands(
              plan,
              _groups,
              _strips,
              _guard,
            );
            _commandJob!.advance();
            if (_commandJob!.isReady) {
              final input = _commandJob!.takeInput();
              _commandJob = null;
              if (_expectedScene != null &&
                  input != _expectedScene!.pictureInput) {
                ForumBodyEmphasisLinePreparation._mismatch();
              }
              _sceneJob = ForumBodyTextPicturePreparation(
                cache: cache,
                input: input,
                text: const [],
                paragraphRows: _groups,
                marks: _binding!.marks,
                ensureOwner: _guard,
                additionalOwnedLeases: _otherOwned,
              );
              _phase = _AllocatedPhase.scene;
            }
          case _AllocatedPhase.scene:
            final work = _sceneJob!.advance(
              maxParts: 1,
              cachedOnly: cachedOnly,
            );
            if (work.waitingForLayoutBudget || _sceneJob!.cacheMiss) {
              _cacheMiss = _sceneJob!.cacheMiss;
              used += work.partsPrepared;
              return step(work.waitingForLayoutBudget);
            }
            if (_sceneJob!.isReady) {
              _picture = _sceneJob!.takeLease();
              _sceneJob = null;
              _release = 0;
              _phase = _AllocatedPhase.releaseParents;
            }
          case _AllocatedPhase.releaseParents:
            if (_release < _parents.length) {
              _parents[_release++].release();
            } else {
              _parents.clear();
              _groups.clear();
              _strips.clear();
              _release = 0;
              _phase = _AllocatedPhase.releaseMarks;
            }
          case _AllocatedPhase.releaseMarks:
            if (_release < _binding!.marks.length) {
              _binding!.marks[_release++].release();
            } else {
              _binding!.marks.clear();
              _phase = _AllocatedPhase.publish;
            }
          case _AllocatedPhase.publish:
            final base = _binding!.base!;
            final row = ForumBodyParagraphRowView.bind(
              parent: base,
              metrics: source.rowInput!.row,
              ensureOwner: _ensureOwner!,
            );
            _guard();
            _result = ForumBodyEmphasisAllocatedLayout._(
              allocation: plan,
              base: base,
              row: row,
              picture: _picture!,
              ensureOwner: _ensureOwner!,
            );
            _binding!.base = null;
            _binding!.row = null;
            _binding = null;
            _picture = null;
            _phase = _AllocatedPhase.ready;
          case _AllocatedPhase.ready:
          case _AllocatedPhase.transferred:
          case _AllocatedPhase.closed:
            throw StateError('Allocated emphasis preparation is retired');
        }
        used++;
        _guard();
      }
      return step();
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _verifyParent(ForumBodyParagraphLease parent) =>
      _verifyAllocatedParent(_allocation!, _binding!.base!, parent);

  static bool _samePhaseLine(
    ForumBodyParagraphLine a,
    ForumBodyParagraphLine b,
  ) =>
      a.startUtf16 == b.startUtf16 &&
      a.endUtf16 == b.endUtf16 &&
      a.coverageStartUtf16 == b.coverageStartUtf16 &&
      a.coverageEndUtf16 == b.coverageEndUtf16 &&
      a.engineStartUtf16 == b.engineStartUtf16 &&
      a.engineEndUtf16 == b.engineEndUtf16 &&
      a.engineCoverageStartUtf16 == b.engineCoverageStartUtf16 &&
      a.engineCoverageEndUtf16 == b.engineCoverageEndUtf16 &&
      a.unpaintedTrailingSpaceStartUtf16 ==
          b.unpaintedTrailingSpaceStartUtf16 &&
      a.engineUnpaintedTrailingSpaceStartUtf16 ==
          b.engineUnpaintedTrailingSpaceStartUtf16 &&
      a.canBreakBefore == b.canBreakBefore &&
      a.canBreakAfter == b.canBreakAfter &&
      a.top == b.top &&
      a.bottom == b.bottom &&
      a.baseline == b.baseline &&
      a.left == b.left &&
      a.width == b.width;

  ForumBodyEmphasisAllocatedLayout takeLayout() {
    if (_operating) {
      throw StateError('Allocated emphasis preparation is reentrant');
    }
    _operating = true;
    try {
      _guard();
      if (!isReady) {
        throw StateError('Allocated emphasis preparation is incomplete');
      }
      final result = _result!;
      _result = null;
      _phase = _AllocatedPhase.transferred;
      _dropInputs();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _AllocatedPhase.closed ||
        _phase == _AllocatedPhase.transferred) {
      throw StateError('Allocated emphasis preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _AllocatedPhase.closed ||
        _cache?.isClosed != false ||
        (_binding?.base != null && !_cache!.ownsLease(_binding!.base!)) ||
        (_picture != null && !_cache!.ownsLease(_picture!)) ||
        (_result != null && _result!.isDisposed)) {
      throw StateError('Allocated emphasis owner is retired');
    }
  }

  void _dropInputs() {
    _allocation = null;
    _cache = null;
    _ensureOwner = null;
    _callerScaler = null;
    _scales = null;
    _slots = null;
    _prefix = null;
    _additionalOwned = null;
    _phaseRequests = const [];
    _frames = null;
    _expectedScene = null;
    _commandJob?.close();
    _commandJob = null;
  }

  void close() {
    if (_phase == _AllocatedPhase.closed ||
        _phase == _AllocatedPhase.transferred) {
      return;
    }
    _phase = _AllocatedPhase.closed;
    final binding = _binding, picture = _picture, result = _result;
    _binding = null;
    _picture = null;
    _result = null;
    try {
      _binder?.close();
      _binder = null;
      _pending?.close();
      _pending = null;
      _frameJob?.close();
      _frameJob = null;
      _groupJob?.close();
      _groupJob = null;
      _physicalJob?.close();
      _physicalJob = null;
      _sceneJob?.close();
      _sceneJob = null;
    } finally {
      try {
        result?.close();
        picture?.release();
        binding?.close();
      } finally {
        for (final parent in _parents) {
          parent.release();
        }
        _parents.clear();
        _groups.clear();
        _strips.clear();
        _probe?.close();
        _probe = null;
        _dropInputs();
      }
    }
  }
}
