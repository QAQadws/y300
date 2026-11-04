import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import '../paragraph/forum_body_paragraph_row.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_emphasis_text_geometry.dart';
import 'forum_body_inline_emphasis_parent_preparation.dart';
import 'forum_body_inline_paragraph_request.dart';
import 'forum_body_inline_logical_paint_rows.dart';
import 'forum_body_inline_parent_rows.dart';
import 'forum_body_inline_row_reference.dart';

/// The final natural parent and its actual glyph/logical paint strips. Numeric
/// geometry only: physical allocation, child binding and visible scene/page
/// admission are not established by this snapshot.
final class ForumBodyInlineEmphasisIsolationMetrics {
  const ForumBodyInlineEmphasisIsolationMetrics._(
    this.natural,
    this.request,
    this.reference,
    this.rows,
    this.logicalRows,
  );
  final ForumBodyInlineEmphasisParentMetrics natural;
  final ForumBodyInlineParagraphRequest request;
  final ForumBodyInlineRowReference reference;
  final ForumBodyInlineParentRows rows;
  final ForumBodyInlineLogicalPaintRows logicalRows;
  ForumBodyInlineEmphasisTextGeometry get geometry => rows.geometry;
}

enum _IsolationPhase {
  beginPrefix,
  prefix,
  probe,
  acquire,
  classify,
  reference,
  geometry,
  verifyFonts,
  verifyTargets,
  verifyAtoms,
  rows,
  logicalRows,
  ready,
  transferred,
  closed,
}

