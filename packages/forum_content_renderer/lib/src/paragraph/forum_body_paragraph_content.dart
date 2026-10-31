import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../flow/forum_body_styled_flow_cursor.dart';
import '../style/forum_body_length.dart';
import '../style/forum_body_paint_text_style.dart';
import '../style/forum_body_style_options.dart';

enum ForumBodyParagraphInputFailure {
  identity,
  structure,
  inputLimit,
  runLimit,
}

/// Single-line callers supply a projection without hard breaks. Fitting uses
/// a paint transform after the actual per-size TextScaler; intrinsic layout
/// reports its natural width without fitting, clipping or changing font size.
enum ForumBodyParagraphLayoutMode { wrap, fitSingleLine, intrinsicSingleLine }

final class ForumBodyParagraphInputException implements Exception {
  const ForumBodyParagraphInputException(this.failure, this.path);
  final ForumBodyParagraphInputFailure failure;
  final String? path;
  @override
  String toString() => 'ForumBodyParagraphInputException(${failure.name})';
}

final class ForumBodyParagraphRun {
  const ForumBodyParagraphRun(this.path, this.style);
  final String path;
  final ForumBodyResolvedStyle style;
}

/// One text paragraph's display text and styles, without DOM or Host state.
/// The source projection is not a persisted novel semantic coordinate.
final class ForumBodyParagraphContent {
  ForumBodyParagraphContent._({
    required this.identity,
    required this.path,
    required this.fontRevision,
    required this.styleRevision,
    required this.style,
    required this.layoutMode,
    required this.projection,
    required List<ForumBodyParagraphRun> runs,
    required List<ForumBodyStyleIssue> issues,
  }) : runs = List.unmodifiable(runs),
       issues = List.unmodifiable(issues);

  final ForumBodyIdentity identity;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final ForumBodyResolvedStyle style;
  final ForumBodyParagraphLayoutMode layoutMode;
  final HtmlDisplayTextProjection projection;
  final List<ForumBodyParagraphRun> runs;
  final List<ForumBodyStyleIssue> issues;

  /// No recognizers are retained; interaction uses the same layout coordinates.
  late final TextSpan textSpan = TextSpan(
    style: style.textStyle,
    children: [
      for (final part in projection.parts)
        TextSpan(
          text: part.text,
          style: forumBodyPaintTextStyle(runs[part.runIndex].style),
        ),
    ],
  );
}

/// Complex containers/resources require their own block/inline layout. They
/// cannot pass through this ordinary paragraph port and silently lose content.
final class ForumBodyParagraphContentBuilder {
  const ForumBodyParagraphContentBuilder({
    this.maxInputCodeUnits = 16384,
    this.maxRuns = 512,
  }) : assert(maxInputCodeUnits >= 0),
       assert(maxRuns >= 0);
  final int maxInputCodeUnits;
  final int maxRuns;

