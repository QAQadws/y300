import 'package:flutter/painting.dart';

import '../flow/forum_body_inline_flow_content.dart';
import '../inline/forum_body_inline_font_frame_plan.dart';
import '../inline/forum_body_inline_font_overflow.dart';
import '../inline/forum_body_inline_plan_input.dart';
import '../inline/forum_body_inline_plan_preparation.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_text_page_content.dart';

enum _InlineAdmissionPhase {
  initial,
  probe,
  frames,
  alias,
  ready,
  transferred,
  closed,
}

/// One source preparation, with conditional font-frame allocation. A fitting
/// natural input transfers its same lease. Overflow reuses existing full-source
/// numeric workers and transfers only a qualified natural alias to composition.
final class ForumBodyInlinePageAdmission {
  ForumBodyInlinePageAdmission({
    ForumBodyInlineFlowContent? input,
    ForumBodyInlinePlanInput? continuation,
    ForumBodyInlinePlanInput? prefix,
    bool keepTrailingSpace = false,
    required double width,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    required void Function(int text, int runs) validateCounts,
  }) : _cache = cache,
       _scaler = textScaler,
       _ensureOwner = ensureOwner,
       _validateCounts = validateCounts {
    try {
      _guard();
      if (continuation != null) {
        if (input != null || prefix != null || continuation.width != width) {
          throw ArgumentError(
            'Inline continuation belongs to a different input',
          );
        }
        _validateSource(continuation);
        _initial = ForumBodyInlinePlanPreparation(
          input: continuation,
          cache: cache,
          textScaler: textScaler,
          ensureOwner: _guard,
        );
      } else {
        if (input == null) throw ArgumentError.notNull('input');
        _initial = ForumBodyInlinePlanPreparation.fromFlow(
          input: input,
          prefix: prefix,
          keepTrailingSpace: keepTrailingSpace,
          width: width,
          cache: cache,
          textScaler: textScaler,
          ensureOwner: _guard,
          validateInput: _validateSource,
        );
      }
    } catch (_) {
      close();
      rethrow;
    }
  }
  ForumBodyParagraphCache? _cache;
  TextScaler? _scaler;
  void Function()? _ensureOwner;
  void Function(int, int)? _validateCounts;
  ForumBodyInlinePlanInput? _readySource;
  ForumBodyInlinePlanPreparation? _initial;
  ForumBodyInlineFontOverflowPreparation? _probe;
  ForumBodyInlineFontFramePreparation? _frames;
  ForumBodyInlineFontFrameMeasurement? _measurement;
  ForumBodyInlinePageContent? _content;
  ForumBodyInlineParagraphLease? _lease;
  var _phase = _InlineAdmissionPhase.initial;
  bool _operating = false;
  bool get isReady => _phase == _InlineAdmissionPhase.ready;
  ForumBodyInlinePlanInput get readySource {
    _guard();
    if (!isReady) throw StateError('Inline admission is incomplete');
    return _content!.fontFrames?.source ?? _readySource!;
  }