/// Borrows the source-qualified final natural parent. Owns only the current
/// isolated parent and retries measured insufficient paint gaps in place.
/// No first paint or picture is prepared; the containing format retains the
/// natural parent and is responsible for complete page/scene admission.
final class ForumBodyInlineEmphasisIsolationPreparation {
  ForumBodyInlineEmphasisIsolationPreparation({
    required ForumBodyInlineEmphasisParentMetrics metrics,
    required ForumBodyInlineParagraphLease natural,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    double rowIsolationPitch = 256,
    this.maxLines = 4096,
    this.maxAtoms = 512,
    this.maxBoxes = 32768,
    this.maxGlyphQueries = 16384,
    this.maxOwnedLeases = 32768,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _metrics = metrics,
       _natural = natural,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _pitch = rowIsolationPitch,
       _additionalOwned = additionalOwnedLeases {
    if (!rowIsolationPitch.isFinite ||
        rowIsolationPitch <= 0 ||
        rowIsolationPitch > 16384 ||
        maxLines <= 0 ||
        maxAtoms < 0 ||
        maxBoxes < 0 ||
        maxGlyphQueries < 0 ||
        maxOwnedLeases <= 0) {
      throw ArgumentError('Invalid mixed parent isolation budget');
    }
    try {
      _guard();
      final geometry = metrics.geometry;
      if (!identical(natural.content, metrics.text.glyphInput.glyphs) ||
          natural.nativeInputIdentity != geometry.nativeInputIdentity ||
          !identical(natural.layout.lines, geometry.lines) ||
          natural.layout.rowIsolationPitch != null) {
        _sourceFailure();
      }
      if (geometry.lineCount > maxLines ||
          natural.layout.atomBoxes.length > maxAtoms) {
        throw const ForumBodyEmphasisGeometryException(
          ForumBodyEmphasisGeometryFailure.limit,
        );
      }
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }

  final int maxLines, maxAtoms, maxBoxes, maxGlyphQueries, maxOwnedLeases;
  ForumBodyInlineEmphasisParentMetrics? _metrics;
  ForumBodyInlineParagraphLease? _natural, _pending;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyInlineParagraphRequest? _request;
  ForumBodyParagraphBudgetProbe? _probe;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  List<ForumBodyNativeParagraphLease> _owned = [];
  ForumBodyParagraphBudgetException? _rejection;
  ForumBodyInlineRowReferencePreparation? _referenceWork;
  ForumBodyInlineRowReference? _reference;
  ForumBodyInlineEmphasisGeometryPreparation? _geometryWork;
  ForumBodyInlineEmphasisTextGeometry? _geometry;
  ForumBodyInlineParentRowPreparation? _rowWork;
  ForumBodyInlineLogicalPaintRowPreparation? _logicalWork;
  ForumBodyInlineParentRows? _rows;
  ForumBodyInlineEmphasisIsolationMetrics? _result;
  var _phase = _IsolationPhase.beginPrefix;
  double _pitch;
  int _blockedAt = -1, _rejectedAt = -1, _font = 0, _target = 0, _atom = 0;
  bool _operating = false, _cacheMiss = false;
  bool get isReady => _phase == _IsolationPhase.ready;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [?_pending];

  ForumBodyEmphasisLineStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Mixed parent isolation is reentrant');
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
        _guard();
        final rejectedAt = cache.budgetRevision;
        try {
          switch (_phase) {
            case _IsolationPhase.beginPrefix:
              _request ??= ForumBodyInlineParagraphRequest(
                content: _natural!.content,
                dimensions: _metrics!.page.dimensions,
                layoutMode: _metrics!.page.layoutMode,
                rowIsolationPitch: _pitch,
              );
              _probe = cache.createBudgetProbe();
              _probe!.includeLease(_natural!);
              _owned = [_natural!];
              final values =
                  _additionalOwned?.call() ??
                  const <ForumBodyNativeParagraphLease>[];
              _guard();
              final iterator = values.iterator;
              _guard();
              _prefix = iterator;
              _phase = _IsolationPhase.prefix;
            case _IsolationPhase.prefix:
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
                    ? _IsolationPhase.probe
                    : _IsolationPhase.classify;
              }
            case _IsolationPhase.probe:
              _request!.includeBudget(
                _probe!,
                width: _metrics!.requestWidth,
                textScaler: _metrics!.textScaler,
                minimumLineCount: _metrics!.geometry.lineCount,
              );
              _guard();
              _probe!.close();
              _probe = null;
              _phase = _IsolationPhase.acquire;
            case _IsolationPhase.acquire:
              final acquired = _request!.acquire(
                cache,
                width: _metrics!.requestWidth,
                textScaler: _metrics!.textScaler,
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
                _phase = _IsolationPhase.beginPrefix;
                used++;
                return step();
              }
              _pending = acquired;
              _owned = [];
              _referenceWork = ForumBodyInlineRowReferencePreparation(
                natural: _natural!,
                isolated: acquired,
                ensureOwner: _guard,
                maxLines: maxLines,
                maxAtoms: maxAtoms,
              );
              _phase = _IsolationPhase.reference;
            case _IsolationPhase.classify:
              final rejection = _rejection!;
              final external = cache.isBlockedByExternalPins(rejection, _owned);
              _guard();
              if (cache.budgetRevision != _rejectedAt) {
                _releaseProbe();
                _rejection = null;
                _blockedAt = -1;
                _phase = _IsolationPhase.beginPrefix;
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
              _blockedAt = _rejectedAt;
              _phase = _IsolationPhase.beginPrefix;
              used++;
              return step(cache.budgetRevision == _blockedAt);
            case _IsolationPhase.reference:
              final work = _referenceWork!;
              used += work.advance(maxParts: maxParts - used);
              _guard();
              if (work.isReady) {
                _reference = work.takeReference();
                _referenceWork = null;
                _geometryWork = ForumBodyInlineEmphasisGeometryPreparation(
                  input: _metrics!.text,
                  parent: _pending!,
                  ensureOwner: _guard,
                  maxBoxes: maxBoxes,
                  maxGlyphQueries: maxGlyphQueries,
                );
                _phase = _IsolationPhase.geometry;
              }
              continue;
            case _IsolationPhase.geometry:
              final work = _geometryWork!;
              used += work.advance(maxParts: maxParts - used);
              _guard();
              if (work.isReady) {
                _geometry = work.takeGeometry();
                _geometryWork = null;
                final old = _metrics!.geometry;
                if (_geometry!.lineCount != old.lineCount ||
                    _geometry!.targets.length != old.targets.length ||
                    _geometry!.atomLineIndices.length !=
                        old.atomLineIndices.length) {
                  _sourceFailure();
                }
                _phase = _IsolationPhase.verifyFonts;
              }
              continue;
            case _IsolationPhase.verifyFonts:
              if (_font < _geometry!.lineCount) {
                final row = _font++,
                    a = _metrics!.geometry.parentFontBounds[row],
                    b = _geometry!.parentFontBounds[row];
                if (a == null || b == null) {
                  if (a != b) _sourceFailure();
                } else {
                  _verifyFont(a, b, row);
                }
              } else {
                _phase = _IsolationPhase.verifyTargets;
              }
            case _IsolationPhase.verifyTargets:
              if (_target < _geometry!.targets.length) {
                final i = _target++,
                    a = _metrics!.geometry.targets[i],
                    b = _geometry!.targets[i];
                if (!identical(a.unit, b.unit) ||
                    a.lineIndex != b.lineIndex ||
                    a.sourceStartLine != b.sourceStartLine ||
                    a.sourceEndLine != b.sourceEndLine) {
                  _sourceFailure();
                }
                _verifyFont(
                  a.governingFontBounds,
                  b.governingFontBounds,
                  a.lineIndex,
                );
              } else {
                _phase = _IsolationPhase.verifyAtoms;
              }
            case _IsolationPhase.verifyAtoms:
              if (_atom < _geometry!.atomLineIndices.length) {
                final i = _atom++, actual = _geometry!.atomLineIndices[i];
                if (actual != _metrics!.geometry.atomLineIndices[i] ||
                    actual != _reference!.atomLineIndices[i]) {
                  _sourceFailure();
                }
              } else {
                _rowWork = ForumBodyInlineParentRowPreparation(
                  parent: _pending!,
                  geometry: _geometry!,
                  ensureOwner: _guard,
                  maxLines: maxLines,
                );
                _phase = _IsolationPhase.rows;
              }
            case _IsolationPhase.rows:
              final work = _rowWork!;
              used += work.advance(maxParts: maxParts - used);
              _guard();
              if (work.isReady) {
                _rows = work.takeRows();
                _rowWork = null;
                _logicalWork = ForumBodyInlineLogicalPaintRowPreparation(
                  parent: _pending!,
                  geometry: _geometry!,
                  ensureOwner: _guard,
                  maxLines: maxLines,
                  maxAtoms: maxAtoms,
                );
                _phase = _IsolationPhase.logicalRows;
              }
              continue;
            case _IsolationPhase.logicalRows:
              final work = _logicalWork!;
              used += work.advance(maxParts: maxParts - used);
              _guard();
              if (work.isReady) {
                _result = ForumBodyInlineEmphasisIsolationMetrics._(
                  _metrics!,
                  _request!,
                  _reference!,
                  _rows!,
                  work.takeRows(),
                );
                _rows = null;
                _logicalWork = null;
                _phase = _IsolationPhase.ready;
              }
              continue;
            case _IsolationPhase.ready:
            case _IsolationPhase.transferred:
            case _IsolationPhase.closed:
              throw StateError('Mixed parent isolation is retired');
          }
          used++;
          _guard();
        } on ForumBodyParagraphRowException catch (error) {
          if (error.failure != ForumBodyParagraphRowFailure.isolation) rethrow;
          _retry(error);
          // A failing delegate does not expose its consumed count. Charge the
          // remaining allowance so retrying cannot undercount this slice.
          used = maxParts;
        } on ForumBodyParagraphBudgetException catch (error) {
          _guard();
          if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
          _releaseProbe();
          _rejection = error;
          _rejectedAt = rejectedAt;
          _phase = _IsolationPhase.beginPrefix;
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

  void _verifyFont(Rect a, Rect b, int row) {
    final ref = _reference!;
    if (!forumBodyHaveSameShiftedNativeFontBounds(
      a,
      b,
      originalBaseline: ref.naturalLines[row].baseline,
      actualBaseline: ref.isolatedLines[row].baseline,
    )) {
      throw const ForumBodyEmphasisLineException(
        ForumBodyEmphasisLineFailure.geometry,
      );
    }
  }

  void _retry(ForumBodyParagraphRowException error) {
    _guard();
    final required = error.requiredPitch;
    if (required == null || !required.isFinite || required <= _pitch) {
      throw error;
    }
    final next = math.max(required, _pitch * 2);
    if (next > 16384) throw error;
    _rowWork?.close();
    _rowWork = null;
    _logicalWork?.close();
    _logicalWork = null;
    _rows = null;
    _geometry = null;
    _reference = null;
    final previous = _pending!;
    _pending = null;
    previous.release();
    _guard();
    _request = null;
    _font = _target = _atom = 0;
    _pitch = next;
    _phase = _IsolationPhase.beginPrefix;
    _guard();
  }

  ({
    ForumBodyInlineEmphasisIsolationMetrics metrics,
    ForumBodyInlineParagraphLease parent,
  })
  takeMeasurement() {
    if (_operating) throw StateError('Mixed parent isolation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Mixed parent isolation is incomplete');
      final result = (metrics: _result!, parent: _pending!);
      _pending = null;
      _phase = _IsolationPhase.transferred;
      _drop();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  static Never _sourceFailure() => throw const ForumBodyEmphasisLineException(
    ForumBodyEmphasisLineFailure.source,
  );
  void _guard() {
    if (_phase == _IsolationPhase.closed ||
        _phase == _IsolationPhase.transferred) {
      throw StateError('Mixed parent isolation is retired');
    }
    _ensureOwner!();
    if (_phase == _IsolationPhase.closed ||
        _phase == _IsolationPhase.transferred ||
        _cache!.isClosed ||
        !_cache!.ownsLease(_natural!) ||
        (_pending != null && !_cache!.ownsLease(_pending!))) {
      throw StateError('Mixed parent isolation owner is retired');
    }
  }

  void _releaseProbe() {
    _probe?.close();
    _probe = null;
    _prefix = null;
    _owned = [];
  }

  void close() {
    if (_phase == _IsolationPhase.closed ||
        _phase == _IsolationPhase.transferred) {
      return;
    }
    _phase = _IsolationPhase.closed;
    try {
      _pending?.release();
    } finally {
      _pending = null;
      _drop();
    }
  }

  void _drop() {
    _referenceWork?.close();
    _referenceWork = null;
    _geometryWork?.close();
    _geometryWork = null;
    _rowWork?.close();
    _rowWork = null;
    _logicalWork?.close();
    _logicalWork = null;
    _rows = null;
    _releaseProbe();
    _metrics = null;
    _natural = null;
    _cache = null;
    _ensureOwner = null;
    _additionalOwned = null;
    _request = null;
    _rejection = null;
    _reference = null;
    _geometry = null;
    _result = null;
  }
}
