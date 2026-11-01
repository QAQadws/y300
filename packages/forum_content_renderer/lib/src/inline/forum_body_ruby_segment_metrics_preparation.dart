import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_text_request.dart';
import '../paragraph/forum_body_text_request_preparation.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_group_preparation.dart';
import 'forum_body_ruby_segment_request.dart';
import 'forum_body_text_band_layout.dart';

enum ForumBodyRubySegmentMetricsPreparationState {
  active,
  ready,
  transferred,
  failed,
  closed,
}

/// Glyph-only component planning: release each measured member before reading
/// the next, then drive the existing pure span composition in bounded units.
/// This is not the visible component's complete pin-budget/adoption transaction.
final class ForumBodyRubySegmentMetricsPreparation {
  ForumBodyRubySegmentMetricsPreparation({
    required ForumBodyParagraphCache cache,
    required ForumBodyRubySegmentRequest request,
    required void Function() ensureOwner,
    TextScaler textScaler = TextScaler.noScaling,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _cache = cache,
       _request = request,
       _ensureOwner = ensureOwner,
       _scaler = textScaler,
       _additionalOwned = additionalOwnedLeases;
  ForumBodyParagraphCache? _cache;
  ForumBodyRubySegmentRequest? _request;
  void Function()? _ensureOwner;
  TextScaler? _scaler;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyRubyGroupPreparation? _base;
  ForumBodyTextRequestPreparation? _span;
  ForumBodyRubySegmentComposition? _composition;
  final _columns = <ForumBodyRubyGroupMetrics>[];
  final _gaps = <ForumBodyRubyMeasuredGap>[];
  final _measured = <ForumBodyRubyMeasuredSpan>[];
  ForumBodyRubySegmentMetrics? _result;
  ForumBodyTextRequest? _failedRequest;
  var _state = ForumBodyRubySegmentMetricsPreparationState.active;
  var _operating = false;
  var _waiting = false;
  var _cacheMiss = false;
  var _preparedColumns = 0;
  var _preparedSpans = 0;
  int get preparedColumnCount => _preparedColumns;
  int get preparedSpanCount => _preparedSpans;
  int get preparedGapCount => _gaps.length;
  ForumBodyRubySegmentMetricsPreparationState get state => _state;
  bool get isReady =>
      _state == ForumBodyRubySegmentMetricsPreparationState.ready;
  bool get cacheMiss => _cacheMiss;
  ForumBodyTextRequest? get failedRequest => _failedRequest;
  ForumBodyTextRequest? get currentRequest => _request == null
      ? null
      : _columns.length < _request!.bases.length
      ? _request!.bases[_columns.length]
      : _gaps.length < _request!.gaps.length
      ? _request!.gaps[_gaps.length].request
      : _measured.length < _request!.spans.length
      ? _request!.spans[_measured.length].request
      : null;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    if (_base != null) ..._base!.nativeLeases,
    if (_span != null) ..._span!.nativeLeases,
  ];
  ForumBodyParagraphBudgetException? get lastBudgetRejection => !_waiting
      ? null
      : _base?.lastBudgetRejection ?? _span?.lastBudgetRejection;

  ForumBodyRubyGroupPreparationStep advance({int maxParts = 32}) {
    if (_state != ForumBodyRubySegmentMetricsPreparationState.active) {
      throw StateError('Segment metrics are not active');
    }
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() => _advance(maxParts, false));
  }

