part of 'forum_body_emphasis_paragraph_metrics.dart';

enum _ParagraphPhase {
  setup,
  scales,
  prefix,
  probe,
  natural,
  naturalFrames,
  isolated,
  reference,
  isolatedFrames,
  paintParent,
  paintFrames,
  group,
  physical,
  allocate,
  sceneInput,
  lines,
  commit,
  release,
  publish,
  ready,
  transferred,
  closed,
}

/// Computes readable row frames for one wrapping paragraph.
/// Natural/isolated parents and their frame tables are reused across groups;
/// each group's existing measurement/allocation is consumed cooperatively.
/// No painting is prepared and no partial paragraph escapes this transaction.
final class ForumBodyEmphasisParagraphPreparation {
  ForumBodyEmphasisParagraphPreparation({
    required ForumBodyParagraphContent content,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    required this.width,
    TextScaler textScaler = TextScaler.noScaling,
    double rowIsolationPitch = 256,
    this.maxLines = 4096,
    this.maxGroupLines = 64,
    this.maxHeight = 1048576,
    this.captureIntrinsicWidths = false,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _content = content,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _callerScaler = textScaler,
       _pitch = rowIsolationPitch,
       _additionalOwned = additionalOwnedLeases {
    try {
      _guard();
      if (content.isSourceFree ||
          content.paintLayer != ForumBodyParagraphPaintLayer.all ||
          content.layoutMode != ForumBodyParagraphLayoutMode.wrap) {
        _fail(ForumBodyEmphasisParagraphFailure.input);
      }
      if (!width.isFinite ||
          width <= 0 ||
          width > 16384 ||
          !rowIsolationPitch.isFinite ||
          rowIsolationPitch <= 0 ||
          rowIsolationPitch > 16384 ||
          maxLines <= 0 ||
          maxGroupLines <= 0 ||
          maxGroupLines > 64 ||
          !maxHeight.isFinite ||
          maxHeight <= 0) {
        throw ArgumentError('Invalid emphasis paragraph budget');
      }
    } catch (_) {
      close();
      rethrow;
    }
  }
  final double width, maxHeight;
  final bool captureIntrinsicWidths;
  final int maxLines, maxGroupLines;
  ForumBodyParagraphContent? _content;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  TextScaler? _callerScaler;
  _ParagraphScaler? _scaler;
  Map<double, double> _scales = {};
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyParagraphPaintInput? _paintInput;
  List<ForumBodyParagraphContent> _paintContents = const [];
  final _paintParents = <ForumBodyParagraphLease>[];
  final _paintPhases = <ForumBodyEmphasisMeasuredPaintPhase>[];
  ForumBodyEmphasisAllocatedSceneInputPreparation? _sceneInputJob;
  ForumBodyEmphasisAllocatedSceneInput? _sceneInput;
  int _paintLayer = 0, _releasedParent = 0;
  ForumBodyTextRequestPreparation? _requestJob;
  ForumBodyParagraphBudgetProbe? _probe;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  bool _prefixStarted = false;
  int _probeParent = 0, _style = -1, _start = 0, _row = 0;
  double _pitch, _height = 0, _emptyBaseline = 0;
  bool _terminal = false;
  ForumBodyParagraphLease? _natural, _isolated;
  ({double minimum, double preferred})? _intrinsicWidths;
  ForumBodyParagraphLineFramePreparation? _frameJob;
  ForumBodyParagraphLineFrames? _naturalFrames, _isolatedFrames;
  ForumBodyParagraphRowReferencePreparation? _referenceJob;
  ForumBodyParagraphRowReference? _reference;
  ForumBodyParagraphRowPreparation? _groupJob;
  ForumBodyParagraphRowMetrics? _group;
  ForumBodyParagraphPhysicalLinePreparation? _physicalJob;
  ForumBodyEmphasisRowAllocationPreparation? _allocationJob;
  ForumBodyEmphasisRowAllocation? _allocation;
  List<ForumBodyEmphasisParagraphGroup>? _groups = [];
  List<ForumBodyParagraphLine>? _lines = [];
  ForumBodyEmphasisParagraphMetrics? _result;
  int _retainedText = 0;
  bool _operating = false, _cacheMiss = false;
  var _phase = _ParagraphPhase.setup;
  bool get isReady => _phase == _ParagraphPhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    if (_natural?.isActive == true) yield _natural!;
    if (_isolated?.isActive == true) yield _isolated!;
    yield* _paintParents.where((parent) => parent.isActive);
    if (_requestJob != null) yield* _requestJob!.nativeLeases;
  }

  Iterable<ForumBodyNativeParagraphLease> _otherOwned() sync* {
    final extra =
        _additionalOwned?.call() ?? const <ForumBodyNativeParagraphLease>[];
    _guard();
    yield* extra;
    if (_natural?.isActive == true) yield _natural!;
    if (_isolated?.isActive == true) yield _isolated!;
    yield* _paintParents.where((parent) => parent.isActive);
  }

  ForumBodyEmphasisLineStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) {
      throw StateError('Emphasis paragraph preparation is reentrant');
    }
    _operating = true;
    final cache = _cache,
        builds = cache?.layoutBuildCount ?? 0,
        pictures = cache?.pictureBuildCount ?? 0;
    var used = 0;
    ForumBodyEmphasisLineStep step([bool waiting = false]) => (
      partsPrepared: used,
      nativeLayoutsBuilt: (cache?.layoutBuildCount ?? builds) - builds,
      picturesRecorded: (cache?.pictureBuildCount ?? pictures) - pictures,
      waitingForLayoutBudget: waiting,
    );
    try {
      _guard();
      _cacheMiss = false;
      while (used < maxParts && !isReady && cache!.layoutBuildCount == builds) {
        _guard();
        try {
          switch (_phase) {
            case _ParagraphPhase.setup:
              _paintInput = ForumBodyParagraphPaintInput(_content!);
              _paintContents = [
                _paintInput!.background,
                _paintInput!.foreground,
                _paintInput!.decoration,
              ];
              _phase = _ParagraphPhase.scales;
            case _ParagraphPhase.scales:
              final content = _content!;
              if (_style < content.runs.length) {
                final style = _style < 0
                    ? content.style
                    : content.runs[_style].style;
                _sample(style.textStyle.fontSize!);
                _style++;
              } else {
                _scaler = _ParagraphScaler(UnmodifiableMapView(_scales));
                _scales = {};
                _callerScaler = null;
                _probe = cache.createBudgetProbe();
                _phase = _ParagraphPhase.prefix;
              }
            case _ParagraphPhase.prefix:
              if (!_prefixStarted) {
                final values =
                    _additionalOwned?.call() ??
                    const <ForumBodyNativeParagraphLease>[];
                _guard();
                _prefix = values.iterator;
                _prefixStarted = true;
              } else if (_prefix!.moveNext()) {
                _guard();
                _probe!.includeLease(_prefix!.current);
              } else {
                _prefix = null;
                _phase = _ParagraphPhase.probe;
              }
            case _ParagraphPhase.probe:
              if (_probeParent < (_content!.projection.text.isEmpty ? 2 : 5)) {
                final index = _probeParent++;
                ForumBodyTextRequest.paragraph(
                  index < 2 ? _content! : _paintContents[index - 2],
                  rowIsolationPitch: index == 0 ? null : _pitch,
                ).includeBudget(_probe!, width: width, textScaler: _scaler!);
              } else {
                _probe!.close();
                _probe = null;
                _phase = _ParagraphPhase.natural;
              }
            case _ParagraphPhase.natural:
            case _ParagraphPhase.isolated:
              final isolated = _phase == _ParagraphPhase.isolated;
              _requestJob ??= ForumBodyTextRequestPreparation(
                cache: cache,
                request: ForumBodyTextRequest.paragraph(
                  _content!,
                  rowIsolationPitch: isolated ? _pitch : null,
                ),
                ensureOwner: _guard,
                preparePaint: false,
                width: width,
                textScaler: _scaler!,
                additionalOwnedLeases: _otherOwned,
              );
              final work = _requestJob!.advance(cachedOnly: cachedOnly);
              if (work.waiting || work.cacheMiss) {
                _cacheMiss = work.cacheMiss;
                used += work.units;
                return step(work.waiting);
              }
              if (_requestJob!.isReady) {
                final lease =
                    _requestJob!.takeLease() as ForumBodyParagraphLease;
                _requestJob = null;
                if (isolated) {
                  _isolated = lease;
                  _referenceJob = ForumBodyParagraphRowReferencePreparation(
                    natural: _natural!,
                    isolated: lease,
                    ensureOwner: _guard,
                    maxLines: maxLines,
                  );
                  _phase = _ParagraphPhase.reference;
                } else {
                  _natural = lease;
                  _emptyBaseline = lease.layout.alphabeticBaseline;
                  _terminal = lease.layout.hasTerminalEmptyLine;
                  _frameJob = ForumBodyParagraphLineFramePreparation(
                    parent: lease,
                    ensureOwner: _guard,
                    maxLines: maxLines,
                  );
                  _phase = _ParagraphPhase.naturalFrames;
                }
              }
            case _ParagraphPhase.naturalFrames:
            case _ParagraphPhase.isolatedFrames:
              final natural = _phase == _ParagraphPhase.naturalFrames;
              _frameJob!.advance(maxParts: 1);
              if (_frameJob!.isReady) {
                final frames = _frameJob!.takeFrames();
                _frameJob = null;
                if (natural) {
                  _naturalFrames = frames;
                  _phase = _ParagraphPhase.isolated;
                } else {
                  _isolatedFrames = frames;
                  _phase = _reference!.lineCount == 0
                      ? _ParagraphPhase.group
                      : _ParagraphPhase.paintParent;
                }
              }
            case _ParagraphPhase.paintParent:
              _requestJob ??= ForumBodyTextRequestPreparation(
                cache: cache,
                request: ForumBodyTextRequest.paragraph(
                  _paintContents[_paintLayer],
                  rowIsolationPitch: _pitch,
                ),
                ensureOwner: _guard,
                preparePaint: false,
                width: width,
                textScaler: _scaler!,
                additionalOwnedLeases: _otherOwned,
              );
              final work = _requestJob!.advance(cachedOnly: cachedOnly);
              if (work.waiting || work.cacheMiss) {
                _cacheMiss = work.cacheMiss;
                used += work.units;
                return step(work.waiting);
              }
              if (_requestJob!.isReady) {
                final parent =
                    _requestJob!.takeLease() as ForumBodyParagraphLease;
                _requestJob = null;
                _paintParents.add(parent);
                _frameJob = ForumBodyParagraphLineFramePreparation(
                  parent: parent,
                  ensureOwner: _guard,
                  maxLines: maxLines,
                );
                _phase = _ParagraphPhase.paintFrames;
              }
            case _ParagraphPhase.paintFrames:
              _frameJob!.advance(maxParts: 1);
              if (_frameJob!.isReady) {
                final frames = _frameJob!.takeFrames();
                _frameJob = null;
                _paintPhases.add((parent: _paintParents.last, frames: frames));
                _paintLayer++;
                _phase = _paintLayer < 3
                    ? _ParagraphPhase.paintParent
                    : _ParagraphPhase.group;
              }
            case _ParagraphPhase.reference:
              _referenceJob!.advance(maxParts: 1);
              if (_referenceJob!.isReady) {
                _reference = _referenceJob!.takeReference();
                _referenceJob = null;
                _frameJob = ForumBodyParagraphLineFramePreparation(
                  parent: _isolated!,
                  ensureOwner: _guard,
                  maxLines: maxLines,
                );
                _phase = _ParagraphPhase.isolatedFrames;
              }
            case _ParagraphPhase.group:
              if (_start == _reference!.lineCount) {
                if (_lines!.length != _reference!.lineCount ||
                    (_groups!.isNotEmpty &&
                        _groups!.last.endUtf16 !=
                            _content!.projection.text.length)) {
                  _fail(ForumBodyEmphasisParagraphFailure.geometry);
                }
                if (_groups!.isEmpty) _height = _natural!.layout.height;
                _phase = _ParagraphPhase.release;
              } else {
                _groupJob ??= ForumBodyParagraphRowPreparation(
                  parent: _isolated!,
                  startLine: _start,
                  ensureOwner: _guard,
                  maxLines: maxGroupLines,
                );
                _groupJob!.advance(maxParts: 1);
                if (_groupJob!.isReady) {
                  _group = _groupJob!.takeMetrics();
                  _groupJob = null;
                  _physicalJob = ForumBodyParagraphPhysicalLinePreparation(
                    group: ForumBodyParagraphRowView.bind(
                      parent: _isolated!,
                      metrics: _group!,
                      ensureOwner: _guard,
                    ),
                    frames: _isolatedFrames!,
                    ensureOwner: _guard,
                  );
                  _phase = _ParagraphPhase.physical;
                }
              }
            case _ParagraphPhase.physical:
              _physicalJob!.advance(maxParts: 1);
              if (_physicalJob!.isReady) {
                final physical = _physicalJob!.takeSelectors();
                _physicalJob = null;
                if (_height >= maxHeight) {
                  _fail(ForumBodyEmphasisParagraphFailure.limit);
                }
                _allocationJob = ForumBodyEmphasisRowAllocationPreparation(
                  source: _group!,
                  textScaler: _scaler!,
                  reference: _reference!,
                  naturalFrames: _naturalFrames!,
                  isolatedFrames: _isolatedFrames!,
                  physicalLines: physical,
                  ensureOwner: _guard,
                  maxLines: maxGroupLines,
                  maxHeight: maxHeight - _height,
                  paintInput: _paintInput!,
                );
                _phase = _ParagraphPhase.allocate;
              }
            case _ParagraphPhase.allocate:
              _allocationJob!.advance(maxParts: 1);
              if (_allocationJob!.isReady) {
                _allocation = _allocationJob!.takeAllocation();
                _allocationJob = null;
                _sceneInputJob =
                    ForumBodyEmphasisAllocatedSceneInputPreparation(
                      allocation: _allocation!,
                      source: _isolated!,
                      phases: _paintPhases,
                      ensureOwner: _guard,
                    );
                _phase = _ParagraphPhase.sceneInput;
              }
            case _ParagraphPhase.sceneInput:
              _sceneInputJob!.advance(maxParts: 1);
              if (_sceneInputJob!.isReady) {
                _sceneInput = _sceneInputJob!.takeInput();
                _sceneInputJob = null;
                _row = 0;
                _phase = _ParagraphPhase.lines;
              }
            case _ParagraphPhase.lines:
              if (_row < _allocation!.rows.length) {
                final row = _allocation!.rows[_row++];
                _lines!.add(
                  _placeLine(
                    _reference!.naturalLines[row.physicalLine.lineIndex],
                    row,
                    _height,
                  ),
                );
              } else {
                _phase = _ParagraphPhase.commit;
              }
            case _ParagraphPhase.commit:
              if (_group!.startUtf16 !=
                      (_groups!.isEmpty ? 0 : _groups!.last.endUtf16) ||
                  _height + _allocation!.height > maxHeight) {
                _fail(ForumBodyEmphasisParagraphFailure.geometry);
              }
              _groups!.add(
                ForumBodyEmphasisParagraphGroup._(_sceneInput!, _height),
              );
              _height += _allocation!.height;
              _retainedText += _group!.content.projection.text.length;
              _start = _group!.selector.endLine;
              _group = null;
              _allocation = null;
              _sceneInput = null;
              _phase = _ParagraphPhase.group;
            case _ParagraphPhase.release:
              if (_releasedParent < _paintParents.length) {
                _paintParents[_releasedParent++].release();
                _guard();
                break;
              }
              _paintParents.clear();
              _paintPhases.clear();
              final natural = _natural!;
              if (captureIntrinsicWidths) {
                _intrinsicWidths = natural.layout.intrinsicWidths;
              }
              _natural = null;
              natural.release();
              _guard();
              final isolated = _isolated!;
              _isolated = null;
              isolated.release();
              _guard();
              _phase = _ParagraphPhase.publish;
            case _ParagraphPhase.publish:
              if (!_height.isFinite || _height < 0 || _height > maxHeight) {
                _fail(ForumBodyEmphasisParagraphFailure.limit);
              }
              _result = ForumBodyEmphasisParagraphMetrics._(
                content: _content!,
                reference: _reference!,
                groups: _groups!,
                lines: _lines!,
                textScaler: _scaler!,
                height: _height,
                intrinsicWidths: _intrinsicWidths,
                alphabeticBaseline: _lines!.isEmpty
                    ? _emptyBaseline
                    : _lines!.first.baseline,
                hasTerminalEmptyLine: _terminal,
                retainedTextCodeUnits:
                    _content!.projection.text.length + _retainedText,
                retainedRuns: _content!.runs.length,
              );
              _groups = null;
              _lines = null;
              _phase = _ParagraphPhase.ready;
            case _ParagraphPhase.ready:
            case _ParagraphPhase.transferred:
            case _ParagraphPhase.closed:
              throw StateError('Emphasis paragraph preparation is retired');
          }
        } on ForumBodyParagraphRowException catch (error) {
          if (error.failure != ForumBodyParagraphRowFailure.isolation) rethrow;
          _retryIsolation(error);
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

  void _sample(double size) {
    if (_scales.containsKey(size)) return;
    final value = _callerScaler!.scale(size);
    _guard();
    if (!size.isFinite ||
        size <= 0 ||
        !value.isFinite ||
        value <= 0 ||
        value > 4096) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.scale,
      );
    }
    _scales[size] = value;
  }

  void _retryIsolation(ForumBodyParagraphRowException error) {
    final required = error.requiredPitch;
    if (required == null || !required.isFinite || required <= _pitch) {
      throw error;
    }
    final next = math.max(required, _pitch * 2);
    if (next > 16384) throw error;
    _groupJob?.close();
    _groupJob = null;
    _physicalJob?.close();
    _physicalJob = null;
    _allocationJob?.close();
    _allocationJob = null;
    _sceneInputJob?.close();
    _sceneInputJob = null;
    _releasePaintParents();
    _guard();
    _paintLayer = 0;
    final isolated = _isolated;
    _isolated = null;
    isolated?.release();
    _guard();
    _reference = null;
    _isolatedFrames = null;
    _group = null;
    _allocation = null;
    _sceneInput = null;
    _groups = [];
    _lines = [];
    _height = 0;
    _retainedText = 0;
    _start = 0;
    _pitch = next;
    _phase = _ParagraphPhase.isolated;
  }

  ForumBodyEmphasisParagraphMetrics takeMetrics() {
    if (_operating) {
      throw StateError('Emphasis paragraph preparation is reentrant');
    }
    _operating = true;
    try {
      _guard();
      if (!isReady) {
        throw StateError('Emphasis paragraph preparation is incomplete');
      }
      final result = _result!;
      _result = null;
      _phase = _ParagraphPhase.transferred;
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
    if (_phase == _ParagraphPhase.closed ||
        _phase == _ParagraphPhase.transferred) {
      throw StateError('Emphasis paragraph preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _ParagraphPhase.closed ||
        _cache?.isClosed != false ||
        (_natural != null && !_cache!.ownsLease(_natural!)) ||
        (_isolated != null && !_cache!.ownsLease(_isolated!))) {
      throw StateError('Emphasis paragraph owner is retired');
    }
  }

  static ForumBodyParagraphLine _placeLine(
    ForumBodyParagraphLine source,
    ForumBodyEmphasisAllocatedRow row,
    double top,
  ) => source.withVerticalFrame(
    top: top + row.flowTop,
    bottom: top + row.flowBottom,
    baseline: top + row.alphabeticBaseline,
  );

  static Never _fail(ForumBodyEmphasisParagraphFailure failure) =>
      throw ForumBodyEmphasisParagraphException(failure);
  void _dropInputs() {
    _content = null;
    _cache = null;
    _ensureOwner = null;
    _callerScaler = null;
    _scaler = null;
    _scales = {};
    _additionalOwned = null;
    _prefix = null;
    _naturalFrames = null;
    _isolatedFrames = null;
    _reference = null;
    _group = null;
    _allocation = null;
    _paintInput = null;
    _paintContents = const [];
    _sceneInput = null;
    _groups = null;
    _lines = null;
    _result = null;
  }

  void _releasePaintParents() {
    final parents = List<ForumBodyParagraphLease>.of(_paintParents);
    _paintParents.clear();
    _paintPhases.clear();
    Object? failure;
    StackTrace? stack;
    for (final parent in parents) {
      try {
        parent.release();
      } catch (error, trace) {
        failure ??= error;
        stack ??= trace;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, stack!);
  }

  void close() {
    if (_phase == _ParagraphPhase.closed ||
        _phase == _ParagraphPhase.transferred) {
      return;
    }
    _phase = _ParagraphPhase.closed;
    try {
      _requestJob?.close();
      _requestJob = null;
      _frameJob?.close();
      _frameJob = null;
      _referenceJob?.close();
      _referenceJob = null;
      _groupJob?.close();
      _groupJob = null;
      _physicalJob?.close();
      _physicalJob = null;
      _allocationJob?.close();
      _allocationJob = null;
      _sceneInputJob?.close();
      _sceneInputJob = null;
    } finally {
      try {
        _natural?.release();
      } finally {
        _natural = null;
        try {
          _isolated?.release();
        } finally {
          _isolated = null;
          try {
            _releasePaintParents();
          } finally {
            _probe?.close();
            _probe = null;
            _dropInputs();
          }
        }
      }
    }
  }
}

final class _ParagraphScaler extends TextScaler {
  const _ParagraphScaler(this.values);
  final Map<double, double> values;
  @override
  double scale(double size) =>
      values[size] ?? (throw StateError('Emphasis font size was not captured'));
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}
