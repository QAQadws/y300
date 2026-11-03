part of 'forum_body_emphasis_line_layout.dart';

enum _TreeEmphasisScenePhase {
  scales,
  prefix,
  probe,
  glyphs,
  bind,
  qualify,
  collectFonts,
  scene,
  releaseFonts,
  backgrounds,
  publish,
  ready,
  transferred,
  closed,
}

/// One current-source transaction: freeze/qualify the measured scaling, admit
/// the complete actual prefix, bind the glyph tree and original marked leaves,
/// then record one shared marker scene. No isolated line scene is acquired.
final class ForumBodyRubyTreeEmphasisScenePreparation {
  ForumBodyRubyTreeEmphasisScenePreparation({
    required ForumBodyRubyGlyphTreeInput input,
    required ForumBodyRubyTreeEmphasisPlan plan,
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
      final metrics = plan.placement.input.input;
      if (!identical(input, metrics.geometry.metrics.input) ||
          width != input.maxWidth) {
        _mismatch();
      }
      _samples = metrics.effectiveScales.entries.iterator;
    } catch (_) {
      close();
      rethrow;
    }
  }
  ForumBodyRubyTreeEmphasisPlan? _plan;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner, _ensureVisibleOwner;
  TextScaler? _callerScaler;
  Iterator<MapEntry<double, double>>? _samples;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  bool _prefixStarted = false;
  Iterator<ForumBodyNativeBudgetSlot>? _slots;
  ForumBodyParagraphBudgetProbe? _probe;
  ForumBodyRubyGlyphTreeBindingPreparation? _glyphWorker;
  ForumBodyRubyGlyphTreeBinding? _glyphs;
  ForumBodyEmphasisLinePreparation? _binder;
  _RubyEmphasisGlyphBinding? _binding;
  Map<Object, ForumBodyEmphasisMarkLease> _markers = {};
  Iterator<ForumBodyEmphasisMarkLease>? _release;
  ForumBodyTextPicturePreparation? _scene;
  ForumBodyTextPictureLease? _picture;
  List<({Rect rect, ForumBodyRubyContainerFontBox font})> _backgrounds = [];
  ForumBodyRubyTreeEmphasisLayout? _result;
  var _phase = _TreeEmphasisScenePhase.scales;
  int _source = 0, _background = 0;
  bool _operating = false, _cacheMiss = false, _waiting = false;
  bool get isReady => _phase == _TreeEmphasisScenePhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    yield* _glyphWorker?.nativeLeases ?? const [];
    yield* _glyphs?.nativeLeases ?? const [];
    yield* _binder?.nativeLeases ?? const [];
    yield* _binding?.nativeLeases ?? const [];
    yield* _markers.values.where((mark) => mark.isActive);
    yield* _scene?.nativeLeases ?? const [];
    if (_picture case final picture?) yield picture;
    yield* _result?.nativeLeases ?? const [];
  }

  /// The active child's own aliases are accounted by that child. Other owned
  /// glyph/font handles and the caller's prefix stay explicit for pin pressure.
  Iterable<ForumBodyNativeParagraphLease> _otherOwned() sync* {
    yield* _glyphs?.nativeLeases ?? const [];
    yield* _binding?.nativeLeases ?? const [];
    yield* _markers.values.where((mark) => mark.isActive);
    if (_picture case final picture?) yield picture;
    yield* _additionalOwned?.call() ?? const [];
  }

  ForumBodyEmphasisLineStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      final cache = _cache!,
          builds = cache.layoutBuildCount,
          pictures = cache.pictureBuildCount;
      var parts = 0;
      _cacheMiss = _waiting = false;
      while (!isReady && parts < maxParts) {
        final used = _advance(cachedOnly);
        parts += used;
        _guard();
        if (used == 0 ||
            _cacheMiss ||
            _waiting ||
            cache.layoutBuildCount != builds ||
            cache.pictureBuildCount != pictures) {
          break;
        }
      }
      return (
        partsPrepared: parts,
        nativeLayoutsBuilt: cache.layoutBuildCount - builds,
        picturesRecorded: cache.pictureBuildCount - pictures,
        waitingForLayoutBudget: _waiting,
      );
    });
  }

  int _advance(bool cachedOnly) {
    final plan = _plan!, cache = _cache!, metrics = plan.placement.input.input;
    switch (_phase) {
      case _TreeEmphasisScenePhase.scales:
        if (_samples!.moveNext()) {
          final sample = _samples!.current,
              actual = _callerScaler!.scale(sample.key);
          _guard();
          if (actual != sample.value) {
            throw const ForumBodyParagraphLayoutException(
              ForumBodyParagraphLayoutFailure.scale,
            );
          }
        } else {
          _samples = null;
          _callerScaler = null;
          _probe = cache.createBudgetProbe();
          _slots = plan.nativeBudgetFootprint.iterator;
          _phase = _TreeEmphasisScenePhase.prefix;
        }
      case _TreeEmphasisScenePhase.prefix:
        if (!_prefixStarted) {
          final owned = _additionalOwned?.call() ?? const [];
          _guard();
          final iterator = owned.iterator;
          _guard();
          _prefix = iterator;
          _prefixStarted = true;
        } else {
          final hasNext = _prefix!.moveNext();
          _guard();
          if (hasNext) {
            final lease = _prefix!.current;
            _guard();
            _probe!.includeLease(lease);
          } else {
            _prefix = null;
            _phase = _TreeEmphasisScenePhase.probe;
          }
        }
      case _TreeEmphasisScenePhase.probe:
        final hasNext = _slots!.moveNext();
        _guard();
        if (hasNext) {
          final slot = _slots!.current;
          slot.request.includeBudget(
            _probe!,
            width: slot.width,
            minimumLineCount: slot.minimumLineCount,
            textScaler: metrics.textScaler,
          );
        } else {
          _slots = null;
          _probe!.close();
          _probe = null;
          _phase = _TreeEmphasisScenePhase.glyphs;
        }
      case _TreeEmphasisScenePhase.glyphs:
        if (_glyphWorker == null) {
          final work = ForumBodyRubyGlyphTreeBindingPreparation(
            geometry: metrics.geometry,
            cache: cache,
            ensureOwner: _guard,
            ensureVisibleOwner: _ensureVisibleOwner,
            expectedTextScaler: metrics.textScaler,
            additionalOwnedLeases: _otherOwned,
          );
          try {
            _guard();
          } catch (_) {
            work.close();
            rethrow;
          }
          _glyphWorker = work;
        } else {
          final work = _glyphWorker!,
              step = work.advance(maxParts: 1, cachedOnly: cachedOnly);
          _cacheMiss = work.cacheMiss;
          _waiting = step.waitingForLayoutBudget;
          _guard();
          if (work.isReady) {
            _glyphs = work.takeBinding();
            _glyphWorker = null;
            work.close();
            _phase = _TreeEmphasisScenePhase.bind;
          }
          return step.formatUnitsPrepared;
        }
      case _TreeEmphasisScenePhase.bind:
        if (_source == metrics.sources.length) {
          _phase = _TreeEmphasisScenePhase.scene;
        } else if (_binder == null) {
          final source = metrics.sources[_source],
              line = source.line,
              id = source.source.source.id,
              bound = _glyphs!.sourceForId(id);
          if (!identical(bound.position, source.source) ||
              !identical(line.input, bound.source.emphasis) ||
              !identical(
                line.baseRequest,
                metrics.geometry.metrics.input.requestForSource(id),
              )) {
            _mismatch();
          }
          final work = ForumBodyEmphasisLinePreparation._work(
            input: line.input,
            metrics: line,
            cache: cache,
            ensureOwner: _guard,
            baseRequest: line.baseRequest,
            width: line.requestWidth,
            textScaler: metrics.textScaler,
            measureOnly: true,
            bindOnly: true,
            prepareBindingPaint: true,
            additionalOwnedLeases: _otherOwned,
          );
          try {
            _guard();
          } catch (_) {
            work.close();
            rethrow;
          }
          _binder = work;
        } else {
          final work = _binder!,
              step = work.advance(maxParts: 1, cachedOnly: cachedOnly);
          _cacheMiss = work.cacheMiss;
          _waiting = step.waitingForLayoutBudget;
          _guard();
          if (work.isReady) {
            _binding = work._takeGlyphBinding();
            _binder = null;
            work.close();
            _phase = _TreeEmphasisScenePhase.qualify;
          }
          return step.partsPrepared;
        }
      case _TreeEmphasisScenePhase.qualify:
        final source = metrics.sources[_source].source.source,
            lease = _binding!.source!,
            bound = _glyphs!.sourceForId(source.id);
        if (!cache.ownsLease(lease) ||
            !identical(lease.content, source.glyphs) ||
            lease.nativeInputIdentity != bound.glyphNativeInputIdentity) {
          _mismatch();
        }
        _binding!.source = null;
        lease.release();
        _phase = _TreeEmphasisScenePhase.collectFonts;
      case _TreeEmphasisScenePhase.collectFonts:
        if (_binding!.marks.isNotEmpty) {
          final mark = _binding!.marks.removeLast();
          try {
            if (!cache.ownsLease(mark)) {
              throw StateError('Ruby tree marker owner is retired');
            }
            final key = mark.nativeInputIdentity;
            if (_markers.containsKey(key)) {
              mark.release();
            } else {
              _markers[key] = mark;
            }
          } catch (_) {
            mark.release();
            rethrow;
          }
        } else {
          _binding!.close();
          _binding = null;
          _source++;
          _phase = _TreeEmphasisScenePhase.bind;
        }
      case _TreeEmphasisScenePhase.scene:
        final input = plan.markerPictureInput;
        if (input == null) {
          if (_markers.isNotEmpty) _mismatch();
          _phase = _TreeEmphasisScenePhase.backgrounds;
        } else if (_scene == null) {
          final work = ForumBodyTextPicturePreparation.cooperative(
            cache: cache,
            input: input,
            text: const [],
            marks: _markers.values,
            ensureOwner: _guard,
            additionalOwnedLeases: _otherOwned,
          );
          try {
            _guard();
          } catch (_) {
            work.close();
            rethrow;
          }
          _scene = work;
        } else {
          final work = _scene!,
              step = work.advance(maxParts: 1, cachedOnly: cachedOnly);
          _cacheMiss = work.cacheMiss;
          _waiting = step.waitingForLayoutBudget;
          _guard();
          if (work.isReady) {
            _picture = work.takeLease();
            _scene = null;
            work.close();
            _release = _markers.values.iterator;
            _phase = _TreeEmphasisScenePhase.releaseFonts;
          }
          return step.partsPrepared;
        }
      case _TreeEmphasisScenePhase.releaseFonts:
        if (_release!.moveNext()) {
          _release!.current.release();
        } else {
          _release = null;
          _markers = {};
          _phase = _TreeEmphasisScenePhase.backgrounds;
        }
      case _TreeEmphasisScenePhase.backgrounds:
        final surfaces = _glyphs!.backgrounds;
        if (_background < surfaces.length) {
          final surface = surfaces[_background++];
          _backgrounds.add((
            rect: surface.rect.shift(plan.frame.childOffset),
            font: surface.font,
          ));
        } else {
          _phase = _TreeEmphasisScenePhase.publish;
        }
      case _TreeEmphasisScenePhase.publish:
        _checkVisibleOwner();
        _result = ForumBodyRubyTreeEmphasisLayout._(
          plan: plan,
          glyphs: _glyphs!,
          picture: _picture,
          backgrounds: _backgrounds,
          ensureOwner: _ensureVisibleOwner!,
        );
        _glyphs = null;
        _picture = null;
        _backgrounds = [];
        _phase = _TreeEmphasisScenePhase.ready;
      case _TreeEmphasisScenePhase.ready:
      case _TreeEmphasisScenePhase.transferred:
      case _TreeEmphasisScenePhase.closed:
        throw StateError('Ruby tree emphasis scene is retired');
    }
    return 1;
  }

  static Never _mismatch() => throw const ForumBodyEmphasisLineException(
    ForumBodyEmphasisLineFailure.source,
  );
  ForumBodyRubyTreeEmphasisLayout takeLayout() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Ruby tree emphasis scene is incomplete');
    _checkVisibleOwner();
    final result = _result!;
    _result = null;
    _phase = _TreeEmphasisScenePhase.transferred;
    _drop();
    return result;
  });
  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Ruby tree emphasis scene is reentrant');
    _operating = true;
    try {
      return action();
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _checkVisibleOwner() {
    _ensureVisibleOwner!();
    _guard();
  }

  void _guard() {
    if (_phase == _TreeEmphasisScenePhase.closed ||
        _phase == _TreeEmphasisScenePhase.transferred) {
      throw StateError('Ruby tree emphasis scene is retired');
    }
    _ensureOwner!();
    if (_phase == _TreeEmphasisScenePhase.closed ||
        _cache!.isClosed ||
        (_glyphs != null && !_glyphs!.isActive) ||
        (_binding?.source != null && !_cache!.ownsLease(_binding!.source!)) ||
        (_picture != null && !_cache!.ownsLease(_picture!)) ||
        (_result != null && !_result!.isActive)) {
      throw StateError('Ruby tree emphasis scene owner is retired');
    }
  }

  void _drop() {
    _probe?.close();
    _probe = null;
    _prefix = null;
    _slots = null;
    _samples = null;
    _callerScaler = null;
    _plan = null;
    _cache = null;
    _ensureOwner = null;
    _ensureVisibleOwner = null;
    _additionalOwned = null;
    _release = null;
    _backgrounds = [];
  }

  void close() {
    if (_phase == _TreeEmphasisScenePhase.closed ||
        _phase == _TreeEmphasisScenePhase.transferred) {
      return;
    }
    _phase = _TreeEmphasisScenePhase.closed;
    final glyphWorker = _glyphWorker,
        binder = _binder,
        scene = _scene,
        binding = _binding,
        glyphs = _glyphs,
        picture = _picture,
        result = _result,
        markers = _markers;
    _glyphWorker = null;
    _binder = null;
    _scene = null;
    _binding = null;
    _glyphs = null;
    _picture = null;
    _result = null;
    _markers = {};
    Object? failure;
    StackTrace? stack;
    void attempt(void Function() release) {
      try {
        release();
      } catch (error, trace) {
        failure ??= error;
        stack ??= trace;
      }
    }

    for (final release in <void Function()>[
      if (glyphWorker != null) glyphWorker.close,
      if (binder != null) binder.close,
      if (scene != null) scene.close,
      if (binding != null) binding.close,
      if (glyphs != null) glyphs.close,
      if (picture != null) picture.release,
      if (result != null) result.close,
    ]) {
      attempt(release);
    }
    for (final mark in markers.values) {
      attempt(mark.release);
    }
    attempt(_drop);
    if (failure != null) Error.throwWithStackTrace(failure!, stack!);
  }
}
