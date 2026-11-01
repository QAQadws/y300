import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../pagination/forum_body_text_page_content.dart';
import '../paragraph/forum_body_text_request.dart';
import 'forum_body_inline_plan_input.dart';
import 'forum_body_ruby_atom_plan.dart';
import 'forum_body_ruby_atom_request.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_group_preparation.dart';
import 'forum_body_ruby_segment_metrics_preparation.dart';
import 'forum_body_ruby_soft_space_layout.dart';
import 'forum_body_ruby_row_alignment.dart';
import 'forum_body_text_band_content.dart';
import 'forum_body_text_band_layout.dart';
import 'forum_body_ruby_container_background.dart';
import 'forum_body_ruby_root_box.dart';
import '../paragraph/forum_body_paragraph_content.dart';

enum _State { active, ready, transferred, closed }

/// The session's one pending mixed format, using its cache/guard/scheduler.
/// Child glyph metrics and the parent shape occur in distinct bounded units;
/// published input is pure and only the actual parent lease enters composer.
final class ForumBodyInlinePlanPreparation {
  ForumBodyInlinePlanPreparation({
    required ForumBodyInlinePlanInput input,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
  }) : _input = input,
       _cache = cache,
       _textScaler = textScaler,
       _ensureOwner = ensureOwner,
       width = input.width;

  ForumBodyInlinePlanInput? _input;
  ForumBodyParagraphCache? _cache;
  TextScaler? _textScaler;
  void Function()? _ensureOwner;
  final double width;
  final _metrics = <ForumBodyRubyAtomMetrics>[];
  final _backgroundFonts =
      <ForumBodyRubyContainerBackground, ForumBodyRubyContainerFontBox>{};
  final _rootFonts = <ForumBodyRubyRootBoxInput, ForumBodyRubyRootFontBox>{};
  ForumBodyRubyRowAlignment? _alignment;
  final _retriedBands = Set<ForumBodyTextBandContent>.identity();
  ForumBodyRubyGroupPreparation? _pair;
  ForumBodyRubySegmentMetricsPreparation? _segment;
  ForumBodyRubySoftSpacePreparation? _space;
  ForumBodyInlineParagraphLease? _parent;
  ForumBodyInlineParagraphLease? _probe;
  Set<int> _finalTrimmedAtoms = const {};
  ForumBodyInlinePageContent? _result;
  var _state = _State.active;
  var _operating = false;
  bool get isReady => _state == _State.ready;

