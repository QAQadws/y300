part of 'forum_body_emphasis_line_layout.dart';

enum _LinePhase {
  fonts,
  inputs,
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
  basePaint,
  scene,
  releaseMarks,
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

typedef _RawMark = ({int unit, int mark, Offset offset, Rect bounds});

/// One cooperative transaction over the owner's existing native cache. The
/// caller's full/half-size scaler samples freeze before any native request.
final class ForumBodyEmphasisLinePreparation {
  ForumBodyEmphasisLinePreparation({
    required ForumBodyEmphasisTextInput input,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    ForumBodyTextRequest? baseRequest,
    this.width = 16384,
    TextScaler textScaler = TextScaler.noScaling,
  }) : _input = input,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _callerScaler = textScaler,
       _request =
           baseRequest ??
           ForumBodyTextRequest.paragraph(input.glyphInput.glyphs) {
    try {
      _guard();
      if (!width.isFinite || width <= 0 || width > 16384) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.width,
        );
      }
      if (!identical(_request!.content, input.glyphInput.glyphs)) {
        throw const ForumBodyEmphasisLineException(
          ForumBodyEmphasisLineFailure.source,
        );
      }
      if (input.units.length > 512) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.inputLimit,
          input.content.path,
        );
      }
      _contexts = switch (_request!) {
        ForumBodyParagraphTextRequest() => [input.glyphInput.glyphs],
        ForumBodyTextBandChildRequest value => value.band.contexts,
      };
    } catch (_) {
      close();
      rethrow;
    }
  }
  final double width;
  ForumBodyEmphasisTextInput? _input;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  ForumBodyTextRequest? _request;
  TextScaler? _callerScaler;
  List<ForumBodyParagraphContent> _contexts = const [];
  Map<double, double> _scales = {};
  _LineScaler? _scaler;
  var _context = 0, _run = -1, _index = 0, _blockedAt = -1;
  final _markInputs = <ForumBodyEmphasisMarkInput>[];
  final _markIndex = <ForumBodyEmphasisMarkInput, int>{};
  final _runMarks = <int, int>{};
  final _unitMarks = <int>[];
  final _markLeases = <ForumBodyEmphasisMarkLease>[];
  final _rawMarks = <_RawMark>[];
  List<ForumBodyEmphasisLineMark>? _positioned = [];
  final _commands = <ForumBodyTextPictureCommand>[];
  ForumBodyParagraphBudgetProbe? _probe;
  ForumBodyTextLease? _base;
  ForumBodyEmphasisGeometryPreparation? _geometryJob;
  ForumBodyEmphasisTextGeometry? _geometry;
  List<TextBox>? _fontBoxes;
  Rect? _envelope;
  Offset _baseOffset = Offset.zero;
  double _height = 0;
  double? _overTop, _underBottom;
  double _overDescent = 0, _underAscent = 0;
  ForumBodyTextPicturePreparation? _pictureJob;
  ForumBodyTextPictureLease? _picture;
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
                _phase = _LinePhase.probeBase;
              }
            case _LinePhase.probeBase:
              _request!.includeBudget(
                _probe!,
                width: width,
                textScaler: _scaler!,
                minimumLineCount: input.content.projection.text.isEmpty ? 0 : 1,
              );
              _phase = _LinePhase.probeMarks;
            case _LinePhase.probeMarks:
              if (_index < _markInputs.length) {
                _probe!.includeEmphasisMark(
                  input: _markInputs[_index++],
                  textScaler: _scaler!,
                );
              } else {
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
              if (found is ForumBodyParagraphLease &&
                  found.layout.lineCount > 1) {
                throw const ForumBodyEmphasisLineException(
                  ForumBodyEmphasisLineFailure.lines,
                );
              }
              _geometryJob = ForumBodyEmphasisGeometryPreparation(
                input: input,
                base: found,
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
              final layout = _base!.layout;
              _envelope = Rect.fromLTWH(0, 0, layout.width, layout.height);
              _fontBoxes = layout.selectionBoxes(
                0,
                input.content.projection.text.length,
              );
              if (_fontBoxes!.length > 4096) _invalid();
              _phase = _LinePhase.bounds;
            case _LinePhase.bounds:
              if (_index < _fontBoxes!.length) {
                final box = _fontBoxes![_index++].toRect();
                _checkRect(box);
                _envelope = _envelope!.expandToInclude(box);
              } else {
                _fontBoxes = null;
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
                if (side == ForumBodyEmphasisSide.over) {
                  if (_overTop == null || target.fontBounds.top < _overTop!) {
                    _overTop = target.fontBounds.top;
                  }
                  if (descent > _overDescent) _overDescent = descent;
                } else {
                  if (_underBottom == null ||
                      target.fontBounds.bottom > _underBottom!) {
                    _underBottom = target.fontBounds.bottom;
                  }
                  if (ascent > _underAscent) _underAscent = ascent;
                }
                final offset = Offset(
                  target.fontBounds.center.dx - size.center.dx,
                  0,
                );
                final bounds = size.shift(offset);
                _checkRect(bounds);
                _rawMarks.add((
                  unit: _index,
                  mark: _unitMarks[_index],
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
                final baseline = side == ForumBodyEmphasisSide.over
                    ? _overTop! - _overDescent
                    : _underBottom! + _underAscent;
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
                ForumBodyTextPictureCommand.fromText(_base!, _baseOffset),
              );
              _index = 0;
              _phase = _LinePhase.commands;
            case _LinePhase.commands:
              if (_index < _rawMarks.length) {
                final raw = _rawMarks[_index++];
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
                  ),
                );
              } else {
                _phase = _LinePhase.basePaint;
              }
            case _LinePhase.basePaint:
              if (_base is ForumBodyTextBandChildLease &&
                  !_base!.layout.isPaintPrepared) {
                if (cachedOnly) {
                  _cacheMiss = true;
                  used++;
                  return step();
                }
                if (cache.prepareBandChildPaint(
                  _base! as ForumBodyTextBandChildLease,
                )) {
                  pictures++;
                }
              }
              _pictureJob = ForumBodyTextPicturePreparation(
                cache: cache,
                input: ForumBodyTextPictureInput(
                  commands: _commands,
                  maxCommands: 513,
                ),
                text: [_base!],
                marks: _markLeases,
                ensureOwner: _guard,
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
                _phase = _LinePhase.publish;
              }
            case _LinePhase.publish:
              _result = ForumBodyEmphasisLineLayout._(
                input: input,
                base: _base!,
                picture: _picture!,
                baseOffset: _baseOffset,
                fontBounds: _envelope!.shift(_baseOffset),
                width: _base!.layout.width,
                height: _height,
                alphabeticBaseline:
                    _base!.layout.alphabeticBaseline + _baseOffset.dy,
                marks: _positioned!,
                ensureOwner: _ensureOwner!,
              );
              _positioned = null;
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
          if (!cache.isBlockedByExternalPins(error, nativeLeases)) {
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

  ForumBodyEmphasisLineLayout takeLayout() {
    if (_operating) throw StateError('Emphasis line preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Emphasis line preparation is incomplete');
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
    _request = null;
    _callerScaler = null;
    _scaler = null;
    _contexts = const [];
    _geometry = null;
    _fontBoxes = null;
    _positioned = null;
    _cache = null;
    _ensureOwner = null;
    _scales.clear();
    _markInputs.clear();
    _markIndex.clear();
    _runMarks.clear();
    _unitMarks.clear();
    _rawMarks.clear();
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
