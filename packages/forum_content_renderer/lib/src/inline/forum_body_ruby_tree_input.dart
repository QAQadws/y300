import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart'
    show HtmlProjectedSourcePosition;

import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_text_request.dart';
import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_text_request_preparation.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_inline_text_window.dart';
import 'forum_body_ruby_annotation_input.dart';
import 'forum_body_ruby_annotation_pairing.dart';
import 'forum_body_ruby_child_input.dart';
import 'forum_body_ruby_base_input.dart';
import 'forum_body_ruby_container_background.dart';
import 'forum_body_ruby_content.dart';
import 'forum_body_ruby_root_box.dart';
import 'forum_body_inline_plan_input.dart';
import 'forum_body_inline_source_preparation.dart';
import 'forum_body_ruby_whitespace.dart';
import 'forum_body_emphasis_text_input.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_group_preparation.dart';
import 'forum_body_ruby_tree_metrics_preparation.dart';
import 'forum_body_ruby_tree_child_geometry.dart';
import 'forum_body_ruby_tree_layout.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_emphasis_mark.dart';
import 'forum_body_text_band_layout.dart';
import 'forum_body_ruby_band_stack.dart';

part 'forum_body_ruby_tree_segment_input.dart';
part 'forum_body_ruby_glyph_tree_input.dart';
part 'forum_body_ruby_glyph_tree_metrics.dart';
part 'forum_body_ruby_glyph_tree_geometry.dart';
part 'forum_body_ruby_glyph_tree_bands.dart';
part 'forum_body_ruby_glyph_tree_binding.dart';
part 'forum_body_ruby_empty_annotation_fonts.dart';
part 'forum_body_ruby_tree_emphasis_metrics.dart';
part 'forum_body_ruby_tree_decoration_bands.dart';
part 'forum_body_ruby_tree_emphasis_placement.dart';

/// Internal postorder graph of real nested columns and segments. Source leaves
/// stay in original base/annotation order; their IDs are not DOM offsets.
/// Mixed sequences keep a real intrinsic inline plan, not summed text widths.
final class ForumBodyRubyTreeInput {
  // Both lists transfer from the retired builder; neither is mutated again.
  ForumBodyRubyTreeInput._(
    List<ForumBodyRubyTreeNode> nodes,
    List<ForumBodyTextRequest> requests,
    List<ForumBodyRubyTreeSource> sources,
    this.maxWidth, [
    Object? structure,
  ]) : nodes = UnmodifiableListView(nodes),
       nativeRequests = UnmodifiableListView(requests),
       sources = UnmodifiableListView(sources),
       _structure = structure ?? Object();
  final Object _structure;
  final List<ForumBodyRubyTreeNode> nodes;
  final double maxWidth;
  final List<ForumBodyTextRequest> nativeRequests;
  final List<ForumBodyRubyTreeSource> sources;
  late final extraTextCodeUnits = nodes
      .whereType<ForumBodyRubyTreeInline>()
      .fold<int>(0, (sum, node) => sum + node.input.retainedTextCodeUnits);
  late final extraRuns = nodes.whereType<ForumBodyRubyTreeInline>().fold<int>(
    0,
    (sum, node) => sum + node.input.retainedRuns,
  );
  int get root => nodes.length - 1;
  ForumBodyRubyTreeRoot get rootGroup => nodes.last as ForumBodyRubyTreeRoot;
  bool hasSameStructure(ForumBodyRubyTreeInput other) =>
      identical(_structure, other._structure);

  /// Batch rebinding changes only actual native requests, never a leaf's
  /// current source/style object or the structural graph.
  ForumBodyRubyTreeInput mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) {
    final mapped = <ForumBodyRubyTreeNode>[];
    final requests = <ForumBodyTextRequest>[];
    for (final node in nodes) {
      if (node is ForumBodyRubyTreeText && node.needsNative) {
        final request = map(node.request);
        if (!identical(request.content, node.content)) {
          throw ForumBodyParagraphInputException(
            ForumBodyParagraphInputFailure.identity,
            node.content.path,
          );
        }
        mapped.add(
          ForumBodyRubyTreeText._request(node.original, node.content, request),
        );
        requests.add(request);
      } else {
        mapped.add(node);
      }
    }
    return ForumBodyRubyTreeInput._(
      mapped,
      requests,
      sources,
      maxWidth,
      _structure,
    );
  }
}

