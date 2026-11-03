part of 'forum_body_emphasis_line_layout.dart';

enum _InlineFontPhase {
  samples,
  verifyParent,
  inputs,
  beginPrefix,
  prefix,
  probeFont,
  font,
  classify,
  publish,
  ready,
  transferred,
  closed,
}

/// Source/key-qualified temporary marker-font measurements. Only the current
/// font is owned; the actual parent and additional transaction prefix are
/// borrowed. Complete page/scene admission belongs to the containing format.
final class ForumBodyInlineEmphasisFontPreparation {
  ForumBodyInlineEmphasisFontPreparation({
    required ForumBodyInlineEmphasisTextGeometry geometry,
    required ForumBodyInlineParagraphRequest parentRequest,
    required ForumBodyInlineParagraphLease parent,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    required TextScaler expectedTextScaler,
    required this.width,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _geometry = geometry,
       _request = parentRequest,
       _parent = parent,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _callerScaler = expectedTextScaler,
       _additionalOwned = additionalOwnedLeases {
    try {
      _guard();
      if (!width.isFinite || width <= 0 || width > 16384) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.width,
        );
      }
      if (!identical(parent.content, geometry.input.glyphInput.glyphs) ||
          !identical(parentRequest.content, parent.content)) {
        throw const ForumBodyEmphasisLineException(
          ForumBodyEmphasisLineFailure.source,
        );
      }
      if (geometry.nativeInputIdentity != parent.nativeInputIdentity ||
          geometry.lineCount != parent.layout.lineCount) {
        _mismatch();
      }
      _samples = geometry.input.nativeFontSizes.iterator;
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  final double width;
  ForumBodyInlineEmphasisTextGeometry? _geometry;
  ForumBodyInlineParagraphRequest? _request;
  ForumBodyInlineParagraphLease? _parent;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  TextScaler? _callerScaler;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  Iterator<double>? _samples;
  Map<double, double> _scales = {};
  _LineScaler? _scaler;
  List<ForumBodyEmphasisMarkRequest> _requests = [];
  Map<ForumBodyEmphasisMarkInput, int> _byInput = {};
  Map<int, int> _byRun = {};
  List<int> _unitFonts = [];
  List<ForumBodyEmphasisMarkFontMetrics> _fonts = [];
  ForumBodyEmphasisMarkLease? _pending;
  ForumBodyParagraphBudgetProbe? _probe;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  List<ForumBodyNativeParagraphLease> _owned = [];
  ForumBodyParagraphBudgetException? _rejection;
  int _unit = 0, _font = 0, _blockedAt = -1, _rejectedAt = -1;
  var _phase = _InlineFontPhase.samples;
  bool _operating = false, _cacheMiss = false;
  bool get isReady => _phase == _InlineFontPhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [?_pending];
  ForumBodyInlineEmphasisFontMetrics? _result;

  ForumBodyEmphasisLineStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Inline emphasis fonts are reentrant');
    _operating = true;
    var used = 0;
    final cache = _cache;
    final before = cache?.layoutBuildCount ?? 0;
    ForumBodyEmphasisLineStep step([bool waiting = false]) => (
      partsPrepared: used,
      nativeLayoutsBuilt: cache!.layoutBuildCount - before,
      picturesRecorded: 0,
      waitingForLayoutBudget: waiting,
    );
    try {
      _guard();
      _cacheMiss = false;
      if (_blockedAt == cache!.budgetRevision) return step(true);
      while (used < maxParts && !isReady && cache.layoutBuildCount == before) {
        _guard();
        final rejectedAt = cache.budgetRevision;
        try {
          switch (_phase) {
            case _InlineFontPhase.samples:
              if (_samples!.moveNext()) {
                final size = _samples!.current;
                if (!size.isFinite || size <= 0) _invalidScale();
                if (!_scales.containsKey(size)) {
                  final scaled = _callerScaler!.scale(size);
                  _guard();
                  if (!scaled.isFinite || scaled <= 0 || scaled > 4096) {
                    _invalidScale();
                  }
                  _scales[size] = scaled;
                }
              } else {
                _samples = null;
                _scaler = _LineScaler(UnmodifiableMapView(_scales));
                _scales = {};
                _callerScaler = null;
                _phase = _InlineFontPhase.verifyParent;
              }
            case _InlineFontPhase.verifyParent:
              // Qualify the requested key BEFORE any actual prefix is included.
              // Otherwise that prefix would hide a mismatching requested key.
              final probe = _probe = cache.createBudgetProbe();
              _request!.includeBudget(
                probe,
                width: width,
                textScaler: _scaler!,
                minimumLineCount: _geometry!.lineCount,
              );
              _guard();
              final keys = probe.snapshotNativeIdentities();
              if (keys.length != 1 ||
                  !keys.contains(_parent!.nativeInputIdentity)) {
                _mismatch();
              }
              probe.close();
              _probe = null;
              _phase = _InlineFontPhase.inputs;
            case _InlineFontPhase.inputs:
              final input = _geometry!.input;
              if (_unit < input.units.length) {
                final run = input.units[_unit++].runIndex;
                var index = _byRun[run];
                if (index == null) {
                  final mark = ForumBodyEmphasisMarkInput(
                    style: input.content.runs[run].style,
                    fontRevision: input.content.fontRevision,
                    styleRevision: input.content.styleRevision,
                  );
                  index = _byInput[mark];
                  if (index == null) {
                    index = _requests.length;
                    _byInput[mark] = index;
                    _requests.add(ForumBodyEmphasisMarkRequest(mark));
                  }
                  _byRun[run] = index;
                }
                _unitFonts.add(index);
              } else {
                _byInput = {};
                _byRun = {};
                _phase = _requests.isEmpty
                    ? _InlineFontPhase.publish
                    : _InlineFontPhase.beginPrefix;
              }
            case _InlineFontPhase.beginPrefix:
              _probe = cache.createBudgetProbe();
              _probe!.includeLease(_parent!);
              _owned = [_parent!];
              final values =
                  _additionalOwned?.call() ??
                  const <ForumBodyNativeParagraphLease>[];
              _guard();
              final iterator = values.iterator;
              _guard();
              _prefix = iterator;
              _phase = _InlineFontPhase.prefix;
            case _InlineFontPhase.prefix:
              final iterator = _prefix!;
              final more = iterator.moveNext();
              _guard();
              if (more) {
                final lease = iterator.current;
                _guard();
                _probe!.includeLease(lease);
                _owned.add(lease);
              } else {
                _prefix = null;
                _phase = _rejection == null
                    ? _InlineFontPhase.probeFont
                    : _InlineFontPhase.classify;
              }
            case _InlineFontPhase.probeFont:
              _requests[_font].includeBudget(
                _probe!,
                width: width,
                textScaler: _scaler!,
              );
              _guard();
              _probe!.close();
              _probe = null;
              _phase = _InlineFontPhase.font;
            case _InlineFontPhase.font:
              final request = _requests[_font];
              final lease = request.acquire(
                cache,
                width: width,
                textScaler: _scaler!,
                cachedOnly: cachedOnly,
              );
              if (lease == null) {
                _guard();
                _cacheMiss = true;
                _owned = [];
                _phase = _InlineFontPhase.beginPrefix;
                used++;
                return step();
              }
              _pending = lease;
              try {
                _guard();
                final layout = lease.layout;
                ForumBodyEmphasisLinePreparation._checkRect(layout.fontBounds);
                if (!layout.width.isFinite ||
                    !layout.height.isFinite ||
                    layout.height <= 0 ||
                    !layout.alphabeticBaseline.isFinite) {
                  throw const ForumBodyEmphasisLineException(
                    ForumBodyEmphasisLineFailure.geometry,
                  );
                }
                _fonts.add(
                  ForumBodyEmphasisMarkFontMetrics._(
                    request: request,
                    nativeInputIdentity: lease.nativeInputIdentity,
                    scaledFontSize: _scaler!.scale(
                      request.input.textStyle.fontSize!,
                    ),
                    width: layout.width,
                    height: layout.height,
                    alphabeticBaseline: layout.alphabeticBaseline,
                    fontBounds: layout.fontBounds,
                  ),
                );
                _guard();
                _font++;
                _owned = [];
                _phase = _font == _requests.length
                    ? _InlineFontPhase.publish
                    : _InlineFontPhase.beginPrefix;
              } finally {
                lease.release();
                _pending = null;
              }
            case _InlineFontPhase.classify:
              final external = cache.isBlockedByExternalPins(
                _rejection!,
                _owned,
              );
              _guard();
              if (cache.budgetRevision != _rejectedAt) {
                _probe!.close();
                _probe = null;
                _owned = [];
                _rejection = null;
                _blockedAt = -1;
                _phase = _InlineFontPhase.beginPrefix;
                used++;
                return step();
              }
              if (!external) {
                throw ForumBodyParagraphBudgetException(
                  ForumBodyParagraphBudgetFailure.content,
                  requiredEstimatedBytes: _rejection!.requiredEstimatedBytes,
                  requiredAdditionalEntries:
                      _rejection!.requiredAdditionalEntries,
                );
              }
              _probe!.close();
              _probe = null;
              _owned = [];
              _rejection = null;
              _blockedAt = _rejectedAt;
              _phase = _InlineFontPhase.beginPrefix;
              used++;
              return step(cache.budgetRevision == _blockedAt);
            case _InlineFontPhase.publish:
              _result = ForumBodyInlineEmphasisFontMetrics._(
                geometry: _geometry!,
                parentRequest: _request!,
                requestWidth: width,
                textScaler: _scaler!,
                fonts: _fonts,
                unitFonts: _unitFonts,
              );
              _fonts = [];
              _unitFonts = [];
              _requests = [];
              _phase = _InlineFontPhase.ready;
            case _InlineFontPhase.ready:
            case _InlineFontPhase.transferred:
            case _InlineFontPhase.closed:
              throw StateError('Inline emphasis fonts are retired');
          }
          used++;
          _guard();
        } on ForumBodyParagraphBudgetException catch (error) {
          _guard();
          if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
          _probe?.close();
          _probe = null;
          _prefix = null;
          _owned = [];
          _rejection = error;
          _rejectedAt = rejectedAt;
          _phase = _InlineFontPhase.beginPrefix;
          used++;
          break;
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

  ForumBodyInlineEmphasisFontMetrics takeMetrics() {
    if (_operating) throw StateError('Inline emphasis fonts are reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Inline emphasis fonts are incomplete');
      final result = _result!;
      _phase = _InlineFontPhase.transferred;
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
    if (_phase == _InlineFontPhase.closed ||
        _phase == _InlineFontPhase.transferred) {
      throw StateError('Inline emphasis fonts are retired');
    }
    _ensureOwner!();
    if (_phase == _InlineFontPhase.closed ||
        _phase == _InlineFontPhase.transferred ||
        _cache!.isClosed ||
        !_cache!.ownsLease(_parent!) ||
        (_pending != null && !_cache!.ownsLease(_pending!))) {
      throw StateError('Inline emphasis font owner is retired');
    }
  }

  static Never _mismatch() => throw const ForumBodyEmphasisLineException(
    ForumBodyEmphasisLineFailure.metrics,
  );
  static Never _invalidScale() => throw const ForumBodyParagraphLayoutException(
    ForumBodyParagraphLayoutFailure.scale,
  );
  void _drop() {
    _probe?.close();
    _probe = null;
    _prefix = null;
    _owned = [];
    _geometry = null;
    _request = null;
    _parent = null;
    _cache = null;
    _ensureOwner = null;
    _callerScaler = null;
    _additionalOwned = null;
    _samples = null;
    _scales = {};
    _scaler = null;
    _requests = [];
    _byInput = {};
    _byRun = {};
    _unitFonts = [];
    _fonts = [];
    _rejection = null;
    _result = null;
  }

  void close() {
    if (_phase == _InlineFontPhase.closed ||
        _phase == _InlineFontPhase.transferred) {
      return;
    }
    _phase = _InlineFontPhase.closed;
    _pending?.release();
    _pending = null;
    _drop();
  }
}
