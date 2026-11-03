part of 'forum_body_ruby_tree_input.dart';

/// Actual natural font metrics for one original empty RT. The source-free
/// request contributes no glyph, display unit, selection or rendered coverage.
/// Its opaque key is measurement metadata, never visible-source authority.
final class ForumBodyRubyEmptyAnnotationFont {
  const ForumBodyRubyEmptyAnnotationFont._({
    required this.source,
    required this.rank,
    required this.side,
    required this.request,
    required this.nativeInputIdentity,
    required this.bounds,
    required this.alphabeticBaseline,
  });
  final ForumBodyRubyGlyphTreeSourcePosition source;
  final int rank;
  final ForumBodyRubySide side;
  final ForumBodyTextRequest request;
  final Object nativeInputIdentity;
  final Rect bounds;
  final double alphabeticBaseline;
}

/// Pure empty-RT font inputs for a later annotation/decoration composition.
/// Measuring these fonts does not move the existing glyph stack or complete
/// empty/auto-hidden row placement, marker alignment, scene or source binding.
final class ForumBodyRubyEmptyAnnotationFonts {
  ForumBodyRubyEmptyAnnotationFonts._(
    this.bands,
    List<ForumBodyRubyEmptyAnnotationFont> fonts,
    Map<int, ForumBodyRubyEmptyAnnotationFont> bySource,
    Map<double, double> scales,
    double rootSize,
  ) : fonts = UnmodifiableListView(fonts),
      _bySource = UnmodifiableMapView(bySource),
      textScaler = _EmptyAnnotationScaler(
        UnmodifiableMapView(scales),
        rootSize,
      );
  final ForumBodyRubyGlyphTreeBands bands;
  final List<ForumBodyRubyEmptyAnnotationFont> fonts;
  final Map<int, ForumBodyRubyEmptyAnnotationFont> _bySource;
  final TextScaler textScaler;
  Map<double, double> get effectiveScales =>
      (textScaler as _EmptyAnnotationScaler).samples;
  ForumBodyRubyEmptyAnnotationFont? fontForSource(int id) {
    bands.geometry.sourceForId(id);
    return _bySource[id];
  }

  /// Transient measurement inputs, not a final visible handle/scene count.
  Iterable<ForumBodyNativeRequestSlot> get fontMeasurementFootprint sync* {
    for (final font in fonts) {
      yield (
        request: font.request,
        width: bands.geometry.metrics.input.maxWidth,
        minimumLineCount: 0,
      );
    }
  }
}

enum _EmptyFontPhase {
  scales,
  sources,
  measure,
  publish,
  ready,
  transferred,
  closed,
}