  bool tryPrepareCached({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      return isReady || _advance(maxParts, true).isReady;
    });
  }

  ForumBodyRubyGroupPreparationStep _advance(int maxParts, bool cachedOnly) {
    _guard();
    final cache = _cache!;
    final request = _request!;
    final builds = cache.layoutBuildCount;
    final pictures = cache.pictureBuildCount;
    var units = 0;
    var parts = 0;
    var inspected = 0;
    _waiting = false;
    _cacheMiss = false;
    while (units < maxParts && !isReady) {
      if (cache.layoutBuildCount != builds) break;
      if (_columns.length < request.bases.length ||
          _gaps.length < request.gaps.length) {
        final isGap = _columns.length == request.bases.length;
        // Reuse the actual font-box measurement without consuming a base index
        // or inventing annotation glyphs for the original gap text.
        final base = _base ??= ForumBodyRubyGroupPreparation.forSegmentBase(
          cache: cache,
          base: isGap
              ? request.gaps[_gaps.length].request
              : request.bases[_columns.length],
          sides: request.sides,
          ensureOwner: _guard,
          textScaler: _scaler!,
          maxWidth: request.maxWidth,
          additionalOwnedLeases: _additionalOwned,
        );
        ForumBodyRubyGroupPreparationStep? step;
        final before = base.workCount;
        final partsBefore = base.preparedPartCount;
        if (cachedOnly) {
          base.tryPrepareCached(maxParts: maxParts - units);
        } else {
          step = base.advance(maxParts: maxParts - units);
        }
        final used = base.workCount - before;
        units += used;
        parts += base.preparedPartCount - partsBefore;
        inspected += step?.partsInspected ?? 0;
        _guard();
        _waiting = base.waitingForLayoutBudget;
        _cacheMiss = base.cacheMiss;
        final complete = base.isReady;
        if (complete) {
          final metrics = base.takeMetrics();
          if (isGap) {
            _gaps.add(
              ForumBodyRubyMeasuredGap(
                beforeColumn: request.gaps[_gaps.length].beforeColumn,
                font: metrics,
              ),
            );
          } else {
            _columns.add(metrics);
            _preparedColumns++;
          }
          base.close();
          _base = null;
        }
        if (_waiting || _cacheMiss || (!complete && used == 0)) break;
      } else if (_measured.length < request.spans.length) {
        final input = request.spans[_measured.length];
        final hasText = input.request.content.projection.text.isNotEmpty;
        if (hasText) {
          final member = _span ??= ForumBodyTextRequestPreparation(
            cache: cache,
            request: input.request,
            ensureOwner: _guard,
            preparePaint: false,
            textScaler: _scaler!,
            width: request.maxWidth,
            additionalOwnedLeases: _additionalOwned,
          );
          final step = member.advance(cachedOnly: cachedOnly);
          units += step.units;
          _guard();
          _waiting = step.waiting;
          _cacheMiss = step.cacheMiss;
          if (!member.isReady) break;
          final lease = member.takeLease();
          member.close();
          _span = null;
          try {
            _guard();
            _measure(
              input,
              ForumBodyRubyAnnotationMetrics.measure(
                cache: cache,
                lease: lease,
                side: request.sides[input.annotationIndex],
                gap: input.gap,
              ),
            );
          } finally {
            lease.release();
          }
          parts++;
        } else {
          _measure(
            input,
            ForumBodyRubyAnnotationMetrics.measure(
              cache: cache,
              lease: null,
              side: request.sides[input.annotationIndex],
              gap: input.gap,
            ),
          );
          units++;
        }
        _guard();
      } else {
        final composition = _composition ??= ForumBodyRubySegmentComposition(
          columns: _columns,
          gaps: _gaps,
          spans: _measured,
          direction: request.direction,
          maxWidth: request.maxWidth,
        );
        if (!composition.isComplete) {
          units += composition.advance(maxParts: maxParts - units);
          _guard();
        }
        if (composition.isComplete && units < maxParts) {
          _result = composition.result;
          _composition = null;
          _request = null;
          _scaler = null;
          _columns.clear();
          _measured.clear();
          _state = ForumBodyRubySegmentMetricsPreparationState.ready;
          units++;
        }
      }
    }
    return ForumBodyRubyGroupPreparationStep(
      partsPrepared: parts,
      partsInspected: inspected,
      layoutsBuilt: cache.layoutBuildCount - builds,
      picturesBuilt: cache.pictureBuildCount - pictures,
      formatUnitsPrepared: units,
      isReady: isReady,
      waitingForLayoutBudget: _waiting,
    );
  }

  void _measure(
    ForumBodyRubySpanRequest input,
    ForumBodyRubyAnnotationMetrics value,
  ) {
    _guard();
    _measured.add(
      ForumBodyRubyMeasuredSpan(
        startColumn: input.startColumn,
        endColumn: input.endColumn,
        annotationIndex: input.annotationIndex,
        annotation: value,
      ),
    );
    _preparedSpans++;
  }

  ForumBodyRubySegmentMetrics takeMetrics() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Segment metrics are incomplete');
    final result = _result!;
    _result = null;
    _state = ForumBodyRubySegmentMetricsPreparationState.transferred;
    _dropOwner();
    return result;
  });
  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Segment metric preparation is reentrant');
    _operating = true;
    try {
      return action();
    } catch (error) {
      final failed = error is ForumBodyTextBandLayoutException
          ? currentRequest
          : null;
      _retire(ForumBodyRubySegmentMetricsPreparationState.failed);
      _failedRequest = failed;
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_state != ForumBodyRubySegmentMetricsPreparationState.active &&
        !isReady) {
      throw StateError('Segment metrics are retired');
    }
    _ensureOwner!();
    if ((_state != ForumBodyRubySegmentMetricsPreparationState.active &&
            !isReady) ||
        _cache!.isClosed) {
      throw StateError('Segment metrics owner is retired');
    }
    for (final lease in nativeLeases) {
      if (!_cache!.ownsLease(lease)) {
        throw StateError('Segment metric glyph is retired');
      }
    }
  }

  void _retire(ForumBodyRubySegmentMetricsPreparationState state) {
    if (_state != ForumBodyRubySegmentMetricsPreparationState.active &&
        !isReady) {
      return;
    }
    _state = state;
    _base?.close();
    _base = null;
    _span?.close();
    _span = null;
    _composition = null;
    _columns.clear();
    _gaps.clear();
    _measured.clear();
    _result = null;
    _dropOwner();
  }

  void _dropOwner() {
    _cache = null;
    _request = null;
    _ensureOwner = null;
    _scaler = null;
    _additionalOwned = null;
    _waiting = false;
    _cacheMiss = false;
  }

  void close() {
    _failedRequest = null;
    _retire(ForumBodyRubySegmentMetricsPreparationState.closed);
  }
}
