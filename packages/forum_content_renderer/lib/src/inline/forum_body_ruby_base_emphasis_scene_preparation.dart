part of 'forum_body_emphasis_line_layout.dart';

final class _RubyEmphasisGlyphBinding {
  _RubyEmphasisGlyphBinding(this.source, this.marks);
  ForumBodyTextLease? source;
  final List<ForumBodyEmphasisMarkLease> marks;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?source,
    ...marks.where((mark) => mark.isActive),
  ];
  void close() {
    final base = source;
    source = null;
    try {
      for (final mark in marks) {
        mark.release();
      }
    } finally {
      marks.clear();
      base?.release();
    }
  }
}

enum _RubyBaseScenePhase {
  prefix,
  probe,
  bind,
  scene,
  releaseMarks,
  publish,
  ready,
  transferred,
  closed,
}

/// Reuses the emphasis line's full original/glyph/marker qualification and the
/// existing native picture transaction. Only the final base scene is recorded;
/// the ordinary isolated emphasis scene is never acquired or retained.
final class ForumBodyRubyBaseEmphasisScenePreparation {
  ForumBodyRubyBaseEmphasisScenePreparation({
    required ForumBodyEmphasisTextInput input,
    required ForumBodyRubyBaseEmphasisPlan plan,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    required double width,
    required TextScaler expectedTextScaler,
    void Function()? ensureVisibleOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _plan = plan,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _ensureVisibleOwner = ensureVisibleOwner ?? ensureOwner,
       _callerScaler = expectedTextScaler,
       _additionalOwned = additionalOwnedLeases {
    try {
      _guard();
      if (!identical(input, plan.geometry.line.input) ||
          width != plan.geometry.line.requestWidth) {
        ForumBodyEmphasisLinePreparation._mismatch();
      }
      _slots = plan.nativeBudgetFootprint.iterator;
      _probe = cache.createBudgetProbe();
    } catch (_) {
      close();
      rethrow;
    }
  }
  ForumBodyRubyBaseEmphasisPlan? _plan;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner, _ensureVisibleOwner;
  TextScaler? _callerScaler;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  bool _prefixStarted = false;
  Iterator<ForumBodyNativeBudgetSlot>? _slots;
  ForumBodyParagraphBudgetProbe? _probe;
  ForumBodyEmphasisLinePreparation? _binder;
  _RubyEmphasisGlyphBinding? _binding;
  ForumBodyTextPicturePreparation? _scene;
  ForumBodyTextPictureLease? _picture;
  ForumBodyRubyBaseEmphasisLayout? _result;
  var _phase = _RubyBaseScenePhase.prefix;
  int _released = 0;
  bool _operating = false, _cacheMiss = false;
  bool get isReady => _phase == _RubyBaseScenePhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    if (_binder != null) ..._binder!.nativeLeases,
    if (_binding != null) ..._binding!.nativeLeases,
    if (_scene != null) ..._scene!.nativeLeases,
    ?_picture,
    if (_result != null) ..._result!.nativeLeases,
  ];
  Iterable<ForumBodyNativeParagraphLease> _otherOwned() sync* {
    yield* nativeLeases;
    yield* _additionalOwned?.call() ?? const [];
  }

  ForumBodyEmphasisLineStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Ruby emphasis scene is reentrant');
    _operating = true;
    var parts = 0;
    final cache = _cache;
    final builds = cache?.layoutBuildCount ?? 0;
    final pictures = cache?.pictureBuildCount ?? 0;
    ForumBodyEmphasisLineStep step([bool waiting = false]) => (
      partsPrepared: parts,
      nativeLayoutsBuilt: (cache?.layoutBuildCount ?? builds) - builds,
      picturesRecorded: (cache?.pictureBuildCount ?? pictures) - pictures,
      waitingForLayoutBudget: waiting,
    );
    try {
      _guard();
      _cacheMiss = false;
      while (!isReady &&
          parts < maxParts &&
          cache!.layoutBuildCount == builds &&
          cache.pictureBuildCount == pictures) {
        final plan = _plan!, line = plan.geometry.line;
        switch (_phase) {
          case _RubyBaseScenePhase.prefix:
            if (!_prefixStarted) {
              final prefix = _additionalOwned?.call() ?? const [];
              _guard();
              _prefix = prefix.iterator;
              _prefixStarted = true;
            } else if (_prefix!.moveNext()) {
              _guard();
              _probe!.includeLease(_prefix!.current);
            } else {
              _guard();
              _prefix = null;
              _phase = _RubyBaseScenePhase.probe;
            }
          case _RubyBaseScenePhase.probe:
            if (_slots!.moveNext()) {
              _guard();
              final slot = _slots!.current;
              slot.request.includeBudget(
                _probe!,
                width: slot.width,
                minimumLineCount: slot.minimumLineCount,
                textScaler: line.textScaler,
              );
            } else {
              _guard();
              _slots = null;
              _probe!.close();
              _probe = null;
              _binder = ForumBodyEmphasisLinePreparation._work(
                input: line.input,
                cache: cache,
                ensureOwner: _guard,
                width: line.requestWidth,
                textScaler: _callerScaler!,
                measureOnly: true,
                bindOnly: true,
                prepareBindingPaint: true,
                metrics: line,
                baseRequest: line.baseRequest,
                additionalOwnedLeases: _otherOwned,
              );
              _callerScaler = null;
              _phase = _RubyBaseScenePhase.bind;
            }
          case _RubyBaseScenePhase.bind:
            final work = _binder!.advance(maxParts: 1, cachedOnly: cachedOnly);
            if (work.waitingForLayoutBudget || _binder!.cacheMiss) {
              _cacheMiss = _binder!.cacheMiss;
              parts += work.partsPrepared;
              return step(work.waitingForLayoutBudget);
            }
            if (_binder!.isReady) {
              _binding = _binder!._takeGlyphBinding();
              _binder!.close();
              _binder = null;
              _scene = ForumBodyTextPicturePreparation.cooperative(
                cache: cache,
                input: plan.pictureInput,
                text: [_binding!.source!],
                marks: _binding!.marks,
                ensureOwner: _guard,
                additionalOwnedLeases: _otherOwned,
              );
              _phase = _RubyBaseScenePhase.scene;
            }
          case _RubyBaseScenePhase.scene:
            final work = _scene!.advance(maxParts: 1, cachedOnly: cachedOnly);
            if (work.waitingForLayoutBudget || _scene!.cacheMiss) {
              _cacheMiss = _scene!.cacheMiss;
              parts += work.partsPrepared;
              return step(work.waitingForLayoutBudget);
            }
            if (_scene!.isReady) {
              _picture = _scene!.takeLease();
              _scene!.close();
              _scene = null;
              _phase = _RubyBaseScenePhase.releaseMarks;
            }
          case _RubyBaseScenePhase.releaseMarks:
            if (_released < _binding!.marks.length) {
              _binding!.marks[_released++].release();
            } else {
              _binding!.marks.clear();
              _phase = _RubyBaseScenePhase.publish;
            }
          case _RubyBaseScenePhase.publish:
            _ensureVisibleOwner!();
            _guard();
            _result = ForumBodyRubyBaseEmphasisLayout._(
              plan: plan,
              source: _binding!.source!,
              picture: _picture!,
              ensureOwner: _ensureVisibleOwner!,
            );
            _binding!.source = null;
            _binding!.close();
            _binding = null;
            _picture = null;
            _phase = _RubyBaseScenePhase.ready;
          case _RubyBaseScenePhase.ready:
          case _RubyBaseScenePhase.transferred:
          case _RubyBaseScenePhase.closed:
            throw StateError('Ruby emphasis scene is retired');
        }
        parts++;
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

  ForumBodyRubyBaseEmphasisLayout takeLayout() {
    if (_operating) throw StateError('Ruby emphasis scene is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Ruby emphasis scene is incomplete');
      _ensureVisibleOwner!();
      _guard();
      final result = _result!;
      _result = null;
      _phase = _RubyBaseScenePhase.transferred;
      _drop();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _RubyBaseScenePhase.closed ||
        _phase == _RubyBaseScenePhase.transferred) {
      throw StateError('Ruby emphasis scene is retired');
    }
    _ensureOwner!();
    if (_phase == _RubyBaseScenePhase.closed ||
        _cache == null ||
        _cache!.isClosed ||
        (_binding?.source != null && !_cache!.ownsLease(_binding!.source!)) ||
        (_picture != null && !_cache!.ownsLease(_picture!)) ||
        (_result != null && !_result!.isActive)) {
      throw StateError('Ruby emphasis scene owner is retired');
    }
  }

  void _drop() {
    _probe?.close();
    _probe = null;
    _prefix = null;
    _slots = null;
    _plan = null;
    _cache = null;
    _ensureOwner = null;
    _ensureVisibleOwner = null;
    _additionalOwned = null;
    _callerScaler = null;
  }

  void close() {
    if (_phase == _RubyBaseScenePhase.closed ||
        _phase == _RubyBaseScenePhase.transferred) {
      return;
    }
    _phase = _RubyBaseScenePhase.closed;
    try {
      _binder?.close();
      _scene?.close();
    } finally {
      _binder = null;
      _scene = null;
      try {
        _binding?.close();
        _picture?.release();
        _result?.close();
      } finally {
        _binding = null;
        _picture = null;
        _result = null;
        _drop();
      }
    }
  }
}
