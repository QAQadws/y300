import 'package:forum_content_renderer/forum_text.dart';

import '../document/forum_body_document.dart';
import '../flow/forum_body_styled_flow_cursor.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';

import 'forum_body_ruby_content.dart';

/// Resumable ruby grammar over the sole styled IR flow. No font is shaped and
/// no HTML is sliced. The readable entry collects nested bases into their
/// enclosing text sequence. The structural entry preserves authored units.
///
/// Borrows the cursor exclusively until complete/close. Style diagnostics stay
/// with the flow's owner, which can drain them between bounded advances.
final class ForumBodyRubyContentCursor {
  factory ForumBodyRubyContentCursor.openCurrent(
    ForumBodyStyledFlowCursor flow, {
    ForumBodyParagraphContentBuilder paragraphBuilder =
        const ForumBodyParagraphContentBuilder(),
    ForumBodyRubyContentLimits limits = const ForumBodyRubyContentLimits(),
  }) => ForumBodyRubyContentCursor._open(flow, paragraphBuilder, limits, 1);

  factory ForumBodyRubyContentCursor.openReadable(
    ForumBodyStyledFlowCursor flow, {
    required ForumBodyParagraphContentBuilder paragraphBuilder,
    required ForumBodyRubyContentLimits limits,
  }) => ForumBodyRubyContentCursor._open(
    flow,
    paragraphBuilder,
    limits,
    1,
    flattenNested: true,
  );

  ForumBodyRubyContentCursor._open(
    this._flow,
    this.paragraphBuilder,
    this.limits,
    this._depth, {
    bool flattenNested = false,
  }) : _flattenNested = flattenNested {
    final flow = _flow!;
    if (flow.isClosed) throw StateError('Styled flow cursor is closed');
    final event = flow.current;
    final node = event?.node;
    if (event == null ||
        event.phase != ForumBodyFlowPhase.open ||
        node is! ForumBodyElement ||
        node.kind != ForumBodyElementKind.ruby ||
        !flow.isOpenElement(event)) {
      throw ForumBodyRubyContentException(
        ForumBodyRubyContentFailure.identity,
        node?.path,
      );
    }
    if (_depth > limits.maxDepth) {
      throw ForumBodyRubyContentException(
        ForumBodyRubyContentFailure.depthLimit,
        node.path,
      );
    }
    _root = event;
    _last = event;
    rootPath = node.path;
    rootSource = node.source;
    rootStyle = event.style;
    identity = flow.identity;
    fontRevision = flow.fontRevision;
    styleRevision = flow.styleRevision;
    if (event.style.hidden) {
      _ignore(
        ForumBodyRubyIgnoredContent(
          node.path,
          node.source,
          ForumBodyRubyIgnoredReason.hidden,
        ),
      );
    } else {
      _base = _parts(event);
    }
  }

  static const revision = 7;
  ForumBodyStyledFlowCursor? _flow;
  ForumBodyStyledFlowEvent? _root;
  ForumBodyStyledFlowEvent? _last;
  final ForumBodyParagraphContentBuilder paragraphBuilder;
  final ForumBodyRubyContentLimits limits;
  final int _depth;
  final bool _flattenNested;
  late final ForumBodyIdentity identity;
  late final String fontRevision;
  late final int styleRevision;
  late final String rootPath;
  late final HtmlSourceTextRange rootSource;
  late final ForumBodyResolvedStyle rootStyle;
  _RubyParts? _base;
  _RubyParts? _explicitBase;
  _RubyParts? _annotation;
  _RubyParts? _annotationContainer;
  final _annotations = <ForumBodyRubyAnnotationContent>[];
  final _annotationGaps = <ForumBodyRubyRootAnnotationGap>[];
  ForumBodyParagraphSequence? _annotationGap;
  final _ignored = <ForumBodyRubyIgnoredContent>[];
  List<ForumBodyStyledFlowEvent> _whitespace = [];
  Iterator<ForumBodyStyledFlowEvent>? _carryWhitespace;
  ForumBodyStyledFlowEvent? _deferred;
  ForumBodyElement? _skipped;
  _NestedRuby? _nested;
  int _flattenedDepth = 0;
  bool _annotationMode = false;
  bool _complete = false;
  bool _closed = false;
  int _inputCodeUnits = 0;
  int _textRuns = 0;
  int _groupCount = 0;
  int _structureItems = 0;
  int _localIndex = 0;
  int _orphanColumns = 0;
  ForumBodyRubyGroupContent? _current;