  ForumBodyParagraphContent build({
    required ForumBodyDocument document,
    required ForumBodyStyleResult styles,
    String? path,
    ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) {
    if (document.identity != styles.identity) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        path,
      );
    }
    final root = path == null ? null : document.nodeAtPath(path);
    if (path != null && root == null) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        path,
      );
    }
    final base = path == null ? styles.root : styles.byPath[path];
    if (base == null) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        path,
      );
    }
    final pending = <Iterator<ForumBodyNode>>[
      (root == null ? document.nodes : [root]).iterator,
    ];
    final collector = _ParagraphCollector(
      identity: document.identity,
      path: path,
      fontRevision: styles.fontRevision,
      styleRevision: styles.resolverRevision,
      style: base,
      layoutMode: layoutMode,
      singleLineWhitespace:
          root is ForumBodyElement &&
          root.kind == ForumBodyElementKind.editStatus,
      limits: this,
      emptySourceRune: root?.source.runeStart ?? 0,
    );
    try {
      while (pending.isNotEmpty) {
        if (!pending.last.moveNext()) {
          pending.removeLast();
          continue;
        }
        final node = pending.last.current;
        final style = styles.byPath[node.path];
        if (style == null) {
          throw ForumBodyParagraphInputException(
            ForumBodyParagraphInputFailure.identity,
            node.path,
          );
        }
        if (collector.visit(node, style, isRoot: identical(node, root))) {
          pending.add((node as ForumBodyElement).children.iterator);
        }
      }
      return collector.finish(styles.issues);
    } finally {
      collector.close();
    }
  }

  /// Consume the current ordinary subtree without a full style map. The flow is
  /// borrowed exclusively until the accumulator completes or closes; it remains
  /// owned by the caller. Diagnostics remain with that flow's consumer.
  ForumBodyParagraphAccumulator openCurrent(
    ForumBodyStyledFlowCursor flow, {
    ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) {
    if (flow.isClosed) throw StateError('Styled flow cursor is closed');
    final event = flow.current;
    if (event == null || event.phase == ForumBodyFlowPhase.close) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        event?.node.path,
      );
    }
    final collector = _ParagraphCollector(
      identity: flow.identity,
      path: event.node.path,
      fontRevision: flow.fontRevision,
      styleRevision: flow.styleRevision,
      style: event.style,
      layoutMode: layoutMode,
      singleLineWhitespace:
          event.node is ForumBodyElement &&
          (event.node as ForumBodyElement).kind ==
              ForumBodyElementKind.editStatus,
      limits: this,
      emptySourceRune: event.node.source.runeStart,
    );
    try {
      collector.visit(event.node, event.style, isRoot: true);
      return ForumBodyParagraphAccumulator._(flow, collector, event);
    } catch (_) {
      collector.close();
      rethrow;
    }
  }

  /// Start an inline sequence inside a currently open containing block, or the
  /// anonymous document context. The caller advances the flow and appends its
  /// ordered inline/text events; no complete style map or copied IR is used.
  ForumBodyParagraphSequence openSequence(
    ForumBodyStyledFlowCursor flow, {
    ForumBodyStyledFlowEvent? block,
    ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) {
    if (flow.isClosed) throw StateError('Styled flow cursor is closed');
    if (block != null &&
        (!flow.owns(block) ||
            !flow.isOpenElement(block) ||
            block.phase != ForumBodyFlowPhase.open ||
            block.style.display == ForumBodyDisplay.inline)) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        block.node.path,
      );
    }
    return ForumBodyParagraphSequence._(
      flow,
      _ParagraphCollector(
        identity: flow.identity,
        path: block?.node.path,
        fontRevision: flow.fontRevision,
        styleRevision: flow.styleRevision,
        style: block?.style ?? flow.rootStyle,
        layoutMode: layoutMode,
        singleLineWhitespace:
            block?.node is ForumBodyElement &&
            (block!.node as ForumBodyElement).kind ==
                ForumBodyElementKind.editStatus,
        limits: this,
        emptySourceRune:
            block?.node.source.runeStart ??
            flow.current?.node.source.runeStart ??
            0,
      ),
    );
  }

  /// Text-only fragment inside an already admitted inline formatting root.
  /// The format consumer handles the root itself and partitions its children;
  /// this port does not admit ruby/resources into an ordinary paragraph.
  ForumBodyParagraphSequence openInlineSequence(
    ForumBodyStyledFlowCursor flow, {
    required ForumBodyStyledFlowEvent root,
    ForumBodyParagraphLayoutMode layoutMode =
        ForumBodyParagraphLayoutMode.intrinsicSingleLine,
  }) {
    if (flow.isClosed) throw StateError('Styled flow cursor is closed');
    final node = root.node;
    if (!flow.owns(root) ||
        !flow.isOpenElement(root) ||
        root.phase != ForumBodyFlowPhase.open ||
        node is! ForumBodyElement) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        node.path,
      );
    }
    if (!const {
          ForumBodyElementKind.inline,
          ForumBodyElementKind.unknown,
          ForumBodyElementKind.ruby,
          ForumBodyElementKind.rubyText,
        }.contains(node.kind) ||
        root.style.hidden ||
        root.style.display != ForumBodyDisplay.inline ||
        !_ParagraphCollector._inlineBoxIsEmpty(root.style)) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.structure,
        node.path,
      );
    }
    return ForumBodyParagraphSequence._(
      flow,
      _ParagraphCollector(
        identity: flow.identity,
        path: node.path,
        fontRevision: flow.fontRevision,
        styleRevision: flow.styleRevision,
        style: root.style,
        layoutMode: layoutMode,
        singleLineWhitespace: false,
        preserveCollapsibleEdges: true,
        limits: this,
        emptySourceRune: node.source.runeStart,
      ),
    );
  }
}

/// Inline sequence assembly owned by one structural flow. It does not advance
/// the borrowed cursor, allowing its owner to partition at real hard breaks or
/// block boundaries while preserving author inheritance and source run order.
final class ForumBodyParagraphSequence {
  ForumBodyParagraphSequence._(this._flow, this._collector);
  ForumBodyStyledFlowCursor? _flow;
  final _ParagraphCollector _collector;
  ForumBodyStyledFlowEvent? _last;
  int? _firstIndex;
  bool _closed = false;
  bool get isClosed => _closed;
  bool get hasInput => !_closed && _collector.hasInput;
  bool get hasDisplayText => !_closed && _collector.projection.text.isNotEmpty;

  void appendCurrent() => _append(_flow?.current);

  /// One deferred hard-break event can be appended after bounded lookahead.
  /// Token ownership and monotonic event order still apply.
  void appendEvent(ForumBodyStyledFlowEvent event) => _append(event);

