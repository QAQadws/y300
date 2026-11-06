import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../inline/forum_body_ruby_content.dart';
import '../inline/forum_body_inline_image_input.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_first_line_indent.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_inline_flow_content.dart';
import 'forum_body_styled_flow_cursor.dart';

sealed class ForumBodyTextFlowSequenceContent {
  const ForumBodyTextFlowSequenceContent();
}

final class ForumBodyPlainSequenceContent
    extends ForumBodyTextFlowSequenceContent {
  const ForumBodyPlainSequenceContent(this.content);
  final ForumBodyParagraphContent content;
}

final class ForumBodyInlineSequenceContent
    extends ForumBodyTextFlowSequenceContent {
  const ForumBodyInlineSequenceContent(this.content);
  final ForumBodyInlineFlowContent content;
}

/// Format-local assembly only: traversal, deferred BRs and exclusive ruby
/// borrowing belong to TextFlowCursor. No native resource or second flow lives
/// here. Once split, ordinary edges stay available for parent normalization.
final class ForumBodyTextFlowSequence {
  ForumBodyTextFlowSequence({
    required ForumBodyStyledFlowCursor flow,
    required this.block,
    required this.builder,
    required this.layoutMode,
    required this.rubyLimits,
    this.appliesFirstLineIndent = true,
  }) : _flow = flow,
       _removeSourceIndent = flow.removeSourceIndent,
       identity = flow.identity,
       fontRevision = flow.fontRevision,
       styleRevision = flow.styleRevision,
       path = block?.node.path ?? flow.contentRoot?.path,
       style = block?.paragraphStyle ?? flow.rootStyle {
    _plain = _openPlain();
  }

  ForumBodyStyledFlowCursor? _flow;
  ForumBodyStyledFlowEvent? block;
  final ForumBodyParagraphContentBuilder builder;
  final ForumBodyParagraphLayoutMode layoutMode;
  final ForumBodyRubyContentLimits rubyLimits;
  final bool appliesFirstLineIndent;
  final bool _removeSourceIndent;
  final ForumBodyIdentity identity;
  final String fontRevision;
  final int styleRevision;
  final ForumBodyResolvedStyle style;
  ForumBodyParagraphSequence? _plain;
  final issues = <ForumBodyStyleIssue>[];
  final _parts = <ForumBodyInlineFlowPart>[];
  final _ignored = <ForumBodyRubyIgnoredContent>[];
  int _input = 0;
  int _runs = 0;
  int _groups = 0;
  int _items = 0;
  bool _mixed = false;
  bool _visible = false;
  bool _closed = false;
  int? _firstProtectedTextRune;

  final String? path;
  bool get hasContent => _visible || (_plain?.hasDisplayText ?? false);

  ForumBodyParagraphSequence _openPlain() =>
      builder.openSequence(_flow!, block: block, layoutMode: layoutMode);

  void appendEvent(ForumBodyStyledFlowEvent event) {
    _ensureOpen();
    // A protected inline can share a projection with a plain prose prefix.
    // Capture its source fence while the style ancestry is still active.
    if (_removeSourceIndent &&
        _firstProtectedTextRune == null &&
        event.node is ForumBodyText &&
        !event.style.hidden &&
        !_flow!.isOrdinaryProse) {
      _firstProtectedTextRune = event.node.source.runeStart;
    }
    final plain = _plain ??= _openPlain();
    if (!event.style.baselineShift.isEmpty) _mixed = true;
    final before = (plain.inputCodeUnits, plain.runCount);
    plain.appendEvent(event);
    charge(plain.inputCodeUnits - before.$1, plain.runCount - before.$2);
  }

  void startRuby() {
    _ensureOpen();
    _mixed = true;
    _flushPlain();
  }

  void addImage(ForumBodyInlineImageInput input) {
    _ensureOpen();
    _mixed = true;
    _flushPlain();
    charge(input.retainedCodeUnits, 0, 0, 1);
    _parts.add(ForumBodyInlineFlowImage(input));
    _visible = true;
    _plain ??= _openPlain();
  }

