part of 'forum_body_emphasis_line_layout.dart';

enum _LinePhase {
  verifyScales,
  fonts,
  inputs,
  probePrefix,
  probeBase,
  probeMarks,
  base,
  geometry,
  queryBounds,
  bounds,
  marks,
  place,
  alignMarks,
  frame,
  commands,
  sealMetrics,
  bindingPaint,
  basePaint,
  scene,
  releaseMarks,
  releaseBase,
  publish,
  ready,
  transferred,
  closed,
}

typedef ForumBodyEmphasisLineStep = ({
  int partsPrepared,
  int nativeLayoutsBuilt,
  int picturesRecorded,
  bool waitingForLayoutBudget,
});

typedef _RawMark = ({int unit, int mark, int line, Offset offset, Rect bounds});

/// One actual physical row, not a chapter-wide annotation baseline. Font
/// fallback and mixed sizes share its side metrics; source groups stay intact.
final class _LineMarkAlignment {
  double? overTop, underBottom;
  double overDescent = 0, underAscent = 0;
  void include(
    Rect base,
    double ascent,
    double descent,
    ForumBodyEmphasisSide side,
  ) {
    if (side == ForumBodyEmphasisSide.over) {
      if (overTop == null || base.top < overTop!) overTop = base.top;
      if (descent > overDescent) overDescent = descent;
    } else {
      if (underBottom == null || base.bottom > underBottom!) {
        underBottom = base.bottom;
      }
      if (ascent > underAscent) underAscent = ascent;
    }
  }

  double baseline(ForumBodyEmphasisSide side) =>
      side == ForumBodyEmphasisSide.over
      ? overTop! - overDescent
      : underBottom! + underAscent;
}