  void _append(ForumBodyStyledFlowEvent? event) {
    if (_closed) throw StateError('Paragraph sequence is closed');
    try {
      final flow = _flow!;
      if (flow.isClosed) throw StateError('Styled flow cursor is closed');
      final path = _collector.path;
      if (event == null ||
          !flow.owns(event) ||
          (_last != null && event.index <= _last!.index) ||
          event.phase == ForumBodyFlowPhase.close ||
          (path != null && !event.node.path.startsWith('$path/'))) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.identity,
          event?.node.path,
        );
      }
      _collector.visit(event.node, event.style, isRoot: false);
      _firstIndex ??= event.index;
      _last = event;
    } catch (_) {
      close();
      rethrow;
    }
  }

  /// Consume another same-context raw sequence without normalizing whitespace
  /// twice. This preserves CRLF/collapse behavior around a discarded terminal
  /// BR. On failure only the receiver retires; the caller still owns [other].
  void appendSequence(ForumBodyParagraphSequence other) {
    if (_closed) throw StateError('Paragraph sequence is closed');
    try {
      if (other._closed ||
          identical(this, other) ||
          !identical(_flow, other._flow) ||
          _flow!.isClosed ||
          (_last != null &&
              other._firstIndex != null &&
              other._firstIndex! <= _last!.index)) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.identity,
          _collector.path,
        );
      }
      _collector.absorb(other._collector);
      _firstIndex ??= other._firstIndex;
      _last = other._last ?? _last;
      other.close();
    } catch (_) {
      close();
      rethrow;
    }
  }

  ForumBodyParagraphContent finish({
    Iterable<ForumBodyStyleIssue> issues = const [],
  }) {
    if (_closed) throw StateError('Paragraph sequence is closed');
    try {
      if (_flow!.isClosed) throw StateError('Styled flow cursor is closed');
      return _collector.finish(issues);
    } finally {
      close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _flow = null;
    _last = null;
    _collector.close();
  }
}

/// A bounded ordinary paragraph consumer. Progress limits count structural
/// events, including hidden nodes and closing containers. Native shaping occurs
/// later; finishing a paragraph does not confirm page or semantic coverage.
final class ForumBodyParagraphAccumulator {
  ForumBodyParagraphAccumulator._(
    this._flow,
    this._collector,
    ForumBodyStyledFlowEvent event,
  ) : _last = event,
      _complete = event.phase == ForumBodyFlowPhase.text;

  ForumBodyStyledFlowCursor? _flow;
  final _ParagraphCollector _collector;
  ForumBodyStyledFlowEvent? _last;
  bool _complete;
  bool _closed = false;
  bool get isComplete => _complete;
  bool get isClosed => _closed;

  int advance({required int maxEvents}) {
    if (_closed) throw StateError('Paragraph accumulator is closed');
    if (maxEvents <= 0) throw ArgumentError.value(maxEvents, 'maxEvents');
    if (_complete) return 0;
    try {
      final flow = _flow!;
      if (flow.isClosed) throw StateError('Styled flow cursor is closed');
      if (!identical(flow.current, _last)) _invalid();
      var consumed = 0;
      while (consumed < maxEvents && !_complete) {
        if (!flow.moveNext()) _invalid();
        final event = flow.current!;
        _last = event;
        consumed++;
        final path = _collector.path!;
        if (event.node.path == path) {
          if (event.phase != ForumBodyFlowPhase.close) _invalid();
          _complete = true;
          _flow = null;
        } else {
          if (!event.node.path.startsWith('$path/')) _invalid();
          if (event.phase != ForumBodyFlowPhase.close) {
            _collector.visit(event.node, event.style, isRoot: false);
          }
        }
      }
      return consumed;
    } catch (_) {
      close();
      rethrow;
    }
  }

  Never _invalid() => throw ForumBodyParagraphInputException(
    ForumBodyParagraphInputFailure.identity,
    _collector.path,
  );

  /// Issue ownership stays with the flow caller; only this subtree's issues
  /// belong in the resulting paragraph. The returned value owns immutable data.
  ForumBodyParagraphContent finish({
    Iterable<ForumBodyStyleIssue> issues = const [],
  }) {
    if (_closed) throw StateError('Paragraph accumulator is closed');
    if (!_complete) throw StateError('Paragraph subtree is not complete');
    try {
      return _collector.finish(issues);
    } finally {
      close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _flow = null;
    _last = null;
    _collector.close();
  }
}

/// One implementation of structure admission, limits and whitespace projection
/// for both the eager compatibility port and resumable IR consumption.
final class _ParagraphCollector {
  _ParagraphCollector({
    required this.identity,
    required this.path,
    required this.fontRevision,
    required this.styleRevision,
    required this.style,
    required this.layoutMode,
    required this.singleLineWhitespace,
    required this.limits,
    required this.emptySourceRune,
    this.preserveCollapsibleEdges = false,
  });
  final ForumBodyIdentity identity;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final ForumBodyResolvedStyle style;
  final ForumBodyParagraphLayoutMode layoutMode;
  final bool singleLineWhitespace;
  final ForumBodyParagraphContentBuilder limits;
  final int emptySourceRune;
  final bool preserveCollapsibleEdges;
  final _inputs = <HtmlDisplayTextRun>[];
  final _runs = <ForumBodyParagraphRun>[];
  HtmlDisplayTextProjection? _projection;
  int _inputSize = 0;
  bool get hasInput => _inputs.isNotEmpty;

