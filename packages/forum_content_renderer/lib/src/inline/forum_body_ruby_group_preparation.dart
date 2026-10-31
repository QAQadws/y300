import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_ruby_group_layout.dart';

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
  });
  final int partsPrepared;
  final int layoutsBuilt;
  final int partsInspected;
  final bool isReady;
  final bool waitingForLayoutBudget;
  bool get madeProgress => partsPrepared > 0 || partsInspected > 0 || isReady;
}

/// A format-local transaction for one already grouped ruby pair. Each advance
/// stops after its first native build; cached work and a whole-pair budget probe
/// are bounded by two parts. No timer, scheduler, DOM or persistent anchor is
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
  }) {
    ForumBodyRubyGroupLayout.validateInputs(
      base: base,
      annotation: annotation,
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
      gap,
      maxWidth,
      annotation.projection.text.isEmpty ? 1 : 2,
    );
  }

  ForumBodyRubyGroupPreparation._(
    this._cache,
    ForumBodyParagraphContent base,
    ForumBodyParagraphContent annotation,
    this._ensureOwner,
    this._textScaler,
    this.gap,
    this.maxWidth,
    this.expectedPartCount,
  ) : _contents = [base, annotation];

  ForumBodyParagraphCache? _cache;
  List<ForumBodyParagraphContent> _contents;
  void Function()? _ensureOwner;
  TextScaler? _textScaler;
  final double gap;
  final double maxWidth;
  final int expectedPartCount;
  final _leases = <ForumBodyParagraphLease>[];
  ForumBodyRubyGroupLayout? _group;
  var _state = ForumBodyRubyGroupPreparationState.active;
  var _preparedParts = 0;
  var _waiting = false;
  var _budgetChecked = false;
  var _operating = false;

  ForumBodyRubyGroupPreparationState get state => _state;
  bool get isReady => _state == ForumBodyRubyGroupPreparationState.ready;
  bool get waitingForLayoutBudget => _waiting;
  int get preparedPartCount => _preparedParts;

  ForumBodyRubyGroupPreparationStep advance() {
    if (_state != ForumBodyRubyGroupPreparationState.active) {
      throw StateError('Ruby preparation is not active');
    }
    return _operate(() {
      _guard();
      final cache = _cache!;
      final partsBefore = _preparedParts;
      final buildsBefore = cache.layoutBuildCount;
      var inspected = 0;
      var rejectedAt = cache.budgetRevision;
      _waiting = false;
      try {
        while (_preparedParts < expectedPartCount) {
          rejectedAt = cache.budgetRevision;
          _acquire(cachedOnly: false);
          if (cache.layoutBuildCount != buildsBefore) break;
        }
        _finishIfReady();
      } on ForumBodyParagraphBudgetException catch (error) {
        _guard();
        if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
        if (!cache.isBlockedByExternalPins(error, _leases)) {
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
    while (_preparedParts < expectedPartCount) {
      if (!_acquire(cachedOnly: true)) return false;
    }
    _finishIfReady();
    return true;
  });

  bool _acquire({required bool cachedOnly}) {
    final content = _contents[_preparedParts];
    final cache = _cache!;
    final lease = cachedOnly
        ? cache.tryAcquireCached(
            content: content,
            width: maxWidth,
            textScaler: _textScaler!,
          )
        : cache.acquire(
            content: content,
            width: maxWidth,
            textScaler: _textScaler!,
          );
    try {
      _guard();
    } catch (_) {
      lease?.release();
      rethrow;
    }
    if (lease == null) return false;
    _leases.add(lease);
    _preparedParts++;
    return true;
  }

  int _inspectBudget() {
    final probe = _cache!.createBudgetProbe();
    try {
      for (var i = 0; i < expectedPartCount; i++) {
        probe.include(
          content: _contents[i],
          width: maxWidth,
          minimumLineCount: 1,
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
    final group = ForumBodyRubyGroupLayout.adopt(
      cache: _cache!,
      baseLease: _leases[0],
      annotation: _contents[1],
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
    _contents = const [];
    _textScaler = null;
    _state = ForumBodyRubyGroupPreparationState.ready;
  }

  ForumBodyRubyGroupLayout takeLayout() {
    if (!isReady) throw StateError('Ruby preparation is not ready');
    return _operate(() {
      _guard();
      final group = _group!;
      _group = null;
      _state = ForumBodyRubyGroupPreparationState.transferred;
      _dropOwner();
      return group;
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
      if (!_cache!.ownsLease(lease)) {
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
    _dropOwner();
  }

  void _dropOwner() {
    _cache = null;
    _contents = const [];
    _textScaler = null;
    _ensureOwner = null;
    _waiting = false;
  }

  void close() => _retire(ForumBodyRubyGroupPreparationState.closed);
}
