import 'dart:collection';

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import 'forum_body_emphasis_allocation_geometry.dart';
import 'forum_body_paragraph_frame.dart';
import 'forum_body_inline_emphasis_paint_reference.dart';
import 'forum_body_inline_emphasis_paint_view.dart';
import 'forum_body_inline_emphasis_row_allocation.dart';
import 'forum_body_inline_paragraph_request.dart';
import 'forum_body_inline_span_content.dart';

/// Owns only three phase aliases. The actual source parent remains borrowed
/// from the containing format, which also owns source/child/scene admission.
final class ForumBodyInlineEmphasisPaintBinding {
  ForumBodyInlineEmphasisPaintBinding._(
    this.view,
    List<ForumBodyInlineParagraphLease> phases,
  ) : phases = UnmodifiableListView(phases);
  final ForumBodyInlineEmphasisPaintView view;
  final List<ForumBodyInlineParagraphLease> phases;
  bool _closed = false;
  bool get isPaintPrepared => !_closed && view.isPaintPrepared;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    if (!_closed) yield* phases;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final parent in phases) {
      parent.release();
    }
  }
}

enum _Phase {
  scales,
  source,
  beginPrefix,
  known,
  prefix,
  probe,
  classify,
  acquire,
  paint,
  reference,
  publish,
  ready,
  transferred,
  closed,
}

/// Gets all three real phase parents through the existing cache. Source plus
/// phases and the caller's preparing prefix share ONE complete budget probe.
/// Each advance stops after at most one native shape OR first-paint recording;
/// pure qualification reuses the current reference worker. No scene is recorded.
final class ForumBodyInlineEmphasisPaintPreparation {
  ForumBodyInlineEmphasisPaintPreparation({
    required ForumBodyInlineEmphasisRowAllocation allocation,
    required ForumBodyInlineParagraphLease source,
    required ForumBodyParagraphCache cache,
    required TextScaler expectedTextScaler,
    required void Function() ensureOwner,
    void Function()? ensureVisibleOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
    this.preparePaint = true,
    this.maxLines = 4096,
    this.maxAtoms = 512,
    this.maxBoxes = 32768,
    this.maxGlyphQueries = 65536,
    this.maxOwnedLeases = 32768,
  }) : _allocation = allocation,
       _source = source,
       _cache = cache,
       _callerScaler = expectedTextScaler,
       _ensureOwner = ensureOwner,
       _ensureVisibleOwner = ensureVisibleOwner ?? ensureOwner,
       _additionalOwned = additionalOwnedLeases {
    if (maxLines <= 0 ||
        maxAtoms < 0 ||
        maxBoxes < 0 ||
        maxGlyphQueries < 0 ||
        maxOwnedLeases <= 0) {
      throw ArgumentError('Invalid mixed phase acquisition budget');
    }
    try {
      _guard();
      final input = allocation.input;
      if (!identical(source.content, input.request.content) ||
          source.nativeInputIdentity != input.reference.isolatedInputIdentity ||
          !identical(source.layout.lines, input.reference.isolatedLines)) {
        _sourceFailure();
      }
      if (maxOwnedLeases < 4 ||
          source.layout.lineCount > maxLines ||
          source.layout.atomBoxes.length > maxAtoms) {
        _limit();
      }
      _paint = ForumBodyInlinePaintInput(source.content);
      _requests = List.unmodifiable([
        for (final content in [
          _paint!.background,
          _paint!.foreground,
          _paint!.decoration,
        ])
          ForumBodyInlineParagraphRequest(
            content: content,
            dimensions: input.request.dimensions,
            layoutMode: input.request.layoutMode,
            rowIsolationPitch: input.request.rowIsolationPitch,
          ),
      ]);
      _scales = input.natural.effectiveScales.entries.iterator;
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }

  final bool preparePaint;
  final int maxLines, maxAtoms, maxBoxes, maxGlyphQueries, maxOwnedLeases;
  ForumBodyInlineEmphasisRowAllocation? _allocation;
  ForumBodyInlineParagraphLease? _source;
  ForumBodyParagraphCache? _cache;
  TextScaler? _callerScaler;
  Iterator<MapEntry<double, double>>? _scales;
  void Function()? _ensureOwner, _ensureVisibleOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyInlinePaintInput? _paint;
  List<ForumBodyInlineParagraphRequest> _requests = const [];
  List<ForumBodyInlineParagraphLease> _parents = [];
  List<ForumBodyNativeParagraphLease> _owned = [];
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  ForumBodyParagraphBudgetProbe? _probe;
  ForumBodyParagraphBudgetException? _rejection, _waitingRejection;
  ForumBodyInlineEmphasisPaintReferencePreparation? _referenceWork;
  ForumBodyInlineEmphasisPaintReference? _reference;
  ForumBodyInlineEmphasisPaintView? _view;
  var _phase = _Phase.scales, _action = _Phase.acquire;
  int _layer = 0, _known = 0, _request = 0, _blockedAt = -1, _rejectedAt = -1;
  bool _operating = false, _cacheMiss = false;
  bool get isReady => _phase == _Phase.ready;
  bool get cacheMiss => _cacheMiss;
  ForumBodyParagraphBudgetException? get lastBudgetRejection =>
      _rejection ?? _waitingRejection;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    yield* _parents;
  }

