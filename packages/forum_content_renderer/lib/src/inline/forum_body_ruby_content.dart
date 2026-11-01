import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';

sealed class ForumBodyRubyInlineContent {
  const ForumBodyRubyInlineContent();
}

final class ForumBodyRubyTextContent extends ForumBodyRubyInlineContent {
  const ForumBodyRubyTextContent(this.content);
  final ForumBodyParagraphContent content;
}

/// One explicit RB unit. Its boundary, including an empty or whitespace-only
/// unit, must survive until annotation pairing; it is not a transparent span.
final class ForumBodyRubyBaseContent extends ForumBodyRubyInlineContent {
  ForumBodyRubyBaseContent({
    required this.path,
    required this.source,
    required this.style,
    required List<ForumBodyRubyInlineContent> parts,
  }) : parts = List.unmodifiable(parts);
  final String path;
  final HtmlSourceTextRange source;
  final ForumBodyResolvedStyle style;
  final List<ForumBodyRubyInlineContent> parts;
}

final class ForumBodyRubyNestedContent extends ForumBodyRubyInlineContent {
  ForumBodyRubyNestedContent({
    required this.path,
    required this.source,
    required this.style,
    required List<ForumBodyRubyGroupContent> groups,
  }) : groups = List.unmodifiable(groups);
  final String path;
  final HtmlSourceTextRange source;
  final ForumBodyResolvedStyle style;
  final List<ForumBodyRubyGroupContent> groups;
}

sealed class ForumBodyRubyAnnotationContent extends ForumBodyRubyInlineContent {
  factory ForumBodyRubyAnnotationContent({
    required String path,
    required HtmlSourceTextRange source,
    required ForumBodyResolvedStyle style,
    required List<ForumBodyRubyInlineContent> parts,
  }) = ForumBodyRubyTextAnnotationContent;

  ForumBodyRubyAnnotationContent._({
    required this.path,
    required this.source,
    required this.style,
    required List<ForumBodyRubyInlineContent> parts,
  }) : parts = List.unmodifiable(parts);
  final String path;
  final HtmlSourceTextRange source;
  final ForumBodyResolvedStyle style;
  final List<ForumBodyRubyInlineContent> parts;
}

final class ForumBodyRubyTextAnnotationContent
    extends ForumBodyRubyAnnotationContent {
  ForumBodyRubyTextAnnotationContent({
    required super.path,
    required super.source,
    required super.style,
    required super.parts,
  }) : super._();
}

/// One real RTC, not another annotation column. Its ordered parts retain RT
/// boxes, anonymous text, whitespace and nested ruby until level pairing.
final class ForumBodyRubyAnnotationContainerContent
    extends ForumBodyRubyAnnotationContent {
  ForumBodyRubyAnnotationContainerContent({
    required super.path,
    required super.source,
    required super.style,
    required super.parts,
  }) : super._();
}

/// An original root-level whitespace context preceding an actual RT entry.
typedef ForumBodyRubyRootAnnotationGap = ({
  int beforeAnnotationIndex,
  ForumBodyParagraphContent content,
});

/// A stable base segment and all its associated annotations. Empty/unpaired
/// segments remain explicit; unsupported display must never discard their text.
final class ForumBodyRubyGroupContent {
  ForumBodyRubyGroupContent({
    required this.identity,
    required this.fontRevision,
    required this.styleRevision,
    required this.style,
    required this.rootPath,
    required this.index,
    required List<ForumBodyRubyInlineContent> base,
    required List<ForumBodyRubyAnnotationContent> annotations,
    List<ForumBodyRubyRootAnnotationGap> annotationGaps = const [],
  }) : base = List.unmodifiable(base),
       annotations = List.unmodifiable(annotations),
       annotationGaps = annotationGaps.isEmpty
           ? const []
           : List.unmodifiable(annotationGaps);
  final ForumBodyIdentity identity;
  final String fontRevision;
  final int styleRevision;
  final ForumBodyResolvedStyle style;
  final String rootPath;
  final int index;
  final List<ForumBodyRubyInlineContent> base;

  /// Root-level RT and RTC entries in original order. RTC.parts owns its RT
  /// children; neither the container nor those children are flattened here.
  final List<ForumBodyRubyAnnotationContent> annotations;

  /// Real text between consecutive root RTs. The index identifies the original
  /// following annotation entry, including RTC entries; it is not a column.
  final List<ForumBodyRubyRootAnnotationGap> annotationGaps;
}

enum ForumBodyRubyIgnoredReason { fallback, annotationWhitespace, hidden }

/// Structural omission only, not evidence that the enclosed source was read.
final class ForumBodyRubyIgnoredContent {
  const ForumBodyRubyIgnoredContent(this.path, this.source, this.reason);
  final String path;
  final HtmlSourceTextRange source;
  final ForumBodyRubyIgnoredReason reason;
}

enum ForumBodyRubyContentFailure {
  identity,
  structure,
  inputLimit,
  runLimit,
  groupLimit,
  depthLimit,
  structureLimit,
}

final class ForumBodyRubyContentException implements Exception {
  const ForumBodyRubyContentException(this.failure, this.path);
  final ForumBodyRubyContentFailure failure;
  final String? path;
  @override
  String toString() => 'ForumBodyRubyContentException(${failure.name})';
}

final class ForumBodyRubyContentLimits {
  const ForumBodyRubyContentLimits({
    this.maxInputCodeUnits = 16384,
    this.maxTextRuns = 512,
    this.maxGroups = 512,
    this.maxDepth = 96,
    this.maxStructureItems = 512,
  }) : assert(maxInputCodeUnits >= 0),
       assert(maxTextRuns >= 0),
       assert(maxGroups >= 0),
       assert(maxStructureItems >= 0),
       assert(maxDepth > 0);
  final int maxInputCodeUnits;
  final int maxTextRuns;
  final int maxGroups;
  final int maxDepth;
  final int maxStructureItems;
}
