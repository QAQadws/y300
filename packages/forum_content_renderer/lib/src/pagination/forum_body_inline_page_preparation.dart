import 'dart:collection';

import 'package:flutter/painting.dart';

import '../document/forum_body_document.dart';
import '../inline/forum_body_inline_paragraph_view.dart';
import '../inline/forum_body_inline_paint_command.dart';
import '../inline/forum_body_inline_paragraph_layout.dart';
import '../inline/forum_body_inline_emphasis_row_allocation.dart';
import '../inline/forum_body_ruby_container_background.dart';
import '../inline/forum_body_emphasis_allocation_geometry.dart';
import '../inline/forum_body_ruby_atom_plan.dart';
import '../inline/forum_body_text_baseline_layout.dart';
import '../inline/forum_body_text_baseline_preparation.dart';
import '../inline/forum_body_ruby_group_layout.dart';
import '../inline/forum_body_ruby_group_preparation.dart';
import '../inline/forum_body_ruby_segment_layout.dart';
import '../inline/forum_body_ruby_segment_preparation.dart';
import '../inline/forum_body_ruby_soft_space_layout.dart';
import '../inline/forum_body_paragraph_frame.dart' show ForumBodyFontFrameStep;
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import '../paragraph/forum_body_native_budget_input.dart';
import 'forum_body_source_hint.dart';
import 'forum_body_text_page_binding.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_text_page_content.dart';

part 'forum_body_inline_emphasis_child_preparation.dart';

/// The standard page and a qualified current-source child transaction consume
/// the same numeric window. No manufactured public page/coverage is published.
final class _InlinePreparationWindow {
  _InlinePreparationWindow.page(ForumBodyTextPageFragment f)
    : path = f.path,
      fontRevision = f.fontRevision,
      styleRevision = f.styleRevision,
      startLine = f.startLine,
      endLine = f.endLine,
      coverageStartUtf16 = f.coverageStartUtf16,
      coverageEndUtf16 = f.coverageEndUtf16,
      engineRange = f.engineRange,
      sourceHint = f.sourceHint,
      width = f.width,
      height = f.height;
  _InlinePreparationWindow.current(
    ForumBodyInlineParagraphLease parent,
    ForumBodyInlineParagraphFragment f,
  ) : path = parent.content.path,
      fontRevision = parent.content.fontRevision,
      styleRevision = parent.content.styleRevision,
      startLine = f.startLine,
      endLine = f.endLine,
      coverageStartUtf16 = f.coverageStartUtf16,
      coverageEndUtf16 = f.coverageEndUtf16,
      engineRange = (
        startUtf16: f.engineCoverageStartUtf16,
        endUtf16: f.engineCoverageEndUtf16,
      ),
      sourceHint = forumBodySourceHint(
        parent.content.projection.display,
        f.coverageStartUtf16,
        f.coverageEndUtf16,
      ),
      width = parent.layout.width,
      height = f.height;
  final String? path;
  final String fontRevision;
  final int styleRevision,
      startLine,
      endLine,
      coverageStartUtf16,
      coverageEndUtf16;
  final ({int runeStart, int runeEnd})? sourceHint;
  final ({int startUtf16, int endUtf16})? engineRange;
  final double width, height;
}

/// Format-local resource preparation borrowed by the sole page transaction.
/// One call acquires a parent, advances one pair, or binds the completed view.
/// The page owns rollback, aggregate admission, scheduling and reservations.
final class ForumBodyInlinePagePreparation {
  ForumBodyInlinePagePreparation({
    required ForumBodyInlinePageContent input,
    required ForumBodyTextPageFragment fragment,
    required this.identity,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    void Function()? ensureVisibleOwner,
    required Iterable<ForumBodyNativeParagraphLease> Function() ownedPageLeases,
  }) : _fragment = fragment,
       _window = _InlinePreparationWindow.page(fragment),
       _input = input,
       _cache = cache,
       _textScaler = textScaler,
       _ensureOwner = ensureOwner,
       _ensureVisibleOwner = ensureVisibleOwner ?? ensureOwner,
       _ownedPageLeases = ownedPageLeases;

