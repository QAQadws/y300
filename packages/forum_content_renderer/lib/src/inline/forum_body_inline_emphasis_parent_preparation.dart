import 'dart:collection';

import 'package:flutter/painting.dart';

import '../flow/forum_body_inline_flow_content.dart';
import '../pagination/forum_body_text_page_content.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_emphasis_text_geometry.dart';
import 'forum_body_emphasis_text_input.dart';
import 'forum_body_inline_emphasis_child_bands.dart';
import 'forum_body_inline_emphasis_reflow_preparation.dart';
import 'forum_body_inline_emphasis_reflow_reference.dart';
import 'forum_body_inline_emphasis_row_placement.dart';
import 'forum_body_inline_paragraph_request.dart';
import 'forum_body_inline_plan_input.dart';
import 'forum_body_inline_plan_preparation.dart';
import 'forum_body_inline_source_preparation.dart';

/// Complete natural-parent measurement, with immutable source/child plans and
/// the actual final geometry. Isolation, row allocation and visible admission
/// still belong to the containing format; this is not readable page content.
final class ForumBodyInlineEmphasisParentMetrics {
  const ForumBodyInlineEmphasisParentMetrics._(
    this.reflow,
    this.geometry,
    this.textScaler,
    this.requestWidth,
  );
  final ForumBodyInlineEmphasisReflowReference reflow;
  final ForumBodyInlineEmphasisTextGeometry geometry;
  final TextScaler textScaler;

  /// Native request constraint; intrinsic output width may be smaller.
  final double requestWidth;
  Map<double, double> get effectiveScales =>
      (textScaler as _CapturedInlineScaler).values;
  ForumBodyInlinePageContent get page => reflow.children.page;
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
  fonts,
  bands,
  rows,
  reflow,
  releaseOriginal,
  ready,
  transferred,
  closed,
}

