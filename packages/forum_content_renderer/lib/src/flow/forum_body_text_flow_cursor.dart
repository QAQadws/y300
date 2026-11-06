import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_collapse_layout.dart';
import '../document/forum_body_document.dart';
import '../inline/forum_body_inline_image_input.dart';
import '../inline/forum_body_ruby_content.dart';
import '../inline/forum_body_ruby_content_cursor.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_blank_line_filter.dart';
import 'forum_body_styled_flow_cursor.dart';
import 'forum_body_inline_flow_content.dart';
import 'forum_body_text_flow_sequence.dart';

sealed class ForumBodyTextFlowUnit {
  const ForumBodyTextFlowUnit._(this.identity);
  final ForumBodyIdentity identity;
}

final class ForumBodyTextFlowParagraph extends ForumBodyTextFlowUnit {
  ForumBodyTextFlowParagraph._(this.index, this.content, this.window)
    : super._(content.identity);
  final int index;
  final ForumBodyParagraphContent content;
  final ForumBodyParagraphWindow window;
}

/// Unmeasured mixed formatting input, never an ordinary paragraph with its
/// annotation flattened into text. Its parent layout is prepared separately.
final class ForumBodyTextFlowInline extends ForumBodyTextFlowUnit {
  ForumBodyTextFlowInline._(this.index, this.content, this.window)
    : super._(content.identity);
  final int index;
  final ForumBodyInlineFlowContent content;
  final ForumBodyParagraphWindow window;
}

/// A resource keeps its actual source object and a distinct ordered input;
/// zero textual length never becomes an invented paragraph or glyph.
final class ForumBodyTextFlowImage extends ForumBodyTextFlowUnit {
  ForumBodyTextFlowImage._(super.identity, this.index, this.event) : super._();
  final int index;
  final ForumBodyStyledFlowEvent event;
}

/// A real table whose descendants are consumed by the dedicated layout.
final class ForumBodyTextFlowTable extends ForumBodyTextFlowUnit {
  const ForumBodyTextFlowTable._(super.identity, this.event) : super._();
  final ForumBodyStyledFlowEvent event;
  ForumBodyElement get element => event.node as ForumBodyElement;
}

enum ForumBodyTextFlowBoundaryKind { openBlock, closeBlock, endDocument }

/// Block structure remains explicit for the block renderer. A terminal BR
/// omitted by ordinary HTML whitespace rules is retained here with provenance;
/// its source range must not be guessed from the displayed paragraph length.
final class ForumBodyTextFlowBoundary extends ForumBodyTextFlowUnit {
  const ForumBodyTextFlowBoundary._(
    super.identity,
    this.kind,
    this.event,
    this.trimmedTerminalBreak,
  ) : super._();
  final ForumBodyTextFlowBoundaryKind kind;
  final ForumBodyStyledFlowEvent? event;
  final ForumBodyStyledFlowEvent? trimmedTerminalBreak;
}

/// Bounded text partitioning over one styled IR traversal. It retains the open
/// block stack and at most a before/after sequence around one deferred BR, plus
/// the last confirmed break layout input. Each sequence uses the same input/run
/// limits. Ruby exclusively borrows that same flow and remains an unmeasured
/// mixed context. Frozen inline resources use their explicit resolver; other
/// images retain the block resource path. No HTML is sliced or font shaped.
/// Edit notices use a single-line source projection and their own following-BR
/// normalization; ordinary text keeps its original whitespace policy.
final class ForumBodyTextFlowCursor {
  ForumBodyTextFlowCursor({
    required ForumBodyDocument document,
    required ForumBodyReaderStyle reader,
    this.paragraphBuilder = const ForumBodyParagraphContentBuilder(),
    this.rubyLimits = const ForumBodyRubyContentLimits(),
    this.inlineImageResolver,
    ForumBodyCollapseLayout? collapses,
    ForumBodyElement? contentRoot,
    this.dedicatedTables = false,
    this.captureFloats = false,
    this.dedicateFloatedTables = false,
  }) : _tableDocument =
           dedicatedTables && captureFloats && dedicateFloatedTables
           ? document
           : null,
       _tableCollapses = collapses,
       _blankLines = reader.compressBlankLines && contentRoot == null
           ? ForumBodyBlankLineFilter()
           : null,
       _flow = ForumBodyStyledFlowCursor(
         document: document,
         reader: reader,
         collapses: collapses,
         contentRoot: contentRoot,
       );
  static const revision = 17;
  final bool dedicatedTables;

