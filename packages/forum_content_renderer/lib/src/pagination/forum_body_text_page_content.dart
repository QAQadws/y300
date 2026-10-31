import 'package:flutter/painting.dart';
import '../document/forum_body_document.dart';

import '../inline/forum_body_inline_span_content.dart';
import '../inline/forum_body_ruby_group_layout.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_text_request.dart';
import 'forum_body_text_page_binding.dart';
import 'forum_body_text_page_composer.dart';

/// Pure source-bound child requests. Dimensions belong to the measured parent
/// plan, not these requests; visible preparation rechecks actual child metrics.
final class ForumBodyRubyPairRequest {
  ForumBodyRubyPairRequest({
    required this.base,
    required this.annotation,
    this.gap = 0,
    this.maxWidth = 16384,
  }) {
    ForumBodyRubyGroupLayout.validateInputs(
      base: base.content,
      annotation: annotation.content,
      gap: gap,
      maxWidth: maxWidth,
    );
  }
  final ForumBodyTextRequest base;
  final ForumBodyTextRequest annotation;
  final double gap;
  final double maxWidth;
  bool get hasAnnotation => annotation.content.projection.text.isNotEmpty;
  int get nativeHandleCount => hasAnnotation ? 2 : 1;
}

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
    required List<ForumBodyRubyPairRequest> rubyGroups,
    ForumBodyParagraphLayoutMode layoutMode,
  }) = ForumBodyInlinePageContent;
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
    required this.content,
    required List<PlaceholderDimensions> dimensions,
    required List<ForumBodyRubyPairRequest> rubyGroups,
    this.layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) : dimensions = List.unmodifiable(dimensions),
       rubyGroups = List.unmodifiable(rubyGroups),
       super._() {
    content.validateDimensions(this.dimensions);
    if (rubyGroups.length != content.projection.atoms.length ||
        layoutMode == ForumBodyParagraphLayoutMode.fitSingleLine) {
      throw ArgumentError('Invalid inline page input');
    }
    final retained = Set<ForumBodyParagraphContent>.identity()
      ..addAll(content.contexts.map((item) => item.content));
    for (final (index, group) in rubyGroups.indexed) {
      content.resolveAtomicContexts(index, [
        group.base.content,
        if (group.hasAnnotation) group.annotation.content,
      ]);
      for (final request in [
        group.base,
        if (group.hasAnnotation) group.annotation,
      ]) {
        // Keep the complete band input inside this already bounded paragraph.
        // An off-input tail must not evade the session's retention accounting.
        if (request is ForumBodyTextBandChildRequest &&
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
  final List<ForumBodyRubyPairRequest> rubyGroups;
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
      result.add(atom.index);
    }
    return List.unmodifiable(result);
  }

  @override
  int nativeHandleCountFor(ForumBodyTextPageFragment fragment) =>
      1 +
      visibleAtoms(
        fragment,
      ).fold<int>(0, (sum, index) => sum + rubyGroups[index].nativeHandleCount);
}
