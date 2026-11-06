import 'dart:collection';

import 'package:flutter/painting.dart';

import '../flow/forum_body_inline_flow_content.dart';
import '../pagination/forum_body_text_page_content.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_emphasis_text_geometry.dart';
import 'forum_body_emphasis_text_input.dart';
import 'forum_body_inline_paragraph_request.dart';
import 'forum_body_inline_plan_input.dart';
import 'forum_body_inline_plan_preparation.dart';

/// Complete natural-parent measurement, with immutable source/child plans and
/// actual row geometry. Isolation, row allocation and visible admission
/// still belong to the containing format; this is not readable page content.
final class ForumBodyInlineEmphasisParentMetrics {
  const ForumBodyInlineEmphasisParentMetrics._(
    this.page,
    this.geometry,
    this.textScaler,
    this.requestWidth,
  );
  final ForumBodyInlinePageContent page;
  final ForumBodyInlineEmphasisTextGeometry geometry;
  final TextScaler textScaler;

  /// Native request constraint; intrinsic output width may be smaller.
  final double requestWidth;
  Map<double, double> get effectiveScales =>
      (textScaler as _CapturedInlineScaler).values;
  ForumBodyInlineEmphasisTextInput get text => geometry.input;
  ForumBodyInlineParagraphRequest get parentRequest =>
      ForumBodyInlineParagraphRequest(
        content: text.glyphInput.glyphs,
        dimensions: page.dimensions,
        layoutMode: page.layoutMode,
      );
}

enum _ParentPhase {
  source,
  text,
  inputFonts,
  parentFonts,
  initial,
  geometry,
  ready,
  transferred,
  closed,
}

/// Measures the natural inline parent and captures its actual row geometry.
/// Native work shares the caller's cache and frozen per-size scaling.
final class ForumBodyInlineEmphasisParentPreparation {
  ForumBodyInlineEmphasisParentPreparation({
    required ForumBodyInlinePlanInput input,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
    int maxUnits = 32768,
    int maxBoxes = 32768,
    int maxGlyphQueries = 16384,
    int maxFontSizes = 2048,
  }) : this._(
         input,
         null,
         input.width,
         cache,
         textScaler,
         ensureOwner,
         null,
         additionalOwnedLeases,
         maxUnits,
         maxBoxes,
         maxGlyphQueries,
         maxFontSizes,
       );

  ForumBodyInlineEmphasisParentPreparation.fromFlow({
    required ForumBodyInlineFlowContent input,
    required double width,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    void Function(ForumBodyInlinePlanInput)? validateInput,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
    int maxUnits = 32768,
    int maxBoxes = 32768,
    int maxGlyphQueries = 16384,
    int maxFontSizes = 2048,
  }) : this._(
         null,
         input,
         width,
         cache,
         textScaler,
         ensureOwner,
         validateInput,
         additionalOwnedLeases,
         maxUnits,
         maxBoxes,
         maxGlyphQueries,
         maxFontSizes,
       );