  bool get isComplete => _complete;
  bool get isClosed => _closed;
  int get inputCodeUnits => _inputCodeUnits;
  int get textRunCount => _textRuns;
  int get groupCount => _groupCount;
  int get structureItemCount => _structureItems;
  ForumBodyRubyGroupContent? get current => _current;

  List<ForumBodyRubyIgnoredContent> takeIgnored() {
    if (_closed) throw StateError('Ruby content cursor is closed');
    final result = List<ForumBodyRubyIgnoredContent>.unmodifiable(_ignored);
    _ignored.clear();
    return result;
  }

  _RubyParts _parts(ForumBodyStyledFlowEvent root) => _RubyParts(
    root,
    paragraphBuilder.openInlineSequence(_flow!, root: root),
    _item,
  );

  /// Work includes replay of the bounded one-event/whitespace lookahead. New
  /// flow reads are counted separately, so deferral cannot bypass maxEvents.
  ({int eventsRead, int workDone, bool hasOutput, bool isComplete}) advance({
    required int maxEvents,
  }) {
    if (_closed) throw StateError('Ruby content cursor is closed');
    if (maxEvents <= 0) throw ArgumentError.value(maxEvents);
    _current = null;
    if (_complete) {
      return (eventsRead: 0, workDone: 0, hasOutput: false, isComplete: true);
    }
    var read = 0;
    var work = 0;
    try {
      final flow = _flow!;
      if (flow.isClosed || !identical(flow.current, _last)) {
        _fail(ForumBodyRubyContentFailure.identity);
      }
      while (!_complete && work < maxEvents) {
        final nested = _nested;
        if (nested != null) {
          final child = nested.cursor;
          final before = (
            child.inputCodeUnits,
            child.textRunCount,
            child.groupCount,
            child.structureItemCount,
          );
          final step = child.advance(maxEvents: maxEvents - work);
          read += step.eventsRead;
          work += step.workDone;
          _last = flow.current;
          _charge(
            child.inputCodeUnits - before.$1,
            child.textRunCount - before.$2,
            child.groupCount - before.$3,
            child.structureItemCount - before.$4,
          );
          _ignored.addAll(child.takeIgnored());
          if (step.hasOutput) nested.groups.add(child.current!);
          if (step.isComplete) {
            _item();
            nested.target.parts.add(
              ForumBodyRubyNestedContent(
                path: child.rootPath,
                source: child.rootSource,
                style: child.rootStyle,
                groups: nested.groups,
              ),
            );
            child.close();
            _nested = null;
          }
          continue;
        }
        ForumBodyStyledFlowEvent? event;
        final carry = _carryWhitespace;
        if (carry != null) {
          if (carry.moveNext()) {
            final gap = _annotationGap;
            if (gap != null) {
              gap.appendEvent(carry.current);
              work++;
              continue;
            }
            event = carry.current;
          } else {
            _carryWhitespace = null;
            final gap = _annotationGap;
            if (gap != null) {
              _annotationGap = null;
              try {
                _item();
                _annotationGaps.add((
                  beforeAnnotationIndex: _annotations.length,
                  content: gap.finish(),
                ));
              } finally {
                gap.close();
              }
              work++;
              continue;
            }
          }
        }
        if (event == null) {
          event = _deferred;
          _deferred = null;
        }
        if (event == null) {
          if (!flow.moveNext()) _fail(ForumBodyRubyContentFailure.identity);
          event = flow.current!;
          _last = event;
          read++;
          final node = event.node;
          if (event.phase == ForumBodyFlowPhase.text && node is ForumBodyText) {
            _charge(node.text.length, 1, 0);
          } else if (event.phase == ForumBodyFlowPhase.open &&
              node is ForumBodyElement &&
              node.kind == ForumBodyElementKind.hardBreak) {
            _charge(1, 1, 0);
          }
        }
        work++;
        if (_consume(event)) break;
      }
      return (
        eventsRead: read,
        workDone: work,
        hasOutput: _current != null,
        isComplete: _complete,
      );
    } catch (_) {
      close();
      rethrow;
    }
  }

