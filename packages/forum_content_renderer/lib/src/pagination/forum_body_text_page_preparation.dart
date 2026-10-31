import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_text_page_binding.dart';
import 'forum_body_text_page_composer.dart';

enum ForumBodyTextPagePreparationState {
  active,
  ready,
  transferred,
  failed,
  closed,
}

enum ForumBodyTextPagePreparationFailure { intrinsicBudget }

final class ForumBodyTextPagePreparationException implements Exception {
  const ForumBodyTextPagePreparationException(this.failure);
  final ForumBodyTextPagePreparationFailure failure;
  @override
  String toString() => 'ForumBodyTextPagePreparationException(${failure.name})';
}

final class ForumBodyTextPagePreparationStep {
  const ForumBodyTextPagePreparationStep(
    this.fragmentsPrepared,
    this.layoutsBuilt,
    this.isReady,
    this.waitingForLayoutBudget, {
    this.fragmentsInspected = 0,
  });
  final int fragmentsPrepared;
  final int layoutsBuilt;
  final bool isReady;
  final bool waitingForLayoutBudget;
  final int fragmentsInspected;
  // A discarded build under budget pressure is cost, not retained progress.
  bool get madeProgress =>
      fragmentsPrepared > 0 || fragmentsInspected > 0 || isReady;
}

// Internal construction keeps reservation/owner callbacks in the session; only
// cursor types, not this factory, are exported through the package entry.
ForumBodyTextPagePreparation createForumBodyTextPagePreparation({
  required ForumBodyParagraphCache cache,
  required ForumBodyTextPageSnapshot snapshot,
  required int pageIndex,
  required List<ForumBodyParagraphContent> contents,
  required TextScaler textScaler,
  required void Function() ensureOwner,
  required void Function(
    ForumBodyTextPagePreparation,
    List<ForumBodyParagraphLease>,
  )
  onTransfer,
  required void Function(ForumBodyTextPagePreparation) onRetire,
}) => ForumBodyTextPagePreparation._(
  cache,
  snapshot,
  pageIndex,
  contents,
  textScaler,
  ensureOwner,
  onTransfer,
  onRetire,
);

/// A transactional view preparation for one already published page. Each
/// advance acquires at most maxFragments and stops after its first native build.
/// Partial leases are never exposed; close rolls them back. Terminal cursors
/// drop cache/content/owner references while retaining only pure page metadata.
final class ForumBodyTextPagePreparation {
  ForumBodyTextPagePreparation._(
    this._cache,
    this.snapshot,
    this.pageIndex,
    this._contents,
    this._textScaler,
    this._ensureOwner,
    this._onTransfer,
    this._onRetire,
  );
  ForumBodyParagraphCache? _cache;
  final ForumBodyTextPageSnapshot snapshot;
  final int pageIndex;
  List<ForumBodyParagraphContent> _contents;
  TextScaler? _textScaler;
  void Function()? _ensureOwner;
  void Function(ForumBodyTextPagePreparation, List<ForumBodyParagraphLease>)?
  _onTransfer;
  void Function(ForumBodyTextPagePreparation)? _onRetire;
  final _leases = <ForumBodyParagraphLease>[];
  ForumBodyTextPagePreparationState _state =
      ForumBodyTextPagePreparationState.active;
  bool _waiting = false;
  ForumBodyParagraphBudgetProbe? _budgetProbe;
  int _probeIndex = 0;
  int _rejectedAtRevision = 0;
  bool _pageBudgetChecked = false;

  ForumBodyTextPagePreparationState get state => _state;
  bool get isReady => _state == ForumBodyTextPagePreparationState.ready;
  bool get waitingForLayoutBudget => _waiting;
  int get preparedFragmentCount => _leases.length;
  int get expectedFragmentCount => snapshot[pageIndex].fragments.length;

  ForumBodyTextPagePreparationStep advance({required int maxFragments}) {
    _guard();
    if (_state != ForumBodyTextPagePreparationState.active) {
      throw StateError('Page preparation is not active');
    }
    if (maxFragments <= 0) {
      throw ArgumentError.value(maxFragments, 'maxFragments');
    }
    final cache = _cache!;
    final before = _leases.length;
    final buildsBefore = cache.layoutBuildCount;
    var inspected = 0;
    _waiting = false;
    ForumBodyTextPagePreparationStep result() =>
        ForumBodyTextPagePreparationStep(
          _leases.length - before,
          cache.layoutBuildCount - buildsBefore,
          isReady,
          _waiting,
          fragmentsInspected: inspected,
        );
    try {
      if (_budgetProbe != null) {
        inspected = _inspectBudget(maxFragments);
        return result();
      }
      while (_leases.length < expectedFragmentCount &&
          _leases.length - before < maxFragments) {
        _rejectedAtRevision = cache.budgetRevision;
        _acquire(cachedOnly: false);
        if (cache.layoutBuildCount != buildsBefore) break;
      }
      _finishIfReady();
      return result();
    } on ForumBodyParagraphBudgetException catch (error) {
      var externalPressure = false;
      try {
        _guard();
        externalPressure = cache.isBlockedByExternalPins(error, _leases);
      } catch (_) {
        _abort();
        rethrow;
      }
      if (error.failure == ForumBodyParagraphBudgetFailure.pinned) {
        if (externalPressure) {
          if (!_pageBudgetChecked) {
            _budgetProbe = cache.createBudgetProbe();
            try {
              inspected = _inspectBudget(maxFragments);
            } catch (_) {
              _abort();
              rethrow;
            }
            return result();
          }
          _waiting = true;
          return result();
        }
        _abort();
        throw const ForumBodyTextPagePreparationException(
          ForumBodyTextPagePreparationFailure.intrinsicBudget,
        );
      }
      _abort();
      rethrow;
    } catch (_) {
      _abort();
      rethrow;
    }
  }

