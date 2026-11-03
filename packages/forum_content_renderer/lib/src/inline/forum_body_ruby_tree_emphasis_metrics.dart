part of 'forum_body_ruby_tree_input.dart';

/// One real native leaf's original/glyph association and measured emphasis
/// fonts. Its isolated line envelope is NOT a base box for ancestor ruby stacks.
final class ForumBodyRubyTreeEmphasisSourceMetrics {
  const ForumBodyRubyTreeEmphasisSourceMetrics._(this.source, this.line);
  final ForumBodyRubyGlyphTreeSourcePosition source;
  final ForumBodyEmphasisLineMetrics line;
}

/// Source-bound measurements for the complete glyph hierarchy. Contains no
/// native resource or owner, and grants no visible-tree or marker-scene binding.
/// Empty RT clearance and physical marker-row alignment still require composition.
final class ForumBodyRubyTreeEmphasisMetrics {
  ForumBodyRubyTreeEmphasisMetrics._(
    this.emptyFonts,
    List<ForumBodyRubyTreeEmphasisSourceMetrics> sources,
    Map<int, ForumBodyRubyTreeEmphasisSourceMetrics> bySource,
    this.textScaler,
  ) : sources = UnmodifiableListView(sources),
      _bySource = UnmodifiableMapView(bySource);
  final ForumBodyRubyEmptyAnnotationFonts emptyFonts;
  ForumBodyRubyGlyphTreeGeometry get geometry => emptyFonts.bands.geometry;
  final List<ForumBodyRubyTreeEmphasisSourceMetrics> sources;
  final Map<int, ForumBodyRubyTreeEmphasisSourceMetrics> _bySource;
  final TextScaler textScaler;
  Map<double, double> get effectiveScales =>
      (textScaler as _RubyFormatScaler).samples;
  ForumBodyRubyTreeEmphasisSourceMetrics? sourceForId(int id) {
    geometry.sourceForId(id);
    return _bySource[id];
  }

  /// Real transient font requests only. Isolated line scene slots are excluded;
  /// final glyph/marker retention and the merged scene have their own admission.
  Iterable<ForumBodyNativeRequestSlot> get fontMeasurementFootprint sync* {
    yield* emptyFonts.fontMeasurementFootprint;
    for (final source in sources) {
      yield* source.line.nativeFootprint;
    }
  }
}

enum _TreeEmphasisPhase {
  scales,
  sources,
  units,
  lines,
  qualify,
  publish,
  ready,
  transferred,
  closed,
}

