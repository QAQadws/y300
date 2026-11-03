import 'package:flutter/painting.dart';

import 'forum_body_paragraph_cache.dart';
import 'forum_body_text_request.dart';

enum _MemberState { active, ready, transferred, failed, closed }

/// One native request, sharing the existing cache's pin/byte/recording rules.
/// It stops after the first shape OR picture and owns only its pending lease.
/// A component/page remains responsible for probing its complete footprint.
final class ForumBodyTextRequestPreparation {
  ForumBodyTextRequestPreparation({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextRequest request,
    required void Function() ensureOwner,
    required this.preparePaint,
    TextScaler textScaler = TextScaler.noScaling,
    this.width = 16384,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _cache = cache,
       _request = request,
       _ensureOwner = ensureOwner,
       _scaler = textScaler,
       _additionalOwned = additionalOwnedLeases;
  ForumBodyParagraphCache? _cache;
  ForumBodyTextRequest? _request;
  void Function()? _ensureOwner;
  TextScaler? _scaler;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  final bool preparePaint;
  final double width;
  ForumBodyTextLease? _pending;
  ForumBodyParagraphBudgetProbe? _probe;
  ForumBodyParagraphBudgetException? _rejection;
  var _blockedRevision = -1;
  var _state = _MemberState.active;
  var _operating = false;
  bool get isReady => _state == _MemberState.ready;
  ForumBodyParagraphBudgetException? get lastBudgetRejection => _rejection;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [?_pending];

  ({int units, bool waiting, bool cacheMiss}) advance({
    bool cachedOnly = false,
  }) => _operate(() {
    _guard();
    if (isReady) return (units: 0, waiting: false, cacheMiss: false);
    final cache = _cache!;
    if (_rejection != null && cache.budgetRevision == _blockedRevision) {
      return (units: 0, waiting: true, cacheMiss: false);
    }
    final builds = cache.layoutBuildCount;
    final rejectedAt = cache.budgetRevision;
    _rejection = null;
    try {
      if (_pending == null) {
        final acquired = _request!.acquire(
          cache,
          width: width,
          textScaler: _scaler!,
          cachedOnly: cachedOnly,
        );
        try {
          _guard();
        } catch (_) {
          acquired?.release();
          rethrow;
        }
        _pending = acquired;
        if (_pending == null) {
          return (units: 1, waiting: false, cacheMiss: true);
        }
      }
      if (preparePaint && !_pending!.layout.isPaintPrepared) {
        if (cachedOnly) return (units: 1, waiting: false, cacheMiss: true);
        if (cache.layoutBuildCount != builds) {
          return (units: 1, waiting: false, cacheMiss: false);
        }
        cache.prepareTextPaint(_pending!);
        _guard();
      }
      _state = _MemberState.ready;
      return (units: 1, waiting: false, cacheMiss: false);
    } on ForumBodyParagraphBudgetException catch (error) {
      _guard();
      if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
      final additional =
          _additionalOwned?.call() ?? const <ForumBodyNativeParagraphLease>[];
      _guard();
      final external = cache.isBlockedByExternalPins(error, [
        ...nativeLeases,
        ...additional,
      ]);
      _guard();
      if (cache.budgetRevision != rejectedAt) {
        _blockedRevision = -1;
        return (units: 1, waiting: false, cacheMiss: false);
      }
      if (!external) {
        throw ForumBodyParagraphBudgetException(
          ForumBodyParagraphBudgetFailure.content,
          requiredEstimatedBytes: error.requiredEstimatedBytes,
          requiredAdditionalEntries: error.requiredAdditionalEntries,
        );
      }
      final probe = _probe = cache.createBudgetProbe();
      try {
        _request!.includeBudget(probe, width: width, textScaler: _scaler!);
        _guard();
      } finally {
        probe.close();
        _probe = null;
      }
      _rejection = error;
      _blockedRevision = rejectedAt;
      return (
        units: 1,
        waiting: cache.budgetRevision == rejectedAt,
        cacheMiss: false,
      );
    }
  });

  ForumBodyTextLease takeLease() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Text request preparation is incomplete');
    final lease = _pending!;
    _pending = null;
    _state = _MemberState.transferred;
    _dropOwner();
    return lease;
  });
  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Text request preparation is reentrant');
    _operating = true;
    try {
      return action();
    } catch (_) {
      _retire(_MemberState.failed);
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_state != _MemberState.active && !isReady) {
      throw StateError('Text request preparation is retired');
    }
    _ensureOwner!();
    if ((_state != _MemberState.active && !isReady) ||
        _cache!.isClosed ||
        (_pending != null && !_cache!.ownsLease(_pending!))) {
      throw StateError('Text request owner is retired');
    }
  }

  void _retire(_MemberState state) {
    if (_state != _MemberState.active && !isReady) return;
    _state = state;
    _pending?.release();
    _pending = null;
    _dropOwner();
  }

  void _dropOwner() {
    _probe?.close();
    _probe = null;
    _cache = null;
    _request = null;
    _scaler = null;
    _ensureOwner = null;
    _additionalOwned = null;
    _rejection = null;
  }

  void close() => _retire(_MemberState.closed);
}