  int _inspectBudget(int maxFragments) {
    var inspected = 0;
    final probe = _budgetProbe!;
    try {
      while (_probeIndex < expectedFragmentCount && inspected < maxFragments) {
        final fragment = snapshot[pageIndex].fragments[_probeIndex];
        probe.include(
          content: _contents[_probeIndex],
          width: fragment.width,
          minimumLineCount: fragment.endLine,
          textScaler: _textScaler!,
        );
        _guard();
        _probeIndex++;
        inspected++;
      }
      if (_probeIndex == expectedFragmentCount) {
        _pageBudgetChecked = true;
        probe.close();
        _budgetProbe = null;
        // A release during bounded inspection must cause a fresh admission,
        // not a wait for an event that has already happened.
        _waiting = _cache!.budgetRevision == _rejectedAtRevision;
      }
      return inspected;
    } on ForumBodyParagraphBudgetException {
      // The whole lower bound exceeds capacity even after every foreign pin
      // releases. Preserve visible/source owners and roll back just this view.
      throw const ForumBodyTextPagePreparationException(
        ForumBodyTextPagePreparationFailure.intrinsicBudget,
      );
    }
  }

  /// Bounded by the reserved page's fragment count; never shapes on a miss.
  /// A miss retains warm partial work so advance can continue outside build.
  bool tryPrepareCached() {
    _guard();
    if (isReady) return true;
    _waiting = false;
    try {
      while (_leases.length < expectedFragmentCount) {
        if (!_acquire(cachedOnly: true)) return false;
      }
      _finishIfReady();
      return true;
    } catch (_) {
      _abort();
      rethrow;
    }
  }

  bool _acquire({required bool cachedOnly}) {
    final index = _leases.length;
    final fragment = snapshot[pageIndex].fragments[index];
    final cache = _cache!;
    final lease = cachedOnly
        ? cache.tryAcquireCached(
            content: _contents[index],
            width: fragment.width,
            textScaler: _textScaler!,
          )
        : cache.acquire(
            content: _contents[index],
            width: fragment.width,
            textScaler: _textScaler!,
          );
    if (lease == null) return false;
    try {
      _guard();
    } catch (_) {
      lease.release();
      rethrow;
    }
    _leases.add(lease);
    return true;
  }

  void _finishIfReady() {
    if (_leases.length != expectedFragmentCount) return;
    _guard();
    validateForumBodyTextPageBinding(
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: snapshot.layoutId,
      leases: _leases,
    );
    _state = ForumBodyTextPagePreparationState.ready;
    _waiting = false;
  }

  List<ForumBodyParagraphLease> takeLeases() {
    _guard();
    if (!isReady) throw StateError('Page preparation is not ready');
    try {
      validateForumBodyTextPageBinding(
        snapshot: snapshot,
        pageIndex: pageIndex,
        layoutId: snapshot.layoutId,
        leases: _leases,
      );
      final result = List<ForumBodyParagraphLease>.unmodifiable(_leases);
      _onTransfer!(this, result);
      _leases.clear();
      _state = ForumBodyTextPagePreparationState.transferred;
      _dropOwner();
      return result;
    } catch (_) {
      _abort();
      rethrow;
    }
  }

  void _guard() {
    if (_state != ForumBodyTextPagePreparationState.active && !isReady) {
      throw StateError('Page preparation is retired');
    }
    _ensureOwner!();
    if (_state != ForumBodyTextPagePreparationState.active && !isReady) {
      throw StateError('Page preparation is retired');
    }
  }

  void _abort() {
    try {
      _ensureOwner?.call();
    } finally {
      _retire(ForumBodyTextPagePreparationState.failed);
    }
  }

  void _retire(ForumBodyTextPagePreparationState state) {
    if (_state != ForumBodyTextPagePreparationState.active && !isReady) return;
    _state = state;
    for (final lease in _leases) {
      lease.release();
    }
    _leases.clear();
    final retire = _onRetire;
    _dropOwner();
    retire?.call(this);
  }

  void _dropOwner() {
    _budgetProbe?.close();
    _budgetProbe = null;
    _cache = null;
    _contents = const [];
    _textScaler = null;
    _ensureOwner = null;
    _onTransfer = null;
    _onRetire = null;
    _waiting = false;
  }

  void close() => _retire(ForumBodyTextPagePreparationState.closed);
}