  bool _consume(ForumBodyStyledFlowEvent event) {
    final node = event.node;
    if (node.path == rootPath) {
      if (event.phase != ForumBodyFlowPhase.close) {
        _fail(ForumBodyRubyContentFailure.identity);
      }
      _ignoreWhitespace();
      _complete = true;
      if (!rootStyle.hidden) _publish();
      return _current != null;
    }
    if (!node.path.startsWith('$rootPath/')) {
      _fail(ForumBodyRubyContentFailure.identity);
    }
    if (rootStyle.hidden) return false;
    final skipped = _skipped;
    if (skipped != null) {
      if (node.path == skipped.path &&
          event.phase == ForumBodyFlowPhase.close) {
        _skipped = null;
      }
      return false;
    }
    if (_flattenedDepth > 0) {
      _consumeFlattenedRuby(event);
      return false;
    }
    final direct = _parent(node.path) == rootPath;
    if (event.phase == ForumBodyFlowPhase.close) {
      if (_explicitBase?.root.node.path == node.path) {
        final base = _explicitBase!;
        base.flush(keepEmpty: true);
        _item();
        _base!.parts.add(
          ForumBodyRubyBaseContent(
            path: node.path,
            source: node.source,
            style: base.root.style,
            parts: base.parts,
          ),
        );
        base.close();
        _explicitBase = null;
      }
      if (_annotation?.root.node.path == node.path) {
        final annotation = _annotation!;
        annotation.flush(keepEmpty: true);
        _item();
        final value = ForumBodyRubyAnnotationContent(
          path: node.path,
          source: node.source,
          style: annotation.root.style,
          parts: annotation.parts,
        );
        final container = _annotationContainer;
        if (container == null) {
          _annotations.add(value);
          if (_base!.parts.isEmpty) {
            // Keep the prior orphan-column limit even though publication now
            // waits for all annotation levels of this segment to be known.
            _charge(0, 0, 1);
            _orphanColumns++;
          }
        } else {
          container.parts.add(value);
        }
        annotation.close();
        _annotation = null;
      }
      if (_annotationContainer?.root.node.path == node.path) {
        final container = _annotationContainer!;
        container.flush();
        _item();
        _annotations.add(
          ForumBodyRubyAnnotationContainerContent(
            path: node.path,
            source: node.source,
            style: container.root.style,
            parts: container.parts,
          ),
        );
        container.close();
        _annotationContainer = null;
      }
      return false;
    }
    if (node is ForumBodyElement &&
        node.kind == ForumBodyElementKind.rubyAnnotationContainer) {
      if (!direct || _annotationContainer != null || _annotation != null) {
        _fail(ForumBodyRubyContentFailure.structure);
      }
      _annotationMode = true;
      if (event.style.hidden) {
        _skip(node, ForumBodyRubyIgnoredReason.hidden);
      } else {
        _ignoreWhitespace();
        _base!.flush();
        _annotationContainer = _parts(event);
      }
      return false;
    }
    final annotationParent = _annotationContainer?.root.node.path ?? rootPath;
    if (_parent(node.path) == annotationParent &&
        node is ForumBodyElement &&
        (node.kind == ForumBodyElementKind.rubyText ||
            node.kind == ForumBodyElementKind.rubyFallback)) {
      if (direct) {
        _annotationMode = true;
        if (node.kind == ForumBodyElementKind.rubyText && !event.style.hidden) {
          if (_whitespace.isNotEmpty &&
              _annotations.lastOrNull is ForumBodyRubyTextAnnotationContent) {
            _annotationGap = paragraphBuilder.openInlineSequence(
              _flow!,
              root: _root!,
              suppressLineBreaks: true,
            );
            _carryWhitespace = _whitespace.iterator;
            _whitespace = [];
            _deferred = event;
            return false;
          }
          _ignoreWhitespace();
        }
      }
      if (node.kind == ForumBodyElementKind.rubyFallback ||
          event.style.hidden) {
        _skip(
          node,
          node.kind == ForumBodyElementKind.rubyFallback
              ? ForumBodyRubyIgnoredReason.fallback
              : ForumBodyRubyIgnoredReason.hidden,
        );
      } else {
        (_annotationContainer ?? _base!).flush();
        _annotation = _parts(event);
      }
      return false;
    }
    if (event.style.hidden) {
      _ignoreHidden(node);
      return false;
    }
    if (direct && _annotationMode) {
      if (node is ForumBodyText && node.text.runes.every(_interElementSpace)) {
        _whitespace.add(event);
        return false;
      }
      _carryWhitespace = _whitespace.iterator;
      _whitespace = [];
      _deferred = event;
      _annotationMode = false;
      _publish();
      return _current != null;
    }
    if (node is ForumBodyElement &&
        node.kind == ForumBodyElementKind.rubyBase) {
      if (!direct ||
          _explicitBase != null ||
          _annotation != null ||
          _annotationContainer != null) {
        _fail(ForumBodyRubyContentFailure.structure);
      }
      _base!.flush();
      _explicitBase = _parts(event);
      return false;
    }
    if (node is ForumBodyElement && node.kind == ForumBodyElementKind.ruby) {
      if (_flattenNested) {
        _enterFlattenedRuby();
        return false;
      }
      final target = _activeParts;
      target.flush();
      _nested = _NestedRuby(
        ForumBodyRubyContentCursor._open(
          _flow!,
          paragraphBuilder,
          limits,
          _depth + 1,
        ),
        target,
      );
      return false;
    }
    if (node is ForumBodyElement &&
        (node.kind == ForumBodyElementKind.rubyText ||
            node.kind == ForumBodyElementKind.rubyFallback)) {
      _fail(ForumBodyRubyContentFailure.structure);
    }
    _appendToActiveParts(event);
    return false;
  }