  ({int partsPrepared, bool isReady, bool waitingForLayoutBudget}) advance({
    int maxParts = 32,
  }) {
    if (_state != _State.active) throw StateError('Inline plan is not active');
    if (maxParts <= 0) throw ArgumentError.value(maxParts, 'maxParts');
    return _operate(() {
      _guard();
      final cache = _cache!;
      final before = cache.layoutBuildCount;
      var parts = 0;
      var waiting = false;
      while (_metrics.length < _input!.atoms.length && parts < maxParts) {
        final request = _input!.atoms[_metrics.length];
        final root = request.rootBox;
        if (root != null && !_rootFonts.containsKey(root)) {
          final step = _prepareFont(root.fontStrut, (height, baseline) {
            _rootFonts[root] = ForumBodyRubyRootFontBox(
              input: root,
              height: height,
              alphabeticBaseline: baseline,
            );
          });
          parts += step.partsPrepared;
          waiting = step.waitingForLayoutBudget;
          if (waiting ||
              cache.layoutBuildCount != before ||
              parts == maxParts) {
            break;
          }
          continue;
        }
        final background = request.background;
        if (background != null && !_backgroundFonts.containsKey(background)) {
          final step = _prepareFont(background.fontStrut, (height, baseline) {
            _backgroundFonts[background] = ForumBodyRubyContainerFontBox(
              background: background,
              height: height,
              alphabeticBaseline: baseline,
            );
          });
          parts += step.partsPrepared;
          waiting = step.waitingForLayoutBudget;
          if (waiting ||
              cache.layoutBuildCount != before ||
              parts == maxParts) {
            break;
          }
          continue;
        }
        try {
          final revisionBefore = cache.budgetRevision;
          final step = _advanceMetric(request, maxParts - parts);
          final budgetChanged = cache.budgetRevision != revisionBefore;
          parts += step.formatUnitsPrepared;
          if (step.formatUnitsPrepared == 0 &&
              (step.madeProgress || budgetChanged)) {
            parts++;
          }
          waiting = step.waitingForLayoutBudget;
          if (!step.madeProgress) {
            if (!waiting && !budgetChanged) {
              throw StateError('Inline metric preparation made no progress');
            }
            break;
          }
          if (waiting || cache.layoutBuildCount != before) break;
        } on ForumBodyTextBandLayoutException catch (error) {
          _guard();
          // Native child counts omit empty ranks, just like admission. Numeric
          // finalization cannot throw a native band isolation exception.
          final count = _pair?.preparedPartCount;
          final failed =
              _space?.failedRequest ??
              _segment?.failedRequest ??
              (count != null && count < request.nativeRequests.length
                  ? request.nativeRequests[count]
                  : null);
          if (failed is! ForumBodyTextBandChildRequest) rethrow;
          _closeMetric();
          final hint = error.requiredGutter;
          final retry =
              error.failure == ForumBodyTextBandLayoutFailure.isolation &&
              hint != null &&
              hint.isFinite &&
              hint > 0 &&
              hint <= 16384 &&
              _retriedBands.add(failed.band);
          _input!.replaceBand(
            failed.band,
            // Keep one logical pixel beyond the measured minimum so native
            // float rounding cannot repeatedly miss the isolation boundary.
            retry ? (hint + 1).clamp(1.0, 16384.0) : null,
          );
          // A failed native band never triggers another shape in this unit.
          parts++;
          break;
        }
      }
      if (_metrics.length == _input!.atoms.length &&
          parts < maxParts &&
          cache.layoutBuildCount == before) {
        final step = _advanceLayout(maxParts: maxParts - parts);
        parts += step.partsPrepared;
        waiting = step.waitingForLayoutBudget;
      }
      return (
        partsPrepared: parts,
        isReady: isReady,
        waitingForLayoutBudget: waiting,
      );
    });
  }

  ForumBodyRubyGroupPreparationStep _advanceMetric(
    ForumBodyRubyAtomRequest request,
    int maxParts,
  ) {
    switch (request) {
      case ForumBodyRubyColumnAtomRequest(:final value):
        final pair = _pair ??= ForumBodyRubyGroupPreparation.forLayerMetrics(
          cache: _cache!,
          base: value.base,
          annotations: value.annotations,
          ensureOwner: _guard,
          textScaler: _textScaler!,
          maxWidth: value.maxWidth,
        );
        final step = pair.advance(maxParts: maxParts);
        if (step.isReady) {
          _metrics.add(ForumBodyRubyAtomMetrics.column(pair.takeMetrics()));
          _closeMetric();
        }
        return step;
      case ForumBodyRubySegmentAtomRequest(:final value):
        final segment = _segment ??= ForumBodyRubySegmentMetricsPreparation(
          cache: _cache!,
          request: value,
          ensureOwner: _guard,
          textScaler: _textScaler!,
        );
        final step = segment.advance(maxParts: maxParts);
        if (step.isReady) {
          _metrics.add(ForumBodyRubyAtomMetrics.segment(segment.takeMetrics()));
          _closeMetric();
        }
        return step;
      case ForumBodyRubySoftSpaceAtomRequest(:final value):
        final space = _space ??= ForumBodyRubySoftSpacePreparation.forMetrics(
          cache: _cache!,
          request: value,
          ensureOwner: _guard,
          textScaler: _textScaler!,
        );
        final step = space.advance(maxParts: maxParts);
        if (step.isReady) {
          _metrics.add(ForumBodyRubyAtomMetrics.softSpace(space.takeMetrics()));
          _closeMetric();
        }
        return step;
    }
  }