  /// Requires a consumer for exclusion controls, including clearance BRs.
  final bool captureFloats;

  /// Book pages give a whole table its own viewport even inside a float shell.
  final bool dedicateFloatedTables;
  final ForumBodyInlineImageResolver? inlineImageResolver;
  final ForumBodyParagraphContentBuilder paragraphBuilder;
  final ForumBodyRubyContentLimits rubyLimits;
  final ForumBodyStyledFlowCursor _flow;
  ForumBodyBlankLineFilter? _blankLines;
  ForumBodyDocument? _tableDocument;
  ForumBodyCollapseLayout? _tableCollapses;
  final _blocks = <ForumBodyStyledFlowEvent>[];
  final _startedBlocks = <ForumBodyStyledFlowEvent>{};
  final _dedicatedTableShells = <String>{};
  ForumBodyTextFlowImage? _pendingImage;
  String? _delegatedTable;
  String? _inlineAtomClosePath;
  final _emptyListItems = <String, ForumBodyParagraphSequence>{};
  final _issues = <ForumBodyStyleIssue>[];
  ForumBodyTextFlowSequence? _before;
  ForumBodyTextFlowSequence? _after;
  ForumBodyRubyContentCursor? _ruby;
  ForumBodyTextFlowSequence? _rubyTarget;
  ForumBodyStyledFlowEvent? _break;
  List<ForumBodyStyleIssue> _breakIssues = const [];
  ForumBodyTextFlowSequenceContent? _lastConfirmed;
  ForumBodyStyledFlowEvent? _boundary;
  bool _boundaryPending = false;
  ForumBodyStyledFlowEvent? _trimmedBreak;
  ForumBodyTextFlowUnit? _current;
  int _paragraphIndex = 0;
  bool _complete = false;
  bool _closed = false;
  String? _followingEditStatusParent;
  bool _followingEditStatusHasBreak = false;

  bool get _insideEditStatus =>
      _blocks.isNotEmpty &&
      (_blocks.last.node as ForumBodyElement).kind ==
          ForumBodyElementKind.editStatus;

  ForumBodyIdentity get identity => _flow.identity;
  String get fontRevision => _flow.fontRevision;
  int get styleRevision => _flow.styleRevision;
  ForumBodyResolvedStyle get rootStyle => _flow.rootStyle;
  int get resolvedNodeCount => _flow.resolvedNodeCount;
  ForumBodyTextFlowUnit? get current => _current;
  bool get isComplete => _complete;
  bool get isClosed => _closed;