sealed class ForumBodyRubyTreeNode {
  const ForumBodyRubyTreeNode();
}

final class ForumBodyRubyTreeSource {
  const ForumBodyRubyTreeSource(this.id, this.content);
  // Text nodes retain their graph ID. Inline contexts have distinct negative
  // IDs in this graph; neither kind is a DOM/source/semantic coordinate.
  final int id;
  final ForumBodyParagraphContent content;
}

final class ForumBodyRubyTreeText extends ForumBodyRubyTreeNode {
  ForumBodyRubyTreeText._(this.original, this.content, this.needsNative)
    : request = ForumBodyTextRequest.paragraph(content);
  ForumBodyRubyTreeText._request(this.original, this.content, this.request)
    : needsNative = true;
  final ForumBodyParagraphContent original;
  final ForumBodyParagraphContent content;
  // Empty annotation contexts remain in the graph, with no native glyph lease.
  // An empty base still requires its actual native font box.
  final bool needsNative;
  final ForumBodyTextRequest request;
}

sealed class ForumBodyRubyTreeContainer extends ForumBodyRubyTreeNode {
  const ForumBodyRubyTreeContainer(this.font, this.background);
  final ForumBodyRubyRootBoxInput font;
  final ForumBodyRubyContainerBackground? background;
}

final class ForumBodyRubyTreeFrame extends ForumBodyRubyTreeContainer {
  const ForumBodyRubyTreeFrame._(
    super.font,
    super.background,
    this.input,
    this.child,
  );
  final ForumBodyRubySequenceChildInput input;
  final int child;
}

final class ForumBodyRubyTreeInline extends ForumBodyRubyTreeContainer {
  ForumBodyRubyTreeInline._(
    super.font,
    super.background,
    this.input,
    List<ForumBodyRubyTreeSource> sources,
  ) : sources = UnmodifiableListView(sources);
  final ForumBodyInlinePlanInput input;
  final List<ForumBodyRubyTreeSource> sources;
}

sealed class ForumBodyRubyTreeRoot extends ForumBodyRubyTreeContainer {
  const ForumBodyRubyTreeRoot(super.font, super.background, this.group);
  final ForumBodyRubyGroupContent group;
}

final class ForumBodyRubyTreeGroup extends ForumBodyRubyTreeRoot {
  ForumBodyRubyTreeGroup._(
    super.font,
    super.background,
    super.group,
    this.base,
    List<({int? child, ForumBodyRubySide side})> annotations,
  ) : annotations = UnmodifiableListView(annotations);
  ForumBodyRubyTreeGroup._withFont(
    ForumBodyRubyRootBoxInput font,
    ForumBodyRubyTreeGroup source,
  ) : base = source.base,
      annotations = source.annotations,
      super(font, source.background, source.group);
  final int base;
  final List<({int? child, ForumBodyRubySide side})> annotations;
}

enum ForumBodyRubyTreeSegmentChildKind { base, gap, span, annotationGap, fence }

typedef ForumBodyRubyTreeSegmentChild = ({
  int node,
  ForumBodyRubyTreeSegmentChildKind kind,
  int index,
});
typedef ForumBodyRubyTreeSegmentSpan = ({
  int child,
  int startColumn,
  int endColumn,
  int rank,
});
typedef ForumBodyRubyTreeSegmentGap = ({int child, int beforeColumn});
typedef ForumBodyRubyTreeSegmentAnnotationGap = ({int child, int beforeSpan});
typedef ForumBodyRubyTreeSegmentFence = ({
  int child,
  int beforeColumn,
  int? rank,
});