/// One cooperative transaction over the owner's existing native cache. The
/// caller's full/half-size scaler samples freeze before any native request.
/// An optional page prefix is borrowed for admission and pin classification;
/// cancellation never releases those caller-owned handles.
final class ForumBodyEmphasisLinePreparation {
  ForumBodyEmphasisLinePreparation.row({
    required ForumBodyEmphasisRowInput input,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    void Function()? ensureVisibleOwner,
    TextScaler textScaler = TextScaler.noScaling,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : this._work(
         input: input.text,
         rowInput: input,
         cache: cache,
         ensureOwner: ensureOwner,
         ensureVisibleOwner: ensureVisibleOwner,
         width: input.row.width,
         textScaler: textScaler,
         measureOnly: false,
         additionalOwnedLeases: additionalOwnedLeases,
       );

  ForumBodyEmphasisLinePreparation({
    required ForumBodyEmphasisTextInput input,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    void Function()? ensureVisibleOwner,
    ForumBodyTextRequest? baseRequest,
    double width = 16384,
    TextScaler textScaler = TextScaler.noScaling,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : this._work(
         input: input,
         cache: cache,
         ensureOwner: ensureOwner,
         ensureVisibleOwner: ensureVisibleOwner,
         baseRequest: baseRequest,
         width: width,
         textScaler: textScaler,
         measureOnly: false,
         additionalOwnedLeases: additionalOwnedLeases,
       );

  /// Rebind a pure plan to current source/fonts. The current caller supplies
  /// width and actual scaling; equal-size text cannot substitute its source.
  ForumBodyEmphasisLinePreparation.fromMetrics({
    required ForumBodyEmphasisTextInput input,
    required ForumBodyEmphasisLineMetrics metrics,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    void Function()? ensureVisibleOwner,
    required double width,
    required TextScaler expectedTextScaler,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : this._work(
         input: input,
         cache: cache,
         ensureOwner: ensureOwner,
         ensureVisibleOwner: ensureVisibleOwner,
         baseRequest: metrics.baseRequest,
         rowInput: metrics.rowInput,
         width: width,
         textScaler: expectedTextScaler,
         measureOnly: false,
         metrics: metrics,
         additionalOwnedLeases: additionalOwnedLeases,
       );

  ForumBodyEmphasisLinePreparation._work({
    required ForumBodyEmphasisTextInput input,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    void Function()? ensureVisibleOwner,
    required this.width,
    required TextScaler textScaler,
    required bool measureOnly,
    bool bindOnly = false,
    bool prepareBindingPaint = false,
    ForumBodyTextRequest? baseRequest,
    ForumBodyEmphasisLineMetrics? metrics,
    ForumBodyEmphasisRowInput? rowInput,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _input = input,
       _rowInput = rowInput,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _ensureVisibleOwner = ensureVisibleOwner ?? ensureOwner,
       _callerScaler = textScaler,
       _measureOnly = measureOnly,
       _bindOnly = bindOnly,
       _prepareBindingPaint = prepareBindingPaint,
       _expected = metrics,
       _additionalOwned = additionalOwnedLeases,
       _request =
           baseRequest ??
           ForumBodyTextRequest.paragraph(
             rowInput?.parentGlyphInput.glyphs ?? input.glyphInput.glyphs,
             rowIsolationPitch: rowInput?.row.rowIsolationPitch,
           ) {
    try {
      _guard();
      if (bindOnly && metrics == null) {
        _mismatch();
      }
      if (!width.isFinite || width <= 0 || width > 16384) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.width,
        );
      }
      if (!identical(
            _request!.content,
            rowInput?.parentGlyphInput.glyphs ?? input.glyphInput.glyphs,
          ) ||
          (rowInput != null &&
              (!identical(input, rowInput.text) ||
                  width != rowInput.row.width ||
                  _request is! ForumBodyParagraphTextRequest ||
                  (_request as ForumBodyParagraphTextRequest)
                          .rowIsolationPitch !=
                      rowInput.row.rowIsolationPitch))) {
        throw const ForumBodyEmphasisLineException(
          ForumBodyEmphasisLineFailure.source,
        );
      }
      if (metrics != null &&
          (!identical(input, metrics.input) ||
              !identical(rowInput, metrics.rowInput) ||
              width != metrics.requestWidth)) {
        _mismatch();
      }
      if (input.units.length > 512) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.inputLimit,
          input.content.path,
        );
      }
      _contexts = switch (_request!) {
        ForumBodyParagraphTextRequest() => [_request!.content],
        ForumBodyTextBandChildRequest value => value.band.contexts,
      };
      if (metrics != null) {
        _contexts = const [];
        _scaler = metrics.textScaler as _LineScaler;
        _scaleChecks = metrics.effectiveScales.entries.iterator;
        _markInputs = metrics._markInputs;
        _unitMarks = metrics._unitMarks;
        _phase = _LinePhase.verifyScales;
      }
    } catch (_) {
      close();
      rethrow;
    }
  }
  final double width;
  final bool _measureOnly;
  final bool _bindOnly;
  final bool _prepareBindingPaint;
  ForumBodyEmphasisLineMetrics? _expected;
  Iterator<MapEntry<double, double>>? _scaleChecks;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  bool _prefixStarted = false;
  ForumBodyEmphasisTextInput? _input;
  ForumBodyEmphasisRowInput? _rowInput;
  ForumBodyParagraphRowView? _rowView;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner, _ensureVisibleOwner;
  ForumBodyTextRequest? _request;
  TextScaler? _callerScaler;
  List<ForumBodyParagraphContent> _contexts = const [];
  Map<double, double> _scales = {};
  _LineScaler? _scaler;
  var _context = 0, _run = -1, _index = 0, _blockedAt = -1;
  List<ForumBodyEmphasisMarkInput> _markInputs = [];
  final _markIndex = <ForumBodyEmphasisMarkInput, int>{};
  final _runMarks = <int, int>{};
  List<int> _unitMarks = [];
  List<Object> _markKeys = [];
  List<ForumBodyEmphasisMarkLease> _markLeases = [];
  final _rawMarks = <_RawMark>[];
  List<ForumBodyEmphasisLineMark>? _positioned = [];
  final _commands = <ForumBodyTextPictureCommand>[];
  ForumBodyParagraphBudgetProbe? _probe;
  ForumBodyTextLease? _base;
  ForumBodyEmphasisGeometryPreparation? _geometryJob;
  ForumBodyEmphasisTextGeometry? _geometry;
  List<TextBox>? _fontBoxes;
  Rect? _envelope;
  Rect? _baseFontBounds;
  Offset _baseOffset = Offset.zero;
  double _height = 0;
  final _alignments = <int, _LineMarkAlignment>{};
  ForumBodyTextPicturePreparation? _pictureJob;
  ForumBodyTextPictureLease? _picture;
  ForumBodyEmphasisLineMetrics? _numeric;
  ForumBodyEmphasisLineLayout? _result;
  var _phase = _LinePhase.fonts;
  bool _operating = false;
  bool get isReady => _phase == _LinePhase.ready;
  bool get cacheMiss => _cacheMiss;
  bool _cacheMiss = false;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    if (_base != null) yield _base!;
    for (final mark in _markLeases) {
      if (mark.isActive) yield mark;
    }
    if (_pictureJob != null) yield* _pictureJob!.nativeLeases;
    if (_picture != null) yield _picture!;
    if (_result != null) yield* _result!.nativeLeases;
  }

  void _sample(double? size) {
    if (size == null || !size.isFinite || size <= 0) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.scale,
      );
    }
    if (_scales.containsKey(size)) return;
    final scaled = _callerScaler!.scale(size);
    _guard();
    if (!scaled.isFinite || scaled <= 0 || scaled > 4096) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.scale,
      );
    }
    _scales[size] = scaled;
  }

  ForumBodyEmphasisLineStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Emphasis line preparation is reentrant');
    _operating = true;
    var used = 0, layouts = 0, pictures = 0;
    ForumBodyEmphasisLineStep step([bool waiting = false]) => (
      partsPrepared: used,
      nativeLayoutsBuilt: layouts,
      picturesRecorded: pictures,
      waitingForLayoutBudget: waiting,
    );
    try {
      _guard();
      _cacheMiss = false;
      if (_blockedAt == _cache!.budgetRevision) return step(true);
      while (used < maxParts && !isReady && layouts + pictures == 0) {
        _guard();
        final cache = _cache!, input = _input!;
        final rejectedAt = cache.budgetRevision;
        try {
          switch (_phase) {
            case _LinePhase.verifyScales:
              if (_scaleChecks!.moveNext()) {
                final sample = _scaleChecks!.current;
                final value = _callerScaler!.scale(sample.key);
                _guard();
                if (!value.isFinite ||
                    value <= 0 ||
                    value > 4096 ||
                    value != sample.value) {
                  _mismatch();
                }
              } else {
                _scaleChecks = null;
                _callerScaler = null;
                _probe = cache.createBudgetProbe();
                _phase = _additionalOwned == null
                    ? _LinePhase.probeBase
                    : _LinePhase.probePrefix;
              }
            case _LinePhase.fonts:
              if (_context < _contexts.length) {
                final content = _contexts[_context];
                if (_run < content.runs.length) {
                  final style = _run < 0
                      ? content.style
                      : content.runs[_run].style;
                  _sample(style.textStyle.fontSize);
                  _run++;
                } else {
                  _context++;
                  _run = -1;
                }
              } else {
                _contexts = const [];
                _phase = _LinePhase.inputs;
              }
            case _LinePhase.inputs:
              if (_index < input.units.length) {
                final run = input.units[_index++].runIndex;
                var mark = _runMarks[run];
                if (mark == null) {
                  final value = ForumBodyEmphasisMarkInput(
                    style: input.content.runs[run].style,
                    fontRevision: input.content.fontRevision,
                    styleRevision: input.content.styleRevision,
                  );
                  _sample(value.textStyle.fontSize);
                  mark = _markIndex[value];
                  if (mark == null) {
                    mark = _markInputs.length;
                    _markIndex[value] = mark;
                    _markInputs.add(value);
                  }
                  _runMarks[run] = mark;
                }
                _unitMarks.add(mark);
              } else {
                _scaler = _LineScaler(UnmodifiableMapView(_scales));
                // Native painters may retain this scaler after the job retires.
                // Transfer its map; cleanup must not clear the captured values.
                _scales = {};
                _callerScaler = null;
                _probe = cache.createBudgetProbe();
                _index = 0;
                _phase = _additionalOwned == null
                    ? _LinePhase.probeBase
                    : _LinePhase.probePrefix;
              }
            case _LinePhase.probePrefix:
              if (!_prefixStarted) {
                final prefix = _additionalOwned?.call() ?? const [];
                _guard();
                _prefix = prefix.iterator;
                _prefixStarted = true;
              } else if (_prefix!.moveNext()) {
                _guard();
                _probe!.includeLease(_prefix!.current);
              } else {
                _prefix = null;
                _phase = _LinePhase.probeBase;
              }
            case _LinePhase.probeBase:
              _request!.includeBudget(
                _probe!,
                width: width,
                textScaler: _scaler!,
                minimumLineCount:
                    _rowInput?.row.parentLineCount ??
                    (input.content.projection.text.isEmpty ? 0 : 1),
              );
              _phase = _LinePhase.probeMarks;
            case _LinePhase.probeMarks:
              if (_index < _markInputs.length) {
                _probe!.includeEmphasisMark(
                  input: _markInputs[_index++],
                  textScaler: _scaler!,
                );
              } else {
                // A measured scene is a pure specification. Include its slot
                // before reacquiring fonts, without recording or trusting it.
                if (!_measureOnly && _expected != null) {
                  _probe!.includeTextPicture(_expected!.pictureInput);
                }
                _probe!.close();
                _probe = null;
                _index = 0;
                _phase = _LinePhase.base;
              }
            case _LinePhase.base:
              var found = _request!.acquire(
                cache,
                width: width,
                textScaler: _scaler!,
                cachedOnly: true,
              );
              if (found == null) {
                if (cachedOnly) {
                  _cacheMiss = true;
                  used++;
                  return step();
                }
                found = _request!.acquire(
                  cache,
                  width: width,
                  textScaler: _scaler!,
                  cachedOnly: false,
                )!;
                layouts++;
              }
              try {
                _guard();
              } catch (_) {
                found.release();
                rethrow;
              }
              _base = found;
              if (_expected != null &&
                  found.nativeInputIdentity != _expected!._baseKey) {
                _mismatch();
              }
              final rowInput = _rowInput;
              if (rowInput != null) {
                if (found.nativeInputIdentity !=
                    rowInput.row.nativeInputIdentity) {
                  _mismatch();
                }
                _rowView = ForumBodyParagraphRowView.bind(
                  parent: found as ForumBodyParagraphLease,
                  metrics: rowInput.row,
                  ensureOwner: _guard,
                );
                _guard();
              }
              if (rowInput == null &&
                  found is ForumBodyParagraphLease &&
                  found.layout.lineCount > 1) {
                throw const ForumBodyEmphasisLineException(
                  ForumBodyEmphasisLineFailure.lines,
                );
              }
              _geometryJob = rowInput == null
                  ? ForumBodyEmphasisGeometryPreparation(
                      input: input,
                      base: found,
                      ensureOwner: _guard,
                    )
                  : ForumBodyEmphasisGeometryPreparation.row(
                      input: rowInput,
                      base: _rowView!,
                      ensureOwner: _guard,
                    );
              _phase = _LinePhase.geometry;
            case _LinePhase.geometry:
              final job = _geometryJob!;
              job.advance(maxParts: 1);
              if (job.isReady) {
                _geometry = job.takeGeometry();
                _geometryJob = null;
                _phase = _LinePhase.queryBounds;
              }
            case _LinePhase.queryBounds:
              final layout = _textLayout;
              _envelope = Rect.fromLTWH(0, 0, layout.width, layout.height);
              final boxes = layout.selectionBoxes(
                0,
                input.content.projection.text.length,
              );
              _guard();
              _fontBoxes = boxes;
              if (_fontBoxes!.length > 4096) _invalid();
              _phase = _LinePhase.bounds;
            case _LinePhase.bounds:
              if (_index < _fontBoxes!.length) {
                final box = _fontBoxes![_index++].toRect();
                _checkRect(box);
                _envelope = _envelope!.expandToInclude(box);
              } else {
                _fontBoxes = null;
                _baseFontBounds = _envelope;
                _index = 0;
                _phase = _LinePhase.marks;
              }
            case _LinePhase.marks:
              if (_index < _markInputs.length) {
                final value = _markInputs[_index];
                var found = cache.tryAcquireEmphasisMarkCached(
                  input: value,
                  textScaler: _scaler!,
                );
                if (found == null) {
                  if (cachedOnly) {
                    _cacheMiss = true;
                    used++;
                    return step();
                  }
                  found = cache.acquireEmphasisMark(
                    input: value,
                    textScaler: _scaler!,
                  );
                  layouts++;
                }
                try {
                  _guard();
                } catch (_) {
                  found.release();
                  rethrow;
                }
                _markLeases.add(found);
                final key = found.nativeInputIdentity;
                if (_expected != null && key != _expected!._markKeys[_index]) {
                  _mismatch();
                }
                _markKeys.add(key);
                _index++;
              } else {
                _index = 0;
                _phase = _LinePhase.place;
              }
            case _LinePhase.place:
              if (_index < _geometry!.targets.length) {
                final target = _geometry!.targets[_index];
                final mark = _markLeases[_unitMarks[_index]];
                final scale = _fitScale;
                final rect = mark.layout.fontBounds;
                _checkRect(rect);
                final size = Rect.fromLTRB(
                  rect.left * scale,
                  rect.top * scale,
                  rect.right * scale,
                  rect.bottom * scale,
                );
                final side = input
                    .content
                    .runs[target.unit.runIndex]
                    .style
                    .textEmphasis
                    .side;
                final descent =
                    (rect.bottom - mark.layout.alphabeticBaseline) * scale;
                final ascent =
                    (mark.layout.alphabeticBaseline - rect.top) * scale;
                final baseBounds = _rowInput == null
                    ? target.fontBounds
                    : target.governingFontBounds;
                _alignments
                    .putIfAbsent(target.lineIndex, _LineMarkAlignment.new)
                    .include(baseBounds, ascent, descent, side);
                final offset = Offset(baseBounds.center.dx - size.center.dx, 0);
                final bounds = size.shift(offset);
                _checkRect(bounds);
                _rawMarks.add((
                  unit: _index,
                  mark: _unitMarks[_index],
                  line: target.lineIndex,
                  offset: offset,
                  bounds: bounds,
                ));
                _index++;
              } else {
                _index = 0;
                _phase = _LinePhase.alignMarks;
              }
            case _LinePhase.alignMarks:
              if (_index < _rawMarks.length) {
                final raw = _rawMarks[_index];
                final unit = input.units[raw.unit];
                final side =
                    input.content.runs[unit.runIndex].style.textEmphasis.side;
                // Font fallback and mixed sizes still share one physical
                // annotation baseline per side, just like one ruby text row.
                final baseline = _alignments[raw.line]!.baseline(side);
                final offset = Offset(
                  raw.offset.dx,
                  baseline -
                      _markLeases[raw.mark].layout.alphabeticBaseline *
                          _fitScale,
                );
                final bounds = raw.bounds.shift(offset - raw.offset);
                _rawMarks[_index++] = (
                  unit: raw.unit,
                  mark: raw.mark,
                  line: raw.line,
                  offset: offset,
                  bounds: bounds,
                );
                _envelope = _envelope!.expandToInclude(bounds);
              } else {
                _phase = _LinePhase.frame;
              }
            case _LinePhase.frame:
              _checkRect(_envelope!);
              _baseOffset = Offset(0, -_envelope!.top.floorToDouble());
              _checkOffset(_baseOffset);
              _height = _envelope!.bottom.ceilToDouble() + _baseOffset.dy;
              if (!_height.isFinite || _height > 1048576) _invalid();
              _commands.add(
                _rowView == null
                    ? ForumBodyTextPictureCommand.fromText(_base!, _baseOffset)
                    : ForumBodyTextPictureCommand.fromParagraphRow(
                        _rowView!,
                        _baseOffset,
                      ),
              );
              _index = 0;
              _phase = _LinePhase.commands;
            case _LinePhase.commands:
              if (_index < _rawMarks.length) {
                final raw = _rawMarks[_index++];
                final font = _markLeases[raw.mark].layout;
                final fontRect = font.fontBounds;
                final side = input
                    .content
                    .runs[input.units[raw.unit].runIndex]
                    .style
                    .textEmphasis
                    .side;
                final offset = raw.offset + _baseOffset;
                _checkOffset(offset);
                _commands.add(
                  ForumBodyTextPictureCommand.fromEmphasisMark(
                    _markLeases[raw.mark],
                    offset,
                    fitScale: _fitScale,
                  ),
                );
                _positioned!.add(
                  ForumBodyEmphasisLineMark._(
                    unitIndex: raw.unit,
                    input: _markInputs[raw.mark],
                    offset: offset,
                    fontBounds: raw.bounds.shift(_baseOffset),
                    fitScale: _fitScale,
                    lineIndex: raw.line,
                    baseRelativeOffset: raw.offset,
                    baseRelativeAlphabeticBaseline: _alignments[raw.line]!
                        .baseline(side),
                    scaledFontBounds: Rect.fromLTRB(
                      fontRect.left * _fitScale,
                      fontRect.top * _fitScale,
                      fontRect.right * _fitScale,
                      fontRect.bottom * _fitScale,
                    ),
                    scaledAlphabeticBaseline:
                        font.alphabeticBaseline * _fitScale,
                  ),
                );
                if (_expected != null) {
                  final actual = _positioned!.last,
                      expected = _expected!.marks[_index - 1];
                  if (actual.unitIndex != expected.unitIndex ||
                      actual.lineIndex != expected.lineIndex ||
                      actual.input != expected.input ||
                      actual.offset != expected.offset ||
                      actual.fontBounds != expected.fontBounds ||
                      actual.baseRelativeOffset !=
                          expected.baseRelativeOffset ||
                      actual.baseRelativeAlphabeticBaseline !=
                          expected.baseRelativeAlphabeticBaseline ||
                      actual.scaledFontBounds != expected.scaledFontBounds ||
                      actual.scaledAlphabeticBaseline !=
                          expected.scaledAlphabeticBaseline ||
                      actual.fitScale != expected.fitScale) {
                    _mismatch();
                  }
                }
              } else {
                _phase = _LinePhase.sealMetrics;
              }
            case _LinePhase.sealMetrics:
              final pictureInput = ForumBodyTextPictureInput(
                commands: _commands,
                maxCommands: 513,
              );
              final bounds = _envelope!.shift(_baseOffset);
              final base = _textLayout;
              final baseline = base.alphabeticBaseline + _baseOffset.dy;
              final source = _base;
              final paragraphLine =
                  _rowInput == null &&
                      source is ForumBodyParagraphLease &&
                      source.layout.lines.isNotEmpty
                  ? source.layout.lines.single
                  : null;
              if (_expected != null) {
                final expected = _expected!;
                if (_baseOffset != expected.baseOffset ||
                    _baseFontBounds != expected.baseFontBounds ||
                    base.alphabeticBaseline !=
                        expected.baseAlphabeticBaseline ||
                    bounds != expected.fontBounds ||
                    base.width != expected.width ||
                    _height != expected.height ||
                    baseline != expected.alphabeticBaseline ||
                    _lineValues(paragraphLine) !=
                        _lineValues(expected.paragraphLine) ||
                    pictureInput != expected.pictureInput ||
                    _positioned!.length != expected.marks.length) {
                  _mismatch();
                }
                _numeric = expected;
              } else {
                _numeric = ForumBodyEmphasisLineMetrics._(
                  input: input,
                  rowInput: _rowInput,
                  baseRequest: _request!,
                  requestWidth: width,
                  textScaler: _scaler!,
                  baseOffset: _baseOffset,
                  baseFontBounds: _baseFontBounds!,
                  baseAlphabeticBaseline: base.alphabeticBaseline,
                  fontBounds: bounds,
                  width: base.width,
                  height: _height,
                  alphabeticBaseline: baseline,
                  pictureInput: pictureInput,
                  paragraphLine: paragraphLine,
                  baseKey: _base!.nativeInputIdentity,
                  markKeys: _markKeys,
                  markInputs: _markInputs,
                  unitMarks: _unitMarks,
                  marks: _positioned!,
                );
                // Transfer retired writers; cleanup cannot mutate a pure plan.
                _markKeys = [];
                _markInputs = [];
                _unitMarks = [];
              }
              _positioned = null;
              _index = 0;
              _phase = _bindOnly
                  ? (_prepareBindingPaint
                        ? _LinePhase.bindingPaint
                        : _LinePhase.ready)
                  : _measureOnly
                  ? _LinePhase.releaseMarks
                  : _LinePhase.basePaint;
            case _LinePhase.bindingPaint:
              if (!_base!.layout.isPaintPrepared) {
                if (cachedOnly) {
                  _cacheMiss = true;
                  used++;
                  return step();
                }
                if (cache.prepareTextPaint(_base!)) pictures++;
              }
              _phase = _LinePhase.ready;
            case _LinePhase.basePaint:
              if (!_base!.layout.isPaintPrepared) {
                if (cachedOnly) {
                  _cacheMiss = true;
                  used++;
                  return step();
                }
                if (cache.prepareTextPaint(_base!)) {
                  pictures++;
                }
              }
              _pictureJob = ForumBodyTextPicturePreparation(
                cache: cache,
                input: _numeric!.pictureInput,
                text: _rowView == null ? [_base!] : const [],
                paragraphRows: _rowView == null ? const [] : [_rowView!],
                marks: _markLeases,
                ensureOwner: _guard,
                additionalOwnedLeases: _additionalOwned,
              );
              _phase = _LinePhase.scene;
            case _LinePhase.scene:
              final job = _pictureJob!;
              final work = job.advance(maxParts: 1, cachedOnly: cachedOnly);
              pictures += work.picturesRecorded;
              if (work.waitingForLayoutBudget) {
                used += work.partsPrepared;
                return step(true);
              }
              if (job.cacheMiss) {
                _cacheMiss = true;
                used += work.partsPrepared;
                return step();
              }
              if (job.isReady) {
                _picture = job.takeLease();
                _pictureJob = null;
                _index = 0;
                _phase = _LinePhase.releaseMarks;
              }
            case _LinePhase.releaseMarks:
              if (_index < _markLeases.length) {
                _markLeases[_index++].release();
              } else {
                _markLeases.clear();
                _phase = _measureOnly
                    ? _LinePhase.releaseBase
                    : _LinePhase.publish;
              }
            case _LinePhase.releaseBase:
              _base!.release();
              _base = null;
              _phase = _LinePhase.ready;
            case _LinePhase.publish:
              _checkVisibleOwner();
              final row = _rowInput == null
                  ? null
                  : ForumBodyParagraphRowView.bind(
                      parent: _base! as ForumBodyParagraphLease,
                      metrics: _rowInput!.row,
                      ensureOwner: _ensureVisibleOwner!,
                    );
              _guard();
              _result = ForumBodyEmphasisLineLayout._(
                metrics: _numeric!,
                base: _base!,
                picture: _picture!,
                ensureOwner: _ensureVisibleOwner!,
                row: row,
              );
              _numeric = null;
              _base = null;
              _picture = null;
              _phase = _LinePhase.ready;
            case _LinePhase.ready:
            case _LinePhase.transferred:
            case _LinePhase.closed:
              throw StateError('Emphasis line preparation is retired');
          }
          used++;
          _guard();
        } on ForumBodyParagraphBudgetException catch (error) {
          _guard();
          if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
          final additional = _additionalOwned?.call() ?? const [];
          _guard();
          final external = cache.isBlockedByExternalPins(error, [
            ...nativeLeases,
            ...additional,
          ]);
          _guard();
          if (!external) {
            throw ForumBodyParagraphBudgetException(
              ForumBodyParagraphBudgetFailure.content,
              requiredEstimatedBytes: error.requiredEstimatedBytes,
              requiredAdditionalEntries: error.requiredAdditionalEntries,
            );
          }
          _blockedAt = rejectedAt;
          used++;
          return step(cache.budgetRevision == rejectedAt);
        }
      }
      return step();
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  double get _fitScale => _base is ForumBodyParagraphLease
      ? (_base! as ForumBodyParagraphLease).layout.paintScale
      : 1;
  ForumBodyTextLayout get _textLayout => _rowView ?? _base!.layout;

  ForumBodyEmphasisLineLayout takeLayout() {
    if (_operating) throw StateError('Emphasis line preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady || _measureOnly) {
        throw StateError('Emphasis line preparation is incomplete');
      }
      _checkVisibleOwner();
      final result = _result!;
      _result = null;
      _phase = _LinePhase.transferred;
      _dropInputs();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyEmphasisLineMetrics _takeMetrics() {
    if (_operating) throw StateError('Emphasis line preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady || !_measureOnly || _bindOnly) {
        throw StateError('Emphasis metrics are incomplete');
      }
      final result = _numeric!;
      _numeric = null;
      _phase = _LinePhase.transferred;
      _dropInputs();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  /// Reuse the full measured-font/source verification without recording the
  /// old isolated scene. The allocated renderer adopts these OWNED handles.
  _EmphasisNativeBinding _takeBinding() {
    if (_operating) throw StateError('Emphasis line preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady || !_bindOnly) {
        throw StateError('Emphasis binding is incomplete');
      }
      final base = _base! as ForumBodyParagraphLease;
      final row = ForumBodyParagraphRowView.bind(
        parent: base,
        metrics: _rowInput!.row,
        ensureOwner: _ensureOwner!,
      );
      _guard();
      final result = _EmphasisNativeBinding(base, row, _markLeases);
      _markLeases = [];
      _base = null;
      _phase = _LinePhase.transferred;
      _dropInputs();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  _RubyEmphasisGlyphBinding _takeGlyphBinding() {
    if (_operating) throw StateError('Emphasis line preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady ||
          !_bindOnly ||
          _rowInput != null ||
          !_prepareBindingPaint) {
        throw StateError('Ruby emphasis binding is incomplete');
      }
      final result = _RubyEmphasisGlyphBinding(_base!, _markLeases);
      _base = null;
      _markLeases = [];
      _phase = _LinePhase.transferred;
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
    if (_phase == _LinePhase.closed || _phase == _LinePhase.transferred) {
      throw StateError('Emphasis line preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _LinePhase.closed ||
        _cache == null ||
        _cache!.isClosed ||
        (_base != null && !_cache!.ownsLease(_base!)) ||
        (_picture != null && !_cache!.ownsLease(_picture!)) ||
        (_result != null && _result!.isDisposed)) {
      throw StateError('Emphasis line owner is retired');
    }
  }

  void _checkVisibleOwner() {
    if (!identical(_ensureVisibleOwner, _ensureOwner)) {
      _ensureVisibleOwner!();
      _guard();
    }
  }

  static Object? _lineValues(ForumBodyParagraphLine? line) => line == null
      ? null
      : (
          line.top,
          line.bottom,
          line.baseline,
          line.left,
          line.width,
          line.startUtf16,
          line.endUtf16,
          line.coverageStartUtf16,
          line.coverageEndUtf16,
          line.engineStartUtf16,
          line.engineEndUtf16,
          line.engineCoverageStartUtf16,
          line.engineCoverageEndUtf16,
          line.unpaintedTrailingSpaceStartUtf16,
          line.engineUnpaintedTrailingSpaceStartUtf16,
          line.canBreakBefore,
          line.canBreakAfter,
        );

  static void _checkRect(Rect rect) {
    if (!rect.left.isFinite ||
        !rect.top.isFinite ||
        !rect.right.isFinite ||
        !rect.bottom.isFinite ||
        rect.width < 0 ||
        rect.height < 0) {
      _invalid();
    }
  }

  static Never _invalid() => throw const ForumBodyEmphasisLineException(
    ForumBodyEmphasisLineFailure.geometry,
  );
  static Never _mismatch() => throw const ForumBodyEmphasisLineException(
    ForumBodyEmphasisLineFailure.metrics,
  );

  static void _checkOffset(Offset offset) {
    if (!offset.dx.isFinite ||
        !offset.dy.isFinite ||
        offset.dx.abs() > 32768 ||
        offset.dy.abs() > 32768) {
      _invalid();
    }
  }

  void _dropInputs() {
    _probe?.close();
    _probe = null;
    _input = null;
    _rowInput = null;
    _rowView = null;
    _request = null;
    _callerScaler = null;
    _scaler = null;
    _expected = null;
    _scaleChecks = null;
    _additionalOwned = null;
    _prefix = null;
    _numeric = null;
    _contexts = const [];
    _geometry = null;
    _fontBoxes = null;
    _positioned = null;
    _cache = null;
    _ensureOwner = null;
    _ensureVisibleOwner = null;
    _scales.clear();
    _markInputs = [];
    _markIndex.clear();
    _runMarks.clear();
    _unitMarks = [];
    _markKeys = [];
    _rawMarks.clear();
    _alignments.clear();
    _commands.clear();
  }

  void close() {
    if (_phase == _LinePhase.closed || _phase == _LinePhase.transferred) return;
    _phase = _LinePhase.closed;
    final base = _base, picture = _picture, result = _result;
    _base = null;
    _picture = null;
    _result = null;
    try {
      _geometryJob?.close();
      _geometryJob = null;
      _pictureJob?.close();
      _pictureJob = null;
    } finally {
      try {
        result?.close();
        picture?.release();
      } finally {
        for (final mark in _markLeases) {
          mark.release();
        }
        _markLeases.clear();
        base?.release();
        _dropInputs();
      }
    }
  }
}

final class _LineScaler extends TextScaler {
  const _LineScaler(this.values);
  final Map<double, double> values;
  @override
  double scale(double fontSize) =>
      values[fontSize] ??
      (throw StateError('Emphasis native font size was not captured'));
  @override
  double get textScaleFactor =>
      throw StateError('Use captured per-size values');
}
