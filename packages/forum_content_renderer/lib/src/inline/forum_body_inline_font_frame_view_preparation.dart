part of 'forum_body_inline_paragraph_view.dart';

enum _FontViewPhase {
  children,
  paint,
  input,
  compare,
  rows,
  scene,
  alias,
  publish,
  ready,
  transferred,
  closed,
}

/// Consumes the current measured parents, prepares actual visible children and
/// one parent display list, then transfers the existing readable inline view.
/// Source qualification, budget probing and recording use the shared workers.
final class ForumBodyInlineFontFrameViewPreparation {
  ForumBodyInlineFontFrameViewPreparation({
    required ForumBodyInlineFontFrameMeasurement measurement,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    void Function()? ensureVisibleOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
    this.startLine = 0,
    int? endLine,
    ForumBodyTextPictureInput? expectedParentInput,
  }) : _expectedInput = expectedParentInput,
       _measurement = measurement,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _ensureVisibleOwner = ensureVisibleOwner ?? ensureOwner,
       _additionalOwned = additionalOwnedLeases,
       endLine = endLine ?? measurement.plan.lines.length {
    try {
      _guard();
      if (measurement.natural.content.projection.hasResources) {
        throw const ForumBodyInlineViewException(
          ForumBodyInlineViewFailure.coverage,
        );
      }
      measurement.plan.fragment(startLine, this.endLine);
      _childWork = ForumBodyInlineEmphasisChildPreparation(
        allocation: measurement.plan.allocation,
        natural: measurement.natural,
        cache: cache,
        expectedTextScaler: textScaler,
        ensureOwner: _guard,
        ensureVisibleOwner: _ensureVisibleOwner,
        additionalOwnedLeases: _childPrefix,
        startLine: startLine,
        endLine: this.endLine,
      );
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int startLine, endLine;
  ForumBodyInlineFontFrameMeasurement? _measurement;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner, _ensureVisibleOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyInlineEmphasisChildPreparation? _childWork;
  ForumBodyInlineEmphasisChildView? _children;
  ForumBodyTextPictureInputComposition? _inputWork;
  ForumBodyTextPictureInput? _sceneInput;
  ForumBodyTextPictureInput? _expectedInput;
  ForumBodyTextPicturePreparation? _sceneWork;
  ForumBodyTextPictureLease? _picture;
  ForumBodyInlineParagraphLease? _isolated;
  ForumBodyInlineParagraphView? _source, _result;
  List<ForumBodyInlinePaintRowView> _rows = [];
  var _phase = _FontViewPhase.children;
  var _paint = 0, _row = 0;
  int _compare = 0;
  bool _operating = false, _miss = false;
  bool get isReady => _phase == _FontViewPhase.ready;
  bool get cacheMiss => _miss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    if (_measurement != null) yield* _measurement!.nativeLeases;
    if (_childWork != null) yield* _childWork!.nativeLeases;
    if (_children != null) yield* _children!.nativeLeases;
    if (_sceneWork != null) yield* _sceneWork!.nativeLeases;
    if (_isolated != null) yield _isolated!;
    if (_picture != null) yield _picture!;
    if (_source != null) yield* _source!.nativeLeases;
    if (_result != null) yield* _result!.nativeLeases;
  }

  Iterable<ForumBodyNativeParagraphLease> _caller() {
    final owned =
        _additionalOwned?.call() ?? const <ForumBodyNativeParagraphLease>[];
    _guard();
    return owned;
  }

  Iterable<ForumBodyNativeParagraphLease> _childPrefix() sync* {
    yield* _caller();
    yield* _measurement!.nativeLeases.skip(
      1,
    ); // Child worker counts natural itself.
  }

  Iterable<ForumBodyNativeParagraphLease> _owned() sync* {
    yield* _caller();
    yield* nativeLeases;
  }

  ({int partsPrepared, bool waitingForLayoutBudget, bool isReady}) advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) {
      throw StateError('Allocated inline preparation is reentrant');
    }
    _operating = true;
    var used = 0;
    try {
      _guard();
      if (isReady) throw StateError('Allocated inline preparation is ready');
      _miss = false;
      final cache = _cache!,
          builds = cache.layoutBuildCount,
          pictures = cache.pictureBuildCount;
      while (!isReady &&
          used < maxParts &&
          cache.layoutBuildCount == builds &&
          cache.pictureBuildCount == pictures) {
        final measurement = _measurement!, plan = measurement.plan;
        switch (_phase) {
          case _FontViewPhase.children:
            final step = _childWork!.advance(
              maxParts: maxParts - used,
              cachedOnly: cachedOnly,
            );
            used += step.partsPrepared;
            _miss = _childWork!.cacheMiss;
            if (_miss || step.waitingForLayoutBudget) {
              return (
                partsPrepared: used,
                waitingForLayoutBudget: step.waitingForLayoutBudget,
                isReady: false,
              );
            }
            if (!_childWork!.isReady) break;
            _children = _childWork!.takeView();
            _childWork = null;
            if (!plan.hasParentPaint(startLine, endLine) &&
                _expectedInput != null) {
              throw const ForumBodyInlineViewException(
                ForumBodyInlineViewFailure.geometry,
              );
            }
            _phase = plan.hasParentPaint(startLine, endLine)
                ? _FontViewPhase.paint
                : _FontViewPhase.alias;
          case _FontViewPhase.paint:
            if (_paint < measurement.paint.phases.length) {
              final phase = measurement.paint.phases[_paint];
              if (!phase.layout.isPaintPrepared && cachedOnly) {
                _miss = true;
                return (
                  partsPrepared: used,
                  waitingForLayoutBudget: false,
                  isReady: false,
                );
              }
              cache.prepareInlineParentPaint(phase);
              _paint++;
            } else {
              _inputWork = ForumBodyTextPictureInputComposition.commandSteps(
                steps: plan.parentPictureSteps(startLine, endLine),
                ensureOwner: _guard,
                maxCommands: ForumBodyTextPictureInput.maximumCommands,
              );
              _phase = _FontViewPhase.input;
            }
            used++;
          case _FontViewPhase.input:
            used += _inputWork!.advance(maxParts: maxParts - used);
            if (!_inputWork!.isReady) break;
            _sceneInput = _inputWork!.takeInput();
            _inputWork = null;
            if (_expectedInput != null &&
                _expectedInput!.commands.length !=
                    _sceneInput!.commands.length) {
              throw const ForumBodyInlineViewException(
                ForumBodyInlineViewFailure.geometry,
              );
            }
            _phase = _FontViewPhase.compare;
          case _FontViewPhase.compare:
            if (_expectedInput != null &&
                _compare < _sceneInput!.commands.length) {
              final index = _compare++;
              if (_sceneInput!.commands[index] !=
                  _expectedInput!.commands[index]) {
                throw const ForumBodyInlineViewException(
                  ForumBodyInlineViewFailure.geometry,
                );
              }
              used++;
              break;
            }
            _row = startLine * 3;
            _phase = _FontViewPhase.rows;
            used++;
          case _FontViewPhase.rows:
            if (_row < endLine * 3) {
              const layers = [
                ForumBodyParagraphPaintLayer.background,
                ForumBodyParagraphPaintLayer.foreground,
                ForumBodyParagraphPaintLayer.decoration,
              ];
              final index = _row++;
              final row = ForumBodyInlinePaintRowView.phase(
                parent: measurement.paint.phases[index % 3],
                reference: measurement.paint.view.reference,
                lineIndex: index ~/ 3,
                layer: layers[index % 3],
                ensureOwner: _guard,
                allocationOrigin: Offset(
                  0,
                  -plan.fragment(startLine, endLine).top,
                ),
              );
              if (!row.selector.isEmpty) _rows.add(row);
            } else {
              _sceneWork = ForumBodyTextPicturePreparation.cooperative(
                cache: cache,
                input: _sceneInput!,
                text: const [],
                inlineRows: _rows,
                ensureOwner: _guard,
                additionalOwnedLeases: _owned,
              );
              _phase = _FontViewPhase.scene;
            }
            used++;
          case _FontViewPhase.scene:
            final step = _sceneWork!.advance(
              maxParts: maxParts - used,
              cachedOnly: cachedOnly,
            );
            used += step.partsPrepared;
            _miss = _sceneWork!.cacheMiss;
            if (_miss || step.waitingForLayoutBudget) {
              return (
                partsPrepared: used,
                waitingForLayoutBudget: step.waitingForLayoutBudget,
                isReady: false,
              );
            }
            if (!_sceneWork!.isReady) break;
            _picture = _sceneWork!.takeLease();
            _sceneWork = null;
            _rows = [];
            _phase = _FontViewPhase.alias;
          case _FontViewPhase.alias:
            _isolated = plan.allocation.input.request.acquire(
              cache,
              width: plan.allocation.input.natural.requestWidth,
              textScaler: plan.textScaler,
              cachedOnly: true,
            );
            _guard();
            if (_isolated == null ||
                !identical(
                  _isolated!.layout.lines,
                  plan.paintReference.sourceLines,
                ) ||
                !identical(_isolated!.content, measurement.isolated.content)) {
              throw StateError('Current query parent disappeared');
            }
            _phase = _FontViewPhase.publish;
            used++;
          case _FontViewPhase.publish:
            _ensureVisibleOwner!();
            _guard();
            final backgrounds = _children!.backgroundSurfaces;
            _source = _children!.takeSourceView();
            _children = null;
            if (!_source!.matchesCurrentParent(measurement.natural) ||
                !identical(_picture?.input, _sceneInput)) {
              throw StateError('Allocated inline source differs');
            }
            final frames = _InlineFontFrameBinding(
              plan,
              startLine,
              endLine,
              _isolated!,
              _picture,
              _ensureVisibleOwner!,
            );
            _result = ForumBodyInlineParagraphView._allocated(
              _source!,
              frames,
              backgrounds,
            );
            // O(1) ownership move: actual child bindings are not rebuilt.
            _source!._parent = null;
            _source!._fragment = null;
            _source!._children = const {};
            _source!._backgrounds = const [];
            _source!._backgroundRows = const [];
            _source = null;
            _isolated = null;
            _picture = null;
            measurement.close();
            _measurement = null;
            _phase = _FontViewPhase.ready;
            used++;
          case _FontViewPhase.ready:
          case _FontViewPhase.transferred:
          case _FontViewPhase.closed:
            throw StateError('Allocated inline preparation is retired');
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

  ForumBodyInlineParagraphView takeView() {
    if (_operating) {
      throw StateError('Allocated inline preparation is reentrant');
    }
    _operating = true;
    try {
      _guard();
      if (!isReady) {
        throw StateError('Allocated inline preparation is incomplete');
      }
      _result!._ensureActive();
      _guard();
      final view = _result!;
      _result = null;
      _phase = _FontViewPhase.transferred;
      _drop();
      return view;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _FontViewPhase.closed ||
        _phase == _FontViewPhase.transferred) {
      throw StateError('Allocated inline preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _FontViewPhase.closed ||
        _phase == _FontViewPhase.transferred ||
        _cache!.isClosed ||
        (_measurement != null &&
            (!_measurement!.isActive ||
                _measurement!.nativeLeases.any(
                  (p) => !_cache!.ownsLease(p),
                )))) {
      throw StateError('Allocated inline owner is retired');
    }
  }

  void close() {
    if (_phase == _FontViewPhase.closed ||
        _phase == _FontViewPhase.transferred) {
      return;
    }
    _phase = _FontViewPhase.closed;
    try {
      _childWork?.close();
      _children?.close();
      _inputWork?.close();
      _sceneWork?.close();
      _source?.close();
      _result?.close();
      _picture?.release();
      _isolated?.release();
    } finally {
      _measurement?.close();
      _drop();
    }
  }

  void _drop() {
    _measurement = null;
    _cache = null;
    _ensureOwner = null;
    _ensureVisibleOwner = null;
    _additionalOwned = null;
    _childWork = null;
    _children = null;
    _inputWork = null;
    _sceneInput = null;
    _expectedInput = null;
    _sceneWork = null;
    _picture = null;
    _isolated = null;
    _source = null;
    _result = null;
    _rows = [];
  }
}