  ForumBodyFontFrameStep advance({int maxParts = 32, bool cachedOnly = false}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Mixed phase acquisition is reentrant');
    _operating = true;
    final cache = _cache,
        builds = cache?.layoutBuildCount ?? 0,
        pictures = cache?.pictureBuildCount ?? 0;
    var used = 0;
    ForumBodyFontFrameStep step([bool waiting = false]) => (
      partsPrepared: used,
      nativeLayoutsBuilt: cache!.layoutBuildCount - builds,
      picturesRecorded: cache.pictureBuildCount - pictures,
      waitingForLayoutBudget: waiting,
    );
    try {
      _guard();
      _cacheMiss = false;
      if (_blockedAt == cache!.budgetRevision) return step(true);
      _waitingRejection = null;
      while (!isReady &&
          used < maxParts &&
          cache.layoutBuildCount == builds &&
          cache.pictureBuildCount == pictures) {
        _guard();
        final input = _allocation!.input, rejectedAt = cache.budgetRevision;
        try {
          switch (_phase) {
            case _Phase.scales:
              final more = _scales!.moveNext();
              _guard();
              if (more) {
                final sample = _scales!.current,
                    actual = _callerScaler!.scale(sample.key);
                _guard();
                if (!actual.isFinite ||
                    actual <= 0 ||
                    actual > 4096 ||
                    actual != sample.value) {
                  _sourceFailure();
                }
              } else {
                _scales = null;
                _callerScaler = null;
                _phase = _Phase.source;
              }
            case _Phase.source:
              final request = input.request;
              if (!_source!.matchesNativeInputs(
                content: request.content,
                width: input.natural.requestWidth,
                dimensions: request.dimensions,
                textScaler: input.natural.textScaler,
                layoutMode: request.layoutMode,
                rowIsolationPitch: request.rowIsolationPitch,
              )) {
                _sourceFailure();
              }
              _phase = _Phase.beginPrefix;
            case _Phase.beginPrefix:
              _releaseProbe();
              _probe = cache.createBudgetProbe();
              _known = _request = 0;
              _phase = _Phase.known;
            case _Phase.known:
              if (_known <= _parents.length) {
                final index = _known++,
                    parent = index == 0 ? _source! : _parents[index - 1];
                if (_owned.length >= maxOwnedLeases) _limit();
                _probe!.includeLease(parent);
                _owned.add(parent);
              } else {
                final values =
                    _additionalOwned?.call() ??
                    const <ForumBodyNativeParagraphLease>[];
                _guard();
                final iterator = values.iterator;
                _guard();
                _prefix = iterator;
                _phase = _Phase.prefix;
              }
            case _Phase.prefix:
              final iterator = _prefix!, more = iterator.moveNext();
              _guard();
              if (more) {
                // All remaining phases will be pinned before qualification;
                // reserve their handle slots while consuming the caller prefix.
                if (_owned.length + (3 - _parents.length) >= maxOwnedLeases) {
                  _limit();
                }
                final parent = iterator.current;
                _guard();
                _probe!.includeLease(parent);
                _owned.add(parent);
              } else {
                _prefix = null;
                _phase = _rejection == null ? _Phase.probe : _Phase.classify;
              }
            case _Phase.probe:
              if (_request < _requests.length) {
                _requests[_request++].includeBudget(
                  _probe!,
                  width: input.natural.requestWidth,
                  textScaler: input.natural.textScaler,
                  minimumLineCount: _source!.layout.lineCount,
                );
              } else {
                _releaseProbe();
                _phase = _action;
              }
            case _Phase.classify:
              // A prefix callback can release a pin. Retire the stale rejection
              // before inspecting its now-obsolete ownership snapshot.
              if (cache.budgetRevision != _rejectedAt) {
                _releaseProbe();
                _rejection = null;
                _blockedAt = -1;
                _phase = _Phase.beginPrefix;
                used++;
                return step();
              }
              final rejection = _rejection!,
                  external = cache.isBlockedByExternalPins(rejection, _owned);
              _guard();
              if (cache.budgetRevision != _rejectedAt) {
                _releaseProbe();
                _rejection = null;
                _blockedAt = -1;
                _phase = _Phase.beginPrefix;
                used++;
                return step();
              }
              if (!external) {
                throw ForumBodyParagraphBudgetException(
                  ForumBodyParagraphBudgetFailure.content,
                  requiredEstimatedBytes: rejection.requiredEstimatedBytes,
                  requiredAdditionalEntries:
                      rejection.requiredAdditionalEntries,
                );
              }
              _releaseProbe();
              _rejection = null;
              _waitingRejection = rejection;
              _blockedAt = _rejectedAt;
              _phase = _Phase.beginPrefix;
              used++;
              return step(cache.budgetRevision == _blockedAt);
            case _Phase.acquire:
              final acquired = _requests[_layer].acquire(
                cache,
                width: input.natural.requestWidth,
                textScaler: input.natural.textScaler,
                cachedOnly: cachedOnly,
              );
              try {
                _guard();
              } catch (_) {
                acquired?.release();
                rethrow;
              }
              if (acquired == null) {
                _cacheMiss = true;
                _phase = _Phase.beginPrefix;
                used++;
                return step();
              }
              _parents.add(acquired);
              _phase = _Phase.paint;
            case _Phase.paint:
              final parent = _parents[_layer];
              if (preparePaint && !parent.layout.isPaintPrepared) {
                if (cachedOnly) {
                  _cacheMiss = true;
                  _action = _Phase.paint;
                  _phase = _Phase.beginPrefix;
                  used++;
                  return step();
                }
                cache.prepareInlineParentPaint(parent);
                _guard();
              }
              if (++_layer < 3) {
                _action = _Phase.acquire;
                _phase = _Phase.beginPrefix;
              } else {
                _phase = _Phase.reference;
              }
            case _Phase.reference:
              final work = _referenceWork ??=
                  ForumBodyInlineEmphasisPaintReferencePreparation(
                    allocation: _allocation!,
                    paintInput: _paint!,
                    source: _source!,
                    phases: _parents,
                    ensureOwner: _guard,
                    maxLines: maxLines,
                    maxAtoms: maxAtoms,
                    maxBoxes: maxBoxes,
                    maxGlyphQueries: maxGlyphQueries,
                  );
              used += work.advance(maxParts: maxParts - used);
              _guard();
              if (work.isReady) {
                _reference = work.takeReference();
                _referenceWork = null;
                _phase = _Phase.publish;
              }
              continue;
            case _Phase.publish:
              // The visible callback survives takeBinding; the worker's guard
              // deliberately retires on transfer and must not back the view.
              final visibleOwner = _ensureVisibleOwner!;
              _view = ForumBodyInlineEmphasisPaintView.bind(
                reference: _reference!,
                source: _source!,
                phases: _parents,
                ensureOwner: visibleOwner,
              );
              _phase = _Phase.ready;
            case _Phase.ready:
            case _Phase.transferred:
            case _Phase.closed:
              throw StateError('Mixed phase acquisition is retired');
          }
          used++;
          _guard();
        } on ForumBodyParagraphBudgetException catch (error) {
          _guard();
          if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
          _action = _phase == _Phase.paint ? _Phase.paint : _Phase.acquire;
          _releaseProbe();
          _rejection = error;
          _rejectedAt = rejectedAt;
          _phase = _Phase.beginPrefix;
          used++;
          break;
        }
      }
      return step();
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyInlineEmphasisPaintBinding takeBinding() {
    if (_operating) throw StateError('Mixed phase acquisition is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Mixed phase acquisition is incomplete');
      _ensureVisibleOwner!();
      _guard();
      final value = ForumBodyInlineEmphasisPaintBinding._(_view!, _parents);
      _parents = [];
      _phase = _Phase.transferred;
      _drop();
      return value;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _Phase.closed || _phase == _Phase.transferred) {
      throw StateError('Mixed phase acquisition is retired');
    }
    _ensureOwner!();
    if (_phase == _Phase.closed ||
        _phase == _Phase.transferred ||
        _cache!.isClosed ||
        !_cache!.ownsLease(_source!) ||
        _parents.any((p) => !_cache!.ownsLease(p))) {
      throw StateError('Mixed phase acquisition owner is retired');
    }
  }

  void _releaseProbe() {
    _probe?.close();
    _probe = null;
    _owned = [];
    _prefix = null;
  }

  void close() {
    if (_phase == _Phase.closed || _phase == _Phase.transferred) return;
    _phase = _Phase.closed;
    final parents = _parents;
    _parents = [];
    try {
      for (final parent in parents) {
        parent.release();
      }
    } finally {
      _drop();
    }
  }

  void _drop() {
    _releaseProbe();
    _referenceWork?.close();
    _referenceWork = null;
    _allocation = null;
    _source = null;
    _cache = null;
    _callerScaler = null;
    _scales = null;
    _ensureOwner = _ensureVisibleOwner = null;
    _additionalOwned = null;
    _paint = null;
    _requests = const [];
    _rejection = _waitingRejection = null;
    _view = null;
    _reference = null;
  }
}

Never _sourceFailure() => throw const ForumBodyEmphasisAllocationException(
  ForumBodyEmphasisAllocationFailure.source,
);
Never _limit() => throw const ForumBodyEmphasisAllocationException(
  ForumBodyEmphasisAllocationFailure.limit,
);