  /// A delivered unit can use zero new events while flushing a known boundary.
  /// One endDocument unit proves this cursor actually consumed its full input;
  /// paragraph-local projections alone are not semantic-anchor evidence.
  ({int eventsRead, int workDone, bool hasOutput, bool isComplete}) advance({
    required int maxEvents,
  }) {
    if (_closed) throw StateError('Text flow cursor is closed');
    if (maxEvents <= 0) throw ArgumentError.value(maxEvents, 'maxEvents');
    _current = null;
    var read = 0;
    var work = 0;
    if (_complete) return _step(read, work);
    try {
      while (true) {
        if (_pendingImage case final image?) {
          _pendingImage = null;
          _markContent();
          _current = image;
          return _step(read, work + 1);
        }
        if (_boundaryPending) {
          if (_flushContext()) return _step(read, work);
          final event = _boundary;
          final table = event != null && event.node.path == _delegatedTable;
          if (event?.phase == ForumBodyFlowPhase.open &&
              (table ||
                  (event!.node as ForumBodyElement).kind ==
                      ForumBodyElementKind.rule) &&
              _emptyListItems.isNotEmpty) {
            final entry = _emptyListItems.entries.last;
            _emptyListItems.remove(entry.key);
            _paragraph(
              ForumBodyPlainSequenceContent(entry.value.finish()),
              ForumBodyParagraphWindow.full,
            );
            return _step(read, work);
          }
          if (event?.phase == ForumBodyFlowPhase.close) {
            final empty = _emptyListItems.remove(event!.node.path);
            if (empty != null) {
              // This proof was opened while the real item was still active.
              // Keep its actual empty source; the marker is never inserted.
              _paragraph(
                ForumBodyPlainSequenceContent(empty.finish()),
                ForumBodyParagraphWindow.full,
              );
              return _step(read, work);
            }
          }
          _boundary = null;
          _boundaryPending = false;
          if (table) {
            _markContent();
            _current = ForumBodyTextFlowTable._(identity, event);
            _trimmedBreak = null;
            return _step(read, work);
          }
          final kind = event == null
              ? ForumBodyTextFlowBoundaryKind.endDocument
              : event.phase == ForumBodyFlowPhase.open
              ? ForumBodyTextFlowBoundaryKind.openBlock
              : ForumBodyTextFlowBoundaryKind.closeBlock;
          if (kind == ForumBodyTextFlowBoundaryKind.openBlock) {
            _blocks.add(event!);
            if ((event.node as ForumBodyElement).kind ==
                ForumBodyElementKind.image) {
              _pendingImage = ForumBodyTextFlowImage._(
                identity,
                _paragraphIndex++,
                event,
              );
            }
            if (event.style.display == ForumBodyDisplay.listItem) {
              _emptyListItems[event.node.path] = paragraphBuilder.openSequence(
                _flow,
                block: event,
              );
            }
          } else if (kind == ForumBodyTextFlowBoundaryKind.closeBlock) {
            if (_blocks.isEmpty || !identical(_blocks.last.node, event!.node)) {
              throw StateError('Unbalanced text flow block');
            }
            _startedBlocks.remove(_blocks.removeLast());
            if ((event.node as ForumBodyElement).kind ==
                ForumBodyElementKind.editStatus) {
              _followingEditStatusParent = _parentPath(event.node.path);
              _followingEditStatusHasBreak = false;
            }
          } else {
            if (_blocks.isNotEmpty) {
              throw StateError('Unclosed text flow block');
            }
            _complete = true;
          }
          _current = ForumBodyTextFlowBoundary._(
            identity,
            kind,
            event,
            _trimmedBreak,
          );
          _trimmedBreak = null;
          return _step(read, work);
        }
        if (work >= maxEvents) return _step(read, work);
        final ruby = _ruby;
        if (ruby != null) {
          final target = _rubyTarget!;
          final before = (
            ruby.inputCodeUnits,
            ruby.textRunCount,
            ruby.groupCount,
            ruby.structureItemCount,
          );
          final step = ruby.advance(maxEvents: maxEvents - work);
          read += step.eventsRead;
          work += step.workDone;
          final issues = _flow.takePendingIssues();
          _issues.addAll(issues);
          target.issues.addAll(issues);
          target.charge(
            ruby.inputCodeUnits - before.$1,
            ruby.textRunCount - before.$2,
            ruby.groupCount - before.$3,
            ruby.structureItemCount - before.$4,
          );
          if (step.hasOutput) target.addRuby(ruby.current!);
          target.addIgnored(ruby.takeIgnored());
          if (step.isComplete) {
            target.endRuby();
            ruby.close();
            _ruby = null;
            _rubyTarget = null;
          }
          continue;
        }
        if (!_flow.moveNext()) {
          _boundaryPending = true;
          continue;
        }
        read++;
        work++;
        final event = _flow.current!;
        final issues = _flow.takePendingIssues();
        _issues.addAll(issues);
        if (_skipFollowingEditStatus(event)) continue;
        if (_blankLines?.omit(_flow, event) == true) continue;
        if (event.phase == ForumBodyFlowPhase.close &&
            _dedicatedTableShells.remove(event.node.path)) {
          continue;
        }
        if (event.style.hidden) continue;
        if (event.phase == ForumBodyFlowPhase.close &&
            event.node.path == _delegatedTable) {
          _delegatedTable = null;
          continue;
        }
        if (event.phase == ForumBodyFlowPhase.close &&
            event.node.path == _inlineAtomClosePath) {
          _inlineAtomClosePath = null;
          continue;
        }
        if (event.phase == ForumBodyFlowPhase.open &&
            event.node is ForumBodyElement) {
          final element = event.node as ForumBodyElement;
          if (_dedicatedTableShells.contains(element.path)) continue;
          final isDedicatedTable =
              dedicatedTables &&
              !_insideEditStatus &&
              element.kind == ForumBodyElementKind.table &&
              event.style.display == ForumBodyDisplay.table;
          if (captureFloats &&
              !_insideEditStatus &&
              !(dedicateFloatedTables && isDedicatedTable) &&
              _captureExclusion(event, element, issues)) {
            continue;
          }
          if (isDedicatedTable) {
            _flow.skipCurrentSubtree(event);
            _delegatedTable = element.path;
            _boundaryPending = true;
            _boundary = event;
            continue;
          }
          if (element.kind == ForumBodyElementKind.image &&
              (event.style.display == ForumBodyDisplay.inline ||
                  event.style.display == ForumBodyDisplay.inlineBlock) &&
              !event.style.visibilityHidden &&
              !_insideEditStatus) {
            final image = inlineImageResolver?.call(
              identity,
              element,
              event.style,
            );
            if (_closed || _flow.isClosed) {
              throw StateError('Inline image resolver retired its flow');
            }
            if (image != null) {
              if (image.identity != identity ||
                  !identical(image.element, element)) {
                throw ForumBodyParagraphInputException(
                  ForumBodyParagraphInputFailure.identity,
                  element.path,
                );
              }
              final target = _break == null
                  ? (_before ??= _newSequence())
                  : (_after ??= _newSequence(continuation: true));
              target.issues.addAll(issues);
              target.addImage(image);
              _inlineAtomClosePath = element.path;
              continue;
            }
          }
        }
        if (_isBlock(event)) {
          if (_insideEditStatus && event.phase != ForumBodyFlowPhase.close) {
            throw ForumBodyParagraphInputException(
              ForumBodyParagraphInputFailure.structure,
              event.node.path,
            );
          }
          _boundaryPending = true;
          _boundary = event;
          continue;
        }
        if (event.phase == ForumBodyFlowPhase.close) continue;
        if (event.node is ForumBodyElement &&
            (event.node as ForumBodyElement).kind ==
                ForumBodyElementKind.hardBreak) {
          if (_insideEditStatus) {
            final target = _before ??= _newSequence();
            target.appendEvent(event);
            target.issues.addAll(issues);
            continue;
          }
          if (_break != null) {
            final content = _confirmBreak();
            _before = _after ?? _newSequence(continuation: true);
            _after = null;
            _break = event;
            _breakIssues = issues;
            _paragraph(
              content,
              ForumBodyParagraphWindow.beforeTerminalEmptyLine,
            );
            return _step(read, work);
          }
          _before ??= _newSequence();
          _break = event;
          _breakIssues = issues;
        } else {
          final target = _break == null
              ? (_before ??= _newSequence())
              : (_after ??= _newSequence(continuation: true));
          target.issues.addAll(issues);
          if (event.node is ForumBodyElement &&
              (event.node as ForumBodyElement).kind ==
                  ForumBodyElementKind.ruby) {
            target.startRuby();
            _rubyTarget = target;
            _ruby = ForumBodyRubyContentCursor.openCurrent(
              _flow,
              paragraphBuilder: paragraphBuilder,
              limits: rubyLimits,
            );
          } else {
            target.appendEvent(event);
          }
        }
      }
    } catch (_) {
      close();
      rethrow;
    }
  }