  _RubyParts get _activeParts =>
      _explicitBase ?? _annotation ?? _annotationContainer ?? _base!;

  void _appendToActiveParts(ForumBodyStyledFlowEvent event) {
    final target = _activeParts;
    target.sequence ??= paragraphBuilder.openInlineSequence(
      _flow!,
      root: target.root,
    );
    target.sequence!.appendEvent(event);
  }

  void _enterFlattenedRuby() {
    if (++_flattenedDepth + _depth > limits.maxDepth) {
      _fail(ForumBodyRubyContentFailure.depthLimit);
    }
    _item();
  }

  void _consumeFlattenedRuby(ForumBodyStyledFlowEvent event) {
    final node = event.node;
    if (event.phase == ForumBodyFlowPhase.close) {
      if (node is ForumBodyElement && node.kind == ForumBodyElementKind.ruby) {
        _flattenedDepth--;
      }
      return;
    }
    if (event.style.hidden) {
      _ignoreHidden(node);
      return;
    }
    if (node is ForumBodyElement) {
      switch (node.kind) {
        case ForumBodyElementKind.ruby:
          _enterFlattenedRuby();
          return;
        case ForumBodyElementKind.rubyBase:
          _item();
          return;
        case ForumBodyElementKind.rubyText ||
            ForumBodyElementKind.rubyAnnotationContainer:
          _skip(node, ForumBodyRubyIgnoredReason.nestedAnnotation);
          return;
        case ForumBodyElementKind.rubyFallback:
          _skip(node, ForumBodyRubyIgnoredReason.fallback);
          return;
        default:
          break;
      }
    }
    // Keep the same collector open across wrappers so its whitespace and
    // source-run rules apply to the resulting ordinary text together.
    _appendToActiveParts(event);
  }

  void _ignoreHidden(ForumBodyNode node) {
    if (node is ForumBodyElement) {
      _skip(node, ForumBodyRubyIgnoredReason.hidden);
    } else {
      _ignore(
        ForumBodyRubyIgnoredContent(
          node.path,
          node.source,
          ForumBodyRubyIgnoredReason.hidden,
        ),
      );
    }
  }