  HtmlDisplayTextProjection get projection =>
      _projection ??= HtmlDisplayTextProjection.build(
        _inputs.isEmpty
            ? [HtmlDisplayTextRun(text: '', sourceRuneStart: emptySourceRune)]
            : _inputs,
        maxOutputCodeUnits: limits.maxInputCodeUnits,
        preserveCollapsibleEdges: preserveCollapsibleEdges,
      );

  void absorb(_ParagraphCollector other) {
    if (identity != other.identity ||
        path != other.path ||
        layoutMode != other.layoutMode ||
        singleLineWhitespace != other.singleLineWhitespace ||
        preserveCollapsibleEdges != other.preserveCollapsibleEdges ||
        !identical(style, other.style)) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        path,
      );
    }
    if (_inputSize + other._inputSize > limits.maxInputCodeUnits) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.inputLimit,
        path,
      );
    }
    if (_inputs.length + other._inputs.length > limits.maxRuns) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.runLimit,
        path,
      );
    }
    _inputSize += other._inputSize;
    _inputs.addAll(other._inputs);
    _runs.addAll(other._runs);
    _projection = null;
  }

  bool visit(
    ForumBodyNode node,
    ForumBodyResolvedStyle style, {
    required bool isRoot,
  }) {
    if (style.hidden) return false;
    if (node is ForumBodyElement &&
        node.kind != ForumBodyElementKind.hardBreak) {
      final ordinaryRoot =
          isRoot &&
          const {
            ForumBodyElementKind.paragraph,
            ForumBodyElementKind.heading,
            ForumBodyElementKind.container,
            ForumBodyElementKind.editStatus,
          }.contains(node.kind);
      final ordinaryInline =
          const {
            ForumBodyElementKind.inline,
            ForumBodyElementKind.unknown,
          }.contains(node.kind) &&
          style.display == ForumBodyDisplay.inline &&
          _inlineBoxIsEmpty(style);
      if (!ordinaryRoot && !ordinaryInline) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.structure,
          node.path,
        );
      }
      return true;
    }
    final text = node is ForumBodyText ? node.text : '\n';
    _inputSize += text.length;
    if (_inputSize > limits.maxInputCodeUnits) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.inputLimit,
        node.path,
      );
    }
    if (_inputs.length >= limits.maxRuns) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.runLimit,
        node.path,
      );
    }
    _inputs.add(
      HtmlDisplayTextRun(
        text: text,
        sourceRuneStart: node.source.runeStart,
        hardBreak: node is ForumBodyElement,
        whiteSpace: singleLineWhitespace
            ? HtmlDisplayWhiteSpace.singleLine
            : switch (style.whiteSpace) {
                ForumBodyWhiteSpace.normal => HtmlDisplayWhiteSpace.normal,
                ForumBodyWhiteSpace.pre => HtmlDisplayWhiteSpace.pre,
                ForumBodyWhiteSpace.preWrap => HtmlDisplayWhiteSpace.preWrap,
                ForumBodyWhiteSpace.preLine => HtmlDisplayWhiteSpace.preLine,
              },
      ),
    );
    _projection = null;
    _runs.add(ForumBodyParagraphRun(node.path, style));
    return false;
  }

  ForumBodyParagraphContent finish(Iterable<ForumBodyStyleIssue> issues) =>
      ForumBodyParagraphContent._(
        identity: identity,
        path: path,
        fontRevision: fontRevision,
        styleRevision: styleRevision,
        style: style,
        layoutMode: layoutMode,
        projection: projection,
        runs: _runs,
        issues: issues
            .where(
              (issue) =>
                  path == null ||
                  issue.path == path ||
                  issue.path.startsWith('$path/'),
            )
            .toList(),
      );

  void close() {
    _inputs.clear();
    _runs.clear();
    _projection = null;
  }

  static bool _inlineBoxIsEmpty(ForumBodyResolvedStyle style) =>
      [
        style.margin.left,
        style.margin.right,
        style.padding.top,
        style.padding.right,
        style.padding.bottom,
        style.padding.left,
      ].every(
        (length) =>
            length.unit != ForumBodyLengthUnit.auto && length.value == 0,
      );
}
