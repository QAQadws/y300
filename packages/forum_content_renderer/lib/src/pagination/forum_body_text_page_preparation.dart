import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../inline/forum_body_ruby_group_preparation.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_inline_page_preparation.dart';
import 'forum_body_text_page_binding.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_text_page_content.dart';

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
    this.partsPrepared = 0,
    this.partsInspected = 0,
    this.picturesBuilt = 0,
  });
  final int fragmentsPrepared;
  final int layoutsBuilt;
  final bool isReady;
  final bool waitingForLayoutBudget;
  final int fragmentsInspected;
  final int partsPrepared;
  final int partsInspected;
  final int picturesBuilt;
  // A discarded native build is cost, not retained preparation progress.
  bool get madeProgress =>
      fragmentsPrepared > 0 ||
      fragmentsInspected > 0 ||
      partsPrepared > 0 ||
      partsInspected > 0 ||
      isReady;
}

// Construction and reservations stay with the existing session owner.
ForumBodyTextPagePreparation createForumBodyTextPagePreparation({
  required ForumBodyParagraphCache cache,
  required ForumBodyTextPageSnapshot snapshot,
  required int pageIndex,
  required List<ForumBodyTextPageContent> inputs,
  required TextScaler textScaler,
  required void Function() ensureOwner,
  required void Function(
    ForumBodyTextPagePreparation,
    List<ForumBodyPreparedTextFragment>,
  )
  onTransfer,
  required void Function(ForumBodyTextPagePreparation) onRetire,
}) {
  final page = snapshot[pageIndex];
  if (inputs.length != page.fragments.length ||
      inputs.any((input) => input.identity != snapshot.identity)) {
    throw const ForumBodyTextPageSurfaceException(
      ForumBodyTextPageSurfaceFailure.identity,
    );
  }
  final count = inputs.indexed.fold<int>(
    0,
    (sum, item) => sum + item.$2.nativeHandleCountFor(page.fragments[item.$1]),
  );
  return ForumBodyTextPagePreparation._(
    cache,
    snapshot,
    pageIndex,
    List.unmodifiable(inputs),
    count,
    textScaler,
    ensureOwner,
    onTransfer,
    onRetire,
  );
}

/// One page transaction with at most one partial mixed fragment. Native shape
/// and picture work use distinct cooperative units. Only complete, validated
/// fragments transfer; cancellation releases parents and every visible child.
final class ForumBodyTextPagePreparation {
  ForumBodyTextPagePreparation._(
    this._cache,
    this.snapshot,
    this.pageIndex,
    this._inputs,
    this.expectedNativeLeaseCount,
    this._textScaler,
    this._ensureOwner,
    this._onTransfer,
    this._onRetire,
  );
  ForumBodyParagraphCache? _cache;
  final ForumBodyTextPageSnapshot snapshot;
  final int pageIndex;
  final int expectedNativeLeaseCount;
  List<ForumBodyTextPageContent> _inputs;
  TextScaler? _textScaler;
  void Function()? _ensureOwner;
  void Function(
    ForumBodyTextPagePreparation,
    List<ForumBodyPreparedTextFragment>,
  )?
  _onTransfer;
  void Function(ForumBodyTextPagePreparation)? _onRetire;
  final _fragments = <ForumBodyPreparedTextFragment>[];
  ForumBodyInlinePagePreparation? _inline;
  var _state = ForumBodyTextPagePreparationState.active;
  bool _operating = false;
  bool _waiting = false;
  bool _cacheMiss = false;
  int _completedWork = 0;
  int get _retainedWork => _completedWork + (_inline?.workCount ?? 0);
  ForumBodyParagraphBudgetProbe? _budgetProbe;
  Iterator<bool>? _probeWork;
  int _probePartsRead = 0;
  int _rejectedAtRevision = 0;
  int _probeBuilds = 0;
  int _probePictures = 0;
  bool _pageBudgetChecked = false;
  int _checkedBuilds = 0;
  int _checkedPictures = 0;
  ForumBodyTextPagePreparationState get state => _state;
  bool get isReady => _state == ForumBodyTextPagePreparationState.ready;
  bool get waitingForLayoutBudget => _waiting;
  bool get cacheMiss =>
      _state == ForumBodyTextPagePreparationState.active && _cacheMiss;
  int get preparedFragmentCount => _fragments.length;
  int get expectedFragmentCount => snapshot[pageIndex].fragments.length;
  Iterable<ForumBodyNativeParagraphLease> get _ownedLeases sync* {
    for (final fragment in _fragments) {
      yield* fragment.nativeLeases;
    }
    final active = _inline;
    if (active != null) {
      yield* active.nativeLeases;
    }
  }

