import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';

import '../document/forum_body_document.dart';
import '../inline/forum_body_inline_paragraph_view.dart';
import '../inline/forum_body_ruby_group_layout.dart';
import '../inline/forum_body_ruby_group_preparation.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
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
  int _nextGroup = 0;
  ForumBodyRubyGroupPreparation? _pair;
  ForumBodyInlineViewAssembly? _binding;
  bool _closed = false;
  bool _advancing = false;
  int _workCount = 0;
  int get workCount => _workCount;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_parent,
    for (final group in _groups.values) ...group.nativeLeases,
    if (_pair != null) ..._pair!.nativeLeases,
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
        final parent = cachedOnly
            ? cache.tryAcquireInlineCached(
                content: input.content,
                width: requestWidth,
                dimensions: input.dimensions,
                textScaler: _textScaler!,
                layoutMode: input.layoutMode,
              )
            : cache.acquireInline(
                content: input.content,
                width: requestWidth,
                dimensions: input.dimensions,
                textScaler: _textScaler!,
                layoutMode: input.layoutMode,
              );
        try {
          _guard();
        } catch (_) {
          parent?.release();
          rethrow;
        }
        if (parent == null) return (cacheMiss: true, view: null);
        try {
          _indices = _validateParent(input, parent);
        } catch (_) {
          parent.release();
          rethrow;
        }
        _parent = parent;
        _workCount++;
        return (cacheMiss: false, view: null);
      }
      if (_nextGroup < _indices.length) {
        final index = _indices[_nextGroup];
        final request = input.rubyGroups[index];
        final pair = _pair ??= ForumBodyRubyGroupPreparation.fromLayerRequests(
          cache: cache,
          base: request.base,
          annotations: request.annotations,
          level: input.rubyLevelMetrics[index],
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
        ensureOwner: _guard,
      );
      _parent = null;
      _groups.clear();
      return _advanceBinding(maxParts);
    } finally {
      _advancing = false;
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

  List<int> _validateParent(
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
      if (layout.lines.isEmpty) {
        if (fragment.startLine != 0 ||
            fragment.endLine != 0 ||
            fragment.coverageStartUtf16 != 0 ||
            fragment.coverageEndUtf16 != 0 ||
            layout.width != fragment.width ||
            layout.height != fragment.height ||
            fragment.sourceHint != null ||
            input.visibleAtoms(fragment).isNotEmpty) {
          throw const ForumBodyTextPageSurfaceException(
            ForumBodyTextPageSurfaceFailure.geometry,
          );
        }
        return const [];
      }
      final view = layout.fragment(fragment.startLine, fragment.endLine);
      final actual = view.atomIndices.toList(growable: false);
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
              ) ||
          !listEquals(actual, input.visibleAtoms(fragment))) {
        throw const ForumBodyTextPageSurfaceException(
          ForumBodyTextPageSurfaceFailure.geometry,
        );
      }
      return actual;
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
    for (final group in _groups.values) {
      group.close();
    }
    _groups.clear();
    _parent?.release();
    _parent = null;
    _input = null;
    _indices = const [];
    _cache = null;
    _textScaler = null;
    _ensureOwner = null;
    _ownedPageLeases = null;
  }
}