  bool _captureExclusion(
    ForumBodyStyledFlowEvent event,
    ForumBodyElement element,
    List<ForumBodyStyleIssue> issues,
  ) {
    final ForumBodyInlineFlowExclusion control;
    if (element.kind == ForumBodyElementKind.hardBreak) {
      if (!_clearsFloats(event.style)) return false;
      control = ForumBodyInlineFlowClear(event);
    } else {
      final side = event.style.floatSide;
      if (side != ForumBodyFloatSide.left && side != ForumBodyFloatSide.right) {
        return false;
      }
      if (dedicatedTables &&
          dedicateFloatedTables &&
          _openDedicatedTableShell(element)) {
        return true;
      }
      control = ForumBodyInlineFlowFloat(event);
    }
    _flow.skipCurrentSubtree(event);
    _inlineAtomClosePath = element.path;
    final target = _break == null
        ? (_before ??= _newSequence())
        : (_after ??= _newSequence(continuation: true));
    target.issues.addAll(issues);
    target.addExclusion(control);
    return true;
  }

  /// A book table owns its viewport. Consume only the surrounding float
  /// declaration and let the normal flow emit its text and the actual table.
  bool _openDedicatedTableShell(ForumBodyElement element) {
    final document = _tableDocument;
    if (document == null ||
        (element.kind != ForumBodyElementKind.inline &&
            element.kind != ForumBodyElementKind.container)) {
      return false;
    }
    for (final table in document.tablesBelow(element)) {
      if (_tableCollapses?.hidesPath(table.path) == true ||
          document
              .ancestryOf(table)!
              .any(
                (node) =>
                    node.kind != ForumBodyElementKind.collapseContent &&
                    node.style.value('display')?.trim().toLowerCase() == 'none',
              )) {
        continue;
      }
      _dedicatedTableShells.add(element.path);
      return true;
    }
    return false;
  }

