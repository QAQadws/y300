import 'package:flutter/painting.dart';

import '../inline/forum_body_emphasis_paragraph_metrics.dart';
import '../inline/forum_body_emphasis_line_layout.dart';
import '../inline/forum_body_emphasis_text_input.dart';
import '../inline/forum_body_fitted_emphasis_plan.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_text_page_content.dart';

enum _AdmissionPhase {
  inspect,
  plain,
  measure,
  entries,
  ready,
  fittedSource,
  fittedMeasure,
  fittedPlan,
  fittedReady,
  closed,
}

/// Selects the paragraph format and prepares only its numeric admission input.
/// The session owns traversal/composition; readable scenes belong to PageJob.
final class ForumBodyEmphasisPageAdmission {
  ForumBodyEmphasisPageAdmission({
    required ForumBodyParagraphContent content,
    required ForumBodyParagraphCache cache,
    required double width,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    required void Function(int text, int runs) validateCounts,
  }) : _content = content,
       _cache = cache,
       _width = width,
       _textScaler = textScaler,
       _ensureOwner = ensureOwner,
       _validateCounts = validateCounts;

  ForumBodyParagraphContent? _content;
  ForumBodyParagraphCache? _cache;
  final double _width;
  TextScaler? _textScaler;
  void Function()? _ensureOwner;
  void Function(int, int)? _validateCounts;
  ForumBodyEmphasisParagraphPreparation? _measurement;
  ForumBodyEmphasisParagraphNativeEntriesPreparation? _entries;
  ForumBodyEmphasisPageContent? _prepared;
  ForumBodyEmphasisParagraphNativeEntries? _result;
  ForumBodyEmphasisTextPreparation? _fittedSource;
  ForumBodyEmphasisLineMetricsPreparation? _fittedMeasure;
  ForumBodyFittedEmphasisPlanPreparation? _fittedPlan;
  ForumBodyFittedEmphasisPageContent? _fittedInput;
  int _style = -1;
  bool _operating = false;
  var _phase = _AdmissionPhase.inspect;

  bool get isReady => isPlain || isFitted || _phase == _AdmissionPhase.ready;
  bool get isFitted => _phase == _AdmissionPhase.fittedReady;
  bool get isPlain => _phase == _AdmissionPhase.plain;
  ForumBodyParagraphContent get plainContent {
    _guard();
    if (!isPlain) throw StateError('Paragraph is not an ordinary input');
    return _content!;
  }