/// Capture current scaling before any font request, then measure only real
/// empty annotation leaves via the owner's shared cache. Empty base struts,
/// collapsed source fences and opaque inline contexts are not RT fonts.
final class ForumBodyRubyEmptyAnnotationFontsPreparation {
  ForumBodyRubyEmptyAnnotationFontsPreparation({
    required ForumBodyRubyGlyphTreeBands bands,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    required TextScaler expectedTextScaler,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _bands = bands,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _callerScaler = expectedTextScaler,
       _additionalOwned = additionalOwnedLeases,
       _samples = bands.geometry.metrics.effectiveGlyphScales.entries.iterator;
  ForumBodyRubyGlyphTreeBands? _bands;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  TextScaler? _callerScaler;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  Iterator<MapEntry<double, double>>? _samples;
  Map<double, double> _scales = {};
  List<ForumBodyRubyEmptyAnnotationFont> _fonts = [];
  Map<int, ForumBodyRubyEmptyAnnotationFont> _bySource = {};
  List<_EmptyFontInput> _inputs = [];
  ForumBodyTextRequestPreparation? _member;
  int _index = 0;
  var _phase = _EmptyFontPhase.scales;
  bool _operating = false, _waiting = false, _cacheMiss = false;
  ForumBodyRubyEmptyAnnotationFonts? _result;
  bool get isReady => _phase == _EmptyFontPhase.ready;
  bool get cacheMiss => _cacheMiss;
  ForumBodyParagraphBudgetException? get lastBudgetRejection =>
      _member?.lastBudgetRejection;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      _member?.nativeLeases ?? const [];

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
      final before = _fonts.length;
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
        partsPrepared: _fonts.length - before,
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
      case _EmptyFontPhase.scales:
        if (_samples!.moveNext()) {
          final entry = _samples!.current;
          final scaled = _callerScaler!.scale(entry.key);
          _guard();
          if (scaled != entry.value) {
            throw ArgumentError(
              'Empty RT font scaler differs from glyph metrics',
            );
          }
          _scales[entry.key] = scaled;
        } else {
          _samples = null;
          _phase = _EmptyFontPhase.sources;
        }
      case _EmptyFontPhase.sources:
        final geometry = _bands!.geometry;
        if (_index == geometry.sources.length) {
          _index = 0;
          _phase = _EmptyFontPhase.measure;
          return 1;
        }
        final source = geometry.sources[_index];
        final binding = source.source, branch = source.node.edge?.branch;
        if (binding.id < 0 ||
            binding.needsNative ||
            binding.content.projection.text.isNotEmpty ||
            (branch != ForumBodyRubyTreeBranch.annotation &&
                branch != ForumBodyRubyTreeBranch.span)) {
          _index++;
          return 1;
        }
        final parent = source.node.parent!;
        final parentInput = geometry.metrics.input.sourceTree.nodes[parent.id];
        final rank = branch == ForumBodyRubyTreeBranch.annotation
            ? source.node.edge!.index
            : (parentInput as ForumBodyRubyTreeSegment)
                  .spans[source.node.edge!.index]
                  .rank;
        final side = _bands!.nodeForId(parent.id).localBands[rank].side;
        final content = binding.content, style = content.style;
        final font = ForumBodyParagraphContent.anonymousInline(
          identity: content.identity,
          fontRevision: content.fontRevision,
          styleRevision: content.styleRevision,
          style: ForumBodyResolvedStyle(
            // A natural RT font is distinct from the author's collapsed row
            // and from any emphasis flag; its original source stays untouched.
            textStyle: style.textStyle.copyWith(height: kTextHeightNone),
            role: style.role,
            textAlign: style.textAlign,
            textDirection: style.textDirection,
          ),
        );
        final size = font.style.textStyle.fontSize!;
        var scaled = _scales[size];
        if (scaled == null) {
          scaled = _callerScaler!.scale(size);
          _guard();
          _scales[size] = scaled;
        }
        // A cached painter keeps a one-size immutable sample, never this
        // transaction's growing map, owner callback or caller's scaler.
        _inputs.add(
          _EmptyFontInput(
            source,
            rank,
            side,
            ForumBodyTextRequest.paragraph(font),
            _EmptyAnnotationScaler(UnmodifiableMapView({size: scaled}), size),
          ),
        );
        _index++;
      case _EmptyFontPhase.measure:
        if (_index == _inputs.length) {
          _phase = _EmptyFontPhase.publish;
          return 1;
        }
        final input = _inputs[_index];
        final work = _member ??= ForumBodyTextRequestPreparation(
          cache: _cache!,
          request: input.request,
          ensureOwner: _guard,
          preparePaint: false,
          textScaler: input.scaler,
          width: _bands!.geometry.metrics.input.maxWidth,
          additionalOwnedLeases: _additionalOwned,
        );
        final step = work.advance(cachedOnly: cachedOnly);
        _waiting = step.waiting;
        _cacheMiss = step.cacheMiss;
        _guard();
        if (work.isReady) {
          final lease = work.takeLease();
          _member = null;
          work.close();
          try {
            _guard();
            if (!identical(lease.content, input.request.content) ||
                !_cache!.ownsLease(lease)) {
              throw StateError('Empty RT font lost its actual native request');
            }
            final layout = lease.layout;
            final value = ForumBodyRubyEmptyAnnotationFont._(
              source: input.source,
              rank: input.rank,
              side: input.side,
              request: input.request,
              nativeInputIdentity: lease.nativeInputIdentity,
              bounds: Rect.fromLTWH(0, 0, layout.width, layout.height),
              alphabeticBaseline: layout.alphabeticBaseline,
            );
            _fonts.add(value);
            _bySource[value.source.source.id] = value;
          } finally {
            lease.release();
          }
          _index++;
        }
        return step.units;
      case _EmptyFontPhase.publish:
        final bands = _bands!;
        _result = ForumBodyRubyEmptyAnnotationFonts._(
          bands,
          _fonts,
          _bySource,
          _scales,
          bands
              .geometry
              .metrics
              .root
              .font
              .input
              .fontStrut
              .style
              .textStyle
              .fontSize!,
        );
        _fonts = [];
        _bySource = {};
        _scales = {};
        _phase = _EmptyFontPhase.ready;
      case _EmptyFontPhase.ready:
      case _EmptyFontPhase.transferred:
      case _EmptyFontPhase.closed:
        throw StateError('Empty RT font preparation is retired');
    }
    return 1;
  }

  ForumBodyRubyEmptyAnnotationFonts takeFonts() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Empty RT fonts are incomplete');
    final result = _result!;
    _result = null;
    _phase = _EmptyFontPhase.transferred;
    _drop();
    return result;
  });
  T _operate<T>(T Function() action) {
    if (_operating) {
      throw StateError('Empty RT font preparation is reentrant');
    }
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

  void _guard() {
    if (_phase == _EmptyFontPhase.closed ||
        _phase == _EmptyFontPhase.transferred) {
      throw StateError('Empty RT font preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _EmptyFontPhase.closed || _cache!.isClosed) {
      throw StateError('Empty RT font owner is retired');
    }
  }

  void _drop() {
    _member?.close();
    _member = null;
    _bands = null;
    _cache = null;
    _ensureOwner = null;
    _callerScaler = null;
    _additionalOwned = null;
    _samples = null;
    _inputs = [];
    _fonts = [];
    _bySource = {};
    _scales = {};
  }

  void close() {
    if (_phase == _EmptyFontPhase.closed ||
        _phase == _EmptyFontPhase.transferred) {
      return;
    }
    _phase = _EmptyFontPhase.closed;
    _result = null;
    _drop();
  }
}

final class _EmptyFontInput {
  const _EmptyFontInput(
    this.source,
    this.rank,
    this.side,
    this.request,
    this.scaler,
  );
  final ForumBodyRubyGlyphTreeSourcePosition source;
  final int rank;
  final ForumBodyRubySide side;
  final ForumBodyTextRequest request;
  final TextScaler scaler;
}

final class _EmptyAnnotationScaler extends TextScaler {
  const _EmptyAnnotationScaler(this.samples, this.rootSize);
  final Map<double, double> samples;
  final double rootSize;
  @override
  double scale(double fontSize) =>
      samples[fontSize] ??
      (throw ArgumentError.value(fontSize, 'fontSize', 'Unmeasured RT font'));
  @override
  double get textScaleFactor => scale(rootSize) / rootSize;
}
