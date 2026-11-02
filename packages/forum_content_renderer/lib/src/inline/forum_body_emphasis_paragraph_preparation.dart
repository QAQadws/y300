part of 'forum_body_emphasis_paragraph_metrics.dart';

enum _ParagraphPhase {
  glyphs,
  scales,
  prefix,
  probe,
  natural,
  naturalFrames,
  isolated,
  reference,
  isolatedFrames,
  group,
  source,
  measure,
  physical,
  allocate,
  lines,
  commit,
  release,
  publish,
  ready,
  transferred,
  closed,
}

/// The shared-cache numeric transaction for a whole wrapping emphasis context.
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
    this.maxGroupMarks = 512,
    this.maxMarks = 32768,
    this.maxHeight = 1048576,
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
          maxGroupMarks < 0 ||
          maxGroupMarks > 512 ||
          maxMarks < 0 ||
          !maxHeight.isFinite ||
          maxHeight <= 0) {
        throw ArgumentError('Invalid emphasis paragraph budget');
      }
      _glyphJob = ForumBodyEmphasisGlyphPreparation(content: content);
    } catch (_) {
      close();
      rethrow;
    }
  }
  final double width, maxHeight;
  final int maxLines, maxGroupLines, maxGroupMarks, maxMarks;
  ForumBodyParagraphContent? _content;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  TextScaler? _callerScaler;
  _ParagraphScaler? _scaler;
  Map<double, double> _scales = {};
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyEmphasisGlyphPreparation? _glyphJob;
  ForumBodyEmphasisGlyphInput? _glyphs;
  ForumBodyTextRequestPreparation? _requestJob;
  ForumBodyParagraphBudgetProbe? _probe;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  bool _prefixStarted = false;
  int _probeParent = 0, _style = -1, _start = 0, _row = 0;
  double _pitch, _height = 0, _emptyBaseline = 0;
  bool _terminal = false;
  ForumBodyParagraphLease? _natural, _isolated;
  ForumBodyParagraphLineFramePreparation? _frameJob;
  ForumBodyParagraphLineFrames? _naturalFrames, _isolatedFrames;
  ForumBodyParagraphRowReferencePreparation? _referenceJob;
  ForumBodyParagraphRowReference? _reference;
  ForumBodyParagraphRowPreparation? _groupJob;
  ForumBodyParagraphRowMetrics? _group;
  ForumBodyEmphasisRowInputPreparation? _sourceJob;
  ForumBodyEmphasisRowInput? _source;
  ForumBodyEmphasisLineMetricsPreparation? _measureJob;
  ForumBodyEmphasisLineMetrics? _measurement;
  ForumBodyParagraphPhysicalLinePreparation? _physicalJob;
  ForumBodyEmphasisRowAllocationPreparation? _allocationJob;
  ForumBodyEmphasisRowAllocation? _allocation;
  List<ForumBodyEmphasisParagraphGroup>? _groups = [];
  List<ForumBodyParagraphLine>? _lines = [];
  ForumBodyEmphasisParagraphMetrics? _result;
  int _marks = 0, _retainedText = 0, _retainedRuns = 0;
  bool _operating = false, _cacheMiss = false;
  var _phase = _ParagraphPhase.glyphs;
  bool get isReady => _phase == _ParagraphPhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    if (_natural?.isActive == true) yield _natural!;
    if (_isolated?.isActive == true) yield _isolated!;
    if (_requestJob != null) yield* _requestJob!.nativeLeases;
    if (_measureJob != null) yield* _measureJob!.nativeLeases;
  }

  Iterable<ForumBodyNativeParagraphLease> _otherOwned() sync* {
    final extra =
        _additionalOwned?.call() ?? const <ForumBodyNativeParagraphLease>[];
    _guard();
    yield* extra;
    if (_natural?.isActive == true) yield _natural!;
    if (_isolated?.isActive == true) yield _isolated!;
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
            case _ParagraphPhase.glyphs:
              _glyphJob!.advance(maxParts: 1);
              if (_glyphJob!.isReady) {
                _glyphs = _glyphJob!.takeInput();
                _glyphJob = null;
                _phase = _ParagraphPhase.scales;
              }
            case _ParagraphPhase.scales:
              final content = _content!;
              if (_style < content.runs.length) {
                final style = _style < 0
                    ? content.style
                    : content.runs[_style].style;
                _sample(style.textStyle.fontSize!);
                if (style.textEmphasis.isEnabled) {
                  _sample(style.textStyle.fontSize! * .5);
                }
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
              if (_probeParent < 2) {
                ForumBodyTextRequest.paragraph(
                  _glyphs!.glyphs,
                  rowIsolationPitch: _probeParent++ == 0 ? null : _pitch,
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
                  _glyphs!.glyphs,
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
                  _phase = _ParagraphPhase.group;
                }
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
                _retainedRuns =
                    _content!.runs.length +
                    (identical(_glyphs!.glyphs.runs, _content!.runs)
                        ? 0
                        : _glyphs!.glyphs.runs.length);
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
                  _sourceJob = ForumBodyEmphasisRowInputPreparation(
                    parentGlyphInput: _glyphs!,
                    row: _group!,
                    maxUnits: maxGroupMarks,
                  );
                  _phase = _ParagraphPhase.source;
                }
              }
            case _ParagraphPhase.source:
              _sourceJob!.advance(maxParts: 1);
              if (_sourceJob!.isReady) {
                _source = _sourceJob!.takeInput();
                _sourceJob = null;
                if (_source!.text.units.length > maxMarks - _marks) {
                  _fail(ForumBodyEmphasisParagraphFailure.limit);
                }
                _measureJob = ForumBodyEmphasisLineMetricsPreparation.row(
                  input: _source!,
                  cache: cache,
                  ensureOwner: _guard,
                  textScaler: _scaler!,
                  additionalOwnedLeases: _otherOwned,
                );
                _phase = _ParagraphPhase.measure;
              }
            case _ParagraphPhase.measure:
              final work = _measureJob!.advance(
                maxParts: 1,
                cachedOnly: cachedOnly,
              );
              if (work.waitingForLayoutBudget || _measureJob!.cacheMiss) {
                _cacheMiss = _measureJob!.cacheMiss;
                used += work.partsPrepared;
                return step(work.waitingForLayoutBudget);
              }
              if (_measureJob!.isReady) {
                _measurement = _measureJob!.takeMetrics();
                _measureJob = null;
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
            case _ParagraphPhase.physical:
              _physicalJob!.advance(maxParts: 1);
              if (_physicalJob!.isReady) {
                final physical = _physicalJob!.takeSelectors();
                _physicalJob = null;
                if (_height >= maxHeight) {
                  _fail(ForumBodyEmphasisParagraphFailure.limit);
                }
                _allocationJob = ForumBodyEmphasisRowAllocationPreparation(
                  source: _measurement!,
                  reference: _reference!,
                  naturalFrames: _naturalFrames!,
                  isolatedFrames: _isolatedFrames!,
                  physicalLines: physical,
                  ensureOwner: _guard,
                  maxLines: maxGroupLines,
                  maxMarks: maxGroupMarks,
                  maxHeight: maxHeight - _height,
                );
                _phase = _ParagraphPhase.allocate;
              }
            case _ParagraphPhase.allocate:
              _allocationJob!.advance(maxParts: 1);
              if (_allocationJob!.isReady) {
                _allocation = _allocationJob!.takeAllocation();
                _allocationJob = null;
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
                ForumBodyEmphasisParagraphGroup._(_allocation!, _height),
              );
              _height += _allocation!.height;
              _marks += _allocation!.marks.length;
              // Two distinct local projections survive: measured glyph row and
              // original source/glyph window. Full run tables remain shared.
              _retainedText +=
                  _source!.content.projection.text.length +
                  _group!.content.projection.text.length;
              _start = _group!.selector.endLine;
              _group = null;
              _source = null;
              _measurement = null;
              _allocation = null;
              _phase = _ParagraphPhase.group;
            case _ParagraphPhase.release:
              final natural = _natural!;
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
                glyphInput: _glyphs!,
                reference: _reference!,
                groups: _groups!,
                lines: _lines!,
                textScaler: _scaler!,
                height: _height,
                alphabeticBaseline: _lines!.isEmpty
                    ? _emptyBaseline
                    : _lines!.first.baseline,
                hasTerminalEmptyLine: _terminal,
                markCount: _marks,
                retainedTextCodeUnits:
                    _content!.projection.text.length + _retainedText,
                retainedRuns: _retainedRuns,
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
    _sourceJob?.close();
    _sourceJob = null;
    _measureJob?.close();
    _measureJob = null;
    _physicalJob?.close();
    _physicalJob = null;
    _allocationJob?.close();
    _allocationJob = null;
    final isolated = _isolated;
    _isolated = null;
    isolated?.release();
    _guard();
    _reference = null;
    _isolatedFrames = null;
    _group = null;
    _source = null;
    _measurement = null;
    _allocation = null;
    _groups = [];
    _lines = [];
    _height = 0;
    _marks = 0;
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
  ) => ForumBodyParagraphLine(
    top: top + row.flowTop,
    bottom: top + row.flowBottom,
    baseline: top + row.alphabeticBaseline,
    left: source.left,
    width: source.width,
    startUtf16: source.startUtf16,
    endUtf16: source.endUtf16,
    coverageStartUtf16: source.coverageStartUtf16,
    coverageEndUtf16: source.coverageEndUtf16,
    engineStartUtf16: source.engineStartUtf16,
    engineEndUtf16: source.engineEndUtf16,
    engineCoverageStartUtf16: source.engineCoverageStartUtf16,
    engineCoverageEndUtf16: source.engineCoverageEndUtf16,
    unpaintedTrailingSpaceStartUtf16: source.unpaintedTrailingSpaceStartUtf16,
    engineUnpaintedTrailingSpaceStartUtf16:
        source.engineUnpaintedTrailingSpaceStartUtf16,
    canBreakBefore: source.canBreakBefore,
    canBreakAfter: source.canBreakAfter,
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
    _glyphs = null;
    _naturalFrames = null;
    _isolatedFrames = null;
    _reference = null;
    _group = null;
    _source = null;
    _measurement = null;
    _allocation = null;
    _groups = null;
    _lines = null;
    _result = null;
  }

  void close() {
    if (_phase == _ParagraphPhase.closed ||
        _phase == _ParagraphPhase.transferred) {
      return;
    }
    _phase = _ParagraphPhase.closed;
    try {
      _glyphJob?.close();
      _glyphJob = null;
      _requestJob?.close();
      _requestJob = null;
      _frameJob?.close();
      _frameJob = null;
      _referenceJob?.close();
      _referenceJob = null;
      _groupJob?.close();
      _groupJob = null;
      _sourceJob?.close();
      _sourceJob = null;
      _measureJob?.close();
      _measureJob = null;
      _physicalJob?.close();
      _physicalJob = null;
      _allocationJob?.close();
      _allocationJob = null;
    } finally {
      try {
        _natural?.release();
      } finally {
        _natural = null;
        _isolated?.release();
        _isolated = null;
        _probe?.close();
        _probe = null;
        _dropInputs();
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