/// One cooperative measurement transaction from source to the final natural
/// parent. Freezes all parent/child/marker font sizes before native work, and
/// delegates to the existing workers/cache without introducing a scheduler.
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
        _sourceWork = ForumBodyInlineSourcePreparation(
          input: flow,
          width: width,
          ensureOwner: _guard,
        );
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
  ForumBodyInlineSourcePreparation? _sourceWork;
  ForumBodyInlineEmphasisTextPreparation? _textWork;
  ForumBodyInlineEmphasisTextInput? _text;
  Iterator<double>? _samples;
  Map<double, double> _scales = {};
  _CapturedInlineScaler? _scaler;
  ForumBodyInlinePlanPreparation? _initialWork;
  ForumBodyInlinePageContent? _initialPage;
  ForumBodyInlineParagraphLease? _original, _final;
  ForumBodyInlineEmphasisGeometryPreparation? _geometryWork;
  ForumBodyInlineEmphasisFontPreparation? _fontWork;
  ForumBodyInlineEmphasisChildBandsPreparation? _bandWork;
  ForumBodyInlineEmphasisRowPlacementPreparation? _rowWork;
  ForumBodyInlineEmphasisReflowPreparation? _reflowWork;
  ForumBodyInlineEmphasisParentMetrics? _result;
  var _phase = _ParentPhase.text;
  bool _operating = false, _cacheMiss = false;
  int _blockedAt = -1;
  bool get isReady => _phase == _ParentPhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_original,
    ?_final,
    if (_initialWork != null) ..._initialWork!.nativeLeases,
    if (_fontWork != null) ..._fontWork!.nativeLeases,
    if (_reflowWork != null) ..._reflowWork!.nativeLeases,
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
            final work = _sourceWork!;
            used += work.advance(maxParts: maxParts - used);
            _guard();
            if (work.isReady) {
              final input = work.takeInput();
              _sourceWork = null;
              _validateInput?.call(input);
              _guard();
              _validateInput = null;
              _input = input;
              _beginText();
            }
            continue;
          case _ParentPhase.text:
            final work = _textWork!;
            used += work.advance(maxParts: maxParts - used);
            _guard();
            if (work.isReady) {
              _text = work.takeInput();
              _textWork = null;
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
              _original = value.lease;
              _initialPage = value.plan;
              _initialWork = null;
              _input = null; // The mutable band input is never published.
              _geometryWork = ForumBodyInlineEmphasisGeometryPreparation(
                input: _text!,
                parent: _original!,
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
              _fontWork = ForumBodyInlineEmphasisFontPreparation(
                geometry: geometry,
                parentRequest: ForumBodyInlineParagraphRequest(
                  content: _text!.glyphInput.glyphs,
                  dimensions: _initialPage!.dimensions,
                  layoutMode: _initialPage!.layoutMode,
                ),
                parent: _original!,
                cache: cache,
                ensureOwner: _guard,
                expectedTextScaler: _scaler!,
                width: width,
                additionalOwnedLeases: _additionalOwned,
              );
              _phase = _ParentPhase.fonts;
            }
            continue;
          case _ParentPhase.fonts:
            final work = _fontWork!;
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
              final fonts = work.takeMetrics();
              _fontWork = null;
              _bandWork = ForumBodyInlineEmphasisChildBandsPreparation(
                fonts: fonts,
                page: _initialPage!,
                parent: _original!,
                ensureOwner: _guard,
              );
              _phase = _ParentPhase.bands;
            }
            continue;
          case _ParentPhase.bands:
            final work = _bandWork!;
            used += work.advance(maxParts: maxParts - used);
            _guard();
            if (work.isReady) {
              final bands = work.takeBands();
              _bandWork = null;
              _rowWork = ForumBodyInlineEmphasisRowPlacementPreparation(
                input: bands,
                ensureOwner: _guard,
              );
              _phase = _ParentPhase.rows;
            }
            continue;
          case _ParentPhase.rows:
            final work = _rowWork!;
            used += work.advance(maxParts: maxParts - used);
            _guard();
            if (work.isReady) {
              final placement = work.takePlacement();
              _rowWork = null;
              _reflowWork = ForumBodyInlineEmphasisReflowPreparation(
                placement: placement,
                original: _original!,
                cache: cache,
                ensureOwner: _guard,
                additionalOwnedLeases: _additionalOwned,
                maxBoxes: maxBoxes,
                maxGlyphQueries: maxGlyphQueries,
              );
              _phase = _ParentPhase.reflow;
            }
            continue;
          case _ParentPhase.reflow:
            final work = _reflowWork!;
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
              final value = work.takeMeasurement();
              try {
                _guard();
              } catch (_) {
                value.parent.release();
                rethrow;
              }
              _final = value.parent;
              _reflowWork = null;
              _result = ForumBodyInlineEmphasisParentMetrics._(
                value.reference,
                value.geometry,
                _scaler!,
                width,
              );
              _phase = _ParentPhase.releaseOriginal;
            }
            continue;
          case _ParentPhase.releaseOriginal:
            _original!.release();
            _original = null;
            _initialPage = null;
            _text = null;
            _phase = _ParentPhase.ready;
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
      final result = (metrics: _result!, parent: _final!);
      _final = null;
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
        (_original != null && !_cache!.ownsLease(_original!)) ||
        (_final != null && !_cache!.ownsLease(_final!))) {
      throw StateError('Mixed parent measurement owner is retired');
    }
  }

  void close() {
    if (_phase == _ParentPhase.closed || _phase == _ParentPhase.transferred) {
      return;
    }
    _phase = _ParentPhase.closed;
    try {
      _original?.release();
      _final?.release();
    } finally {
      _original = null;
      _final = null;
      _drop();
    }
  }

  void _drop() {
    _sourceWork?.close();
    _sourceWork = null;
    _textWork?.close();
    _textWork = null;
    _initialWork?.close();
    _initialWork = null;
    _geometryWork?.close();
    _geometryWork = null;
    _fontWork?.close();
    _fontWork = null;
    _bandWork?.close();
    _bandWork = null;
    _rowWork?.close();
    _rowWork = null;
    _reflowWork?.close();
    _reflowWork = null;
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
