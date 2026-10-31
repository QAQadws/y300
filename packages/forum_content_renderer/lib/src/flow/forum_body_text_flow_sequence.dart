import '../document/forum_body_document.dart';
import '../inline/forum_body_ruby_content.dart';
import '../paragraph/forum_body_paragraph_content.dart';
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
  }) : _flow = flow,
       identity = flow.identity,
       fontRevision = flow.fontRevision,
       styleRevision = flow.styleRevision,
       style = block?.style ?? flow.rootStyle {
    _plain = _openPlain();
  }

  ForumBodyStyledFlowCursor? _flow;
  ForumBodyStyledFlowEvent? block;
  final ForumBodyParagraphContentBuilder builder;
  final ForumBodyParagraphLayoutMode layoutMode;
  final ForumBodyRubyContentLimits rubyLimits;
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

  String? get path => block?.node.path;
  bool get hasDisplayText => _visible || (_plain?.hasDisplayText ?? false);

  ForumBodyParagraphSequence _openPlain() =>
      builder.openSequence(_flow!, block: block, layoutMode: layoutMode);

  void appendEvent(ForumBodyStyledFlowEvent event) {
    _ensureOpen();
    final plain = _plain ??= _openPlain();
    final before = (plain.inputCodeUnits, plain.runCount);
    plain.appendEvent(event);
    charge(plain.inputCodeUnits - before.$1, plain.runCount - before.$2);
  }

  void startRuby() {
    _ensureOpen();
    _mixed = true;
    _flushPlain();
  }

  void endRuby() {
    _ensureOpen();
    // Admit the next raw sequence while its containing block is still open;
    // a deferred BR can be appended only after that block has closed.
    _plain ??= _openPlain();
  }

  void addRuby(ForumBodyRubyGroupContent group) {
    _ensureOpen();
    _parts.add(ForumBodyInlineFlowRuby(group));
    // The grammar publishes only an actual base or annotation structure. A
    // structured group is retained even when a later format cannot render it.
    _visible = true;
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
        return ForumBodyPlainSequenceContent(_plain!.finish(issues: issues));
      }
      _flushPlain();
      return ForumBodyInlineSequenceContent(
        ForumBodyInlineFlowContent(
          identity: identity,
          path: path,
          fontRevision: fontRevision,
          styleRevision: styleRevision,
          style: style,
          layoutMode: layoutMode,
          parts: _parts,
          ignored: _ignored,
          issues: issues,
        ),
      );
    } finally {
      close();
    }
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
