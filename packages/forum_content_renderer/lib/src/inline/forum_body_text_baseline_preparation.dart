import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_text_request.dart';
import 'forum_body_text_baseline_layout.dart';

/// One text request in the existing page transaction. Shape and first paint
/// occupy separate quanta; numeric-only callers release their temporary lease.
final class ForumBodyTextBaselinePreparation {
  ForumBodyTextBaselinePreparation({
    required ForumBodyParagraphCache cache,
    required this.request,
    required this.baselineShift,
    required this.width,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    this.preparePaint = true,
    this.expectedMetrics,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _cache = cache,
       _textScaler = textScaler,
       _ensureOwner = ensureOwner,
       _additionalOwned = additionalOwnedLeases {
    if (!width.isFinite ||
        width <= 0 ||
        width > 16384 ||
        !baselineShift.isFinite ||
        baselineShift.abs() > 16384) {
      throw ArgumentError('Invalid baseline preparation geometry');
    }
  }

  final ForumBodyTextRequest request;
  final double baselineShift, width;
  final bool preparePaint;
  final ForumBodyTextBaselineMetrics? expectedMetrics;
  ForumBodyParagraphCache? _cache;
  TextScaler? _textScaler;
  void Function()? _ensureOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyTextLease? _pending;
  ForumBodyTextBaselineLayout? _layout;
  bool _ready = false, _closed = false, _operating = false, _waiting = false;
  int _work = 0, _blockedRevision = -1;
  bool cacheMiss = false;
  ForumBodyParagraphBudgetException? _rejection;
  bool get isReady => _ready && !_closed;
  int get workCount => _work;
  ForumBodyParagraphBudgetException? get lastBudgetRejection =>
      _waiting ? _rejection : null;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_pending,
    if (_layout != null) _layout!.lease,
  ];

  ({int partsPrepared, bool isReady, bool waitingForLayoutBudget}) advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Baseline preparation is reentrant');
    _operating = true;
    var units = 0;
    try {
      _guard();
      final cache = _cache!;
      cacheMiss = false;
      if (_waiting && cache.budgetRevision == _blockedRevision) {
        return (partsPrepared: 0, isReady: false, waitingForLayoutBudget: true);
      }
      _waiting = false;
      _rejection = null;
      final builds = cache.layoutBuildCount, pictures = cache.pictureBuildCount;
      var rejectedAt = cache.budgetRevision;
      try {
        while (!isReady && units < maxParts) {
          if (_layout == null && _pending == null) {
            rejectedAt = cache.budgetRevision;
            final lease = request.acquire(
              cache,
              width: width,
              textScaler: _textScaler!,
              cachedOnly: cachedOnly,
            );
            try {
              _guard();
            } catch (_) {
              lease?.release();
              rethrow;
            }
            units++;
            if (lease == null) {
              cacheMiss = true;
              break;
            }
            _pending = lease;
          } else if (_layout == null) {
            final lease = _pending!;
            _pending = null;
            _layout = ForumBodyTextBaselineLayout.adopt(
              cache: cache,
              lease: lease,
              baselineShift: baselineShift,
            );
            final expected = expectedMetrics, actual = _layout!.metrics;
            if (expected != null &&
                (expected.childBounds != actual.childBounds ||
                    expected.childBaseline != actual.childBaseline ||
                    expected.baselineShift != actual.baselineShift)) {
              throw StateError('Baseline text geometry differs from its plan');
            }
            units++;
          } else if (preparePaint && !_layout!.isPaintPrepared) {
            if (cachedOnly) {
              cacheMiss = true;
              break;
            }
            rejectedAt = cache.budgetRevision;
            cache.prepareTextPaint(_layout!.lease);
            units++;
          } else {
            _ready = true;
            units++;
          }
          _guard();
          if (cache.layoutBuildCount != builds ||
              cache.pictureBuildCount != pictures) {
            break;
          }
        }
      } on ForumBodyParagraphBudgetException catch (error) {
        _guard();
        final owned =
            _additionalOwned?.call() ?? const <ForumBodyNativeParagraphLease>[];
        _guard();
        final external = cache.isBlockedByExternalPins(error, [
          ...nativeLeases,
          ...owned,
        ]);
        _guard();
        if (cache.budgetRevision != rejectedAt) {
          units++;
        } else {
          if (!external) rethrow;
          _rejection = error;
          _blockedRevision = rejectedAt;
          _waiting = true;
        }
      }
      _work += units;
      return (
        partsPrepared: units,
        isReady: isReady,
        waitingForLayoutBudget: _waiting,
      );
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyTextBaselineLayout takeLayout() => _transfer(true, () {
    final result = _layout!;
    _layout = null;
    return result;
  });

  ForumBodyTextBaselineMetrics takeMetrics() =>
      _transfer(false, () => _layout!.metrics);

  T _transfer<T>(bool paint, T Function() take) {
    if (_operating || preparePaint != paint || !isReady) {
      throw StateError('No qualified baseline result to transfer');
    }
    _operating = true;
    try {
      _guard();
      final result = take();
      close();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_closed) throw StateError('Baseline preparation is retired');
    _ensureOwner!();
    if (_closed ||
        _cache!.isClosed ||
        (_pending != null && !_cache!.ownsLease(_pending!)) ||
        (_layout != null && _layout!.isDisposed)) {
      throw StateError('Baseline preparation owner is retired');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _pending?.release();
    _layout?.close();
    _pending = null;
    _layout = null;
    _cache = null;
    _textScaler = null;
    _ensureOwner = null;
    _additionalOwned = null;
  }
}
