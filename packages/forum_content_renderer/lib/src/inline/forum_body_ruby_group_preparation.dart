import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_text_request.dart';
import 'forum_body_ruby_group_layout.dart';
import 'forum_body_ruby_group_metrics.dart';

enum ForumBodyRubyGroupPreparationState {
  active,
  ready,
  transferred,
  failed,
  closed,
}

enum ForumBodyRubyGroupPreparationFailure { intrinsicBudget }

final class ForumBodyRubyGroupPreparationException implements Exception {
  const ForumBodyRubyGroupPreparationException(this.failure);
  final ForumBodyRubyGroupPreparationFailure failure;
  @override
  String toString() =>
      'ForumBodyRubyGroupPreparationException(${failure.name})';
}

final class ForumBodyRubyGroupPreparationStep {
  const ForumBodyRubyGroupPreparationStep({
    required this.partsPrepared,
    required this.layoutsBuilt,
    required this.partsInspected,
    required this.isReady,
    required this.waitingForLayoutBudget,
    this.picturesBuilt = 0,
  });
  final int partsPrepared;
  final int layoutsBuilt;
  final int picturesBuilt;
  final int partsInspected;
  final bool isReady;
  final bool waitingForLayoutBudget;
  bool get madeProgress =>
      partsPrepared > 0 ||
      partsInspected > 0 ||
      layoutsBuilt > 0 ||
      picturesBuilt > 0 ||
      isReady;
}

/// A format-local transaction for one already grouped ruby pair. Each advance
/// stops after its first native shape OR picture; cached work and a whole-pair
/// budget probe are bounded by two parts. Glyph-only planning uses this same
/// transaction without pictures and releases its pins before numeric readiness.
/// No timer, scheduler, DOM or persistent anchor is
/// owned here. The page/session owner supplies its generation guard and yields
/// between work units using its existing cooperative scheduler.
final class ForumBodyRubyGroupPreparation {
  factory ForumBodyRubyGroupPreparation({
    required ForumBodyParagraphCache cache,
    required ForumBodyParagraphContent base,
    required ForumBodyParagraphContent annotation,
    required void Function() ensureOwner,
    TextScaler textScaler = TextScaler.noScaling,
    double gap = 0,
    double maxWidth = 16384,
  }) => ForumBodyRubyGroupPreparation.fromRequests(
    cache: cache,
    base: ForumBodyTextRequest.paragraph(base),
    annotation: ForumBodyTextRequest.paragraph(annotation),
    ensureOwner: ensureOwner,
    textScaler: textScaler,
    gap: gap,
    maxWidth: maxWidth,
  );

  factory ForumBodyRubyGroupPreparation.fromRequests({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextRequest base,
    required ForumBodyTextRequest annotation,
    required void Function() ensureOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
    TextScaler textScaler = TextScaler.noScaling,
    double gap = 0,
    double maxWidth = 16384,
  }) => _open(
    cache: cache,
    base: base,
    annotation: annotation,
    ensureOwner: ensureOwner,
    additionalOwnedLeases: additionalOwnedLeases,
    textScaler: textScaler,
    gap: gap,
    maxWidth: maxWidth,
    preparePaint: true,
  );

  /// The same transaction for format planning: prepare only glyphs, measure
  /// actual bounds and release child pins before publishing numeric metrics.
  /// Cached acquisition does not require or create child pictures in this mode.
  factory ForumBodyRubyGroupPreparation.forMetrics({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextRequest base,
    required ForumBodyTextRequest annotation,
    required void Function() ensureOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
    TextScaler textScaler = TextScaler.noScaling,
    double gap = 0,
    double maxWidth = 16384,
  }) => _open(
    cache: cache,
    base: base,
    annotation: annotation,
    ensureOwner: ensureOwner,
    additionalOwnedLeases: additionalOwnedLeases,
    textScaler: textScaler,
    gap: gap,
    maxWidth: maxWidth,
    preparePaint: false,
  );

  static ForumBodyRubyGroupPreparation _open({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextRequest base,
    required ForumBodyTextRequest annotation,
    required void Function() ensureOwner,
    required Iterable<ForumBodyNativeParagraphLease> Function()?
    additionalOwnedLeases,
    required TextScaler textScaler,
    required double gap,
    required double maxWidth,
    required bool preparePaint,
  }) {
    ForumBodyRubyGroupLayout.validateInputs(
      base: base.content,
      annotation: annotation.content,
      gap: gap,
      maxWidth: maxWidth,
    );
    if (cache.isClosed) throw StateError('Ruby preparation owner is retired');
    return ForumBodyRubyGroupPreparation._(
      cache,
      base,
      annotation,
      ensureOwner,
      textScaler,
      additionalOwnedLeases,
      gap,
      maxWidth,
      annotation.content.projection.text.isEmpty ? 1 : 2,
      preparePaint,
    );
  }

