import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../inline/forum_body_ruby_group_preparation.dart';
import '../inline/forum_body_emphasis_line_layout.dart';
import '../inline/forum_body_ruby_atom_plan.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_inline_page_preparation.dart';
import 'forum_body_emphasis_page_preparation.dart';
import 'forum_body_inline_font_frame_page_preparation.dart';
import 'forum_body_text_page_binding.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_text_page_content.dart';
import 'forum_body_list_marker_plan.dart';

enum ForumBodyTextPagePreparationState {
  active,
  ready,
  transferred,
  failed,
  closed,
}

enum ForumBodyTextPagePreparationFailure { intrinsicBudget }

typedef _PageBudgetPart = ({bool startsFragment, void Function() inspect});

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
    (sum, item) =>
        sum + item.$2.nativePreparationHandleCountFor(page.fragments[item.$1]),
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
  ) : _initialProbePending = _inputs.any(
        (input) =>
            input is ForumBodyListItemPageContent ||
            input is ForumBodyEmphasisPageContent ||
            input is ForumBodyFittedEmphasisPageContent ||
            (input is ForumBodyInlinePageContent &&
                (input.fontFrames != null ||
                    input.rubyAtoms.any(
                      (atom) => atom is ForumBodyRubyTreeEmphasisAtomPlan,
                    ))),
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
  ForumBodyPreparedTextFragment? _pendingListBody;
  ForumBodyListMarkerPicturePreparation? _list;
  final _emphasis = <int, ForumBodyEmphasisPagePreparation>{};
  ForumBodyEmphasisPagePreparation? _activeEmphasis;
  final _fontFrames = <int, ForumBodyInlineFontFramePagePreparation>{};
  ForumBodyInlineFontFramePagePreparation? _activeFontFrame;
  ForumBodyEmphasisLinePreparation? _fitted;
  int _fittedWork = 0;
  bool _initialProbePending;
  var _state = ForumBodyTextPagePreparationState.active;
  bool _operating = false;
  bool _waiting = false;
  bool _cacheMiss = false;
  int _completedWork = 0;
  int get _retainedWork =>
      _completedWork +
      (_list?.workCount ?? 0) +
      _fittedWork +
      (_inline?.workCount ?? 0) +
      (_activeEmphasis?.workCount ?? 0) +
      (_activeFontFrame?.workCount ?? 0);
  ForumBodyParagraphBudgetProbe? _budgetProbe;
  Iterator<_PageBudgetPart>? _probeWork;
  _PageBudgetPart? _nextProbePart;
  bool _probeAfterRejection = false;
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
  Iterable<ForumBodyNativeParagraphLease> get _finishedLeases sync* {
    for (final fragment in _fragments) {
      yield* fragment.nativeLeases;
    }
  }

  Iterable<ForumBodyNativeParagraphLease> get _ownedLeases sync* {
    yield* _finishedLeases;
    if (_pendingListBody != null) yield* _pendingListBody!.nativeLeases;
    if (_list != null) yield* _list!.nativeLeases;
    final active = _inline;
    if (active != null) {
      yield* active.nativeLeases;
    }
    if (_activeEmphasis != null) yield* _activeEmphasis!.nativeLeases;
    if (_activeFontFrame != null) yield* _activeFontFrame!.nativeLeases;
    if (_fitted != null) yield* _fitted!.nativeLeases;
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
      if (_initialProbePending) {
        _initialProbePending = false;
        _startBudgetProbe(afterRejection: false);
      }
      if (_budgetProbe != null) {
        final work = _inspectBudget(
          maxFragments: maxFragments,
          maxParts: maxParts,
        );
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
        if (_waiting) {
          if (!_hasCurrentBudgetCheck) _startBudgetProbe();
          break;
        }
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
            maxFragments: maxFragments,
            maxParts: math.max(0, maxParts - (_retainedWork - workBefore)),
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
      if (_initialProbePending) {
        _initialProbePending = false;
        _startBudgetProbe(afterRejection: false);
      }
      if (_budgetProbe != null) {
        _inspectBudget(maxFragments: expectedFragmentCount, maxParts: maxParts);
        return false;
      }
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
        if (_waiting) return false;
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
    final fullInput = _inputs[index];
    final input = fullInput.bodyContent;
    final cache = _cache!;
    if (_pendingListBody != null) {
      final work = _list ??= ForumBodyListMarkerPicturePreparation(
        plan: (fullInput as ForumBodyListItemPageContent).markers,
        cache: cache,
        textScaler: _textScaler!,
        ensureOwner: _guard,
        ownedLeases: () sync* {
          yield* _finishedLeases;
          yield* _pendingListBody!.nativeLeases;
        },
      );
      final step = work.advance(cachedOnly: cachedOnly);
      _waiting = step.waiting;
      if (work.isReady) {
        final picture = work.take();
        _fragments.add(
          ForumBodyPreparedListItemFragment(
            _pendingListBody!,
            (fullInput as ForumBodyListItemPageContent).markers,
            fragment.listMarker!,
            picture,
          ),
        );
        _pendingListBody = null;
        _completedWork += work.workCount;
        _list = null;
      }
      return !step.cacheMiss;
    }
    if (input is ForumBodyFittedEmphasisPageContent) {
      final work = _fitted ??= ForumBodyEmphasisLinePreparation.fromMetrics(
        input: input.plan.metrics.input,
        metrics: input.plan.metrics,
        cache: cache,
        width: input.plan.metrics.requestWidth,
        expectedTextScaler: _textScaler!,
        ensureOwner: _guard,
        ensureVisibleOwner: _ensureOwner!,
        additionalOwnedLeases: () => _finishedLeases,
      );
      final step = work.advance(maxParts: maxParts, cachedOnly: cachedOnly);
      _fittedWork += step.partsPrepared;
      _waiting = step.waitingForLayoutBudget;
      _guard();
      if (work.isReady) {
        final view = work.takeLayout();
        try {
          _guard();
          _acceptBody(
            ForumBodyPreparedTextFragment.fittedEmphasis(
              view: view,
              plan: input.plan,
            ),
          );
          _guard();
        } catch (_) {
          view.close();
          rethrow;
        }
        _fitted = null;
        _completedWork += _fittedWork;
        _fittedWork = 0;
      }
      return !work.cacheMiss;
    }
    if (input is ForumBodyEmphasisPageContent) {
      final active = _activeEmphasis ??= _emphasisPart(index, input);
      final step = active.advance(cachedOnly: cachedOnly, maxParts: maxParts);
      _waiting = step.waiting;
      final view = step.view;
      if (view != null) {
        try {
          _guard();
          _acceptBody(ForumBodyPreparedTextFragment.emphasis(view));
          _guard();
        } catch (_) {
          view.close();
          rethrow;
        }
        _completedWork += active.workCount;
        _activeEmphasis = null;
      }
      return !step.cacheMiss;
    }
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
        _acceptBody(
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
    if (input is ForumBodyInlinePageContent && input.fontFrames != null) {
      final active = _activeFontFrame ??= _fontFramePart(index, input);
      final step = active.advance(cachedOnly: cachedOnly, maxParts: maxParts);
      _waiting = step.waiting;
      if (step.view case final view?) {
        try {
          _guard();
          _acceptBody(ForumBodyPreparedTextFragment.inline(view));
          _guard();
        } catch (_) {
          view.close();
          rethrow;
        }
        _completedWork += active.workCount;
        _activeFontFrame = null;
      }
      return !step.cacheMiss;
    }
    final active = _inline ??= ForumBodyInlinePagePreparation(
      input: input as ForumBodyInlinePageContent,
      fragment: fragment,
      identity: snapshot.identity,
      cache: cache,
      textScaler: _textScaler!,
      ensureOwner: _guard,
      ensureVisibleOwner: _ensureOwner!,
      ownedPageLeases: () => _ownedLeases.toList(growable: false),
    );
    final step = active.advance(cachedOnly: cachedOnly, maxParts: maxParts);
    _waiting = active.waitingForLayoutBudget;
    final view = step.view;
    if (view != null) {
      _inline = null;
      _completedWork += active.workCount;
      _acceptBody(ForumBodyPreparedTextFragment.inline(view));
    }
    return !step.cacheMiss;
  }

  void _acceptBody(ForumBodyPreparedTextFragment body) {
    final fragment = snapshot[pageIndex].fragments[_fragments.length];
    if (fragment.listMarker != null) {
      if (_inputs[_fragments.length] is! ForumBodyListItemPageContent) {
        body.close();
        throw StateError('List marker input is missing');
      }
      _pendingListBody = body;
    } else {
      _fragments.add(body);
    }
  }

  bool get _hasCurrentBudgetCheck =>
      _pageBudgetChecked &&
      _checkedBuilds == _cache!.layoutBuildCount &&
      _checkedPictures == _cache!.pictureBuildCount;

  ForumBodyEmphasisPagePreparation _emphasisPart(
    int index,
    ForumBodyEmphasisPageContent input,
  ) => _emphasis.putIfAbsent(
    index,
    () => ForumBodyEmphasisPagePreparation(
      input: input,
      fragment: snapshot[pageIndex].fragments[index],
      cache: _cache!,
      textScaler: _textScaler!,
      ensureOwner: _guard,
      ensureVisibleOwner: _ensureOwner!,
      ownedPageLeases: () => _finishedLeases,
    ),
  );

  void _startBudgetProbe({bool afterRejection = true}) {
    _budgetProbe?.close();
    _waiting = false;
    _budgetProbe = _cache!.createBudgetProbe();
    _nextProbePart = null;
    _probeAfterRejection = afterRejection;
    _probeBuilds = _cache!.layoutBuildCount;
    _probePictures = _cache!.pictureBuildCount;
    _probeWork = _budgetParts(_budgetProbe!).iterator;
  }

  ForumBodyInlineFontFramePagePreparation _fontFramePart(
    int index,
    ForumBodyInlinePageContent input,
  ) => _fontFrames.putIfAbsent(
    index,
    () => ForumBodyInlineFontFramePagePreparation(
      input: input,
      fragment: snapshot[pageIndex].fragments[index],
      cache: _cache!,
      textScaler: _textScaler!,
      ensureOwner: _guard,
      ensureVisibleOwner: _ensureOwner!,
      ownedPageLeases: () => _finishedLeases,
    ),
  );

  // Parent and child requests are separate bounded inspection units. No native
  // work or large list of callbacks is retained by the whole-page probe.
  Iterable<_PageBudgetPart> _budgetParts(
    ForumBodyParagraphBudgetProbe probe,
  ) sync* {
    final page = snapshot[pageIndex];
    for (final (index, input) in _inputs.indexed) {
      final body = input.bodyContent;
      final fragment = page.fragments[index];
      var parent = true;
      for (final slot in input.nativeBudgetFootprintFor(fragment)) {
        yield (
          startsFragment: parent,
          inspect: () {
            slot.request.includeBudget(
              probe,
              width: slot.width,
              minimumLineCount: slot.minimumLineCount,
              textScaler: body is ForumBodyFittedEmphasisPageContent
                  ? body.plan.metrics.textScaler
                  : body is ForumBodyEmphasisPageContent
                  ? body.paragraph.textScaler
                  : body is ForumBodyInlinePageContent &&
                        body.fontFrames != null
                  ? body.fontFrames!.textScaler
                  : _textScaler!,
            );
          },
        );
        parent = false;
      }
      if (body is ForumBodyEmphasisPageContent) {
        final parts = _emphasisPart(index, body);
        while (!parts.isInputReady) {
          yield (startsFragment: parent, inspect: parts.advanceInput);
          parent = false;
        }
        yield (
          startsFragment: parent,
          inspect: () => parts.includeSceneBudget(probe),
        );
      }
      if (body is ForumBodyInlinePageContent && body.fontFrames != null) {
        final parts = _fontFramePart(index, body);
        while (!parts.isInputReady) {
          yield (startsFragment: parent, inspect: parts.advanceInput);
          parent = false;
        }
        yield (
          startsFragment: parent,
          inspect: () => parts.includeSceneBudget(probe),
        );
      }
    }
  }

  ({int fragments, int parts}) _inspectBudget({
    required int maxFragments,
    required int maxParts,
  }) {
    var fragments = 0;
    var parts = 0;
    try {
      while (parts < maxParts) {
        if (_nextProbePart == null) {
          if (!_probeWork!.moveNext()) {
            _finishBudgetProbe();
            break;
          }
          _guard();
          _nextProbePart = _probeWork!.current;
        }
        final part = _nextProbePart!;
        if (part.startsFragment && fragments >= maxFragments) break;
        _nextProbePart = null;
        part.inspect();
        _guard();
        parts++;
        if (part.startsFragment) fragments++;
        // Look ahead only to an inert descriptor. It performs no probe/native
        // work, and permits exact EOF without confusing handles with work units.
        if (!_probeWork!.moveNext()) {
          _finishBudgetProbe();
          break;
        }
        _guard();
        _nextProbePart = _probeWork!.current;
      }
      return (fragments: fragments, parts: parts);
    } on ForumBodyParagraphBudgetException {
      throw const ForumBodyTextPagePreparationException(
        ForumBodyTextPagePreparationFailure.intrinsicBudget,
      );
    }
  }

  void _finishBudgetProbe() {
    _pageBudgetChecked =
        _probeBuilds == _cache!.layoutBuildCount &&
        _probePictures == _cache!.pictureBuildCount;
    _checkedBuilds = _probeBuilds;
    _checkedPictures = _probePictures;
    final waiting =
        _probeAfterRejection &&
        _pageBudgetChecked &&
        _cache!.budgetRevision == _rejectedAtRevision;
    _closeProbe();
    _waiting = waiting;
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
    _list?.close();
    _list = null;
    _pendingListBody?.close();
    _pendingListBody = null;
    _fitted?.close();
    _fitted = null;
    _fittedWork = 0;
    for (final parts in _emphasis.values) {
      parts.close();
    }
    _emphasis.clear();
    _activeEmphasis = null;
    for (final parts in _fontFrames.values) {
      parts.close();
    }
    _fontFrames.clear();
    _activeFontFrame = null;
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
    _nextProbePart = null;
  }

  void _dropOwner() {
    _closeProbe();
    _fitted?.close();
    _fitted = null;
    _fittedWork = 0;
    for (final parts in _emphasis.values) {
      parts.close();
    }
    _emphasis.clear();
    _activeEmphasis = null;
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
