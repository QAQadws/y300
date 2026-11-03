import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_emphasis_text_geometry.dart';
import 'forum_body_inline_emphasis_children_plan.dart';
import 'forum_body_inline_emphasis_reflow_reference.dart';
import 'forum_body_inline_emphasis_row_placement.dart';
import 'forum_body_inline_paragraph_request.dart';

enum _ReflowPhase {
  children,
  beginPrefix,
  prefix,
  probe,
  acquire,
  classify,
  reference,
  geometry,
  verifyRows,
  verifyTargets,
  verifyAtoms,
  publish,
  ready,
  transferred,
  closed,
}

/// The final-parent measurement transaction. Borrows the initial parent and
/// caller prefix, owns only its new parent, and reuses completed child replans
/// through warm misses or external-pin waits. No paint is prepared here.
final class ForumBodyInlineEmphasisReflowPreparation {
  ForumBodyInlineEmphasisReflowPreparation({
    required ForumBodyInlineEmphasisRowPlacement placement,
    required ForumBodyInlineParagraphLease original,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    this.maxLines = 4096,
    this.maxAtoms = 512,
    this.maxHeight = 1048576,
    this.maxOwnedLeases = 32768,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _placement = placement,
       _original = original,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _additionalOwned = additionalOwnedLeases {
    if (maxLines <= 0 ||
        maxAtoms < 0 ||
        !maxHeight.isFinite ||
        maxHeight <= 0 ||
        maxOwnedLeases <= 0) {
      throw ArgumentError('Invalid mixed reflow preparation budget');
    }
    try {
      _guard();
      final geometry = placement.input.fonts.geometry;
      if (geometry.lineCount > maxLines || original.layout.height > maxHeight) {
        throw const ForumBodyEmphasisGeometryException(
          ForumBodyEmphasisGeometryFailure.limit,
        );
      }
      if (!identical(original.content, geometry.input.glyphInput.glyphs) ||
          !identical(original.layout.lines, geometry.lines) ||
          original.nativeInputIdentity != geometry.nativeInputIdentity ||
          original.layout.rowIsolationPitch != null) {
        throw const ForumBodyEmphasisLineException(
          ForumBodyEmphasisLineFailure.source,
        );
      }
      _childWork = ForumBodyInlineEmphasisChildrenPlanPreparation(
        placement: placement,
        ensureOwner: _guard,
        maxAtoms: maxAtoms,
      );
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int maxLines, maxAtoms, maxOwnedLeases;
  final double maxHeight;
  ForumBodyInlineEmphasisRowPlacement? _placement;
  ForumBodyInlineParagraphLease? _original, _pending;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyInlineEmphasisChildrenPlanPreparation? _childWork;
  ForumBodyInlineEmphasisChildrenPlan? _children;
  ForumBodyInlineParagraphRequest? _request;
  ForumBodyInlineEmphasisReflowReferencePreparation? _referenceWork;
  ForumBodyInlineEmphasisReflowReference? _reference;
  ForumBodyInlineEmphasisGeometryPreparation? _geometryWork;
  ForumBodyInlineEmphasisTextGeometry? _geometry;
  ForumBodyParagraphBudgetProbe? _probe;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  List<ForumBodyNativeParagraphLease> _owned = [];
  ForumBodyParagraphBudgetException? _rejection;
  int _rejectedAt = -1, _blockedAt = -1;
  int _verifiedRow = 0, _verifiedTarget = 0, _verifiedAtom = 0;
  var _phase = _ReflowPhase.children;
  bool _operating = false, _cacheMiss = false;
  bool get isReady => _phase == _ReflowPhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [?_pending];

  ForumBodyEmphasisLineStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Mixed reflow preparation is reentrant');
    _operating = true;
    var used = 0;
    final cache = _cache, before = cache?.layoutBuildCount ?? 0;
    ForumBodyEmphasisLineStep step([bool waiting = false]) => (
      partsPrepared: used,
      nativeLayoutsBuilt: cache!.layoutBuildCount - before,
      picturesRecorded: 0,
      waitingForLayoutBudget: waiting,
    );
    try {
      _guard();
      _cacheMiss = false;
      if (_blockedAt == cache!.budgetRevision) return step(true);
      while (!isReady && used < maxParts && cache.layoutBuildCount == before) {
        final rejectedAt = cache.budgetRevision;
        try {
          switch (_phase) {
            case _ReflowPhase.children:
              final work = _childWork!;
              used += work.advance(maxParts: maxParts - used);
              _guard();
              if (work.isReady) {
                final children = _children = work.takePlan();
                _childWork = null;
                _request = ForumBodyInlineParagraphRequest(
                  content: _original!.content,
                  dimensions: children.page.dimensions,
                  layoutMode: children.page.layoutMode,
                );
                _phase = _ReflowPhase.beginPrefix;
              }
              continue;
            case _ReflowPhase.beginPrefix:
              _probe = cache.createBudgetProbe();
              _probe!.includeLease(_original!);
              _owned = [_original!];
              final values =
                  _additionalOwned?.call() ??
                  const <ForumBodyNativeParagraphLease>[];
              _guard();
              final iterator = values.iterator;
              _guard();
              _prefix = iterator;
              _phase = _ReflowPhase.prefix;
            case _ReflowPhase.prefix:
              final iterator = _prefix!, more = iterator.moveNext();
              _guard();
              if (more) {
                if (_owned.length >= maxOwnedLeases) {
                  throw const ForumBodyEmphasisGeometryException(
                    ForumBodyEmphasisGeometryFailure.limit,
                  );
                }
                final lease = iterator.current;
                _guard();
                _probe!.includeLease(lease);
                _owned.add(lease);
              } else {
                _prefix = null;
                _phase = _rejection == null
                    ? _ReflowPhase.probe
                    : _ReflowPhase.classify;
              }
            case _ReflowPhase.probe:
              _request!.includeBudget(
                _probe!,
                width: _placement!.input.fonts.requestWidth,
                textScaler: _placement!.input.fonts.textScaler,
                minimumLineCount: _placement!.input.fonts.geometry.lineCount,
              );
              _guard();
              _probe!.close();
              _probe = null;
              _phase = _ReflowPhase.acquire;
            case _ReflowPhase.acquire:
              final acquired = _request!.acquire(
                cache,
                width: _placement!.input.fonts.requestWidth,
                textScaler: _placement!.input.fonts.textScaler,
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
                _owned = [];
                _phase = _ReflowPhase.beginPrefix;
                used++;
                return step();
              }
              _pending = acquired;
              _owned = [];
              _referenceWork =
                  ForumBodyInlineEmphasisReflowReferencePreparation(
                    children: _children!,
                    original: _original!,
                    finalParent: acquired,
                    ensureOwner: _guard,
                    maxLines: maxLines,
                    maxAtoms: maxAtoms,
                    maxHeight: maxHeight,
                  );
              _phase = _ReflowPhase.reference;
            case _ReflowPhase.classify:
              final rejection = _rejection!;
              final external = cache.isBlockedByExternalPins(rejection, _owned);
              _guard();
              if (cache.budgetRevision != _rejectedAt) {
                _probe!.close();
                _probe = null;
                _owned = [];
                _rejection = null;
                _blockedAt = -1;
                _phase = _ReflowPhase.beginPrefix;
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
              _probe!.close();
              _probe = null;
              _owned = [];
              _rejection = null;
              _blockedAt = _rejectedAt;
              _phase = _ReflowPhase.beginPrefix;
              used++;
              return step(cache.budgetRevision == _blockedAt);
            case _ReflowPhase.reference:
              final work = _referenceWork!;
              used += work.advance(maxParts: maxParts - used);
              _guard();
              if (work.isReady) {
                _reference = work.takeReference();
                _referenceWork = null;
                _geometryWork = ForumBodyInlineEmphasisGeometryPreparation(
                  input: _placement!.input.fonts.geometry.input,
                  parent: _pending!,
                  ensureOwner: _guard,
                );
                _phase = _ReflowPhase.geometry;
              }
              continue;
            case _ReflowPhase.geometry:
              final work = _geometryWork!;
              used += work.advance(maxParts: maxParts - used);
              _guard();
              if (work.isReady) {
                _geometry = work.takeGeometry();
                _geometryWork = null;
                final old = _placement!.input.fonts.geometry;
                if (_geometry!.lineCount != old.lineCount ||
                    _geometry!.targets.length != old.targets.length ||
                    _geometry!.atomLineIndices.length !=
                        old.atomLineIndices.length) {
                  throw const ForumBodyEmphasisLineException(
                    ForumBodyEmphasisLineFailure.metrics,
                  );
                }
                _phase = _ReflowPhase.verifyRows;
              }
              continue;
            case _ReflowPhase.verifyRows:
              if (_verifiedRow < _geometry!.lineCount) {
                final index = _verifiedRow++;
                final a = _placement!
                        .input
                        .fonts
                        .geometry
                        .parentFontBounds[index],
                    b = _geometry!.parentFontBounds[index];
                if (a == null || b == null) {
                  if (a != b) {
                    throw const ForumBodyEmphasisLineException(
                      ForumBodyEmphasisLineFailure.geometry,
                    );
                  }
                } else {
                  _verifyFontRect(a, b, index);
                }
              } else {
                _phase = _ReflowPhase.verifyTargets;
              }
            case _ReflowPhase.verifyTargets:
              if (_verifiedTarget < _geometry!.targets.length) {
                final index = _verifiedTarget++,
                    a = _placement!.input.fonts.geometry.targets[index],
                    b = _geometry!.targets[index];
                if (!identical(a.unit, b.unit) ||
                    a.lineIndex != b.lineIndex ||
                    a.sourceStartLine != b.sourceStartLine ||
                    a.sourceEndLine != b.sourceEndLine) {
                  throw const ForumBodyEmphasisLineException(
                    ForumBodyEmphasisLineFailure.source,
                  );
                }
                // A complete source unit may span rows with different deltas.
                // Its governing font is row-local; never shift the whole union.
                _verifyFontRect(
                  a.governingFontBounds,
                  b.governingFontBounds,
                  a.lineIndex,
                );
              } else {
                _phase = _ReflowPhase.verifyAtoms;
              }
            case _ReflowPhase.verifyAtoms:
              if (_verifiedAtom < _geometry!.atomLineIndices.length) {
                final index = _verifiedAtom++;
                if (_geometry!.atomLineIndices[index] !=
                    _placement!.input.fonts.geometry.atomLineIndices[index]) {
                  throw const ForumBodyEmphasisLineException(
                    ForumBodyEmphasisLineFailure.source,
                  );
                }
              } else {
                _phase = _ReflowPhase.publish;
              }
            case _ReflowPhase.publish:
              _phase = _ReflowPhase.ready;
            case _ReflowPhase.ready:
            case _ReflowPhase.transferred:
            case _ReflowPhase.closed:
              throw StateError('Mixed reflow preparation is retired');
          }
          used++;
          _guard();
        } on ForumBodyParagraphBudgetException catch (error) {
          _guard();
          if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
          _probe?.close();
          _probe = null;
          _prefix = null;
          _owned = [];
          _rejection = error;
          _rejectedAt = rejectedAt;
          _phase = _ReflowPhase.beginPrefix;
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

  ({
    ForumBodyInlineEmphasisReflowReference reference,
    ForumBodyInlineParagraphLease parent,
    ForumBodyInlineEmphasisTextGeometry geometry,
  })
  takeMeasurement() {
    if (_operating) throw StateError('Mixed reflow preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Mixed reflow preparation is incomplete');
      final result = (
        reference: _reference!,
        parent: _pending!,
        geometry: _geometry!,
      );
      _pending = null;
      _phase = _ReflowPhase.transferred;
      _drop();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _verifyFontRect(Rect original, Rect actual, int row) {
    final ref = _reference!, delta = ref.baselineDeltas[row];
    double tolerance(Rect r, double baseline) =>
        forumBodyNativeVerticalBoxTolerance(
          TextBox.fromLTRBD(
            r.left,
            r.top,
            r.right,
            r.bottom,
            TextDirection.ltr,
          ),
          baseline,
        );
    // Both captured native font endpoints may have Float32 rounding. Retain
    // actual final geometry; this tolerance never changes a source boundary.
    final vertical =
        tolerance(original, ref.originalLines[row].baseline) +
        tolerance(actual, ref.finalLines[row].baseline);
    if (actual.left != original.left ||
        actual.right != original.right ||
        (actual.top - original.top - delta).abs() > vertical ||
        (actual.bottom - original.bottom - delta).abs() > vertical) {
      throw const ForumBodyEmphasisLineException(
        ForumBodyEmphasisLineFailure.geometry,
      );
    }
  }

  void _guard() {
    if (_phase == _ReflowPhase.closed || _phase == _ReflowPhase.transferred) {
      throw StateError('Mixed reflow preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _ReflowPhase.closed ||
        _phase == _ReflowPhase.transferred ||
        _cache!.isClosed ||
        !_cache!.ownsLease(_original!) ||
        (_pending != null && !_cache!.ownsLease(_pending!))) {
      throw StateError('Mixed reflow preparation owner is retired');
    }
  }

  void close() {
    if (_phase == _ReflowPhase.closed || _phase == _ReflowPhase.transferred) {
      return;
    }
    _phase = _ReflowPhase.closed;
    try {
      _pending?.release();
    } finally {
      _pending = null;
      _drop();
    }
  }

  void _drop() {
    _childWork?.close();
    _childWork = null;
    _referenceWork?.close();
    _referenceWork = null;
    _geometryWork?.close();
    _geometryWork = null;
    _probe?.close();
    _probe = null;
    _prefix = null;
    _owned = [];
    _rejection = null;
    _placement = null;
    _original = null;
    _cache = null;
    _ensureOwner = null;
    _additionalOwned = null;
    _children = null;
    _request = null;
    _reference = null;
    _geometry = null;
  }
}