  ({int partsPrepared, bool waitingForLayoutBudget}) _prepareFont(
    ForumBodyParagraphContent font,
    void Function(double height, double baseline) capture,
  ) {
    final cache = _cache!;
    final rejectedAt = cache.budgetRevision;
    ForumBodyParagraphLease? lease;
    try {
      // Use the same admission and single-shape quantum as glyph metrics.
      // This auxiliary strut is never issued as visible/source text.
      lease = cache.acquire(
        content: font,
        width: width,
        textScaler: _textScaler!,
      );
      _guard();
      capture(lease.layout.height, lease.layout.alphabeticBaseline);
      return (partsPrepared: 1, waitingForLayoutBudget: false);
    } on ForumBodyParagraphBudgetException catch (error) {
      _guard();
      if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
      final waiting = cache.budgetRevision == rejectedAt;
      return (partsPrepared: waiting ? 0 : 1, waitingForLayoutBudget: waiting);
    } finally {
      lease?.release();
    }
  }

  void _closeMetric() {
    _pair?.close();
    _pair = null;
    _segment?.close();
    _segment = null;
    _space?.close();
    _space = null;
  }

  ({int partsPrepared, bool waitingForLayoutBudget}) _advanceLayout({
    required int maxParts,
  }) {
    final alignment = _alignment ??= ForumBodyRubyRowAlignment.atoms(
      atoms: _metrics,
      levelIds: _input!.rubyLevelIds,
      atomOffsets: _input!.atomEngineOffsets,
      rootFonts: [
        for (final request in _input!.atoms) _rootFonts[request.rootBox],
      ],
    );
    var parts = 0;
    if (!alignment.isComplete && !alignment.needsRows) {
      parts += alignment.advance(maxParts: maxParts);
      _guard();
      if (parts == maxParts) {
        return (partsPrepared: parts, waitingForLayoutBudget: false);
      }
    }
    if (alignment.needsRows) {
      final step = _acquireParent(alignment, provisional: true);
      return (
        partsPrepared: parts + step.partsPrepared,
        waitingForLayoutBudget: step.waitingForLayoutBudget,
      );
    }
    if (!alignment.isComplete) {
      return (partsPrepared: parts, waitingForLayoutBudget: false);
    }
    if (!alignment.requiresFinalParent) {
      if (_probe != null) {
        _parent = _probe;
        _probe = null;
        _makeReady(alignment);
        return (partsPrepared: parts + 1, waitingForLayoutBudget: false);
      }
      final step = _acquireParent(alignment, provisional: false);
      return (
        partsPrepared: parts + step.partsPrepared,
        waitingForLayoutBudget: step.waitingForLayoutBudget,
      );
    }
    if (_probe != null) {
      // Only the last alias evicts this unneeded provisional shape. Release
      // before the final acquisition so it cannot displace a warm glyph band.
      _probe!.releaseProvisional();
      _probe = null;
      _guard();
      return (partsPrepared: parts + 1, waitingForLayoutBudget: false);
    }
    if (_parent == null) {
      final step = _acquireParent(alignment, provisional: false);
      return (
        partsPrepared: parts + step.partsPrepared,
        waitingForLayoutBudget: step.waitingForLayoutBudget,
      );
    }
    parts += alignment.verifyRows(
      _parent!.layout.lines,
      maxParts: maxParts - parts,
      trimmedAtomIndices: _finalTrimmedAtoms,
    );
    _guard();
    if (alignment.isVerified) _makeReady(alignment);
    return (partsPrepared: parts, waitingForLayoutBudget: false);
  }