  static bool _clearsFloats(ForumBodyResolvedStyle style) =>
      switch (style.clear) {
        ForumBodyClear.left ||
        ForumBodyClear.right ||
        ForumBodyClear.both => true,
        ForumBodyClear.none || ForumBodyClear.unsupported => false,
      };

  static String _parentPath(String path) {
    final separator = path.lastIndexOf('/');
    return separator < 0 ? '' : path.substring(0, separator);
  }

  bool _skipFollowingEditStatus(ForumBodyStyledFlowEvent event) {
    final parent = _followingEditStatusParent;
    if (parent == null) return false;
    final node = event.node;
    if (_parentPath(node.path) == parent) {
      if (node is ForumBodyText &&
          node.text.runes.every(
            HtmlDisplayTextProjection.isSingleLineWhitespace,
          )) {
        // Until the first BR, keep raw whitespace in the normal sequence.
        // Preformatted text must survive if no structural break follows.
        return _followingEditStatusHasBreak;
      }
      if (node is ForumBodyElement &&
          node.kind == ForumBodyElementKind.hardBreak &&
          !(captureFloats && _clearsFloats(event.style))) {
        _followingEditStatusHasBreak = true;
        _before?.close();
        _before = null;
        return true;
      }
    }
    _followingEditStatusParent = null;
    _followingEditStatusHasBreak = false;
    return false;
  }

