import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../flow/forum_body_styled_flow_cursor.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';

import 'forum_body_ruby_content.dart';

/// Resumable ruby grammar over the sole styled IR flow. No font is shaped and
/// no HTML is sliced. Nested ruby stays structured, repeated RTs share their
/// actual base, and RP/annotation whitespace retain explicit source records.
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

  ForumBodyRubyContentCursor._open(
    this._flow,
    this.paragraphBuilder,
    this.limits,
    this._depth,
  ) {
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

  static const revision = 2;
  ForumBodyStyledFlowCursor? _flow;
  ForumBodyStyledFlowEvent? _root;
  ForumBodyStyledFlowEvent? _last;
  final ForumBodyParagraphContentBuilder paragraphBuilder;
  final ForumBodyRubyContentLimits limits;
  final int _depth;
  late final ForumBodyIdentity identity;
  late final String fontRevision;
  late final int styleRevision;
  late final String rootPath;
  late final HtmlSourceTextRange rootSource;
  late final ForumBodyResolvedStyle rootStyle;
  _RubyParts? _base;
  _RubyParts? _annotation;
  final _annotations = <ForumBodyRubyAnnotationContent>[];
  final _ignored = <ForumBodyRubyIgnoredContent>[];
  List<ForumBodyStyledFlowEvent> _whitespace = [];
  Iterator<ForumBodyStyledFlowEvent>? _carryWhitespace;
  ForumBodyStyledFlowEvent? _deferred;
  ForumBodyElement? _skipped;
  _NestedRuby? _nested;
  bool _annotationMode = false;
  bool _complete = false;
  bool _closed = false;
  int _inputCodeUnits = 0;
  int _textRuns = 0;
  int _groupCount = 0;
  int _structureItems = 0;
  int _localIndex = 0;
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
            event = carry.current;
          } else {
            _carryWhitespace = null;
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
    final direct = _parent(node.path) == rootPath;
    if (event.phase == ForumBodyFlowPhase.close) {
      if (_annotation?.root.node.path == node.path) {
        final annotation = _annotation!;
        annotation.flush(keepEmpty: true);
        _item();
        _annotations.add(
          ForumBodyRubyAnnotationContent(
            path: node.path,
            source: node.source,
            style: annotation.root.style,
            parts: annotation.parts,
          ),
        );
        annotation.close();
        _annotation = null;
      }
      return false;
    }
    if (direct &&
        node is ForumBodyElement &&
        (node.kind == ForumBodyElementKind.rubyText ||
            node.kind == ForumBodyElementKind.rubyFallback)) {
      _ignoreWhitespace();
      _annotationMode = true;
      if (node.kind == ForumBodyElementKind.rubyFallback ||
          event.style.hidden) {
        _skip(
          node,
          node.kind == ForumBodyElementKind.rubyFallback
              ? ForumBodyRubyIgnoredReason.fallback
              : ForumBodyRubyIgnoredReason.hidden,
        );
      } else {
        _base!.flush();
        _annotation = _parts(event);
      }
      return false;
    }
    if (event.style.hidden) {
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
    final target = _annotation ?? _base!;
    if (node is ForumBodyElement && node.kind == ForumBodyElementKind.ruby) {
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
    target.sequence ??= paragraphBuilder.openInlineSequence(
      _flow!,
      root: target.root,
    );
    target.sequence!.appendEvent(event);
    return false;
  }

  void _publish() {
    final base = _base!;
    base.flush();
    if (base.parts.isEmpty && _annotations.isEmpty) return;
    _charge(0, 0, 1, 1);
    _current = ForumBodyRubyGroupContent(
      identity: identity,
      fontRevision: fontRevision,
      styleRevision: styleRevision,
      style: rootStyle,
      rootPath: rootPath,
      index: _localIndex++,
      base: base.parts,
      annotations: _annotations,
    );
    base.close();
    _base = _complete ? null : _parts(_root!);
    _annotations.clear();
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
    _annotation?.close();
    _nested?.cursor.close();
    _base = null;
    _annotation = null;
    _nested = null;
    _flow = null;
    _root = null;
    _last = null;
    _skipped = null;
    _current = null;
    _carryWhitespace = null;
    _deferred = null;
    _annotations.clear();
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