  void _publish() {
    final base = _base!;
    base.flush();
    if (base.parts.isEmpty && _annotations.isEmpty) return;
    _charge(0, 0, _orphanColumns == 0 ? 1 : 0, 1);
    _current = ForumBodyRubyGroupContent(
      identity: identity,
      fontRevision: fontRevision,
      styleRevision: styleRevision,
      style: rootStyle,
      rootPath: rootPath,
      index: _localIndex++,
      base: base.parts,
      annotations: _annotations,
      annotationGaps: _annotationGaps,
    );
    base.close();
    _base = _complete ? null : _parts(_root!);
    _annotations.clear();
    _annotationGaps.clear();
    _orphanColumns = 0;
  }

  void _ignoreWhitespace() {
    for (final event in _whitespace) {
      _ignore(
        ForumBodyRubyIgnoredContent(
          event.node.path,
          event.node.source,
          ForumBodyRubyIgnoredReason.annotationWhitespace,
        ),
      );
    }
    _whitespace = [];
  }

  void _skip(ForumBodyElement node, ForumBodyRubyIgnoredReason reason) {
    _ignore(ForumBodyRubyIgnoredContent(node.path, node.source, reason));
    _skipped = node;
  }

  void _item() => _charge(0, 0, 0, 1);
  void _ignore(ForumBodyRubyIgnoredContent value) {
    _item();
    _ignored.add(value);
  }

  void _charge(int codeUnits, int runs, int groups, [int items = 0]) {
    _inputCodeUnits += codeUnits;
    _textRuns += runs;
    _groupCount += groups;
    _structureItems += items;
    if (_inputCodeUnits > limits.maxInputCodeUnits) {
      _fail(ForumBodyRubyContentFailure.inputLimit);
    }
    if (_textRuns > limits.maxTextRuns) {
      _fail(ForumBodyRubyContentFailure.runLimit);
    }
    if (_groupCount > limits.maxGroups) {
      _fail(ForumBodyRubyContentFailure.groupLimit);
    }
    if (_structureItems > limits.maxStructureItems) {
      _fail(ForumBodyRubyContentFailure.structureLimit);
    }
  }

  Never _fail(ForumBodyRubyContentFailure failure) =>
      throw ForumBodyRubyContentException(
        failure,
        _last?.node.path ?? rootPath,
      );
  static String _parent(String path) {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }

  static bool _interElementSpace(int rune) =>
      const {9, 10, 12, 13, 32}.contains(rune);

  void close() {
    if (_closed) return;
    _closed = true;
    _base?.close();
    _explicitBase?.close();
    _annotation?.close();
    _annotationContainer?.close();
    _annotationGap?.close();
    _nested?.cursor.close();
    _base = null;
    _explicitBase = null;
    _annotation = null;
    _annotationContainer = null;
    _annotationGap = null;
    _nested = null;
    _flattenedDepth = 0;
    _flow = null;
    _root = null;
    _last = null;
    _skipped = null;
    _current = null;
    _carryWhitespace = null;
    _deferred = null;
    _annotations.clear();
    _annotationGaps.clear();
    _ignored.clear();
    _whitespace.clear();
  }
}

final class _RubyParts {
  _RubyParts(this.root, this.sequence, this.onItem);
  final ForumBodyStyledFlowEvent root;
  ForumBodyParagraphSequence? sequence;
  final void Function() onItem;
  final parts = <ForumBodyRubyInlineContent>[];
  void flush({bool keepEmpty = false}) {
    final value = sequence;
    sequence = null;
    if (value == null) return;
    try {
      if (value.hasInput || keepEmpty && parts.isEmpty) {
        onItem();
        parts.add(ForumBodyRubyTextContent(value.finish()));
      }
    } finally {
      value.close();
    }
  }

  void close() {
    sequence?.close();
    sequence = null;
    parts.clear();
  }
}

final class _NestedRuby {
  _NestedRuby(this.cursor, this.target);
  final ForumBodyRubyContentCursor cursor;
  final _RubyParts target;
  final groups = <ForumBodyRubyGroupContent>[];
}