  ForumBodyInlineEmphasisParentPreparation._(
    this._input,
    ForumBodyInlineFlowContent? flow,
    this.width,
    this._cache,
    this._callerScaler,
    this._ensureOwner,
    this._validateInput,
    this._additionalOwned,
    this.maxUnits,
    this.maxBoxes,
    this.maxGlyphQueries,
    this.maxFontSizes,
  ) {
    if (maxUnits < 0 ||
        maxBoxes < 0 ||
        maxGlyphQueries < 0 ||
        maxFontSizes <= 0) {
      throw ArgumentError('Invalid mixed parent measurement budget');
    }
    try {
      _guard();
      if (!width.isFinite || width <= 0 || width > 16384) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.width,
        );
      }
      if (flow != null) {
        _flow = flow;
        _phase = _ParentPhase.source;
      } else {
        _beginText();
      }
    } catch (_) {
      close();
      rethrow;
    }
  }

  final double width;
  final int maxUnits, maxBoxes, maxGlyphQueries, maxFontSizes;
  ForumBodyInlinePlanInput? _input;
  ForumBodyParagraphCache? _cache;
  TextScaler? _callerScaler;
  void Function()? _ensureOwner;
  void Function(ForumBodyInlinePlanInput)? _validateInput;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyInlineFlowContent? _flow;
  ForumBodyInlineEmphasisTextPreparation? _textWork;
  ForumBodyInlineEmphasisTextInput? _text;
  Iterator<double>? _samples;
  Map<double, double> _scales = {};
  _CapturedInlineScaler? _scaler;
  ForumBodyInlinePlanPreparation? _initialWork;
  ForumBodyInlinePageContent? _initialPage;
  ForumBodyInlineParagraphLease? _natural;
  ForumBodyInlineEmphasisGeometryPreparation? _geometryWork;
  ForumBodyInlineEmphasisParentMetrics? _result;
  var _phase = _ParentPhase.text;
  bool _operating = false, _cacheMiss = false;
  int _blockedAt = -1;
  bool get isReady => _phase == _ParentPhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_natural,
    if (_initialWork != null) ..._initialWork!.nativeLeases,
  ];

  ForumBodyEmphasisLineStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Mixed parent measurement is reentrant');
    _operating = true;
    var used = 0;
    final cache = _cache, before = cache?.layoutBuildCount ?? 0;
    ForumBodyEmphasisLineStep step([bool waiting = false]) {
      return (
        partsPrepared: used,
        nativeLayoutsBuilt: cache!.layoutBuildCount - before,
        picturesRecorded: 0,
        waitingForLayoutBudget: waiting,
      );
    }

    try {
      _guard();
      _cacheMiss = false;
      if (_blockedAt == cache!.budgetRevision) return step(true);
      _blockedAt = -1;
      final revision = cache.budgetRevision;
      ForumBodyEmphasisLineStep wait() {
        if (revision == cache.budgetRevision) _blockedAt = revision;
        return step(true);
      }

      while (!isReady && used < maxParts && cache.layoutBuildCount == before) {
        _guard();
        switch (_phase) {
          case _ParentPhase.source:
            final input = ForumBodyInlinePlanInput(_flow!, width);
            used++;
            _flow = null;
            _validateInput?.call(input);
            _guard();
            _validateInput = null;
            _input = input;
            _beginText();
            continue;
          case _ParentPhase.text:
            final work = _textWork!;
            used += work.advance(maxParts: maxParts - used);
            _guard();
            if (work.isReady) {
              _text = work.takeInput();
              _textWork = null;
              if (_text!.units.isNotEmpty) {
                throw ArgumentError('Inline font frames require plain text');
              }
              _samples = _input!.nativeFontSizes.iterator;
              _phase = _ParentPhase.inputFonts;
            }
            continue;
          case _ParentPhase.inputFonts:
          case _ParentPhase.parentFonts:
            if (_samples!.moveNext()) {
              _capture(_samples!.current);
            } else if (_phase == _ParentPhase.inputFonts) {
              _samples = _text!.nativeFontSizes.iterator;
              _phase = _ParentPhase.parentFonts;
            } else {
              _samples = null;
              _scaler = _CapturedInlineScaler(UnmodifiableMapView(_scales));
              _scales = {};
              _callerScaler = null;
              _initialWork = ForumBodyInlinePlanPreparation.emphasisParent(
                input: _input!,
                glyphInput: _text!.glyphInput,
                cache: cache,
                textScaler: _scaler!,
                ensureOwner: _guard,
                additionalOwnedLeases: _additionalOwned,
              );
              _phase = _ParentPhase.initial;
            }
          case _ParentPhase.initial:
            final work = _initialWork!;
            final s = work.advance(
              maxParts: maxParts - used,
              cachedOnly: cachedOnly,
            );
            used += s.partsPrepared;
            _guard();
            _cacheMiss = work.cacheMiss;
            if (s.waitingForLayoutBudget) return wait();
            if (_cacheMiss) return step();
            if (work.isReady) {
              final value = work.takeEmphasisParent();
              try {
                _guard();
              } catch (_) {
                value.lease.release();
                rethrow;
              }
              _natural = value.lease;
              _initialPage = value.plan;
              _initialWork = null;
              _input = null; // The mutable band input is never published.
              _geometryWork = ForumBodyInlineEmphasisGeometryPreparation(
                input: _text!,
                parent: _natural!,
                ensureOwner: _guard,
                maxBoxes: maxBoxes,
                maxGlyphQueries: maxGlyphQueries,
              );
              _phase = _ParentPhase.geometry;
            }
            continue;
          case _ParentPhase.geometry:
            final work = _geometryWork!;
            used += work.advance(maxParts: maxParts - used);
            _guard();
            if (work.isReady) {
              final geometry = work.takeGeometry();
              _geometryWork = null;
              final page = _initialPage!;
              if (!identical(page.content, geometry.input.content)) {
                throw const ForumBodyEmphasisGeometryException(
                  ForumBodyEmphasisGeometryFailure.source,
                );
              }
              _result = ForumBodyInlineEmphasisParentMetrics._(
                page,
                geometry,
                _scaler!,
                width,
              );
              _phase = _ParentPhase.ready;
            }
            continue;
          case _ParentPhase.ready:
          case _ParentPhase.transferred:
          case _ParentPhase.closed:
            throw StateError('Mixed parent measurement is retired');
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

  ({
    ForumBodyInlineEmphasisParentMetrics metrics,
    ForumBodyInlineParagraphLease parent,
  })
  takeMeasurement() {
    if (_operating) throw StateError('Mixed parent measurement is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Mixed parent measurement is incomplete');
      final result = (metrics: _result!, parent: _natural!);
      _natural = null;
      _phase = _ParentPhase.transferred;
      _drop();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _beginText() {
    _textWork = ForumBodyInlineEmphasisTextPreparation(
      content: _input!.content,
      ensureOwner: _guard,
      maxUnits: maxUnits,
    );
    _phase = _ParentPhase.text;
  }

  void _capture(double size) {
    if (!size.isFinite || size <= 0) _invalidScale();
    if (_scales.containsKey(size)) return;
    if (_scales.length >= maxFontSizes) {
      throw const ForumBodyEmphasisGeometryException(
        ForumBodyEmphasisGeometryFailure.limit,
      );
    }
    final scaled = _callerScaler!.scale(size);
    _guard();
    if (!scaled.isFinite || scaled <= 0 || scaled > 4096) _invalidScale();
    _scales[size] = scaled;
  }

  static Never _invalidScale() => throw const ForumBodyParagraphLayoutException(
    ForumBodyParagraphLayoutFailure.scale,
  );

  void _guard() {
    if (_phase == _ParentPhase.closed || _phase == _ParentPhase.transferred) {
      throw StateError('Mixed parent measurement is retired');
    }
    _ensureOwner!();
    if (_phase == _ParentPhase.closed ||
        _phase == _ParentPhase.transferred ||
        _cache!.isClosed ||
        (_natural != null && !_cache!.ownsLease(_natural!))) {
      throw StateError('Mixed parent measurement owner is retired');
    }
  }

  void close() {
    if (_phase == _ParentPhase.closed || _phase == _ParentPhase.transferred) {
      return;
    }
    _phase = _ParentPhase.closed;
    try {
      _natural?.release();
    } finally {
      _natural = null;
      _drop();
    }
  }

  void _drop() {
    _flow = null;
    _textWork?.close();
    _textWork = null;
    _initialWork?.close();
    _initialWork = null;
    _geometryWork?.close();
    _geometryWork = null;
    _input = null;
    _initialPage = null;
    _text = null;
    _samples = null;
    _scales = {};
    _scaler = null;
    _callerScaler = null;
    _additionalOwned = null;
    _validateInput = null;
    _ensureOwner = null;
    _cache = null;
    _result = null;
  }
}

final class _CapturedInlineScaler extends TextScaler {
  const _CapturedInlineScaler(this.values);
  final Map<double, double> values;
  @override
  double scale(double fontSize) =>
      values[fontSize] ??
      (throw StateError('Mixed parent native font size was not captured'));
  @override
  double get textScaleFactor =>
      throw StateError('Use captured per-size values');
}
