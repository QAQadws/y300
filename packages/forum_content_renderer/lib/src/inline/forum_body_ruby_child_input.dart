import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_ruby_content.dart';

/// A child unit before native planning. A structured sequence remains typed IR;
/// it must never be shaped as a fabricated flat paragraph or a text lease.
sealed class ForumBodyRubyChildInput {
  const ForumBodyRubyChildInput._();

  factory ForumBodyRubyChildInput.base(
    ForumBodyRubyGroupContent group,
    ForumBodyRubyBaseContent base,
  ) => _resolve(group, base.path, base.source, base.style, base.parts);

  factory ForumBodyRubyChildInput.annotation(
    ForumBodyRubyGroupContent group,
    ForumBodyRubyTextAnnotationContent annotation,
  ) => _resolve(
    group,
    annotation.path,
    annotation.source,
    annotation.style,
    annotation.parts,
  );

  /// An anonymous base has no invented DOM source range. Original parts keep
  /// their own source order and nested boundaries until the parent pairs units.
  factory ForumBodyRubyChildInput.implicit(
    ForumBodyRubyGroupContent group,
    List<ForumBodyRubyInlineContent> parts,
  ) => _resolve(group, group.rootPath, null, group.style, parts);

  String? get path;

  /// Only the existing flat-text adapter may request this. Structured inputs
  /// require a real child plan; refusing here keeps capability claims honest.
  ForumBodyParagraphContent requireText() => switch (this) {
    ForumBodyRubyTextChildInput(:final content) => content,
    ForumBodyRubySequenceChildInput() => _unsupported(path),
  };
}

final class ForumBodyRubyTextChildInput extends ForumBodyRubyChildInput {
  const ForumBodyRubyTextChildInput._(this.content) : super._();
  final ForumBodyParagraphContent content;
  @override
  String? get path => content.path;
}

/// Container metadata and original direct parts, not flattened descendant text.
/// An empty nested root is retained even when its groups contain no glyphs.
final class ForumBodyRubySequenceChildInput extends ForumBodyRubyChildInput {
  ForumBodyRubySequenceChildInput._({
    required this.identity,
    required this.fontRevision,
    required this.styleRevision,
    required this.path,
    required this.source,
    required this.style,
    required List<ForumBodyRubyInlineContent> parts,
  }) : parts = List.unmodifiable(parts),
       super._();
  final ForumBodyIdentity identity;
  final String fontRevision;
  final int styleRevision;
  @override
  final String path;
  final HtmlSourceTextRange? source;
  final ForumBodyResolvedStyle style;
  final List<ForumBodyRubyInlineContent> parts;
}

ForumBodyRubyChildInput _resolve(
  ForumBodyRubyGroupContent group,
  String path,
  HtmlSourceTextRange? source,
  ForumBodyResolvedStyle style,
  List<ForumBodyRubyInlineContent> parts,
) {
  for (final part in parts) {
    switch (part) {
      case ForumBodyRubyTextContent(:final content):
        if (content.identity != group.identity ||
            content.fontRevision != group.fontRevision ||
            content.styleRevision != group.styleRevision) {
          _foreign(content.path);
        }
        if (content.layoutMode !=
            ForumBodyParagraphLayoutMode.intrinsicSingleLine) {
          _unsupported(content.path);
        }
      case ForumBodyRubyNestedContent():
        // Check this level only. A recursive planner validates each admitted
        // descendant in its own bounded unit instead of scanning the whole tree.
        for (final nested in part.groups) {
          if (nested.identity != group.identity ||
              nested.fontRevision != group.fontRevision ||
              nested.styleRevision != group.styleRevision ||
              nested.rootPath != part.path) {
            _foreign(nested.rootPath);
          }
        }
      case ForumBodyRubyBaseContent() || ForumBodyRubyAnnotationContent():
        _unsupported(path);
    }
  }
  if (parts.isEmpty) {
    return ForumBodyRubyTextChildInput._(
      ForumBodyParagraphContent.anonymousInline(
        identity: group.identity,
        fontRevision: group.fontRevision,
        styleRevision: group.styleRevision,
        style: style,
      ),
    );
  }
  if (parts.length == 1 && parts.single is ForumBodyRubyTextContent) {
    return ForumBodyRubyTextChildInput._(
      (parts.single as ForumBodyRubyTextContent).content,
    );
  }
  return ForumBodyRubySequenceChildInput._(
    identity: group.identity,
    fontRevision: group.fontRevision,
    styleRevision: group.styleRevision,
    path: path,
    source: source,
    style: style,
    parts: parts,
  );
}

Never _unsupported(String? path) => throw ForumBodyParagraphInputException(
  ForumBodyParagraphInputFailure.structure,
  path,
);
Never _foreign(String? path) => throw ForumBodyParagraphInputException(
  ForumBodyParagraphInputFailure.identity,
  path,
);