/// One original multi-column group. Every child still has its original source;
/// the shared segment numeric worker allocates spans, never a fake text parent.
final class ForumBodyRubyTreeSegment extends ForumBodyRubyTreeRoot {
  ForumBodyRubyTreeSegment._(
    super.font,
    super.background,
    super.group, {
    required List<int> bases,
    required List<ForumBodyRubyTreeSegmentSpan> spans,
    required List<ForumBodyRubyTreeSegmentGap> gaps,
    required List<ForumBodyRubyTreeSegmentAnnotationGap> annotationGaps,
    required List<ForumBodyRubyTreeSegmentFence> fences,
    required List<ForumBodyRubyTreeSegmentChild> children,
    required List<ForumBodyRubySide> sides,
    required Map<int, List<int>> spanRanks,
    required Map<int, List<int>> annotationGapRanks,
  }) : bases = UnmodifiableListView(bases),
       spans = UnmodifiableListView(spans),
       gaps = UnmodifiableListView(gaps),
       annotationGaps = UnmodifiableListView(annotationGaps),
       fences = UnmodifiableListView(fences),
       children = UnmodifiableListView(children),
       sides = List.unmodifiable(sides),
       spanRanks = UnmodifiableMapView(spanRanks),
       annotationGapRanks = UnmodifiableMapView(annotationGapRanks);
  ForumBodyRubyTreeSegment._withFont(
    ForumBodyRubyRootBoxInput font,
    ForumBodyRubyTreeSegment source,
  ) : bases = source.bases,
      spans = source.spans,
      gaps = source.gaps,
      annotationGaps = source.annotationGaps,
      fences = source.fences,
      children = source.children,
      sides = source.sides,
      spanRanks = source.spanRanks,
      annotationGapRanks = source.annotationGapRanks,
      super(font, source.background, source.group);
  final List<int> bases;
  final List<ForumBodyRubyTreeSegmentSpan> spans;
  final List<ForumBodyRubyTreeSegmentGap> gaps;
  final List<ForumBodyRubyTreeSegmentAnnotationGap> annotationGaps;
  final List<ForumBodyRubyTreeSegmentFence> fences;
  final List<ForumBodyRubyTreeSegmentChild> children;
  final List<ForumBodyRubySide> sides;
  final Map<int, List<int>> spanRanks;
  final Map<int, List<int>> annotationGapRanks;
}

/// Pure, iterative structural preparation. It does not recursively scan a
/// descendant tree or imply that Session can yet publish its source coverage.
/// Each unit enters a group/child, follows one edge, or seals one container.
final class ForumBodyRubyTreeInputPreparation {
  ForumBodyRubyTreeInputPreparation({
    required ForumBodyRubyGroupContent group,
    required this.maxWidth,
  }) : _scope = group,
       _stack = [_GroupWork(group)] {
    if (!maxWidth.isFinite || maxWidth <= 0 || maxWidth > 16384) {
      throw ArgumentError.value(maxWidth, 'maxWidth');
    }
  }
  ForumBodyRubyGroupContent? _scope;
  List<_TreeWork> _stack;
  List<ForumBodyRubyTreeNode> _nodes = [];
  List<ForumBodyTextRequest> _requests = [];
  List<ForumBodyRubyTreeSource> _sources = [];
  final double maxWidth;
  int? _completedChild;
  bool _retired = false;
  bool get isReady => !_retired && _stack.isEmpty;

  int advance({required int maxParts}) {
    if (_retired) throw StateError('Ruby tree input is retired');
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    var units = 0;
    try {
      while (_stack.isNotEmpty && units < maxParts) {
        _stack.last.advance(this);
        units++;
      }
      return units;
    } catch (_) {
      close();
      rethrow;
    }
  }

  void _finish(ForumBodyRubyTreeNode node) {
    _completedChild = _nodes.length;
    if (node is ForumBodyRubyTreeText) {
      _sources.add(ForumBodyRubyTreeSource(_nodes.length, node.content));
    }
    _nodes.add(node);
    if (node is ForumBodyRubyTreeText && node.needsNative) {
      _requests.add(node.request);
    }
    _stack.removeLast().close();
  }