  ({int partsPrepared, bool waitingForLayoutBudget}) _acquireParent(
    ForumBodyRubyRowAlignment alignment, {
    required bool provisional,
  }) {
    final cache = _cache!;
    final rejectedAt = cache.budgetRevision;
    ForumBodyInlineParagraphLease? parent;
    void release() {
      if (identical(_parent, parent)) {
        _parent = null;
        _finalTrimmedAtoms = const {};
      }
      if (identical(_probe, parent)) _probe = null;
      if (provisional) {
        parent?.releaseProvisional();
      } else {
        parent?.release();
      }
    }

    try {
      parent = cache.acquireInline(
        content: _input!.content,
        width: width,
        dimensions: provisional
            ? alignment.provisionalDimensions
            : alignment.dimensions,
        textScaler: _textScaler!,
      );
      _guard();
      if (provisional) {
        _probe = parent;
        alignment.attachRows(
          parent.layout.lines,
          trimmedAtomIndices: alignment.hasSoftSpaces
              ? parent.layout.trimmedAtomIndices.toSet()
              : const {},
        );
      } else {
        _parent = parent;
        _finalTrimmedAtoms = alignment.hasSoftSpaces
            ? parent.layout.trimmedAtomIndices.toSet()
            : const {};
        if (!alignment.requiresFinalParent) _makeReady(alignment);
      }
      return (partsPrepared: 1, waitingForLayoutBudget: false);
    } on ForumBodyParagraphBudgetException catch (error) {
      release();
      _guard();
      if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
      final waiting = cache.budgetRevision == rejectedAt;
      return (partsPrepared: waiting ? 0 : 1, waitingForLayoutBudget: waiting);
    } catch (_) {
      release();
      rethrow;
    }
  }

  void _makeReady(ForumBodyRubyRowAlignment alignment) {
    _guard();
    _result = ForumBodyInlinePageContent.atoms(
      content: _input!.content,
      dimensions: alignment.dimensions,
      rootFonts: {
        for (final (index, request) in _input!.atoms.indexed)
          if (request.rootBox case final root?) index: _rootFonts[root]!,
      },
      trimmedAtomIndices: _finalTrimmedAtoms,
      containerBackgrounds: {
        for (final (index, request) in _input!.atoms.indexed)
          if (request.background case final background?)
            index: _backgroundFonts[background]!,
      },
      rubyAtoms: [
        for (final (index, request) in _input!.atoms.indexed)
          switch ((request, alignment.results[index])) {
            (
              ForumBodyRubyColumnAtomRequest(:final value),
              ForumBodyRubyColumnMetrics(),
            ) =>
              ForumBodyRubyAtomPlan.column(
                request: value,
                level: alignment.targets[index],
              ),
            (
              ForumBodyRubySegmentAtomRequest(:final value),
              ForumBodyRubyComponentMetrics(value: final metrics),
            ) =>
              ForumBodyRubyAtomPlan.segment(request: value, metrics: metrics),
            (
              ForumBodyRubySoftSpaceAtomRequest(:final value),
              ForumBodyRubySpaceMetrics(value: final metrics),
            ) =>
              ForumBodyRubyAtomPlan.softSpace(request: value, metrics: metrics),
            _ => throw StateError('Inline numeric/request atom kinds differ'),
          },
      ],
    );
    _guard();
    _state = _State.ready;
  }

  ({ForumBodyInlinePageContent content, ForumBodyInlineParagraphLease lease})
  take() {
    if (!isReady) throw StateError('Inline plan is not ready');
    return _operate(() {
      _guard();
      final result = (content: _result!, lease: _parent!);
      _parent = null;
      _state = _State.transferred;
      _drop();
      return result;
    });
  }

  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Inline plan operation is reentrant');
    _operating = true;
    try {
      return action();
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_state != _State.active && !isReady) {
      throw StateError('Inline plan is retired');
    }
    _ensureOwner!();
    if ((_state != _State.active && !isReady) ||
        _cache!.isClosed ||
        (_probe != null && !_cache!.ownsLease(_probe!)) ||
        (_parent != null && !_cache!.ownsLease(_parent!))) {
      throw StateError('Inline plan owner is retired');
    }
  }

  void _drop() {
    _closeMetric();
    _parent?.release();
    _parent = null;
    _finalTrimmedAtoms = const {};
    _probe?.releaseProvisional();
    _probe = null;
    _input = null;
    _result = null;
    _metrics.clear();
    _backgroundFonts.clear();
    _rootFonts.clear();
    _alignment = null;
    _retriedBands.clear();
    _cache = null;
    _textScaler = null;
    _ensureOwner = null;
  }

  void close() {
    if (_state != _State.active && !isReady) return;
    _state = _State.closed;
    _drop();
  }
}
