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

final class ForumBodyRubyAnnotationContent {
  ForumBodyRubyAnnotationContent({
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
  }) : base = List.unmodifiable(base),
       annotations = List.unmodifiable(annotations);
  final ForumBodyIdentity identity;
  final String fontRevision;
  final int styleRevision;
  final ForumBodyResolvedStyle style;
  final String rootPath;
  final int index;
  final List<ForumBodyRubyInlineContent> base;
  final List<ForumBodyRubyAnnotationContent> annotations;
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
