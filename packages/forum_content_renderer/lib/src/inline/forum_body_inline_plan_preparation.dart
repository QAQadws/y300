import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../pagination/forum_body_text_page_content.dart';
import '../paragraph/forum_body_text_request.dart';
import 'forum_body_inline_plan_input.dart';
import 'forum_body_inline_span_content.dart';
import 'forum_body_inline_paragraph_request.dart';
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
import '../flow/forum_body_inline_flow_content.dart';
import 'forum_body_inline_source_preparation.dart';
import 'forum_body_ruby_tree_metrics_preparation.dart';
import 'forum_body_ruby_tree_input.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_ruby_tree_emphasis_format_preparation.dart';

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
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _input = input,
       _cache = cache,
       _textScaler = textScaler,
       _ensureOwner = ensureOwner,
       _additionalOwned = additionalOwnedLeases,
       width = input.width;

  /// Measures the explicitly derived glyph parent and complete original child
  /// formats. Transfer remains separate from an ordinary readable inline plan;
  /// parent markers and final physical-row allocation are still required.
  ForumBodyInlinePlanPreparation.emphasisParent({
    required ForumBodyInlinePlanInput input,
    required ForumBodyInlineEmphasisGlyphInput glyphInput,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _input = input,
       _parentGlyphs = glyphInput,
       _cache = cache,
       _textScaler = textScaler,
       _ensureOwner = ensureOwner,
       _additionalOwned = additionalOwnedLeases,
       width = input.width {
    if (!identical(input.content, glyphInput.original)) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        input.content.path,
      );
    }
  }

  ForumBodyInlinePlanPreparation.fromFlow({
    required ForumBodyInlineFlowContent input,
    required this.width,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    void Function(ForumBodyInlinePlanInput)? validateInput,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _cache = cache,
       _textScaler = textScaler,
       _ensureOwner = ensureOwner,
       _additionalOwned = additionalOwnedLeases,
       _validateInput = validateInput {
    _source = ForumBodyInlineSourcePreparation(
      input: input,
      width: width,
      ensureOwner: _guard,
    );
  }

  ForumBodyInlinePlanInput? _input;
  ForumBodyInlineEmphasisGlyphInput? _parentGlyphs;
  ForumBodyInlineSourcePreparation? _source;
  void Function(ForumBodyInlinePlanInput)? _validateInput;
  ForumBodyParagraphCache? _cache;
  TextScaler? _textScaler;
  void Function()? _ensureOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
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
  ForumBodyRubyTreeMetricsPreparation? _tree;
  ForumBodyRubyGlyphTreeMetricsPreparation? _glyph;
  ForumBodyRubyGlyphTreeMetrics? _glyphCurrent, _alignedGlyph;
  ForumBodyRubyTreeEmphasisFormatPreparation? _format, _reformat;
  final _glyphSnapshots = <int, ForumBodyRubyGlyphTreeMetrics>{};
  final _emphasisFormats = <int, ForumBodyRubyTreeEmphasisPlan>{};
  final _atomPlans = <ForumBodyRubyAtomPlan>[];
  final _dimensions = <PlaceholderDimensions>[];
  final _treeSnapshots = <int, ForumBodyRubyTreeMetrics>{};
  ForumBodyInlineParagraphLease? _parent;
  ForumBodyInlineParagraphLease? _probe;
  Set<int> _finalTrimmedAtoms = const {};
  ForumBodyInlinePageContent? _result;
  var _state = _State.active;
  var _operating = false;
  bool get isReady => _state == _State.ready;
  bool _cacheMiss = false;
  int _blockedRevision = -1;
  bool get cacheMiss => _cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_parent,
    ?_probe,
    if (_pair != null) ..._pair!.nativeLeases,
    if (_segment != null) ..._segment!.nativeLeases,
    if (_space != null) ..._space!.nativeLeases,
    if (_tree != null) ..._tree!.nativeLeases,
    if (_glyph != null) ..._glyph!.nativeLeases,
    if (_format != null) ..._format!.nativeLeases,
    if (_reformat != null) ..._reformat!.nativeLeases,
  ];

  ({int partsPrepared, bool isReady, bool waitingForLayoutBudget}) advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (_state != _State.active) throw StateError('Inline plan is not active');
    if (maxParts <= 0) throw ArgumentError.value(maxParts, 'maxParts');
    return _operate(() {
      _guard();
      _cacheMiss = false;
      final cache = _cache!;
      if (_blockedRevision == cache.budgetRevision) {
        return (partsPrepared: 0, isReady: false, waitingForLayoutBudget: true);
      }
      final revisionAtStart = cache.budgetRevision;
      _blockedRevision = -1;
      final before = cache.layoutBuildCount;
      var parts = 0;
      var waiting = false;
      if (_input == null) {
        final source = _source!;
        parts += source.advance(maxParts: maxParts);
        _guard();
        if (!source.isReady) {
          return (
            partsPrepared: parts,
            isReady: false,
            waitingForLayoutBudget: false,
          );
        }
        final input = source.takeInput();
        _source = null;
        _validateInput?.call(input);
        _guard();
        _validateInput = null;
        _input = input;
      }
      while (_metrics.length < _input!.atoms.length && parts < maxParts) {
        final request = _input!.atoms[_metrics.length];
        final root = request.rootBox;
        if (request is! ForumBodyRubyTreeAtomRequest &&
            request is! ForumBodyRubyTreeEmphasisAtomRequest &&
            root != null &&
            !_rootFonts.containsKey(root)) {
          final step = _prepareFont(root.fontStrut, (height, baseline) {
            _rootFonts[root] = ForumBodyRubyRootFontBox(
              input: root,
              height: height,
              alphabeticBaseline: baseline,
            );
          }, cachedOnly: cachedOnly);
          parts += step.partsPrepared;
          waiting = step.waitingForLayoutBudget;
          if (waiting ||
              _cacheMiss ||
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
          }, cachedOnly: cachedOnly);
          parts += step.partsPrepared;
          waiting = step.waitingForLayoutBudget;
          if (waiting ||
              _cacheMiss ||
              cache.layoutBuildCount != before ||
              parts == maxParts) {
            break;
          }
          continue;
        }
        try {
          final revisionBefore = cache.budgetRevision;
          final step = _advanceMetric(request, maxParts - parts, cachedOnly);
          final budgetChanged = cache.budgetRevision != revisionBefore;
          parts += step.formatUnitsPrepared;
          if (step.formatUnitsPrepared == 0 &&
              (step.madeProgress || budgetChanged)) {
            parts++;
          }
          waiting = step.waitingForLayoutBudget;
          if (!step.madeProgress) {
            if (!waiting && !_cacheMiss && !budgetChanged) {
              throw StateError('Inline metric preparation made no progress');
            }
            break;
          }
          if (waiting || _cacheMiss || cache.layoutBuildCount != before) break;
        } on ForumBodyTextBandLayoutException catch (error) {
          _guard();
          // Native child counts omit empty ranks, just like admission. Numeric
          // finalization cannot throw a native band isolation exception.
          final count = _pair?.preparedPartCount;
          final failed =
              _glyph?.failedRequest ??
              _format?.failedRequest ??
              _tree?.failedRequest ??
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
          if (_input!.hasEmphasisTrees) {
            // Shared glyph bands may include already measured earlier atoms.
            // Their complete format keys/positions cannot survive remapping.
            _metrics.clear();
            _treeSnapshots.clear();
            _glyphSnapshots.clear();
            _emphasisFormats.clear();
          }
          // A failed native band never triggers another shape in this unit.
          parts++;
          break;
        }
      }
      if (_metrics.length == _input!.atoms.length &&
          parts < maxParts &&
          cache.layoutBuildCount == before) {
        final step = _advanceLayout(
          maxParts: maxParts - parts,
          cachedOnly: cachedOnly,
        );
        parts += step.partsPrepared;
        waiting = step.waitingForLayoutBudget;
      }
      if (waiting && cache.budgetRevision == revisionAtStart) {
        _blockedRevision = revisionAtStart;
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
    bool cachedOnly,
  ) {
    switch (request) {
      case ForumBodyRubyTreeEmphasisAtomRequest(:final value):
        if (_glyphCurrent == null) {
          final job = _glyph ??= ForumBodyRubyGlyphTreeMetricsPreparation(
            input: value,
            cache: _cache!,
            ensureOwner: _guard,
            textScaler: _textScaler!,
            additionalOwnedLeases: _ownedPrefix,
          );
          final step = job.advance(maxParts: maxParts, cachedOnly: cachedOnly);
          _cacheMiss = job.cacheMiss;
          if (job.isReady) {
            final metrics = job.takeMetrics();
            _guard();
            _glyphCurrent = metrics;
            _glyph = null;
            job.close();
            _rootFonts[value.sourceTree.rootGroup.font] =
                ForumBodyRubyRootFontBox(
                  input: value.sourceTree.rootGroup.font,
                  height: metrics.root.font.height,
                  alphabeticBaseline: metrics.root.font.alphabeticBaseline,
                );
          }
          return step;
        }
        final job = _format ??= ForumBodyRubyTreeEmphasisFormatPreparation(
          glyphMetrics: _glyphCurrent!,
          cache: _cache!,
          ensureOwner: _guard,
          expectedTextScaler: _textScaler!,
          additionalOwnedLeases: _ownedPrefix,
        );
        final step = job.advance(maxParts: maxParts, cachedOnly: cachedOnly);
        _cacheMiss = job.cacheMiss;
        if (job.isReady) {
          final plan = job.takePlan();
          _guard();
          _glyphSnapshots[_metrics.length] = _glyphCurrent!;
          _emphasisFormats[_metrics.length] = plan;
          _metrics.add(_glyphCurrent!.rootAtom);
          _closeMetric();
        }
        return step;
      case ForumBodyRubyTreeAtomRequest(:final value):
        final tree = _tree ??= ForumBodyRubyTreeMetricsPreparation(
          input: value,
          cache: _cache!,
          ensureOwner: _guard,
          textScaler: _textScaler!,
          additionalOwnedLeases: _ownedPrefix,
        );
        final step = tree.advance(maxParts: maxParts, cachedOnly: cachedOnly);
        _cacheMiss = tree.cacheMiss;
        if (step.isReady) {
          final metrics = tree.takeMetrics();
          _treeSnapshots[_metrics.length] = metrics;
          _rootFonts[value.rootGroup.font] = metrics.root.font;
          _metrics.add(metrics.rootAtom);
          _closeMetric();
        }
        return step;
      case ForumBodyRubyColumnAtomRequest(:final value):
        final pair = _pair ??= ForumBodyRubyGroupPreparation.forLayerMetrics(
          cache: _cache!,
          base: value.base,
          annotations: value.annotations,
          ensureOwner: _guard,
          textScaler: _textScaler!,
          maxWidth: value.maxWidth,
          additionalOwnedLeases: _ownedPrefix,
        );
        final step = pair.advance(maxParts: maxParts, cachedOnly: cachedOnly);
        _cacheMiss = pair.cacheMiss;
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
          additionalOwnedLeases: _ownedPrefix,
        );
        final step = segment.advance(
          maxParts: maxParts,
          cachedOnly: cachedOnly,
        );
        _cacheMiss = segment.cacheMiss;
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
          additionalOwnedLeases: _ownedPrefix,
        );
        final step = space.advance(maxParts: maxParts, cachedOnly: cachedOnly);
        _cacheMiss = space.cacheMiss;
        if (step.isReady) {
          _metrics.add(ForumBodyRubyAtomMetrics.softSpace(space.takeMetrics()));
          _closeMetric();
        }
        return step;
    }
  }

  ({int partsPrepared, bool waitingForLayoutBudget}) _prepareFont(
    ForumBodyParagraphContent font,
    void Function(double height, double baseline) capture, {
    required bool cachedOnly,
  }) {
    final cache = _cache!;
    final rejectedAt = cache.budgetRevision;
    ForumBodyParagraphLease? lease;
    try {
      // Use the same admission and single-shape quantum as glyph metrics.
      // This auxiliary strut is never issued as visible/source text.
      lease = cachedOnly
          ? cache.tryAcquireCached(
              content: font,
              width: width,
              textScaler: _textScaler!,
            )
          : cache.acquire(
              content: font,
              width: width,
              textScaler: _textScaler!,
            );
      _guard();
      if (lease == null) {
        _cacheMiss = true;
        return (partsPrepared: 1, waitingForLayoutBudget: false);
      }
      capture(lease.layout.height, lease.layout.alphabeticBaseline);
      return (partsPrepared: 1, waitingForLayoutBudget: false);
    } on ForumBodyParagraphBudgetException catch (error) {
      _guard();
      if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
      final waiting = _classifyPinned(error, rejectedAt);
      return (partsPrepared: waiting ? 0 : 1, waitingForLayoutBudget: waiting);
    } finally {
      lease?.release();
    }
  }

  // Initial metric workers have no parent pins yet. Preserve their existing
  // fast path when neither the caller nor this plan owns an enclosing prefix.
  Iterable<ForumBodyNativeParagraphLease> Function()? get _ownedPrefix =>
      _additionalOwned == null && _parent == null && _probe == null
      ? null
      : _otherOwned;

  bool _classifyPinned(
    ForumBodyParagraphBudgetException error,
    int rejectedAt,
  ) {
    final external = _cache!.isBlockedByExternalPins(error, _otherOwned());
    _guard();
    // Prefix callbacks may release a pin. That rejection describes the older
    // budget, so retry on the next quantum before declaring content pressure.
    if (_cache!.budgetRevision != rejectedAt) return false;
    if (!external) {
      throw ForumBodyParagraphBudgetException(
        ForumBodyParagraphBudgetFailure.content,
        requiredEstimatedBytes: error.requiredEstimatedBytes,
        requiredAdditionalEntries: error.requiredAdditionalEntries,
      );
    }
    return _cache!.budgetRevision == rejectedAt;
  }

  /// A nested worker already accounts for its own pins. Supply this parent's
  /// other live handles and the caller's bounded prefix, without taking aliases
  /// or releasing any borrowed resource. Classification uses actual cache keys.
  Iterable<ForumBodyNativeParagraphLease> _otherOwned() sync* {
    _guard();
    var count = 0;
    for (final lease in [?_parent, ?_probe]) {
      _guard();
      yield lease;
      count++;
    }
    final values =
        _additionalOwned?.call() ?? const <ForumBodyNativeParagraphLease>[];
    _guard();
    final iterator = values.iterator;
    _guard();
    while (true) {
      final more = iterator.moveNext();
      _guard();
      if (!more) break;
      if (count++ >= 32768) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.inputLimit,
          _input!.content.path,
        );
      }
      final lease = iterator.current;
      _guard();
      if (!_cache!.ownsLease(lease)) {
        throw StateError('Inline budget prefix is retired or foreign');
      }
      yield lease;
      _guard();
    }
  }

  void _closeMetric() {
    _glyph?.close();
    _glyph = null;
    _glyphCurrent = null;
    _format?.close();
    _format = null;
    _tree?.close();
    _tree = null;
    _pair?.close();
    _pair = null;
    _segment?.close();
    _segment = null;
    _space?.close();
    _space = null;
  }

  ({int partsPrepared, bool waitingForLayoutBudget}) _advanceLayout({
    required int maxParts,
    required bool cachedOnly,
  }) {
    final alignment = _alignment ??= ForumBodyRubyRowAlignment.atoms(
      atoms: _metrics,
      levelIds: _input!.rubyLevelIds,
      atomOffsets: _input!.atomEngineOffsets,
      rootFonts: [
        for (final request in _input!.atoms) _rootFonts[request.rootBox],
      ],
      discoveryDimensions: [
        for (var index = 0; index < _input!.atoms.length; index++)
          _emphasisFormats[index]?.frame.dimensions,
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
      final step = _acquireParent(
        alignment,
        provisional: true,
        cachedOnly: cachedOnly,
      );
      return (
        partsPrepared: parts + step.partsPrepared,
        waitingForLayoutBudget: step.waitingForLayoutBudget,
      );
    }
    if (!alignment.isComplete) {
      return (partsPrepared: parts, waitingForLayoutBudget: false);
    }
    if (alignment.requiresFinalParent && _probe != null) {
      _probe!.releaseProvisional();
      _probe = null;
      _guard();
      return (partsPrepared: parts + 1, waitingForLayoutBudget: false);
    }
    if (_atomPlans.length < _input!.atoms.length) {
      final step = _advancePlans(
        alignment,
        maxParts: maxParts - parts,
        cachedOnly: cachedOnly,
      );
      parts += step.partsPrepared;
      if (_atomPlans.length < _input!.atoms.length ||
          step.waitingForLayoutBudget ||
          _cacheMiss ||
          parts == maxParts ||
          step.nativeBuilt) {
        return (
          partsPrepared: parts,
          waitingForLayoutBudget: step.waitingForLayoutBudget,
        );
      }
    }
    if (!alignment.requiresFinalParent) {
      if (_probe != null) {
        _parent = _probe;
        _probe = null;
        _makeReady();
        return (partsPrepared: parts + 1, waitingForLayoutBudget: false);
      }
      final step = _acquireParent(
        alignment,
        provisional: false,
        cachedOnly: cachedOnly,
      );
      return (
        partsPrepared: parts + step.partsPrepared,
        waitingForLayoutBudget: step.waitingForLayoutBudget,
      );
    }
    if (_parent == null) {
      final step = _acquireParent(
        alignment,
        provisional: false,
        cachedOnly: cachedOnly,
      );
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
    if (alignment.isVerified) _makeReady();
    return (partsPrepared: parts, waitingForLayoutBudget: false);
  }

  ({int partsPrepared, bool waitingForLayoutBudget}) _acquireParent(
    ForumBodyRubyRowAlignment alignment, {
    required bool provisional,
    required bool cachedOnly,
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
      final request = ForumBodyInlineParagraphRequest(
        content: _parentGlyphs?.glyphs ?? _input!.content,
        dimensions: provisional ? alignment.provisionalDimensions : _dimensions,
        layoutMode: _input!.layoutMode,
      );
      parent = request.acquire(
        cache,
        width: width,
        textScaler: _textScaler!,
        cachedOnly: cachedOnly,
      );
      _guard();
      if (parent == null) {
        _cacheMiss = true;
        return (partsPrepared: 1, waitingForLayoutBudget: false);
      }
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
        if (!alignment.requiresFinalParent) _makeReady();
      }
      return (partsPrepared: 1, waitingForLayoutBudget: false);
    } on ForumBodyParagraphBudgetException catch (error) {
      release();
      _guard();
      if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
      final waiting = _classifyPinned(error, rejectedAt);
      return (partsPrepared: waiting ? 0 : 1, waitingForLayoutBudget: waiting);
    } catch (_) {
      release();
      rethrow;
    }
  }

  void _makeReady() {
    _guard();
    _result = ForumBodyInlinePageContent.atoms(
      content: _input!.content,
      layoutMode: _input!.layoutMode,
      dimensions: _dimensions,
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
      rubyAtoms: _atomPlans,
    );
    _guard();
    _state = _State.ready;
  }

  ({int partsPrepared, bool waitingForLayoutBudget, bool nativeBuilt})
  _advancePlans(
    ForumBodyRubyRowAlignment alignment, {
    required int maxParts,
    required bool cachedOnly,
  }) {
    var parts = 0, waiting = false;
    final cache = _cache!, before = cache.layoutBuildCount;
    while (_atomPlans.length < _input!.atoms.length && parts < maxParts) {
      final index = _atomPlans.length, request = _input!.atoms[index];
      if (request is ForumBodyRubyTreeEmphasisAtomRequest) {
        if (_alignedGlyph == null) {
          final previous = _glyphSnapshots[index]!;
          final current = previous.withAlignedRoot(alignment.results[index]);
          if (identical(previous, current)) {
            _appendEmphasis(request, _emphasisFormats[index]!);
          } else {
            _alignedGlyph = current;
            _reformat = ForumBodyRubyTreeEmphasisFormatPreparation(
              glyphMetrics: current,
              cache: cache,
              ensureOwner: _guard,
              expectedTextScaler: _textScaler!,
              additionalOwnedLeases: _ownedPrefix,
            );
          }
          parts++;
        } else {
          final job = _reformat!,
              step = job.advance(
                maxParts: maxParts - parts,
                cachedOnly: cachedOnly,
              );
          parts += step.formatUnitsPrepared;
          _cacheMiss = job.cacheMiss;
          waiting = step.waitingForLayoutBudget;
          _guard();
          if (job.isReady) {
            final plan = job.takePlan();
            _guard();
            _appendEmphasis(request, plan);
            _reformat = null;
            _alignedGlyph = null;
            job.close();
          }
          if (step.formatUnitsPrepared == 0 ||
              waiting ||
              _cacheMiss ||
              cache.layoutBuildCount != before) {
            break;
          }
        }
      } else {
        _atomPlans.add(switch ((request, alignment.results[index])) {
          (
            ForumBodyRubyTreeAtomRequest(:final value),
            ForumBodyRubyComponentMetrics(value: final metrics),
          ) =>
            ForumBodyRubyAtomPlan.tree(
              request: value,
              metrics: _treeSnapshots[index]!
                  .rebindInput(value)
                  .withRootSegment(metrics),
            ),
          (
            ForumBodyRubyTreeAtomRequest(:final value),
            ForumBodyRubyColumnMetrics(value: final metrics),
          ) =>
            ForumBodyRubyAtomPlan.tree(
              request: value,
              metrics: _treeSnapshots[index]!
                  .rebindInput(value)
                  .withRootGroup(metrics),
            ),
          (
            ForumBodyRubyColumnAtomRequest(:final value),
            ForumBodyRubyColumnMetrics(value: final metrics),
          ) =>
            ForumBodyRubyAtomPlan.column(
              request: value,
              level: alignment.targets[index],
              metrics: metrics,
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
        });
        _dimensions.add(alignment.dimensions[index]);
        parts++;
      }
      _guard();
    }
    return (
      partsPrepared: parts,
      waitingForLayoutBudget: waiting,
      nativeBuilt: cache.layoutBuildCount != before,
    );
  }

  void _appendEmphasis(
    ForumBodyRubyTreeEmphasisAtomRequest request,
    ForumBodyRubyTreeEmphasisPlan plan,
  ) {
    final index = _atomPlans.length, initial = _emphasisFormats[index]!;
    if ((plan.frame.size.width - initial.frame.size.width).abs() >
        ForumBodyRubyGroupMetrics.geometryTolerance) {
      throw const ForumBodyEmphasisLineException(
        ForumBodyEmphasisLineFailure.geometry,
      );
    }
    _atomPlans.add(
      ForumBodyRubyAtomPlan.emphasisTree(request: request.value, format: plan),
    );
    _dimensions.add(
      _rootFonts[request.rootBox]!
          .enclose(
            childSize: plan.frame.size,
            childBaseline: plan.frame.baseline,
          )
          .dimensions,
    );
  }

  ({ForumBodyInlinePageContent content, ForumBodyInlineParagraphLease lease})
  take() {
    if (_parentGlyphs != null) {
      throw StateError('Emphasis parent requires its qualified transfer');
    }
    return _take();
  }

  ({
    ForumBodyInlinePageContent plan,
    ForumBodyInlineEmphasisGlyphInput glyphInput,
    ForumBodyInlineParagraphLease lease,
  })
  takeEmphasisParent() {
    final glyphs = _parentGlyphs;
    if (glyphs == null) throw StateError('No emphasis parent was prepared');
    final value = _take();
    return (plan: value.content, glyphInput: glyphs, lease: value.lease);
  }

  ({ForumBodyInlinePageContent content, ForumBodyInlineParagraphLease lease})
  _take() {
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
    _source?.close();
    _source = null;
    _validateInput = null;
    _treeSnapshots.clear();
    _glyphSnapshots.clear();
    _emphasisFormats.clear();
    _atomPlans.clear();
    _dimensions.clear();
    _reformat?.close();
    _reformat = null;
    _alignedGlyph = null;
    _closeMetric();
    _parent?.release();
    _parent = null;
    _finalTrimmedAtoms = const {};
    _probe?.releaseProvisional();
    _probe = null;
    _input = null;
    _parentGlyphs = null;
    _result = null;
    _metrics.clear();
    _backgroundFonts.clear();
    _rootFonts.clear();
    _alignment = null;
    _retriedBands.clear();
    _cache = null;
    _textScaler = null;
    _ensureOwner = null;
    _additionalOwned = null;
    _blockedRevision = -1;
  }

  void close() {
    if (_state != _State.active && !isReady) return;
    _state = _State.closed;
    _drop();
  }
}