  bool _flushContext() {
    if (_break != null) {
      final preserve =
          _break!.style.whiteSpace == ForumBodyWhiteSpace.pre ||
          _blocks.any((block) => (block.node as ForumBodyElement).tag == 'pre');
      if ((_after?.hasContent ?? false) || preserve) {
        final content = _confirmBreak();
        _before = _after;
        _after = null;
        _paragraph(content, ForumBodyParagraphWindow.beforeTerminalEmptyLine);
        return true;
      }
      _trimmedBreak = _break;
      _break = null;
      _breakIssues = const [];
      final after = _after;
      if (after != null) {
        _before!.appendSequence(after);
        _after = null;
      }
    }
    final before = _before;
    _before = null;
    if (before != null) {
      if (before.hasContent) {
        final content = before.finish();
        _lastConfirmed = null;
        _paragraph(content, ForumBodyParagraphWindow.full);
        return true;
      }
      before.close();
    }
    final tail = _lastConfirmed;
    if (tail != null) {
      _lastConfirmed = null;
      _paragraph(tail, ForumBodyParagraphWindow.terminalEmptyLine);
      return true;
    }
    return false;
  }

  ForumBodyTextFlowSequenceContent _confirmBreak() {
    final before = _before!;
    before.appendEvent(_break!);
    before.issues.addAll(_breakIssues);
    final content = before.finish();
    _before = null;
    _break = null;
    _breakIssues = const [];
    _lastConfirmed = content;
    return content;
  }

  ForumBodyTextFlowSequence _newSequence({bool continuation = false}) =>
      ForumBodyTextFlowSequence(
        flow: _flow,
        block: _blocks.isEmpty ? null : _blocks.last,
        builder: paragraphBuilder,
        rubyLimits: rubyLimits,
        appliesFirstLineIndent:
            !continuation &&
            (_blocks.isEmpty || !_startedBlocks.contains(_blocks.last)),
        layoutMode: _insideEditStatus
            ? ForumBodyParagraphLayoutMode.fitSingleLine
            : ForumBodyParagraphLayoutMode.wrap,
      );

  void _paragraph(
    ForumBodyTextFlowSequenceContent content,
    ForumBodyParagraphWindow window,
  ) {
    _markContent();
    final index = _paragraphIndex++;
    _current = switch (content) {
      ForumBodyPlainSequenceContent() => ForumBodyTextFlowParagraph._(
        index,
        content.content,
        window,
      ),
      ForumBodyInlineSequenceContent() => ForumBodyTextFlowInline._(
        index,
        content.content,
        window,
      ),
    };
  }

  void _markContent() {
    _startedBlocks.addAll(_blocks);
    for (final block in _blocks) {
      _emptyListItems.remove(block.node.path)?.close();
    }
  }

  static bool _isBlock(ForumBodyStyledFlowEvent event) =>
      event.node is ForumBodyElement &&
      (event.node as ForumBodyElement).kind != ForumBodyElementKind.hardBreak &&
      ((event.node as ForumBodyElement).kind == ForumBodyElementKind.image ||
          const {
            ForumBodyDisplay.block,
            ForumBodyDisplay.listItem,
            ForumBodyDisplay.table,
            ForumBodyDisplay.tableRow,
            ForumBodyDisplay.tableCell,
          }.contains(event.style.display));

  ({int eventsRead, int workDone, bool hasOutput, bool isComplete}) _step(
    int read,
    int work,
  ) => (
    eventsRead: read,
    workDone: work,
    hasOutput: _current != null,
    isComplete: _complete,
  );

  List<ForumBodyStyleIssue> takePendingIssues() {
    if (_closed) throw StateError('Text flow cursor is closed');
    final issues = List<ForumBodyStyleIssue>.unmodifiable(_issues);
    _issues.clear();
    return issues;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _ruby?.close();
    _ruby = null;
    _rubyTarget = null;
    _before?.close();
    _after?.close();
    _flow.close();
    _blankLines = null;
    _before = null;
    _after = null;
    _break = null;
    _breakIssues = const [];
    _lastConfirmed = null;
    _boundary = null;
    _trimmedBreak = null;
    _followingEditStatusParent = null;
    _blocks.clear();
    _startedBlocks.clear();
    _dedicatedTableShells.clear();
    _tableDocument = null;
    _tableCollapses = null;
    _pendingImage = null;
    _inlineAtomClosePath = null;
    for (final proof in _emptyListItems.values) {
      proof.close();
    }
    _emptyListItems.clear();
    _issues.clear();
    _current = null;
  }
}