  int _takeChild() {
    final child = _completedChild;
    if (child == null) throw StateError('Ruby child is incomplete');
    _completedChild = null;
    return child;
  }

  void _validate(ForumBodyRubyGroupContent group) {
    final scope = _scope!;
    if (group.identity != scope.identity ||
        group.fontRevision != scope.fontRevision ||
        group.styleRevision != scope.styleRevision) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        group.rootPath,
      );
    }
  }

  ForumBodyRubyTreeInput takeInput() {
    if (!isReady) throw StateError('Ruby tree input is incomplete');
    final result = ForumBodyRubyTreeInput._(
      _nodes,
      _requests,
      _sources,
      maxWidth,
    );
    close();
    return result;
  }

  void close() {
    if (_retired) return;
    _retired = true;
    _scope = null;
    for (final work in _stack) {
      work.close();
    }
    _stack = [];
    _nodes = [];
    _requests = [];
    _sources = [];
    _completedChild = null;
  }
}

sealed class _TreeWork {
  void advance(ForumBodyRubyTreeInputPreparation owner);
  void close() {}
}

final class _GroupWork extends _TreeWork {
  _GroupWork(this.group);
  final ForumBodyRubyGroupContent group;
  ForumBodyRubyAnnotationPairing? pairing;
  ForumBodyRubyRootBoxInput? font;
  ForumBodyRubyContainerBackground? background;
  int? base;
  int rank = 0;
  bool awaitingChild = false;
  final annotations = <({int? child, ForumBodyRubySide side})>[];
  @override
  void advance(ForumBodyRubyTreeInputPreparation owner) {
    if (pairing == null) {
      owner._validate(group);
      final units = resolveForumBodyRubyBaseChildInputs(group);
      final actual = ForumBodyRubyAnnotationPairing(
        group: group,
        baseColumnCount: units
            .where((unit) => unit.kind != ForumBodyRubyBaseInputKind.gap)
            .length,
      );
      if (actual.columnCount != 1 ||
          actual.hasAnnotationGaps ||
          units.length != 1) {
        owner._stack.removeLast().close();
        owner._stack.add(_SegmentGroupWork(group, units, actual));
        return;
      }
      pairing = actual;
      font = ForumBodyRubyRootBoxInput.fromGroup(group);
      background = ForumBodyRubyContainerBackground.fromGroup(group);
      final child = units.single.child;
      if (units.single.kind == ForumBodyRubyBaseInputKind.implicit) {
        if (child is ForumBodyRubyTextChildInput &&
            (forumBodyInlineHasCollapsibleEdge(child.content, leading: true) ||
                forumBodyInlineHasCollapsibleEdge(
                  child.content,
                  leading: false,
                ))) {
          // Such edges belong to the real containing inline context. A closed
          // tree must not trap them in an unbreakable placeholder.
          _unsupported(child.path);
        }
      }
      owner._stack.add(_ChildWork(child, annotation: false));
      return;
    }
    if (base == null) {
      base = owner._takeChild();
      return;
    }
    if (awaitingChild) {
      annotations.add((
        child: owner._takeChild(),
        side: pairing!.levels[rank].side,
      ));
      awaitingChild = false;
      rank++;
      return;
    }
    if (rank < pairing!.levels.length) {
      final level = pairing!.levels[rank];
      if (level.spans.isEmpty) {
        annotations.add((child: null, side: level.side));
        rank++;
      } else {
        final box = level.spans.single.box;
        final child = _annotationChild(group, box);
        awaitingChild = true;
        owner._stack.add(_ChildWork(child, annotation: true));
      }
      return;
    }
    owner._finish(
      ForumBodyRubyTreeGroup._(font!, background, group, base!, annotations),
    );
  }
}