  void addExclusion(ForumBodyInlineFlowExclusion control) {
    _ensureOpen();
    _mixed = true;
    _flushPlain();
    charge(0, 0, 0, 1);
    _parts.add(control);
    _visible = true;
    _plain = _openPlain();
  }

  void endRuby() {
    _ensureOpen();
    // Admit the next raw sequence while its containing block is still open;
    // a deferred BR can be appended only after that block has closed.
    _plain ??= _openPlain();
  }

  void addRuby(ForumBodyRubyGroupContent group) {
    _ensureOpen();
    final readable = _readableRuby(group);
    if (readable.base.isEmpty && readable.annotations.isEmpty) return;
    _parts.add(ForumBodyInlineFlowRuby(readable));
    _visible = true;
  }

  ForumBodyRubyGroupContent _readableRuby(ForumBodyRubyGroupContent group) {
    final annotations = group.annotations;
    if (annotations.length < 2) return group;
    var start = 0;
    while (start < annotations.length &&
        annotations[start] is ForumBodyRubyAnnotationContainerContent &&
        annotations[start].parts.isEmpty) {
      start++;
    }
    // Consecutive direct RTs belong to one level, even with several bases.
    // RTCs are separate levels and keep their actual box and style together.
    var end = start;
    if (start < annotations.length) {
      if (annotations[start] is ForumBodyRubyAnnotationContainerContent) {
        end++;
      } else {
        while (end < annotations.length &&
            annotations[end] is ForumBodyRubyTextAnnotationContent) {
          end++;
        }
      }
    }
    if (start == 0 && end == annotations.length) return group;
    for (final (index, annotation) in annotations.indexed) {
      if (index >= start && index < end) continue;
      _ignored.add(
        ForumBodyRubyIgnoredContent(
          annotation.path,
          annotation.source,
          ForumBodyRubyIgnoredReason.unselectedAnnotationLevel,
        ),
      );
    }
    return ForumBodyRubyGroupContent(
      identity: group.identity,
      fontRevision: group.fontRevision,
      styleRevision: group.styleRevision,
      style: group.style,
      rootPath: group.rootPath,
      index: group.index,
      base: group.base,
      annotations: annotations.sublist(start, end),
      annotationGaps: [
        for (final gap in group.annotationGaps)
          if (gap.beforeAnnotationIndex > start &&
              gap.beforeAnnotationIndex < end)
            (
              beforeAnnotationIndex: gap.beforeAnnotationIndex - start,
              content: gap.content,
            ),
      ],
    );
  }

  void addIgnored(List<ForumBodyRubyIgnoredContent> ignored) {
    _ensureOpen();
    _ignored.addAll(ignored);
  }

