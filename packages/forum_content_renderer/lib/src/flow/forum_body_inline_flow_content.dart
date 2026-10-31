import '../document/forum_body_document.dart';
import '../inline/forum_body_ruby_content.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';

sealed class ForumBodyInlineFlowPart {
  const ForumBodyInlineFlowPart();
}

final class ForumBodyInlineFlowText extends ForumBodyInlineFlowPart {
  const ForumBodyInlineFlowText(this.content);
  final ForumBodyParagraphContent content;
}

final class ForumBodyInlineFlowRuby extends ForumBodyInlineFlowPart {
  const ForumBodyInlineFlowRuby(this.group);
  final ForumBodyRubyGroupContent group;
}

/// One unmeasured formatting context from the sole styled traversal. Ordinary
/// fragments retain collapsible edges for the parent format planner; ruby
/// retains nested/multiple annotations and each independent source context.
/// This is neither a concatenated display projection nor a readable page plan.
final class ForumBodyInlineFlowContent {
  ForumBodyInlineFlowContent({
    required this.identity,
    required this.path,
    required this.fontRevision,
    required this.styleRevision,
    required this.style,
    required this.layoutMode,
    required List<ForumBodyInlineFlowPart> parts,
    required List<ForumBodyRubyIgnoredContent> ignored,
    required List<ForumBodyStyleIssue> issues,
  }) : parts = List.unmodifiable(parts),
       ignored = List.unmodifiable(ignored),
       issues = List.unmodifiable(issues);

  final ForumBodyIdentity identity;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final ForumBodyResolvedStyle style;
  final ForumBodyParagraphLayoutMode layoutMode;
  final List<ForumBodyInlineFlowPart> parts;

  /// Omissions retain their actual source but do not prove visible coverage.
  final List<ForumBodyRubyIgnoredContent> ignored;
  final List<ForumBodyStyleIssue> issues;
}