final class _ChildWork extends _TreeWork {
  _ChildWork(this.input, {required this.annotation, this.emptyNeedsNative});
  final ForumBodyRubyChildInput input;
  final bool annotation;
  final bool? emptyNeedsNative;
  bool awaitingChild = false;
  ForumBodyInlineSourcePreparation? _inline;
  ForumBodyInlinePlanInput? _inlineInput;
  final _inlineSources = <ForumBodyRubyTreeSource>[];
  @override
  void advance(ForumBodyRubyTreeInputPreparation owner) {
    switch (input) {
      case ForumBodyRubyTextChildInput(:final content):
        final actual = annotation
            ? trimForumBodyInlineText(content, leading: true, trailing: true)
            : content;
        owner._finish(
          ForumBodyRubyTreeText._(
            content,
            actual,
            (emptyNeedsNative ?? !annotation) ||
                actual.projection.text.isNotEmpty,
          ),
        );
      case ForumBodyRubySequenceChildInput():
        final sequence = input as ForumBodyRubySequenceChildInput;
        final onlyNested =
            sequence.parts.length == 1 &&
            sequence.parts.single is ForumBodyRubyNestedContent &&
            (sequence.parts.single as ForumBodyRubyNestedContent)
                    .groups
                    .length ==
                1;
        if (!onlyNested) {
          final source = _inline ??= ForumBodyInlineSourcePreparation(
            input: sequence.toInlineFlow(trimCollapsibleEdges: annotation),
            width: owner.maxWidth,
            ensureOwner: () {
              if (owner._retired) {
                throw StateError('Ruby input owner is retired');
              }
            },
          );
          if (_inlineInput == null) {
            source.advance(maxParts: 1);
            if (source.isReady) _inlineInput = source.takeInput();
            return;
          }
          if (_inlineSources.length < _inlineInput!.sourceContexts.length) {
            final source = ForumBodyRubyTreeSource(
              -(owner._sources.length + 1),
              _inlineInput!.sourceContexts[_inlineSources.length],
            );
            owner._sources.add(source);
            _inlineSources.add(source);
            return;
          }
          owner._finish(
            ForumBodyRubyTreeInline._(
              _font(sequence),
              _background(sequence),
              _inlineInput!,
              _inlineSources,
            ),
          );
          return;
        }
        if (!awaitingChild) {
          final nested = sequence.parts.single as ForumBodyRubyNestedContent;
          if (nested.groups.length != 1) _unsupported(nested.path);
          awaitingChild = true;
          owner._stack.add(_GroupWork(nested.groups.single));
          return;
        }
        owner._finish(
          ForumBodyRubyTreeFrame._(
            _font(sequence),
            _background(sequence),
            sequence,
            owner._takeChild(),
          ),
        );
    }
  }

  ForumBodyRubyRootBoxInput _font(ForumBodyRubySequenceChildInput sequence) =>
      ForumBodyRubyRootBoxInput(
        rootPath: sequence.path,
        fontStrut: ForumBodyParagraphContent.anonymousInline(
          identity: sequence.identity,
          fontRevision: sequence.fontRevision,
          styleRevision: sequence.styleRevision,
          style: sequence.style,
        ),
      );
  ForumBodyRubyContainerBackground? _background(
    ForumBodyRubySequenceChildInput sequence,
  ) => sequence.source == null
      ? null
      : ForumBodyRubyContainerBackground.fromContainer(
          identity: sequence.identity,
          fontRevision: sequence.fontRevision,
          styleRevision: sequence.styleRevision,
          path: sequence.path,
          style: sequence.style,
        );
  @override
  void close() {
    _inline?.close();
    _inline = null;
    _inlineInput = null;
  }
}

Never _unsupported(String? path) => throw ForumBodyParagraphInputException(
  ForumBodyParagraphInputFailure.structure,
  path,
);

ForumBodyRubyChildInput _annotationChild(
  ForumBodyRubyGroupContent group,
  ForumBodyRubyAnnotationBoxInput box,
) => switch (box) {
  ForumBodyRubyExplicitAnnotationInput() => ForumBodyRubyChildInput.annotation(
    group,
    box.annotation,
  ),
  ForumBodyRubyAnonymousAnnotationInput() => ForumBodyRubyChildInput.implicit(
    group,
    [ForumBodyRubyTextContent(box.content)],
  ),
};