  void charge(int input, int runs, [int groups = 0, int items = 0]) {
    _ensureOpen();
    _input += input;
    _runs += runs;
    _groups += groups;
    _items += items;
    if (_input > builder.maxInputCodeUnits) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.inputLimit,
        path,
      );
    }
    if (_runs > builder.maxRuns) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.runLimit,
        path,
      );
    }
    if (_groups > rubyLimits.maxGroups) {
      throw ForumBodyRubyContentException(
        ForumBodyRubyContentFailure.groupLimit,
        path,
      );
    }
    if (_items > rubyLimits.maxStructureItems) {
      throw ForumBodyRubyContentException(
        ForumBodyRubyContentFailure.structureLimit,
        path,
      );
    }
  }

  void appendSequence(ForumBodyTextFlowSequence other) {
    _ensureOpen();
    other._ensureOpen();
    if (identical(this, other) ||
        !identical(_flow, other._flow) ||
        path != other.path ||
        !identical(style, other.style) ||
        layoutMode != other.layoutMode) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        path,
      );
    }
    if (!_mixed && !other._mixed) {
      charge(other._input, other._runs, other._groups, other._items);
      _plain!.appendSequence(other._plain!);
      other._plain = null;
    } else {
      _mixed = true;
      _flushPlain();
      other._flushPlain();
      charge(other._input, other._runs, other._groups, other._items);
      _parts.addAll(other._parts);
      _ignored.addAll(other._ignored);
      _visible |= other._visible;
    }
    _firstProtectedTextRune ??= other._firstProtectedTextRune;
    issues.addAll(other.issues);
    other.close();
  }

  void _flushPlain() {
    final plain = _plain;
    _plain = null;
    if (plain == null) return;
    try {
      if (plain.hasInput) {
        _visible |= plain.hasDisplayText;
        charge(0, 0, 0, 1);
        _parts.add(
          ForumBodyInlineFlowText(
            plain.finish(issues: issues, preserveCollapsibleEdges: true),
          ),
        );
      }
    } finally {
      plain.close();
    }
  }

  ForumBodyTextFlowSequenceContent finish() {
    _ensureOpen();
    try {
      if (!_mixed) {
        return ForumBodyPlainSequenceContent(
          _withoutSourceIndent(
            _plain!.finish(issues: issues),
          ).withFirstLineIndent(appliesFirstLineIndent),
        );
      }
      _flushPlain();
      if (_parts.firstOrNull case final ForumBodyInlineFlowText first
          when _removeSourceIndent) {
        final cleaned = _withoutSourceIndent(
          first.content,
          hasFollowingContent: () => _parts
              .skip(1)
              .any(
                (part) => switch (part) {
                  ForumBodyInlineFlowRuby() ||
                  ForumBodyInlineFlowImage() => true,
                  ForumBodyInlineFlowText(:final content) =>
                    content.projection.text.trim().isNotEmpty,
                  ForumBodyInlineFlowExclusion() => false,
                },
              ),
        );
        if (!identical(cleaned, first.content)) {
          if (cleaned.projection.text.isEmpty) {
            _parts.removeAt(0);
          } else {
            _parts[0] = ForumBodyInlineFlowText(cleaned);
          }
        }
      }
      return ForumBodyInlineSequenceContent(
        ForumBodyInlineFlowContent(
          identity: identity,
          path: path,
          fontRevision: fontRevision,
          styleRevision: styleRevision,
          style: style,
          layoutMode: layoutMode,
          appliesFirstLineIndent: appliesFirstLineIndent,
          parts: _parts,
          ignored: _ignored,
          issues: issues,
        ),
      );
    } finally {
      close();
    }
  }

  ForumBodyParagraphContent _withoutSourceIndent(
    ForumBodyParagraphContent content, {
    bool Function()? hasFollowingContent,
  }) {
    final projection = content.projection;
    final text = projection.text;
    if (!_removeSourceIndent ||
        text.isEmpty ||
        !isForumBodyIndentSpace(text.codeUnitAt(0))) {
      return content;
    }
    final protected = _firstProtectedTextRune;
    var end = 0;
    for (final grapheme in projection.graphemeRanges(
      startUtf16: 0,
      endUtf16: text.length,
    )) {
      if (grapheme.endUtf16 - grapheme.startUtf16 != 1 ||
          !isForumBodyIndentSpace(text.codeUnitAt(grapheme.startUtf16))) {
        break;
      }
      if (protected != null &&
          projection
                  .sourceAtUtf16(
                    grapheme.endUtf16,
                    affinity: HtmlProjectionAffinity.upstream,
                  )
                  .sourceRune >
              protected) {
        break;
      }
      end = grapheme.endUtf16;
    }
    // Spacer paragraphs and blank authored lines keep their geometry.
    if (end == 0 ||
        (text.substring(end).trim().isEmpty &&
            hasFollowingContent?.call() != true)) {
      return content;
    }
    return content.displayWindow(startUtf16: end, endUtf16: text.length);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Text flow sequence is closed');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _plain?.close();
    _plain = null;
    _flow = null;
    block = null;
    _parts.clear();
    _ignored.clear();
    issues.clear();
  }
}