  void _validateSource(ForumBodyInlinePlanInput source) {
    _validateCounts!(source.retainedTextCodeUnits, source.retainedRuns);
    _guard();
  }

  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    if (_initial != null) yield* _initial!.nativeLeases;
    if (_frames != null) yield* _frames!.nativeLeases;
    if (_measurement != null) yield* _measurement!.nativeLeases;
    if (_lease != null) yield _lease!;
  }

  ({int partsPrepared, bool waitingForLayoutBudget, bool isReady}) advance({
    int maxParts = 32,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Inline admission is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      final cache = _cache!, builds = cache.layoutBuildCount;
      while (!isReady && used < maxParts && cache.layoutBuildCount == builds) {
        switch (_phase) {
          case _InlineAdmissionPhase.initial:
            final step = _initial!.advance(maxParts: maxParts - used);
            used += step.partsPrepared;
            if (step.waitingForLayoutBudget) {
              return (
                partsPrepared: used,
                waitingForLayoutBudget: true,
                isReady: false,
              );
            }
            if (!_initial!.isReady) break;
            _readySource = _initial!.readySource;
            final ready = _initial!.take();
            _initial = null;
            _lease = ready.lease;
            _content = ready.content;
            if (ready.content.layoutMode != ForumBodyParagraphLayoutMode.wrap) {
              _phase = _InlineAdmissionPhase.ready;
            } else {
              _probe = ForumBodyInlineFontOverflowPreparation(
                parent: ready.lease,
                ensureOwner: _guard,
              );
              _phase = _InlineAdmissionPhase.probe;
            }
          case _InlineAdmissionPhase.probe:
            used += _probe!.advance(maxParts: maxParts - used);
            if (!_probe!.isReady) break;
            final overflow = _probe!.take();
            _probe = null;
            if (!overflow) {
              _phase = _InlineAdmissionPhase.ready;
            } else {
              // Natural measurement can split a word that exceeds the width.
              // Allocate frames for the resulting source and its current atoms.
              final source = _readySource!;
              _validateCounts!(
                _content!.retainedTextCodeUnits + source.retainedTextCodeUnits,
                _content!.retainedRuns + source.retainedRuns,
              );
              _guard();
              _lease!.release();
              _lease = null;
              _content = null;
              _frames = ForumBodyInlineFontFramePreparation(
                input: source,
                cache: cache,
                textScaler: _scaler!,
                ensureOwner: _guard,
              );
              _phase = _InlineAdmissionPhase.frames;
            }
          case _InlineAdmissionPhase.frames:
            final step = _frames!.advance(maxParts: maxParts - used);
            used += step.partsPrepared;
            if (step.waitingForLayoutBudget) {
              return (
                partsPrepared: used,
                waitingForLayoutBudget: true,
                isReady: false,
              );
            }
            if (!_frames!.isReady) break;
            _measurement = _frames!.takeMeasurement();
            _frames = null;
            _content = ForumBodyInlinePageContent.withFontFrames(
              _measurement!.plan,
            );
            _validateCounts!(
              _content!.retainedTextCodeUnits,
              _content!.retainedRuns,
            );
            _guard();
            _phase = _InlineAdmissionPhase.alias;
          case _InlineAdmissionPhase.alias:
            final metrics = _measurement!.plan.allocation.input.natural;
            _lease = metrics.parentRequest.acquire(
              cache,
              width: metrics.requestWidth,
              textScaler: metrics.textScaler,
              cachedOnly: true,
            );
            _guard();
            if (_lease == null ||
                !_lease!.hasSameActiveOwner(_measurement!.natural) ||
                !identical(
                  _lease!.layout.lines,
                  _measurement!.natural.layout.lines,
                )) {
              throw StateError('Measured natural parent disappeared');
            }
            _measurement!.close();
            _measurement = null;
            _phase = _InlineAdmissionPhase.ready;
            used++;
          case _InlineAdmissionPhase.ready:
          case _InlineAdmissionPhase.transferred:
          case _InlineAdmissionPhase.closed:
            throw StateError('Inline admission is retired');
        }
        _guard();
      }
      return (
        partsPrepared: used,
        waitingForLayoutBudget: false,
        isReady: isReady,
      );
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ({ForumBodyInlinePageContent content, ForumBodyInlineParagraphLease lease})
  take() {
    if (_operating) throw StateError('Inline admission is reentrant');
    _guard();
    if (!isReady) throw StateError('Inline admission is incomplete');
    final result = (content: _content!, lease: _lease!);
    _lease = null;
    _phase = _InlineAdmissionPhase.transferred;
    _drop();
    return result;
  }

  void _guard() {
    if (_phase == _InlineAdmissionPhase.closed ||
        _phase == _InlineAdmissionPhase.transferred) {
      throw StateError('Inline admission is retired');
    }
    _ensureOwner!();
    if (_phase == _InlineAdmissionPhase.closed ||
        _phase == _InlineAdmissionPhase.transferred ||
        _cache!.isClosed ||
        (_lease != null && !_cache!.ownsLease(_lease!))) {
      throw StateError('Inline admission owner is retired');
    }
  }

  void close() {
    if (_phase == _InlineAdmissionPhase.closed ||
        _phase == _InlineAdmissionPhase.transferred) {
      return;
    }
    _phase = _InlineAdmissionPhase.closed;
    try {
      _initial?.close();
      _probe?.close();
      _frames?.close();
      _measurement?.close();
    } finally {
      _lease?.release();
      _drop();
    }
  }

  void _drop() {
    _cache = null;
    _scaler = null;
    _ensureOwner = null;
    _validateCounts = null;
    _readySource = null;
    _initial = null;
    _probe = null;
    _frames = null;
    _measurement = null;
    _content = null;
    _lease = null;
  }
}
