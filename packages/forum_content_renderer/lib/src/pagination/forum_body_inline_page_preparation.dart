import 'dart:collection';

import 'package:flutter/painting.dart';

import '../document/forum_body_document.dart';
import '../inline/forum_body_inline_paragraph_view.dart';
import '../inline/forum_body_ruby_atom_plan.dart';
import '../inline/forum_body_ruby_group_layout.dart';
import '../inline/forum_body_ruby_group_preparation.dart';
import '../inline/forum_body_ruby_segment_layout.dart';
import '../inline/forum_body_ruby_segment_preparation.dart';
import '../inline/forum_body_ruby_soft_space_layout.dart';
import '../inline/forum_body_ruby_tree_layout.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import 'forum_body_source_hint.dart';
import 'forum_body_text_page_binding.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_text_page_content.dart';

/// Format-local resource preparation borrowed by the sole page transaction.
/// One call acquires a parent, advances one pair, or binds the completed view.
/// The page owns rollback, aggregate admission, scheduling and reservations.
final class ForumBodyInlinePagePreparation {
  ForumBodyInlinePagePreparation({
    required ForumBodyInlinePageContent input,
    required this.fragment,
    required this.identity,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    required Iterable<ForumBodyNativeParagraphLease> Function() ownedPageLeases,
  }) : _input = input,
       _cache = cache,
       _textScaler = textScaler,
       _ensureOwner = ensureOwner,
       _ownedPageLeases = ownedPageLeases;
  ForumBodyInlinePageContent? _input;
  final ForumBodyTextPageFragment fragment;
  final ForumBodyIdentity identity;
  ForumBodyParagraphCache? _cache;
  TextScaler? _textScaler;
  void Function()? _ensureOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _ownedPageLeases;
  ForumBodyInlineParagraphLease? _parent;
  List<int> _indices = const [];
  final _groups = <int, ForumBodyRubyGroupLayout>{};
  final _segments = <int, ForumBodyRubySegmentLayout>{};
  final _spaces = <int, ForumBodyRubySoftSpaceLayout>{};
  final _trees = <int, ForumBodyRubyTreeLayout>{};
  int _nextGroup = 0;
  ForumBodyRubyGroupPreparation? _pair;
  ForumBodyRubySegmentPreparation? _component;
  ForumBodyRubySoftSpacePreparation? _space;
  ForumBodyRubyTreePreparation? _tree;
  ForumBodyInlineViewAssembly? _binding;
  bool _validatingParent = false;
  var _parentAtom = 0;
  var _engineStart = 0;
  var _engineEnd = 0;
  List<int> _validatedIndices = [];
  bool _closed = false;
  bool _advancing = false;
  int _workCount = 0;
  int get workCount => _workCount;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_parent,
    for (final group in _groups.values) ...group.nativeLeases,
    for (final segment in _segments.values) ...segment.nativeLeases,
    for (final space in _spaces.values) ...space.nativeLeases,
    for (final tree in _trees.values) ...tree.nativeLeases,
    if (_pair != null) ..._pair!.nativeLeases,
    if (_component != null) ..._component!.nativeLeases,
    if (_space != null) ..._space!.nativeLeases,
    if (_tree != null) ..._tree!.nativeLeases,
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
        if (atom is ForumBodyRubyTreePlan) {
          return _advanceTree(index, atom, cachedOnly, maxParts);
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
        startLine: fragment.startLine,
        endLine: fragment.endLine,
        rubyGroups: _groups,
        rubySegments: _segments,
        rubySpaces: _spaces,
        rubyTrees: _trees,
        containerBackgrounds: input.containerBackgrounds,
        rootFonts: input.rootFonts,
        ensureOwner: _guard,
      );
      _parent = null;
      _groups.clear();
      _segments.clear();
      _spaces.clear();
      _trees.clear();
      return _advanceBinding(maxParts);
    } finally {
      _advancing = false;
    }
  }

  ({bool cacheMiss, ForumBodyInlineParagraphView? view}) _advanceTree(
    int index,
    ForumBodyRubyTreePlan atom,
    bool cachedOnly,
    int maxParts,
  ) {
    final job = _tree ??= ForumBodyRubyTreePreparation(
      input: atom.request,
      metrics: atom.metrics,
      cache: _cache!,
      ensureOwner: _guard,
      expectedTextScaler: _textScaler!,
      additionalOwnedLeases: _ownedPageLeases,
    );
    final before = job.workCount;
    final ready = job
        .advance(maxParts: maxParts, cachedOnly: cachedOnly)
        .isReady;
    _guard();
    _workCount += job.workCount - before;
    if (!ready) {
      final rejection = job.lastBudgetRejection;
      if (rejection != null) throw rejection;
      return (cacheMiss: cachedOnly && job.cacheMiss, view: null);
    }
    _trees[index] = job.takeLayout();
    _tree = null;
    _nextGroup++;
    return (cacheMiss: false, view: null);
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
        .projectionForLayout(ForumBodyParagraphLayoutMode.wrap)
        .atoms;
    final actual = _parent!.layout.projection.atoms;
    var units = 0;
    while (_parentAtom < expected.length && units < maxParts) {
      final atom = expected[_parentAtom];
      final native = actual[_parentAtom];
      final trimmed = _input!.trimmedAtomIndices.contains(atom.index);
      final nativeTrimmed = _parent!.layout.isAtomTrimmed(atom.index);
      final visible =
          atom.displayEndUtf16 > fragment.coverageStartUtf16 &&
          atom.displayStartUtf16 < fragment.coverageEndUtf16 &&
          !trimmed;
      final nativeVisible =
          native.engineUtf16 >= _engineStart &&
          native.engineUtf16 < _engineEnd &&
          !nativeTrimmed;
      if (native.index != atom.index ||
          native.isSoftSpace != atom.isSoftSpace ||
          trimmed != nativeTrimmed ||
          native.engineUtf16 != atom.engineUtf16 ||
          native.displayStartUtf16 != atom.displayStartUtf16 ||
          native.displayEndUtf16 != atom.displayEndUtf16 ||
          visible != nativeVisible ||
          (visible &&
              (atom.displayStartUtf16 < fragment.coverageStartUtf16 ||
                  atom.displayEndUtf16 > fragment.coverageEndUtf16))) {
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
        content.path != fragment.path ||
        content.fontRevision != fragment.fontRevision ||
        content.styleRevision != fragment.styleRevision) {
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
        if (fragment.startLine != 0 ||
            fragment.endLine != 0 ||
            fragment.coverageStartUtf16 != 0 ||
            fragment.coverageEndUtf16 != 0 ||
            layout.width != fragment.width ||
            layout.height != fragment.height ||
            fragment.sourceHint != null ||
            layout.projection.atoms.isNotEmpty) {
          throw const ForumBodyTextPageSurfaceException(
            ForumBodyTextPageSurfaceFailure.geometry,
          );
        }
        return;
      }
      final view = layout.fragment(fragment.startLine, fragment.endLine);
      if (layout.isDisposed ||
          layout.width != fragment.width ||
          view.height != fragment.height ||
          view.coverageStartUtf16 != fragment.coverageStartUtf16 ||
          view.coverageEndUtf16 != fragment.coverageEndUtf16 ||
          fragment.sourceHint !=
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
    _pair = null;
    _component?.close();
    _component = null;
    _space?.close();
    _space = null;
    _tree?.close();
    _tree = null;
    for (final tree in _trees.values) {
      tree.close();
    }
    _trees.clear();
    for (final group in _groups.values) {
      group.close();
    }
    _groups.clear();
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
    _ownedPageLeases = null;
  }
}
