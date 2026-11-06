import '../document/forum_body_document.dart';
import '../inline/forum_body_ruby_content.dart';
import '../inline/forum_body_inline_image_input.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_styled_flow_cursor.dart';

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

final class ForumBodyInlineFlowImage extends ForumBodyInlineFlowPart {
  const ForumBodyInlineFlowImage(this.input);
  final ForumBodyInlineImageInput input;
}

/// A control in the parent source order. It does not create a text run or
/// consume any of its subtree in the parent's inline context.
sealed class ForumBodyInlineFlowExclusion extends ForumBodyInlineFlowPart {
  const ForumBodyInlineFlowExclusion(this.event);

  final ForumBodyStyledFlowEvent event;
  ForumBodyElement get element => event.node as ForumBodyElement;
}

final class ForumBodyInlineFlowFloat extends ForumBodyInlineFlowExclusion {
  const ForumBodyInlineFlowFloat(super.event);
}

/// Retains the authored BR, including its source range, even at a block edge.
final class ForumBodyInlineFlowClear extends ForumBodyInlineFlowExclusion {
  const ForumBodyInlineFlowClear(super.event);
}

/// One unmeasured formatting context from the sole styled traversal. Ordinary
/// fragments retain collapsible edges for the parent format planner; readable
/// ruby retains the independent source contexts of the base and selected level.
/// This is neither a concatenated display projection nor a readable page plan.
final class ForumBodyInlineFlowContent {
  ForumBodyInlineFlowContent({
    required this.identity,
    required this.path,
    required this.fontRevision,
    required this.styleRevision,
    required this.style,
    required this.layoutMode,
    this.appliesFirstLineIndent = true,
    this.trimCollapsibleEdges = true,
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
  final bool appliesFirstLineIndent;

  /// Formatting-context edges only. A structured RB can preserve its actual
  /// leading/trailing spaces; RT and block contexts trim collapsible edges.
  /// Internal adjacent-space collapse and original source fences are unchanged.
  final bool trimCollapsibleEdges;
  final List<ForumBodyInlineFlowPart> parts;

  /// Omissions retain their actual source but do not prove visible coverage.
  final List<ForumBodyRubyIgnoredContent> ignored;
  final List<ForumBodyStyleIssue> issues;
}