  ({int partsPrepared, bool waitingForLayoutBudget}) advance({
    required int maxParts,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Emphasis admission is reentrant');
    _operating = true;
    var used = 0;
    final cache = _cache, builds = cache?.layoutBuildCount;
    try {
      _guard();
      while (!isReady && used < maxParts && cache!.layoutBuildCount == builds) {
        switch (_phase) {
          case _AdmissionPhase.inspect:
            final content = _content!;
            if (_style == content.runs.length) {
              _phase = _AdmissionPhase.plain;
            } else {
              final style = _style < 0
                  ? content.style
                  : content.runs[_style].style;
              _style++;
              if (style.textEmphasis.isEnabled) {
                if (content.layoutMode ==
                    ForumBodyParagraphLayoutMode.fitSingleLine) {
                  _fittedSource = ForumBodyEmphasisTextPreparation(
                    content: content,
                  );
                  _phase = _AdmissionPhase.fittedSource;
                  used++;
                  break;
                }
                _measurement = ForumBodyEmphasisParagraphPreparation(
                  content: content,
                  cache: cache,
                  width: _width,
                  textScaler: _textScaler!,
                  ensureOwner: _guard,
                );
                _phase = _AdmissionPhase.measure;
              }
            }
            used++;
          case _AdmissionPhase.measure:
            final work = _measurement!;
            final step = work.advance(maxParts: maxParts - used);
            used += step.partsPrepared;
            _guard();
            if (step.waitingForLayoutBudget) {
              return (partsPrepared: used, waitingForLayoutBudget: true);
            }
            if (!work.isReady) {
              return (partsPrepared: used, waitingForLayoutBudget: false);
            }
            final metrics = work.takeMetrics();
            work.close();
            _measurement = null;
            // An actual empty native strut has no source group or mark. Its
            // already qualified glyph input can use the ordinary path; a text
            // suffix or an empty visible substring is not sufficient proof.
            if (metrics.groups.isEmpty) {
              _content = metrics.glyphInput.glyphs;
              _phase = _AdmissionPhase.plain;
            } else {
              final input = ForumBodyEmphasisPageContent(metrics);
              _validateCounts!(input.retainedTextCodeUnits, input.retainedRuns);
              _guard();
              _prepared = input;
              _entries = ForumBodyEmphasisParagraphNativeEntriesPreparation(
                paragraph: metrics,
                cache: cache,
                ensureOwner: _guard,
              );
              _phase = _AdmissionPhase.entries;
            }
          case _AdmissionPhase.entries:
            final work = _entries!;
            used += work.advance(maxParts: maxParts - used);
            _guard();
            if (!work.isReady) {
              return (partsPrepared: used, waitingForLayoutBudget: false);
            }
            _result = work.take();
            work.close();
            _entries = null;
            _phase = _AdmissionPhase.ready;
          case _AdmissionPhase.fittedSource:
            used += _fittedSource!.advance(maxParts: maxParts - used);
            _guard();
            if (!_fittedSource!.isReady) break;
            _fittedMeasure = ForumBodyEmphasisLineMetricsPreparation(
              input: _fittedSource!.takeInput(),
              cache: cache,
              ensureOwner: _guard,
              width: _width,
              textScaler: _textScaler!,
            );
            _fittedSource = null;
            _phase = _AdmissionPhase.fittedMeasure;
          case _AdmissionPhase.fittedMeasure:
            final job = _fittedMeasure!;
            final step = job.advance(maxParts: maxParts - used);
            used += step.partsPrepared;
            _guard();
            if (step.waitingForLayoutBudget) {
              return (partsPrepared: used, waitingForLayoutBudget: true);
            }
            if (!job.isReady) {
              return (partsPrepared: used, waitingForLayoutBudget: false);
            }
            _fittedPlan = ForumBodyFittedEmphasisPlanPreparation(
              metrics: job.takeMetrics(),
              cache: cache,
              ensureOwner: _guard,
            );
            job.close();
            _fittedMeasure = null;
            _phase = _AdmissionPhase.fittedPlan;
          case _AdmissionPhase.fittedPlan:
            used += _fittedPlan!.advance(maxParts: maxParts - used);
            _guard();
            if (_fittedPlan!.isReady) {
              final input = ForumBodyFittedEmphasisPageContent(
                _fittedPlan!.take(),
              );
              _fittedPlan = null;
              _validateCounts!(input.retainedTextCodeUnits, input.retainedRuns);
              _guard();
              _fittedInput = input;
              _phase = _AdmissionPhase.fittedReady;
            }
          case _AdmissionPhase.plain:
          case _AdmissionPhase.ready:
          case _AdmissionPhase.fittedReady:
          case _AdmissionPhase.closed:
            throw StateError('Emphasis admission is not active');
        }
        _guard();
      }
      return (partsPrepared: used, waitingForLayoutBudget: false);
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ({
    ForumBodyEmphasisPageContent content,
    ForumBodyEmphasisParagraphNativeEntries entries,
  })
  take() {
    if (_operating) throw StateError('Emphasis admission is reentrant');
    _guard();
    if (_phase != _AdmissionPhase.ready) {
      throw StateError('Emphasis admission is incomplete');
    }
    final result = (content: _prepared!, entries: _result!);
    close();
    return result;
  }

  ForumBodyFittedEmphasisPageContent takeFitted() {
    if (_operating) throw StateError('Emphasis admission is reentrant');
    _guard();
    if (!isFitted) throw StateError('Fitted emphasis admission is incomplete');
    final result = _fittedInput!;
    close();
    return result;
  }

  void _guard() {
    if (_phase == _AdmissionPhase.closed) {
      throw StateError('Emphasis admission is retired');
    }
    _ensureOwner!();
    if (_phase == _AdmissionPhase.closed || _cache?.isClosed != false) {
      throw StateError('Emphasis admission owner is retired');
    }
  }

  void close() {
    if (_phase == _AdmissionPhase.closed) return;
    _phase = _AdmissionPhase.closed;
    _measurement?.close();
    _measurement = null;
    _entries?.close();
    _entries = null;
    _fittedSource?.close();
    _fittedSource = null;
    _fittedMeasure?.close();
    _fittedMeasure = null;
    _fittedPlan?.close();
    _fittedPlan = null;
    _fittedInput = null;
    _prepared = null;
    _result = null;
    _content = null;
    _cache = null;
    _textScaler = null;
    _ensureOwner = null;
    _validateCounts = null;
  }
}
