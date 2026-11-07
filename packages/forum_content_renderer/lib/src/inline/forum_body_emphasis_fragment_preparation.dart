part of 'forum_body_emphasis_line_layout.dart';

enum _FragmentPhase {
  scales,
  prefix,
  probe,
  acquireSource,
  acquirePhase,
  frames,
  groupScene,
  compareScene,
  scene,
  releaseParents,
  sourceRows,
  lines,
  publish,
  ready,
  transferred,
  closed,
}

/// Requalifies complete groups in the current cache, sharing whole source and
/// phase parents. Only the final merged scene is recorded. This is the visible
/// counterpart of the pure fragment plan, not another layout/cache pipeline.
final class ForumBodyEmphasisFragmentPreparation {
  ForumBodyEmphasisFragmentPreparation({
    required ForumBodyEmphasisFragmentInput input,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    required double width,
    required TextScaler expectedTextScaler,
    void Function()? ensureVisibleOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _input = input,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _ensureVisibleOwner = ensureVisibleOwner ?? ensureOwner,
       _callerScaler = expectedTextScaler,
       _additionalOwned = additionalOwnedLeases {
    try {
      _guard();
      if (width != input.width) ForumBodyEmphasisLinePreparation._mismatch();
      _scales = input.paragraph.effectiveScales.entries.iterator;
      _slots = input.nativeFootprint.iterator;
      _group = input.selection.startGroup;
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  static const revision = 2;
  ForumBodyEmphasisFragmentInput? _input;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  void Function()? _ensureVisibleOwner;
  TextScaler? _callerScaler;
  Iterator<MapEntry<double, double>>? _scales;
  Iterator<ForumBodyNativeRequestSlot>? _slots;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  bool _prefixStarted = false, _sceneProbed = false;
  ForumBodyParagraphBudgetProbe? _probe;
  ForumBodyParagraphLease? _source;
  ForumBodyTextRequestPreparation? _pending;
  final _parents = <ForumBodyParagraphLease>[];
  final _phases = <ForumBodyEmphasisMeasuredPaintPhase>[];
  ForumBodyParagraphLineFramePreparation? _frameJob;
  ForumBodyEmphasisAllocatedSceneInputPreparation? _groupScene;
  ForumBodyTextPictureInput? _actualScene;
  final _phaseRows = <ForumBodyParagraphRowView>[];
  ForumBodyTextPicturePreparation? _sceneJob;
  ForumBodyTextPictureLease? _picture;
  List<ForumBodyParagraphRowView> _sourceRows = [];
  List<ForumBodyParagraphLine> _lines = [];
  ForumBodyEmphasisFragmentLayout? _result;
  var _phase = _FragmentPhase.scales;
  int _group = 0, _layer = 0, _index = 0;
  bool _operating = false, _cacheMiss = false;
  bool get isReady => _phase == _FragmentPhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get _owned sync* {
    if (_source?.isActive == true) yield _source!;
    yield* _parents.where((p) => p.isActive);
  }

  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    yield* _owned;
    if (_pending != null) yield* _pending!.nativeLeases;
    if (_sceneJob != null) yield* _sceneJob!.nativeLeases;
    if (_picture?.isActive == true) yield _picture!;
    if (_result != null) yield* _result!.nativeLeases;
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
      throw StateError('Emphasis fragment preparation is reentrant');
    }
    _operating = true;
    var used = 0;
    final cache = _cache,
        builds = cache?.layoutBuildCount ?? 0,
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
        final input = _input!, paragraph = input.paragraph;
        switch (_phase) {
          case _FragmentPhase.scales:
            if (_scales!.moveNext()) {
              final sample = _scales!.current,
                  actual = _callerScaler!.scale(sample.key);
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
              _phase = _FragmentPhase.prefix;
            }
          case _FragmentPhase.prefix:
            if (!_prefixStarted) {
              final extra =
                  _additionalOwned?.call() ??
                  const <ForumBodyNativeParagraphLease>[];
              _guard();
              _prefix = extra.iterator;
              _prefixStarted = true;
            } else if (_prefix!.moveNext()) {
              _guard();
              _probe!.includeLease(_prefix!.current);
            } else {
              _prefix = null;
              _phase = _FragmentPhase.probe;
            }
          case _FragmentPhase.probe:
            if (_slots!.moveNext()) {
              final slot = _slots!.current;
              slot.request.includeBudget(
                _probe!,
                width: slot.width,
                textScaler: paragraph.textScaler,
                minimumLineCount: slot.minimumLineCount,
              );
            } else if (!_sceneProbed) {
              _probe!.includeTextPicture(input.pictureInput);
              _sceneProbed = true;
            } else {
              _probe!.close();
              _probe = null;
              _slots = null;
              _phase = _FragmentPhase.acquireSource;
            }
          case _FragmentPhase.acquireSource:
          case _FragmentPhase.acquirePhase:
            final source = _phase == _FragmentPhase.acquireSource;
            final allocation = paragraph.groups[_group].allocation;
            final paint = allocation.paintInput;
            final content = source
                ? paragraph.content
                : switch (_layer) {
                    0 => paint.background,
                    1 => paint.foreground,
                    _ => paint.decoration,
                  };
            _pending ??= ForumBodyTextRequestPreparation(
              cache: cache,
              request: ForumBodyTextRequest.paragraph(
                content,
                rowIsolationPitch: paragraph.reference.rowIsolationPitch,
              ),
              ensureOwner: _guard,
              preparePaint: !source,
              textScaler: paragraph.textScaler,
              width: paragraph.width,
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
              _pending = null;
              if (source) {
                _source = parent;
                if (!identical(parent.content, paragraph.content) ||
                    parent.nativeInputIdentity !=
                        paragraph.reference.isolatedInputIdentity) {
                  ForumBodyEmphasisLinePreparation._mismatch();
                }
                _verifyAllocatedParent(allocation, parent, parent);
                _phase = _FragmentPhase.acquirePhase;
                break;
              }
              _parents.add(parent);
              _verifyAllocatedParent(allocation, _source!, parent);
              _frameJob = ForumBodyParagraphLineFramePreparation(
                parent: parent,
                ensureOwner: _guard,
              );
              _phase = _FragmentPhase.frames;
            }
          case _FragmentPhase.frames:
            _frameJob!.advance(maxParts: 1);
            if (_frameJob!.isReady) {
              final frames = _frameJob!.takeFrames();
              _frameJob = null;
              _phases.add((parent: _parents.last, frames: frames));
              _phase = ++_layer < 3
                  ? _FragmentPhase.acquirePhase
                  : _FragmentPhase.groupScene;
            }
          case _FragmentPhase.groupScene:
            if (_group == input.selection.endGroup) {
              _sceneJob = ForumBodyTextPicturePreparation.cooperative(
                cache: cache,
                input: input.pictureInput,
                text: const [],
                paragraphRows: _phaseRows,
                ensureOwner: _guard,
                additionalOwnedLeases: _otherOwned,
              );
              _phase = _FragmentPhase.scene;
              break;
            }
            final group = paragraph.groups[_group];
            _groupScene ??= ForumBodyEmphasisAllocatedSceneInputPreparation(
              allocation: group.allocation,
              source: _source!,
              phases: _phases,
              ensureOwner: _guard,
            );
            _groupScene!.advance(maxParts: 1);
            if (_groupScene!.isReady) {
              // Replace the child transaction guard before it retires. These
              // views borrow the same three parents through final recording.
              for (final row in _groupScene!._groups) {
                _phaseRows.add(
                  ForumBodyParagraphRowView.bind(
                    parent: row.parent,
                    metrics: row.metrics,
                    ensureOwner: _guard,
                  ),
                );
              }
              _actualScene = _groupScene!.takeInput().pictureInput;
              _groupScene = null;
              _index = 0;
              if (_actualScene!.commands.length !=
                  group.sceneInput.pictureInput.commands.length) {
                ForumBodyEmphasisLinePreparation._mismatch();
              }
              _phase = _FragmentPhase.compareScene;
            }
          case _FragmentPhase.compareScene:
            final expected = paragraph.groups[_group].sceneInput.pictureInput;
            if (_index < expected.commands.length) {
              if (_actualScene!.commands[_index] != expected.commands[_index]) {
                ForumBodyEmphasisLinePreparation._mismatch();
              }
              _index++;
            } else {
              _actualScene = null;
              _group++;
              _phase = _FragmentPhase.groupScene;
            }
          case _FragmentPhase.scene:
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
              _index = 0;
              _phase = _FragmentPhase.releaseParents;
            }
          case _FragmentPhase.releaseParents:
            if (_index < _parents.length) {
              _parents[_index++].release();
            } else {
              _parents.clear();
              _phases.clear();
              _phaseRows.clear();
              _index = input.selection.startGroup;
              _phase = _FragmentPhase.sourceRows;
            }
          case _FragmentPhase.sourceRows:
            if (_index < input.selection.endGroup) {
              _sourceRows.add(
                ForumBodyParagraphRowView.bind(
                  parent: _source!,
                  metrics: paragraph.groups[_index++].source,
                  ensureOwner: _ensureVisibleOwner!,
                ),
              );
            } else {
              _index = input.startLine;
              _phase = _FragmentPhase.lines;
            }
          case _FragmentPhase.lines:
            if (_index < input.endLine) {
              _lines.add(
                paragraph.lines[_index++].shift(
                  Offset(0, -input.selection.top),
                ),
              );
            } else {
              _phase = _FragmentPhase.publish;
            }
          case _FragmentPhase.publish:
            _checkVisibleOwner();
            _result = ForumBodyEmphasisFragmentLayout._(
              input: input,
              source: _source!,
              picture: _picture!,
              rows: _sourceRows,
              lines: _lines,
              ensureOwner: _ensureVisibleOwner!,
            );
            _source = null;
            _picture = null;
            _sourceRows = [];
            _lines = [];
            _phase = _FragmentPhase.ready;
          case _FragmentPhase.ready:
          case _FragmentPhase.transferred:
          case _FragmentPhase.closed:
            throw StateError('Emphasis fragment preparation is retired');
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

  ForumBodyEmphasisFragmentLayout takeLayout() {
    if (_operating) {
      throw StateError('Emphasis fragment preparation is reentrant');
    }
    _operating = true;
    try {
      _guard();
      if (!isReady) {
        throw StateError('Emphasis fragment preparation is incomplete');
      }
      _checkVisibleOwner();
      final result = _result!;
      _result = null;
      _phase = _FragmentPhase.transferred;
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
    if (_phase == _FragmentPhase.closed ||
        _phase == _FragmentPhase.transferred) {
      throw StateError('Emphasis fragment preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _FragmentPhase.closed ||
        _cache?.isClosed != false ||
        (_source != null && !_cache!.ownsLease(_source!)) ||
        (_picture != null && !_cache!.ownsLease(_picture!)) ||
        (_result != null && _result!.isDisposed)) {
      throw StateError('Emphasis fragment owner is retired');
    }
  }

  // A page transaction can retire after delivery while the reader still owns
  // its view. The persistent visible guard must not capture that transaction.
  void _checkVisibleOwner() {
    if (!identical(_ensureVisibleOwner, _ensureOwner)) {
      _ensureVisibleOwner!();
      _guard();
    }
  }

  void _dropInputs() {
    _input = null;
    _cache = null;
    _ensureOwner = null;
    _ensureVisibleOwner = null;
    _callerScaler = null;
    _scales = null;
    _slots = null;
    _prefix = null;
    _additionalOwned = null;
    _actualScene = null;
    _sourceRows = [];
    _lines = [];
  }

  void close() {
    if (_phase == _FragmentPhase.closed ||
        _phase == _FragmentPhase.transferred) {
      return;
    }
    _phase = _FragmentPhase.closed;
    final source = _source, picture = _picture, result = _result;
    _source = null;
    _picture = null;
    _result = null;
    try {
      _pending?.close();
      _pending = null;
      _frameJob?.close();
      _frameJob = null;
      _groupScene?.close();
      _groupScene = null;
      _sceneJob?.close();
      _sceneJob = null;
    } finally {
      try {
        result?.close();
        picture?.release();
        source?.release();
      } finally {
        for (final parent in _parents) {
          parent.release();
        }
        _parents.clear();
        _phases.clear();
        _phaseRows.clear();
        _probe?.close();
        _probe = null;
        _dropInputs();
      }
    }
  }
}