  ForumBodyTextPagePreparationStep advance({
    required int maxFragments,
    int maxParts = 32,
  }) {
    _ensureEntry();
    if (_state != ForumBodyTextPagePreparationState.active) {
      throw StateError('Page preparation is not active');
    }
    if (maxFragments <= 0 || maxParts <= 0) {
      throw ArgumentError('Invalid page preparation budget');
    }
    final cache = _cache!;
    final before = _fragments.length;
    final workBefore = _retainedWork;
    final buildsBefore = cache.layoutBuildCount;
    final picturesBefore = cache.pictureBuildCount;
    var inspectedFragments = 0;
    var inspectedParts = 0;
    _waiting = false;
    _cacheMiss = false;
    ForumBodyTextPagePreparationStep result() =>
        ForumBodyTextPagePreparationStep(
          _fragments.length - before,
          cache.layoutBuildCount - buildsBefore,
          isReady,
          _waiting,
          fragmentsInspected: inspectedFragments,
          partsPrepared: _retainedWork - workBefore,
          partsInspected: inspectedParts,
          picturesBuilt: cache.pictureBuildCount - picturesBefore,
        );
    _operating = true;
    try {
      if (_budgetProbe != null) {
        final work = _inspectBudget(math.min(maxFragments, maxParts));
        inspectedFragments = work.fragments;
        inspectedParts = work.parts;
        return result();
      }
      for (
        var parts = 0;
        parts < maxParts &&
            _fragments.length < expectedFragmentCount &&
            _fragments.length - before < maxFragments;
      ) {
        _rejectedAtRevision = cache.budgetRevision;
        final beforeWork = _retainedWork;
        _prepareNext(cachedOnly: false, maxParts: maxParts - parts);
        parts += math.max(1, _retainedWork - beforeWork);
        if (cache.layoutBuildCount != buildsBefore ||
            cache.pictureBuildCount != picturesBefore) {
          break;
        }
      }
      _finishIfReady();
      return result();
    } on ForumBodyRubyGroupPreparationException {
      _abort();
      throw const ForumBodyTextPagePreparationException(
        ForumBodyTextPagePreparationFailure.intrinsicBudget,
      );
    } on ForumBodyParagraphBudgetException catch (error) {
      try {
        _guard();
        if (error.failure != ForumBodyParagraphBudgetFailure.pinned) {
          _abort();
          rethrow;
        }
        if (!cache.isBlockedByExternalPins(error, _ownedLeases)) {
          throw const ForumBodyTextPagePreparationException(
            ForumBodyTextPagePreparationFailure.intrinsicBudget,
          );
        }
        _guard();
        final current =
            _pageBudgetChecked &&
            _checkedBuilds == cache.layoutBuildCount &&
            _checkedPictures == cache.pictureBuildCount;
        if (!current) {
          _startBudgetProbe();
          final work = _inspectBudget(
            math.min(
              maxFragments,
              math.max(0, maxParts - (_retainedWork - workBefore)),
            ),
          );
          inspectedFragments = work.fragments;
          inspectedParts = work.parts;
        } else {
          _waiting = cache.budgetRevision == _rejectedAtRevision;
        }
        return result();
      } catch (_) {
        _abort();
        rethrow;
      }
    } catch (_) {
      _abort();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  /// Warm lookup is bounded too. A miss or exhausted part budget retains
  /// partial work without shaping or recording pictures inside Widget build.
  bool tryPrepareCached({int maxParts = 32}) {
    _ensureEntry();
    if (maxParts <= 0) throw ArgumentError.value(maxParts, 'maxParts');
    if (isReady) return true;
    _operating = true;
    _waiting = false;
    _cacheMiss = false;
    try {
      for (
        var parts = 0;
        parts < maxParts && _fragments.length < expectedFragmentCount;
      ) {
        final beforeWork = _retainedWork;
        if (!_prepareNext(cachedOnly: true, maxParts: maxParts - parts)) {
          _cacheMiss = true;
          return false;
        }
        parts += math.max(1, _retainedWork - beforeWork);
      }
      _finishIfReady();
      return isReady;
    } catch (_) {
      _abort();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  bool _prepareNext({required bool cachedOnly, required int maxParts}) {
    final index = _fragments.length;
    final fragment = snapshot[pageIndex].fragments[index];
    final input = _inputs[index];
    final cache = _cache!;
    if (input is ForumBodyParagraphPageContent) {
      final requestWidth = input.requestWidthFor(fragment);
      final lease = cachedOnly
          ? cache.tryAcquireCached(
              content: input.content,
              width: requestWidth,
              textScaler: _textScaler!,
            )
          : cache.acquire(
              content: input.content,
              width: requestWidth,
              textScaler: _textScaler!,
            );
      try {
        _guard();
      } catch (_) {
        lease?.release();
        rethrow;
      }
      if (lease == null) return false;
      try {
        _fragments.add(
          ForumBodyPreparedTextFragment.paragraph(
            lease: lease,
            startLine: fragment.startLine,
            endLine: fragment.endLine,
          ),
        );
      } on RangeError {
        throw const ForumBodyTextPageSurfaceException(
          ForumBodyTextPageSurfaceFailure.geometry,
        );
      }
      _completedWork++;
      return true;
    }
    final active = _inline ??= ForumBodyInlinePagePreparation(
      input: input as ForumBodyInlinePageContent,
      fragment: fragment,
      identity: snapshot.identity,
      cache: cache,
      textScaler: _textScaler!,
      ensureOwner: _guard,
      ownedPageLeases: () => _ownedLeases.toList(growable: false),
    );
    final step = active.advance(cachedOnly: cachedOnly, maxParts: maxParts);
    final view = step.view;
    if (view != null) {
      _inline = null;
      _completedWork += active.workCount;
      _fragments.add(ForumBodyPreparedTextFragment.inline(view));
    }
    return !step.cacheMiss;
  }

  void _startBudgetProbe() {
    _budgetProbe?.close();
    _budgetProbe = _cache!.createBudgetProbe();
    _probePartsRead = 0;
    _probeBuilds = _cache!.layoutBuildCount;
    _probePictures = _cache!.pictureBuildCount;
    _probeWork = _budgetParts(_budgetProbe!).iterator;
  }

  // Parent and child requests are separate bounded inspection units. No native
  // work or large list of callbacks is retained by the whole-page probe.
  Iterable<bool> _budgetParts(ForumBodyParagraphBudgetProbe probe) sync* {
    final page = snapshot[pageIndex];
    for (final (index, input) in _inputs.indexed) {
      final fragment = page.fragments[index];
      switch (input) {
        case ForumBodyParagraphPageContent():
          probe.include(
            content: input.content,
            width: input.requestWidthFor(fragment),
            minimumLineCount: fragment.endLine,
            textScaler: _textScaler!,
          );
          yield true;
        case ForumBodyInlinePageContent():
          probe.includeInline(
            content: input.content,
            width: input.requestWidthFor(fragment),
            dimensions: input.dimensions,
            minimumLineCount: fragment.endLine,
            textScaler: _textScaler!,
            layoutMode: input.layoutMode,
          );
          yield true;
          for (final atom in input.visibleAtoms(fragment)) {
            final request = input.rubyAtoms[atom];
            for (final child in request.nativeRequests) {
              child.includeBudget(
                probe,
                width: request.maxWidth,
                textScaler: _textScaler!,
              );
              yield false;
            }
          }
      }
    }
  }

  ({int fragments, int parts}) _inspectBudget(int limit) {
    var fragments = 0;
    var parts = 0;
    try {
      while (_probePartsRead < expectedNativeLeaseCount && parts < limit) {
        if (!_probeWork!.moveNext()) {
          throw StateError('Unordered page budget input');
        }
        _guard();
        _probePartsRead++;
        parts++;
        if (_probeWork!.current) fragments++;
      }
      if (_probePartsRead == expectedNativeLeaseCount) {
        _pageBudgetChecked =
            _probeBuilds == _cache!.layoutBuildCount &&
            _probePictures == _cache!.pictureBuildCount;
        _checkedBuilds = _probeBuilds;
        _checkedPictures = _probePictures;
        _closeProbe();
        _waiting =
            _pageBudgetChecked && _cache!.budgetRevision == _rejectedAtRevision;
      }
      return (fragments: fragments, parts: parts);
    } on ForumBodyParagraphBudgetException {
      throw const ForumBodyTextPagePreparationException(
        ForumBodyTextPagePreparationFailure.intrinsicBudget,
      );
    }
  }

  void _finishIfReady() {
    if (_fragments.length != expectedFragmentCount) return;
    _guard();
    validateForumBodyPreparedTextPageBinding(
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: snapshot.layoutId,
      fragments: _fragments,
    );
    _closeProbe();
    _state = ForumBodyTextPagePreparationState.ready;
    _waiting = false;
  }

  List<ForumBodyParagraphLease> takeLeases() {
    _ensureEntry();
    if (!isReady) throw StateError('Page preparation is not ready');
    if (_fragments.any(
      (fragment) => fragment is! ForumBodyPreparedParagraphFragment,
    )) {
      throw StateError('Mixed page delivery requires prepared fragments');
    }
    return List.unmodifiable(
      takeFragments().map(
        (fragment) => (fragment as ForumBodyPreparedParagraphFragment).lease,
      ),
    );
  }

  List<ForumBodyPreparedTextFragment> takeFragments() {
    _ensureEntry();
    if (!isReady) throw StateError('Page preparation is not ready');
    _operating = true;
    try {
      validateForumBodyPreparedTextPageBinding(
        snapshot: snapshot,
        pageIndex: pageIndex,
        layoutId: snapshot.layoutId,
        fragments: _fragments,
      );
      final result = List<ForumBodyPreparedTextFragment>.unmodifiable(
        _fragments,
      );
      _onTransfer!(this, result);
      _guard();
      _fragments.clear();
      _state = ForumBodyTextPagePreparationState.transferred;
      _dropOwner();
      return result;
    } catch (_) {
      _abort();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _checkReentry() {
    if (_operating) throw StateError('Page preparation operation is reentrant');
  }

  void _ensureEntry() {
    _checkReentry();
    _operating = true;
    try {
      _guard();
    } catch (_) {
      _abort();
      rethrow;
    } finally {
      _operating = false;
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
    if (_cache!.isClosed ||
        _fragments.any((fragment) => !fragment.isActive) ||
        _ownedLeases.any((lease) => !_cache!.ownsLease(lease))) {
      throw StateError('Page preparation owner or fragment is retired');
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
    _inline?.close();
    _inline = null;
    for (final fragment in _fragments) {
      fragment.close();
    }
    _fragments.clear();
    final retire = _onRetire;
    _dropOwner();
    retire?.call(this);
  }

  void _closeProbe() {
    _budgetProbe?.close();
    _budgetProbe = null;
    _probeWork = null;
  }

  void _dropOwner() {
    _closeProbe();
    _cache = null;
    _inputs = const [];
    _textScaler = null;
    _ensureOwner = null;
    _onTransfer = null;
    _onRetire = null;
    _waiting = false;
  }

  void close() => _retire(ForumBodyTextPagePreparationState.closed);
}