  // Only the qualified mixed-emphasis child coordinator can enter here. It
  // supplies its own actual natural parent alias and original source derivation.
  ForumBodyInlinePagePreparation._current({
    required ForumBodyInlinePageContent input,
    required ForumBodyInlineParagraphLease parent,
    required ForumBodyInlineParagraphFragment window,
    required this.identity,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    required void Function() ensureVisibleOwner,
    required Iterable<ForumBodyNativeParagraphLease> Function() ownedPageLeases,
  }) : _fragment = null,
       _window = _InlinePreparationWindow.current(parent, window),
       _input = input,
       _cache = cache,
       _textScaler = textScaler,
       _ensureOwner = ensureOwner,
       _ensureVisibleOwner = ensureVisibleOwner,
       _ownedPageLeases = ownedPageLeases,
       _parent = parent {
    try {
      _guard();
      if (!identical(parent.layout, window.layout)) {
        throw const ForumBodyTextPageSurfaceException(
          ForumBodyTextPageSurfaceFailure.identity,
        );
      }
      _validateParent(input, parent);
      _validatingParent = input.content.projection.atoms.isNotEmpty;
    } catch (_) {
      close();
      rethrow;
    }
  }
  ForumBodyInlinePageContent? _input;
  final ForumBodyTextPageFragment? _fragment;
  final _InlinePreparationWindow _window;
  ForumBodyTextPageFragment get fragment =>
      _fragment ??
      (throw StateError(
        'Current-source children have no published page fragment',
      ));
  final ForumBodyIdentity identity;
  ForumBodyParagraphCache? _cache;
  TextScaler? _textScaler;
  void Function()? _ensureOwner, _ensureVisibleOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _ownedPageLeases;
  ForumBodyInlineParagraphLease? _parent;
  List<int> _indices = const [];
  final _groups = <int, ForumBodyRubyGroupLayout>{};
  final _baselines = <int, ForumBodyTextBaselineLayout>{};
  final _inlineBoxes = <int, ForumBodyInlineParagraphView>{};
  ForumBodyInlinePagePreparation? _inlineBox;
  ForumBodyTextBaselinePreparation? _baseline;
  final _segments = <int, ForumBodyRubySegmentLayout>{};
  final _spaces = <int, ForumBodyRubySoftSpaceLayout>{};
  int _nextGroup = 0;
  ForumBodyRubyGroupPreparation? _pair;
  ForumBodyRubySegmentPreparation? _component;
  ForumBodyRubySoftSpacePreparation? _space;
  ForumBodyInlineViewAssembly? _binding;
  bool _validatingParent = false;
  var _parentAtom = 0;
  var _engineStart = 0;
  var _engineEnd = 0;
  List<int> _validatedIndices = [];
  bool _closed = false;
  bool _advancing = false;
  bool _waiting = false;
  bool get waitingForLayoutBudget => _waiting;
  int _workCount = 0;
  int get workCount => _workCount;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_parent,
    for (final group in _groups.values) ...group.nativeLeases,
    for (final text in _baselines.values) text.lease,
    for (final view in _inlineBoxes.values) ...view.nativeLeases,
    if (_inlineBox != null) ..._inlineBox!.nativeLeases,
    if (_baseline != null) ..._baseline!.nativeLeases,
    for (final segment in _segments.values) ...segment.nativeLeases,
    for (final space in _spaces.values) ...space.nativeLeases,
    if (_pair != null) ..._pair!.nativeLeases,
    if (_component != null) ..._component!.nativeLeases,
    if (_space != null) ..._space!.nativeLeases,
    if (_binding != null) ..._binding!.nativeLeases,
  ];

  ({bool cacheMiss, ForumBodyInlineParagraphView? view}) advance({
    required bool cachedOnly,
    int maxParts = 32,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_advancing) throw StateError('Inline preparation is reentrant');
    _advancing = true;
    try {
      _guard();
      _waiting = false;
      final input = _input!;
      final cache = _cache!;
      if (_binding != null) return _advanceBinding(maxParts);
      if (_parent == null) {
        final requestWidth = input.requestWidthFor(fragment);
        final parent = input.parentRequest.acquire(
          cache,
          width: requestWidth,
          textScaler: _textScaler!,
          cachedOnly: cachedOnly,
        );
        try {
          _guard();
        } catch (_) {
          parent?.release();
          rethrow;
        }
        if (parent == null) return (cacheMiss: true, view: null);
        try {
          _validateParent(input, parent);
        } catch (_) {
          parent.release();
          rethrow;
        }
        _parent = parent;
        _validatingParent = input.content.projection.atoms.isNotEmpty;
        _workCount++;
        return (cacheMiss: false, view: null);
      }
      if (_validatingParent) {
        _validateParentAtoms(maxParts);
        _guard();
        return (cacheMiss: false, view: null);
      }
      if (_nextGroup < _indices.length) {
        final index = _indices[_nextGroup];
        final atom = input.rubyAtoms[index];
        if (atom is ForumBodyInlineImageAtomPlan) {
          if (!identical(input.content.images[index], atom.input)) {
            throw const ForumBodyTextPageSurfaceException(
              ForumBodyTextPageSurfaceFailure.identity,
            );
          }
          _nextGroup++;
          _workCount++;
          return (cacheMiss: false, view: null);
        }
        if (atom is ForumBodyIntrinsicInlineAtomPlan) {
          final target = atom.metrics;
          final job = _inlineBox ??= ForumBodyInlinePagePreparation(
            input: target.input,
            fragment: target.fragment,
            identity: identity,
            cache: cache,
            textScaler: _textScaler!,
            ensureOwner: _guard,
            ensureVisibleOwner: _ensureVisibleOwner,
            ownedPageLeases: _ownedPageLeases!,
          );
          final before = job.workCount;
          final step = job.advance(cachedOnly: cachedOnly, maxParts: maxParts);
          _workCount += job.workCount - before;
          final view = step.view;
          try {
            _guard();
            if (view != null &&
                (view.width != target.size.width ||
                    view.height != target.size.height ||
                    view.lines.single.baseline != target.baseline)) {
              throw const ForumBodyInlineViewException(
                ForumBodyInlineViewFailure.geometry,
              );
            }
          } catch (_) {
            view?.close();
            rethrow;
          }
          if (view == null) return (cacheMiss: step.cacheMiss, view: null);
          _inlineBoxes[index] = view;
          _inlineBox = null;
          _nextGroup++;
          return (cacheMiss: false, view: null);
        }
        if (atom is ForumBodyTextBaselineAtomPlan) {
          final job = _baseline ??= ForumBodyTextBaselinePreparation(
            cache: cache,
            request: atom.request,
            baselineShift: atom.metrics.baselineShift,
            width: atom.maxWidth,
            textScaler: _textScaler!,
            ensureOwner: _guard,
            expectedMetrics: atom.metrics,
            additionalOwnedLeases: _ownedPageLeases,
          );
          final step = job.advance(maxParts: maxParts, cachedOnly: cachedOnly);
          _workCount += step.partsPrepared;
          _guard();
          if (!job.isReady) {
            final rejection = job.lastBudgetRejection;
            if (rejection != null) throw rejection;
            return (cacheMiss: job.cacheMiss, view: null);
          }
          _baselines[index] = job.takeLayout();
          _baseline = null;
          _nextGroup++;
          return (cacheMiss: false, view: null);
        }
        if (atom is ForumBodyRubySegmentPlan) {
          return _advanceComponent(index, atom, cachedOnly, maxParts);
        }
        if (atom is ForumBodyRubySoftSpacePlan) {
          return _advanceSpace(index, atom, cachedOnly, maxParts);
        }
        final column = atom as ForumBodyRubyColumnPlan;
        final request = column.request;
        final pair = _pair ??= ForumBodyRubyGroupPreparation.fromLayerRequests(
          cache: cache,
          base: request.base,
          annotations: request.annotations,
          level: column.level,
          maxWidth: request.maxWidth,
          textScaler: _textScaler!,
          ensureOwner: _guard,
          additionalOwnedLeases: _ownedPageLeases,
        );
        final beforeWork = pair.workCount;
        final ready = cachedOnly
            ? pair.tryPrepareCached(maxParts: maxParts)
            : pair.advance(maxParts: maxParts).isReady;
        _guard();
        _workCount += pair.workCount - beforeWork;
        if (!ready) {
          final rejection = pair.lastBudgetRejection;
          if (rejection != null) throw rejection;
          return (cacheMiss: cachedOnly && pair.cacheMiss, view: null);
        }
        _groups[index] = pair.takeLayout();
        _pair = null;
        _nextGroup++;
        return (cacheMiss: false, view: null);
      }
      _binding = ForumBodyInlineViewAssembly(
        cache: cache,
        parent: _parent!,
        startLine: _window.startLine,
        endLine: _window.endLine,
        rubyGroups: _groups,
        baselineTexts: _baselines,
        intrinsicBoxes: _inlineBoxes,
        rubySegments: _segments,
        rubySpaces: _spaces,
        containerBackgrounds: input.containerBackgrounds,
        rootFonts: input.rootFonts,
        ensureOwner: _guard,
      );
      _parent = null;
      _groups.clear();
      _baselines.clear();
      _inlineBoxes.clear();
      _segments.clear();
      _spaces.clear();
      return _advanceBinding(maxParts);
    } finally {
      _advancing = false;
    }
  }

  ({bool cacheMiss, ForumBodyInlineParagraphView? view}) _advanceComponent(
    int index,
    ForumBodyRubySegmentPlan atom,
    bool cachedOnly,
    int maxParts,
  ) {
    final job = _component ??= ForumBodyRubySegmentPreparation(
      cache: _cache!,
      request: atom.request,
      metrics: atom.metrics,
      ensureOwner: _guard,
      textScaler: _textScaler!,
      additionalOwnedLeases: _ownedPageLeases,
    );
    final before = job.workCount;
    final ready = cachedOnly
        ? job.tryPrepareCached(maxParts: maxParts)
        : job.advance(maxParts: maxParts).isReady;
    _guard();
    _workCount += job.workCount - before;
    if (!ready) {
      final rejection = job.lastBudgetRejection;
      if (rejection != null) throw rejection;
      return (cacheMiss: cachedOnly && job.cacheMiss, view: null);
    }
    _segments[index] = job.takeLayout();
    _component = null;
    _nextGroup++;
    return (cacheMiss: false, view: null);
  }

  ({bool cacheMiss, ForumBodyInlineParagraphView? view}) _advanceSpace(
    int index,
    ForumBodyRubySoftSpacePlan atom,
    bool cachedOnly,
    int maxParts,
  ) {
    final job = _space ??= ForumBodyRubySoftSpacePreparation.fromRequests(
      cache: _cache!,
      request: atom.request,
      metrics: atom.metrics,
      ensureOwner: _guard,
      textScaler: _textScaler!,
      additionalOwnedLeases: _ownedPageLeases,
    );
    final before = job.workCount;
    final ready = cachedOnly
        ? job.tryPrepareCached(maxParts: maxParts)
        : job.advance(maxParts: maxParts).isReady;
    _guard();
    _workCount += job.workCount - before;
    if (!ready) {
      final rejection = job.lastBudgetRejection;
      if (rejection != null) throw rejection;
      return (cacheMiss: cachedOnly && job.cacheMiss, view: null);
    }
    _spaces[index] = job.takeLayout();
    _space = null;
    _nextGroup++;
    return (cacheMiss: false, view: null);
  }

  void _validateParentAtoms(int maxParts) {
    final expected = _input!.content
        .projectionForLayout(_input!.layoutMode)
        .atoms;
    final actual = _parent!.layout.projection.atoms;
    var units = 0;
    while (_parentAtom < expected.length && units < maxParts) {
      final atom = expected[_parentAtom];
      final native = actual[_parentAtom];
      final trimmed = _input!.trimmedAtomIndices.contains(atom.index);
      final nativeTrimmed = _parent!.layout.isAtomTrimmed(atom.index);
      final visible =
          atom.engineUtf16 >= _engineStart &&
          atom.engineUtf16 < _engineEnd &&
          !trimmed;
      final nativeVisible =
          native.engineUtf16 >= _engineStart &&
          native.engineUtf16 < _engineEnd &&
          !nativeTrimmed;
      if (native.index != atom.index ||
          native.isResource != atom.isResource ||
          native.isSoftSpace != atom.isSoftSpace ||
          trimmed != nativeTrimmed ||
          native.engineUtf16 != atom.engineUtf16 ||
          native.displayStartUtf16 != atom.displayStartUtf16 ||
          native.displayEndUtf16 != atom.displayEndUtf16 ||
          visible != nativeVisible ||
          (visible &&
              (atom.engineUtf16 < _engineStart ||
                  atom.engineEndUtf16 > _engineEnd))) {
        throw const ForumBodyTextPageSurfaceException(
          ForumBodyTextPageSurfaceFailure.geometry,
        );
      }
      if (visible) _validatedIndices.add(atom.index);
      _parentAtom++;
      units++;
    }
    _workCount += units;
    if (_parentAtom == expected.length) {
      _indices = UnmodifiableListView(_validatedIndices);
      _validatingParent = false;
    }
  }

  ({bool cacheMiss, ForumBodyInlineParagraphView? view}) _advanceBinding(
    int maxParts,
  ) {
    final binding = _binding!;
    _workCount += binding.advance(maxParts: maxParts);
    _guard();
    if (!binding.isReady) return (cacheMiss: false, view: null);
    final view = binding.takeView();
    _binding = null;
    try {
      _guard();
    } catch (_) {
      view.close();
      rethrow;
    }
    close();
    return (cacheMiss: false, view: view);
  }

  void _validateParent(
    ForumBodyInlinePageContent input,
    ForumBodyInlineParagraphLease lease,
  ) {
    final content = lease.content;
    if (content.identity != identity ||
        content.path != _window.path ||
        content.fontRevision != _window.fontRevision ||
        content.styleRevision != _window.styleRevision) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.identity,
      );
    }
    try {
      final layout = lease.layout;
      if (layout.projection.atoms.length !=
          input.content.projection.atoms.length) {
        throw const ForumBodyTextPageSurfaceException(
          ForumBodyTextPageSurfaceFailure.geometry,
        );
      }
      if (layout.lines.isEmpty) {
        if (_window.startLine != 0 ||
            _window.endLine != 0 ||
            _window.coverageStartUtf16 != 0 ||
            _window.coverageEndUtf16 != 0 ||
            layout.width != _window.width ||
            layout.height != _window.height ||
            _window.sourceHint != null ||
            _window.engineRange != null ||
            layout.projection.atoms.isNotEmpty) {
          throw const ForumBodyTextPageSurfaceException(
            ForumBodyTextPageSurfaceFailure.geometry,
          );
        }
        return;
      }
      final view = layout.fragment(_window.startLine, _window.endLine);
      if (layout.isDisposed ||
          layout.width != _window.width ||
          view.height != _window.height ||
          view.coverageStartUtf16 != _window.coverageStartUtf16 ||
          view.coverageEndUtf16 != _window.coverageEndUtf16 ||
          _window.engineRange !=
              (
                startUtf16: view.engineCoverageStartUtf16,
                endUtf16: view.engineCoverageEndUtf16,
              ) ||
          _window.sourceHint !=
              forumBodySourceHint(
                content.projection.display,
                view.coverageStartUtf16,
                view.coverageEndUtf16,
              )) {
        throw const ForumBodyTextPageSurfaceException(
          ForumBodyTextPageSurfaceFailure.geometry,
        );
      }
      _engineStart = view.engineCoverageStartUtf16;
      _engineEnd = view.engineCoverageEndUtf16;
    } on RangeError {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.geometry,
      );
    } on ForumBodyParagraphLayoutException {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.geometry,
      );
    }
  }

  void _guard() {
    if (_closed) throw StateError('Inline preparation is retired');
    _ensureOwner!();
    if (_closed || _cache!.isClosed) {
      throw StateError('Inline preparation owner is retired');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _binding?.close();
    _binding = null;
    _pair?.close();
    _baseline?.close();
    _baseline = null;
    _inlineBox?.close();
    _inlineBox = null;
    for (final view in _inlineBoxes.values) {
      view.close();
    }
    _inlineBoxes.clear();
    _pair = null;
    _component?.close();
    _component = null;
    _space?.close();
    _space = null;
    for (final group in _groups.values) {
      group.close();
    }
    _groups.clear();
    for (final text in _baselines.values) {
      text.close();
    }
    _baselines.clear();
    for (final segment in _segments.values) {
      segment.close();
    }
    _segments.clear();
    for (final space in _spaces.values) {
      space.close();
    }
    _spaces.clear();
    _parent?.release();
    _parent = null;
    _input = null;
    _indices = const [];
    _validatedIndices = [];
    _validatingParent = false;
    _cache = null;
    _textScaler = null;
    _ensureOwner = null;
    _ensureVisibleOwner = null;
    _ownedPageLeases = null;
  }
}