/// Freeze all actual glyph/empty-RT/half-font samples before native work, then
/// reuse the existing measured-line transaction for each qualified real leaf.
/// No extra source, flattened parent or independently shaped band is invented.
final class ForumBodyRubyTreeEmphasisMetricsPreparation {
  ForumBodyRubyTreeEmphasisMetricsPreparation({
    required ForumBodyRubyEmptyAnnotationFonts emptyFonts,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    required TextScaler expectedTextScaler,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _emptyFonts = emptyFonts,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _callerScaler = expectedTextScaler,
       _additionalOwned = additionalOwnedLeases,
       _samples = emptyFonts.effectiveScales.entries.iterator;
  ForumBodyRubyEmptyAnnotationFonts? _emptyFonts;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  TextScaler? _callerScaler;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  Iterator<MapEntry<double, double>>? _samples;
  Map<double, double> _scales = {};
  _RubyFormatScaler? _scaler;
  List<_TreeEmphasisLeafInput> _inputs = [];
  List<ForumBodyRubyTreeEmphasisSourceMetrics> _sources = [];
  Map<int, ForumBodyRubyTreeEmphasisSourceMetrics> _bySource = {};
  ForumBodyEmphasisLineMetricsPreparation? _line;
  ForumBodyEmphasisLineMetrics? _lineValue;
  ForumBodyTextRequest? _currentRequest, _failedRequest;
  ForumBodyTextRequest? get failedRequest => _failedRequest;
  ForumBodyRubyTreeEmphasisMetrics? _result;
  int _index = 0, _unit = 0;
  bool _operating = false, _cacheMiss = false, _waiting = false;
  var _phase = _TreeEmphasisPhase.scales;
  bool get isReady => _phase == _TreeEmphasisPhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      _line?.nativeLeases ?? const [];

  ForumBodyRubyGroupPreparationStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      final cache = _cache!,
          builds = cache.layoutBuildCount,
          pictures = cache.pictureBuildCount;
      final before = _sources.length;
      var parts = 0;
      _waiting = _cacheMiss = false;
      while (!isReady && parts < maxParts) {
        final used = _advance(cachedOnly);
        parts += used;
        _guard();
        if (used == 0 ||
            _waiting ||
            _cacheMiss ||
            cache.layoutBuildCount != builds ||
            cache.pictureBuildCount != pictures) {
          break;
        }
      }
      return ForumBodyRubyGroupPreparationStep(
        partsPrepared: _sources.length - before,
        layoutsBuilt: cache.layoutBuildCount - builds,
        picturesBuilt: cache.pictureBuildCount - pictures,
        partsInspected: 0,
        formatUnitsPrepared: parts,
        isReady: isReady,
        waitingForLayoutBudget: _waiting,
      );
    });
  }

  int _advance(bool cachedOnly) {
    switch (_phase) {
      case _TreeEmphasisPhase.scales:
        if (_samples!.moveNext()) {
          final entry = _samples!.current;
          final actual = _callerScaler!.scale(entry.key);
          _guard();
          if (actual != entry.value) {
            throw ArgumentError(
              'Ruby emphasis scaler differs from measured glyph/RT fonts',
            );
          }
          _scales[entry.key] = actual;
        } else {
          _samples = null;
          _phase = _TreeEmphasisPhase.sources;
        }
      case _TreeEmphasisPhase.sources:
        final geometry = _emptyFonts!.bands.geometry;
        if (_index < geometry.sources.length) {
          final source = geometry.sources[_index];
          if (source.source.id >= 0 &&
              source.source.needsNative &&
              source.source.emphasis?.units.isNotEmpty == true) {
            _inputs.add(
              _TreeEmphasisLeafInput(
                source,
                geometry.metrics.input.requestForSource(source.source.id),
              ),
            );
            _unit = 0;
            _phase = _TreeEmphasisPhase.units;
          } else {
            _index++;
          }
        } else {
          _scaler = _RubyFormatScaler(
            UnmodifiableMapView(_scales),
            geometry
                .metrics
                .root
                .font
                .input
                .fontStrut
                .style
                .textStyle
                .fontSize!,
          );
          _scales = {};
          _callerScaler = null;
          _index = 0;
          _phase = _TreeEmphasisPhase.lines;
        }
      case _TreeEmphasisPhase.units:
        final input = _inputs.last.source.source.emphasis!;
        if (_unit < input.units.length) {
          final style = input.content.runs[input.units[_unit++].runIndex].style;
          final size = ForumBodyEmphasisMarkInput.resolveFontSize(
            style.textStyle,
          );
          if (!_scales.containsKey(size)) {
            final scaled = _callerScaler!.scale(size);
            _guard();
            if (!scaled.isFinite || scaled <= 0 || scaled > 4096) {
              throw ArgumentError('Invalid ruby emphasis font scale');
            }
            _scales[size] = scaled;
          }
        } else {
          _index++;
          _phase = _TreeEmphasisPhase.sources;
        }
      case _TreeEmphasisPhase.lines:
        if (_index == _inputs.length) {
          _phase = _TreeEmphasisPhase.publish;
          return 1;
        }
        final input = _inputs[_index];
        _currentRequest = input.request;
        final work = _line ??= ForumBodyEmphasisLineMetricsPreparation(
          input: input.source.source.emphasis!,
          baseRequest: input.request,
          cache: _cache!,
          ensureOwner: _guard,
          width: _emptyFonts!.bands.geometry.metrics.input.maxWidth,
          textScaler: _scaler!,
          additionalOwnedLeases: _additionalOwned,
        );
        final step = work.advance(maxParts: 1, cachedOnly: cachedOnly);
        _waiting = step.waitingForLayoutBudget;
        _cacheMiss = work.cacheMiss;
        _guard();
        if (work.isReady) {
          _lineValue = work.takeMetrics();
          _line = null;
          work.close();
          _phase = _TreeEmphasisPhase.qualify;
        }
        return step.partsPrepared;
      case _TreeEmphasisPhase.qualify:
        final input = _inputs[_index], line = _lineValue!;
        final source = input.source.source;
        final box = _emptyFonts!.bands.geometry.metrics.nodes[source.id].box!;
        if (!identical(line.input, source.emphasis) ||
            !identical(line.input.content, source.content) ||
            !identical(line.input.glyphInput.glyphs, source.glyphs) ||
            !identical(line.baseRequest, input.request) ||
            line.rowInput != null ||
            line.baseFontBounds != box.bounds ||
            line.baseAlphabeticBaseline != box.alphabeticBaseline) {
          throw const ForumBodyEmphasisLineException(
            ForumBodyEmphasisLineFailure.metrics,
          );
        }
        final value = ForumBodyRubyTreeEmphasisSourceMetrics._(
          input.source,
          line,
        );
        _sources.add(value);
        _bySource[source.id] = value;
        _lineValue = null;
        _currentRequest = null;
        _index++;
        _phase = _TreeEmphasisPhase.lines;
      case _TreeEmphasisPhase.publish:
        _result = ForumBodyRubyTreeEmphasisMetrics._(
          _emptyFonts!,
          _sources,
          _bySource,
          _scaler!,
        );
        _sources = [];
        _bySource = {};
        _phase = _TreeEmphasisPhase.ready;
      case _TreeEmphasisPhase.ready:
      case _TreeEmphasisPhase.transferred:
      case _TreeEmphasisPhase.closed:
        throw StateError('Ruby tree emphasis measurement is retired');
    }
    return 1;
  }

  ForumBodyRubyTreeEmphasisMetrics takeMetrics() => _operate(() {
    _guard();
    if (!isReady) {
      throw StateError('Ruby tree emphasis measurement is incomplete');
    }
    final result = _result!;
    _result = null;
    _phase = _TreeEmphasisPhase.transferred;
    _drop();
    return result;
  });
  T _operate<T>(T Function() action) {
    if (_operating) {
      throw StateError('Ruby tree emphasis measurement is reentrant');
    }
    _operating = true;
    try {
      return action();
    } catch (error) {
      final failed = error is ForumBodyTextBandLayoutException
          ? _currentRequest
          : null;
      close();
      _failedRequest = failed;
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _TreeEmphasisPhase.closed ||
        _phase == _TreeEmphasisPhase.transferred) {
      throw StateError('Ruby tree emphasis measurement is retired');
    }
    _ensureOwner!();
    if (_phase == _TreeEmphasisPhase.closed || _cache!.isClosed) {
      throw StateError('Ruby tree emphasis owner is retired');
    }
  }

  void _drop() {
    _line?.close();
    _line = null;
    _lineValue = null;
    _emptyFonts = null;
    _cache = null;
    _ensureOwner = null;
    _callerScaler = null;
    _additionalOwned = null;
    _samples = null;
    _scaler = null;
    _currentRequest = null;
    _inputs = [];
    _sources = [];
    _bySource = {};
    _scales = {};
  }

  void close() {
    if (_phase == _TreeEmphasisPhase.closed ||
        _phase == _TreeEmphasisPhase.transferred) {
      return;
    }
    _phase = _TreeEmphasisPhase.closed;
    _result = null;
    _drop();
  }
}

final class _TreeEmphasisLeafInput {
  const _TreeEmphasisLeafInput(this.source, this.request);
  final ForumBodyRubyGlyphTreeSourcePosition source;
  final ForumBodyTextRequest request;
}
