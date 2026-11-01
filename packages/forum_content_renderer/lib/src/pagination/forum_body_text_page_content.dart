import 'package:flutter/painting.dart';
import '../document/forum_body_document.dart';

import '../inline/forum_body_inline_span_content.dart';
import '../inline/forum_body_ruby_atom_plan.dart';
import '../inline/forum_body_ruby_column_request.dart';
import '../inline/forum_body_ruby_group_metrics.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_text_request.dart';
import '../inline/forum_body_text_band_content.dart';
import 'forum_body_text_page_binding.dart';
import 'forum_body_text_page_composer.dart';

export '../inline/forum_body_ruby_column_request.dart';

/// Retained pure input for one composed paragraph, without a native owner,
/// preparation cursor, Context or callback. The session controls total input
/// retention; native resources remain in its existing shared reading cache.
sealed class ForumBodyTextPageContent {
  const ForumBodyTextPageContent._();
  factory ForumBodyTextPageContent.paragraph(
    ForumBodyParagraphContent content,
  ) = ForumBodyParagraphPageContent;
  factory ForumBodyTextPageContent.inline({
    required ForumBodyInlineSpanContent content,
    required List<PlaceholderDimensions> dimensions,
    required List<ForumBodyRubyColumnRequest> rubyGroups,
    List<ForumBodyRubyLevelMetrics?>? rubyLevelMetrics,
    ForumBodyParagraphLayoutMode layoutMode,
  }) = ForumBodyInlinePageContent;
  factory ForumBodyTextPageContent.inlineAtoms({
    required ForumBodyInlineSpanContent content,
    required List<PlaceholderDimensions> dimensions,
    required List<ForumBodyRubyAtomPlan> rubyAtoms,
    Set<int> trimmedAtomIndices,
    ForumBodyParagraphLayoutMode layoutMode,
  }) = ForumBodyInlinePageContent.atoms;
  int get textCodeUnits;
  int get runCount;
  ForumBodyIdentity get identity;
  double requestWidthFor(ForumBodyTextPageFragment fragment);
  int nativeHandleCountFor(ForumBodyTextPageFragment fragment);
}

final class ForumBodyParagraphPageContent extends ForumBodyTextPageContent {
  ForumBodyParagraphPageContent(this.content) : super._() {
    if (content.isSourceFree) {
      throw ArgumentError('Anonymous font struts are not document paragraphs');
    }
  }
  final ForumBodyParagraphContent content;
  @override
  ForumBodyIdentity get identity => content.identity;
  @override
  int get textCodeUnits => content.projection.text.length;
  @override
  int get runCount => content.runs.length;
  @override
  double requestWidthFor(ForumBodyTextPageFragment fragment) =>
      content.layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine &&
          fragment.width == 0
      ? 1
      : fragment.width;
  @override
  int nativeHandleCountFor(ForumBodyTextPageFragment fragment) {
    if (fragment.kind != ForumBodyTextPageFragmentKind.paragraph ||
        fragment.path != content.path ||
        fragment.fontRevision != content.fontRevision ||
        fragment.styleRevision != content.styleRevision) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.identity,
      );
    }
    return 1;
  }
}