  ForumBodyRubyGroupPreparation._(
    this._cache,
    ForumBodyTextRequest base,
    ForumBodyTextRequest annotation,
    this._ensureOwner,
    this._textScaler,
    this._additionalOwnedLeases,
    this.gap,
    this.maxWidth,
    this.expectedPartCount,
    this._preparePaint,
  ) : _requests = [base, annotation];

  ForumBodyParagraphCache? _cache;
  List<ForumBodyTextRequest> _requests;
  void Function()? _ensureOwner;
  TextScaler? _textScaler;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwnedLeases;
  ForumBodyParagraphBudgetException? _lastBudgetRejection;
  final double gap;
  final double maxWidth;
  final int expectedPartCount;
  final bool _preparePaint;
  final _leases = <ForumBodyTextLease>[];
  ForumBodyRubyGroupLayout? _group;
  ForumBodyRubyGroupMetrics? _metrics;
  var _state = ForumBodyRubyGroupPreparationState.active;
  var _preparedParts = 0;
  var _waiting = false;
  var _budgetChecked = false;
  var _operating = false;

  ForumBodyRubyGroupPreparationState get state => _state;
  bool get isReady => _state == ForumBodyRubyGroupPreparationState.ready;
  bool get waitingForLayoutBudget => _waiting;
  int get preparedPartCount => _preparedParts;
  ForumBodyParagraphBudgetException? get lastBudgetRejection =>
      _lastBudgetRejection;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ..._leases,
    if (_group != null) ..._group!.nativeLeases,
  ];

  ForumBodyRubyGroupPreparationStep advance() {
    if (_state != ForumBodyRubyGroupPreparationState.active) {
      throw StateError('Ruby preparation is not active');
    }
    return _operate(() {
      _guard();
      final cache = _cache!;
      final partsBefore = _preparedParts;
      final buildsBefore = cache.layoutBuildCount;
      final picturesBefore = cache.pictureBuildCount;
      var inspected = 0;
      var rejectedAt = cache.budgetRevision;
      _waiting = false;
      _lastBudgetRejection = null;
      try {
        while (_preparedParts < expectedPartCount) {
          rejectedAt = cache.budgetRevision;
          if (_leases.length == _preparedParts) _acquire(cachedOnly: false);
          final lease = _leases[_preparedParts];
          if (_preparePaint && !lease.layout.isPaintPrepared) {
            // The glyph build already consumed this cooperative work unit.
            if (cache.layoutBuildCount != buildsBefore) break;
            cache.prepareBandChildPaint(lease as ForumBodyTextBandChildLease);
            _guard();
          }
          _preparedParts++;
          if (cache.layoutBuildCount != buildsBefore ||
              cache.pictureBuildCount != picturesBefore) {
            break;
          }
        }
        _finishIfReady();
      } on ForumBodyParagraphBudgetException catch (error) {
        _guard();
        if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
        _lastBudgetRejection = error;
        final additional =
            _additionalOwnedLeases?.call() ??
            const <ForumBodyNativeParagraphLease>[];
        _guard();
        final external = cache.isBlockedByExternalPins(error, [
          ..._leases,
          ...additional,
        ]);
        _guard();
        if (!external) {
          throw const ForumBodyRubyGroupPreparationException(
            ForumBodyRubyGroupPreparationFailure.intrinsicBudget,
          );
        }
        if (!_budgetChecked) inspected = _inspectBudget();
        _waiting = cache.budgetRevision == rejectedAt;
      }
      return ForumBodyRubyGroupPreparationStep(
        partsPrepared: _preparedParts - partsBefore,
        layoutsBuilt: cache.layoutBuildCount - buildsBefore,
        picturesBuilt: cache.pictureBuildCount - picturesBefore,
        partsInspected: inspected,
        isReady: isReady,
        waitingForLayoutBudget: _waiting,
      );
    });
  }

  /// At most two cache lookups, never native construction. Warm partial work
  /// stays pinned until a later advance, transfer or cancellation.
  bool tryPrepareCached() => _operate(() {
    _guard();
    if (isReady) return true;
    _waiting = false;
    _lastBudgetRejection = null;
    while (_preparedParts < expectedPartCount) {
      if (_leases.length == _preparedParts && !_acquire(cachedOnly: true)) {
        return false;
      }
      if (_preparePaint && !_leases[_preparedParts].layout.isPaintPrepared) {
        return false;
      }
      _preparedParts++;
    }
    _finishIfReady();
    return true;
  });

  bool _acquire({required bool cachedOnly}) {
    final request = _requests[_preparedParts];
    final cache = _cache!;
    final lease = request.acquire(
      cache,
      width: maxWidth,
      textScaler: _textScaler!,
      cachedOnly: cachedOnly,
    );
    try {
      _guard();
    } catch (_) {
      lease?.release();
      rethrow;
    }
    if (lease == null) return false;
    _leases.add(lease);
    return true;
  }

  int _inspectBudget() {
    final probe = _cache!.createBudgetProbe();
    try {
      for (var i = 0; i < expectedPartCount; i++) {
        _requests[i].includeBudget(
          probe,
          width: maxWidth,
          textScaler: _textScaler!,
        );
        _guard();
      }
      _budgetChecked = true;
      return expectedPartCount;
    } on ForumBodyParagraphBudgetException {
      throw const ForumBodyRubyGroupPreparationException(
        ForumBodyRubyGroupPreparationFailure.intrinsicBudget,
      );
    } finally {
      probe.close();
    }
  }

  void _finishIfReady() {
    if (_preparedParts != expectedPartCount) return;
    _guard();
    if (_preparePaint) {
      final group = ForumBodyRubyGroupLayout.adopt(
        cache: _cache!,
        baseLease: _leases[0],
        annotation: _requests[1].content,
        annotationLease: expectedPartCount == 2 ? _leases[1] : null,
        gap: gap,
        maxWidth: maxWidth,
      );
      _leases.clear();
      try {
        _guard();
      } catch (_) {
        group.close();
        rethrow;
      }
      _group = group;
    } else {
      final metrics = ForumBodyRubyGroupMetrics.measure(
        cache: _cache!,
        baseLease: _leases[0],
        annotation: _requests[1].content,
        annotationLease: expectedPartCount == 2 ? _leases[1] : null,
        gap: gap,
        maxWidth: maxWidth,
      );
      _guard();
      final leases = _leases.toList();
      _leases.clear();
      for (final lease in leases) {
        lease.release();
      }
      // A numeric result owns no pins, including while ready. Still guard its
      // originating generation after release and again at explicit transfer.
      _guard();
      _metrics = metrics;
    }
    _requests = const [];
    _textScaler = null;
    _state = ForumBodyRubyGroupPreparationState.ready;
  }

  ForumBodyRubyGroupLayout takeLayout() {
    if (!isReady) throw StateError('Ruby preparation is not ready');
    if (!_preparePaint) throw StateError('Ruby preparation contains metrics');
    return _operate(() {
      _guard();
      final group = _group!;
      _group = null;
      _state = ForumBodyRubyGroupPreparationState.transferred;
      _dropOwner();
      return group;
    });
  }

  ForumBodyRubyGroupMetrics takeMetrics() {
    if (!isReady) throw StateError('Ruby preparation is not ready');
    if (_preparePaint) throw StateError('Ruby preparation contains a layout');
    return _operate(() {
      _guard();
      final metrics = _metrics!;
      _metrics = null;
      _state = ForumBodyRubyGroupPreparationState.transferred;
      _dropOwner();
      return metrics;
    });
  }

  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Ruby preparation operation is reentrant');
    _operating = true;
    try {
      return action();
    } catch (_) {
      _retire(ForumBodyRubyGroupPreparationState.failed);
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_state != ForumBodyRubyGroupPreparationState.active && !isReady) {
      throw StateError('Ruby preparation is retired');
    }
    _ensureOwner!();
    if ((_state != ForumBodyRubyGroupPreparationState.active && !isReady) ||
        _cache!.isClosed) {
      throw StateError('Ruby preparation owner is retired');
    }
    for (final lease in _leases) {
      if (!_cache!.ownsLease(lease) || lease.layout.isDisposed) {
        throw StateError('Ruby preparation child is retired');
      }
    }
  }

  void _retire(ForumBodyRubyGroupPreparationState state) {
    if (_state != ForumBodyRubyGroupPreparationState.active && !isReady) return;
    _state = state;
    for (final lease in _leases) {
      lease.release();
    }
    _leases.clear();
    _group?.close();
    _group = null;
    _metrics = null;
    _dropOwner();
  }

  void _dropOwner() {
    _cache = null;
    _requests = const [];
    _textScaler = null;
    _ensureOwner = null;
    _additionalOwnedLeases = null;
    _lastBudgetRejection = null;
    _waiting = false;
  }

  void close() => _retire(ForumBodyRubyGroupPreparationState.closed);
}