final class ForumBodyInlinePageContent extends ForumBodyTextPageContent {
  ForumBodyInlinePageContent({
    required ForumBodyInlineSpanContent content,
    required List<PlaceholderDimensions> dimensions,
    required List<ForumBodyRubyColumnRequest> rubyGroups,
    List<ForumBodyRubyLevelMetrics?>? rubyLevelMetrics,
    ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) : this.atoms(
         content: content,
         dimensions: dimensions,
         rubyAtoms: _columnAtoms(rubyGroups, rubyLevelMetrics),
         layoutMode: layoutMode,
       );

  ForumBodyInlinePageContent.atoms({
    required this.content,
    required List<PlaceholderDimensions> dimensions,
    required List<ForumBodyRubyAtomPlan> rubyAtoms,
    Set<int> trimmedAtomIndices = const {},
    this.layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) : dimensions = List.unmodifiable(dimensions),
       rubyAtoms = List.unmodifiable(rubyAtoms),
       trimmedAtomIndices = Set.unmodifiable(trimmedAtomIndices),
       super._() {
    content.validateDimensions(this.dimensions);
    if (rubyAtoms.length != content.projection.atoms.length ||
        layoutMode == ForumBodyParagraphLayoutMode.fitSingleLine) {
      throw ArgumentError('Invalid inline page input');
    }
    final retained = Set<ForumBodyParagraphContent>.identity()
      ..addAll(content.contexts.map((item) => item.content));
    final checkedBands = Set<ForumBodyTextBandContent>.identity();
    for (final index in trimmedAtomIndices) {
      if (index < 0 ||
          index >= rubyAtoms.length ||
          !content.projection.atoms[index].isSoftSpace) {
        throw ArgumentError('Invalid inline trimmed atom snapshot');
      }
    }
    for (final (index, plan) in rubyAtoms.indexed) {
      if (content.projection.atoms[index].isSoftSpace !=
          (plan is ForumBodyRubySoftSpacePlan)) {
        throw ArgumentError(
          'Soft native slots require actual soft-space plans',
        );
      }
      final target = switch (plan) {
        ForumBodyRubySegmentPlan(:final metrics) => (
          size: metrics.size,
          baseline: metrics.baseline,
        ),
        ForumBodyRubySoftSpacePlan(:final metrics) => (
          size: metrics.size,
          baseline: metrics.baseline,
        ),
        _ => null,
      };
      if (target != null) {
        final dimension = this.dimensions[index];
        if ((dimension.size.width - target.size.width).abs() > 1e-4 ||
            (dimension.size.height - target.size.height).abs() > 1e-4 ||
            (dimension.baselineOffset! - target.baseline).abs() > 1e-4) {
          throw ArgumentError(
            'Ruby atom dimensions do not match numeric target',
          );
        }
      }
      content.resolveAtomicContexts(index, [
        for (final request in plan.nativeRequests) request.content,
      ]);
      for (final request in plan.nativeRequests) {
        // Keep the complete band input inside this already bounded paragraph.
        // An off-input tail must not evade the session's retention accounting.
        if (request is ForumBodyTextBandChildRequest &&
            checkedBands.add(request.band) &&
            request.band.contexts.any(
              (context) => !retained.contains(context),
            )) {
          throw ForumBodyParagraphInputException(
            ForumBodyParagraphInputFailure.identity,
            content.path,
          );
        }
      }
    }
  }
  final ForumBodyInlineSpanContent content;
  final List<PlaceholderDimensions> dimensions;
  final List<ForumBodyRubyAtomPlan> rubyAtoms;
  final Set<int> trimmedAtomIndices;
  // Legacy column-only access remains explicit: never drop component members
  // or silently present its first column as the complete parent atom.
  late final List<ForumBodyRubyColumnRequest> rubyGroups = List.unmodifiable([
    for (final atom in rubyAtoms)
      atom is ForumBodyRubyColumnPlan
          ? atom.request
          : throw StateError('Inline input contains non-column atoms'),
  ]);
  late final List<ForumBodyRubyLevelMetrics?> rubyLevelMetrics =
      List.unmodifiable([
        for (final atom in rubyAtoms)
          atom is ForumBodyRubyColumnPlan
              ? atom.level
              : throw StateError('Inline input contains non-column atoms'),
      ]);
  final ForumBodyParagraphLayoutMode layoutMode;
  @override
  ForumBodyIdentity get identity => content.identity;
  @override
  int get textCodeUnits => content.projection.display.text.length;
  @override
  int get runCount => content.runs.length;
  // Intrinsic shaping ignores a valid request width. Preserve an empty physical
  // frame's zero width while still passing native input admission explicitly.
  @override
  double requestWidthFor(ForumBodyTextPageFragment fragment) =>
      layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine &&
          fragment.width == 0
      ? 1
      : fragment.width;

  List<int> visibleAtoms(ForumBodyTextPageFragment fragment) {
    if (fragment.kind != ForumBodyTextPageFragmentKind.inline ||
        fragment.path != content.path ||
        fragment.fontRevision != content.fontRevision ||
        fragment.styleRevision != content.styleRevision) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.identity,
      );
    }
    RangeError.checkValidRange(
      fragment.coverageStartUtf16,
      fragment.coverageEndUtf16,
      content.projection.display.text.length,
    );
    final result = <int>[];
    for (final atom in content.projection.atoms) {
      if (atom.displayEndUtf16 <= fragment.coverageStartUtf16) continue;
      if (atom.displayStartUtf16 >= fragment.coverageEndUtf16) break;
      if (atom.displayStartUtf16 < fragment.coverageStartUtf16 ||
          atom.displayEndUtf16 > fragment.coverageEndUtf16) {
        throw const ForumBodyTextPageSurfaceException(
          ForumBodyTextPageSurfaceFailure.geometry,
        );
      }
      if (!trimmedAtomIndices.contains(atom.index)) result.add(atom.index);
    }
    return List.unmodifiable(result);
  }

  @override
  int nativeHandleCountFor(ForumBodyTextPageFragment fragment) =>
      1 +
      visibleAtoms(
        fragment,
      ).fold<int>(0, (sum, index) => sum + rubyAtoms[index].nativeHandleCount);
}

List<ForumBodyRubyAtomPlan> _columnAtoms(
  List<ForumBodyRubyColumnRequest> requests,
  List<ForumBodyRubyLevelMetrics?>? levels,
) {
  if (levels != null && levels.length != requests.length) {
    throw ArgumentError('Invalid inline page targets');
  }
  return [
    for (final (index, request) in requests.indexed)
      ForumBodyRubyAtomPlan.column(request: request, level: levels?[index]),
  ];
}
