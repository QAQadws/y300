import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../document/forum_body_document.dart';
import '../flow/forum_body_text_flow_cursor.dart';
import '../flow/forum_body_styled_flow_cursor.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_block_box.dart';

enum ForumBodyBlockFlowFailure { structure, geometry }

/// The existing body renderer trims adjoining margins at the fragment's outer
/// edges. This is separate from a later page-break margin/decoration policy.
enum ForumBodyBlockEdgeMargins { trim, preserve }

final class ForumBodyBlockFlowException implements Exception {
  const ForumBodyBlockFlowException(this.failure, this.path);
  final ForumBodyBlockFlowFailure failure;
  final String path;
  @override
  String toString() => 'ForumBodyBlockFlowException(${failure.name})';
}

sealed class ForumBodyBlockFlowUnit {
  const ForumBodyBlockFlowUnit._(this.identity);
  final ForumBodyIdentity identity;
}

/// Continuous-flow gap, not a ready-to-apply page margin. Collapsed margins
/// may be negative and never prove that an earlier page is stable. The page
/// layer must resolve break trimming/decoration and admission before applying
/// these values; paragraph spacing cannot be inferred from a single gap alone.
enum ForumBodyBlockSpaceKind { collapsedMargin, paddingTop, paddingBottom }

final class ForumBodyBlockFlowSpace extends ForumBodyBlockFlowUnit {
  const ForumBodyBlockFlowSpace._(
    super.identity,
    this.kind,
    this.extent,
    this.path,
  ) : super._();
  final ForumBodyBlockSpaceKind kind;
  final double extent;

  /// Padding has one owning block. An adjoining margin group can span several
  /// blocks, so it has no fabricated single-node provenance.
  final String? path;
}

final class ForumBodyBlockFlowParagraph extends ForumBodyBlockFlowUnit {
  ForumBodyBlockFlowParagraph._(
    this.paragraph,
    this.contentLeft,
    this.contentWidth,
  ) : super._(paragraph.identity);
  final ForumBodyTextFlowParagraph paragraph;
  final double contentLeft;
  final double contentWidth;
}

/// Structural controls carry resolved horizontal geometry, not a final border
/// rectangle. Adjoining child margins can still move a parent's first content;
/// painting a container background requires the later block fragment layer.
final class ForumBodyBlockFlowBoundary extends ForumBodyBlockFlowUnit {
  ForumBodyBlockFlowBoundary._(this.boundary, this.box, this.contentLeft)
    : super._(boundary.identity);
  final ForumBodyTextFlowBoundary boundary;
  final ForumBodyBlockBox? box;
  final double contentLeft;
}

/// Normal-flow geometry over the sole text cursor. Adjoining signed margins
/// accumulate as max-positive + min-negative across empty blocks and ancestors;
/// real line content or nonzero padding separates groups. Only active frames,
/// one margin strut and at most three pending units are retained. No measuring,
/// native resource, HTML slice, persistent anchor or page publication is owned.
/// Semantic containers/resources require their own format handlers and fail
/// explicitly instead of being treated as empty/transparent ordinary blocks.
final class ForumBodyBlockFlowCursor {
  ForumBodyBlockFlowCursor({
    required ForumBodyDocument document,
    required ForumBodyReaderStyle reader,
    required this.width,
    this.edgeMargins = ForumBodyBlockEdgeMargins.trim,
    ForumBodyParagraphContentBuilder paragraphBuilder =
        const ForumBodyParagraphContentBuilder(),
  }) : _flow = ForumBodyTextFlowCursor(
         document: document,
         reader: reader,
         paragraphBuilder: paragraphBuilder,
       ),
       _rootFontSize = reader.textStyle.fontSize!,
       _rootDirection = reader.textDirection {
    if (!width.isFinite || width <= 0) {
      _flow.close();
      throw ArgumentError.value(width, 'width');
    }
  }
  static const revision = 1;
  final double width;
  final ForumBodyBlockEdgeMargins edgeMargins;
  final double _rootFontSize;
  final TextDirection _rootDirection;
  final ForumBodyTextFlowCursor _flow;
  final _frames = <_Frame>[];
  final _pending = Queue<ForumBodyBlockFlowUnit>();
  final _issues = <ForumBodyStyleIssue>[];
  double _positiveMargin = 0;
  double _negativeMargin = 0;
  ForumBodyBlockFlowUnit? _current;
  bool _complete = false;
  bool _closed = false;
  bool _hasFlowContent = false;

  ForumBodyIdentity get identity => _flow.identity;
  String get fontRevision => _flow.fontRevision;
  int get styleRevision => _flow.styleRevision;
  int get resolvedNodeCount => _flow.resolvedNodeCount;
  ForumBodyBlockFlowUnit? get current => _current;
  bool get isComplete => _complete;
  bool get isClosed => _closed;

  ({int eventsRead, bool hasOutput, bool isComplete}) advance({
    required int maxEvents,
  }) {
    if (_closed) throw StateError('Block flow cursor is closed');
    if (maxEvents <= 0) throw ArgumentError.value(maxEvents, 'maxEvents');
    _current = null;
    if (_complete) return _step(0);
    var read = 0;
    try {
      while (true) {
        if (_pending.isNotEmpty) {
          _current = _pending.removeFirst();
          final unit = _current;
          if (unit is ForumBodyBlockFlowBoundary &&
              unit.boundary.kind == ForumBodyTextFlowBoundaryKind.endDocument) {
            _complete = true;
          }
          return _step(read);
        }
        if (read >= maxEvents) return _step(read);
        final step = _flow.advance(maxEvents: maxEvents - read);
        read += step.eventsRead;
        _issues.addAll(_flow.takePendingIssues());
        final unit = _flow.current;
        if (unit == null) continue;
        switch (unit) {
          case ForumBodyTextFlowParagraph():
            _flushMargins();
            _hasFlowContent = true;
            _pending.add(
              ForumBodyBlockFlowParagraph._(
                unit,
                _frames.isEmpty ? 0 : _frames.last.contentLeft,
                _frames.isEmpty ? width : _frames.last.box.contentWidth,
              ),
            );
          case ForumBodyTextFlowBoundary():
            _boundary(unit);
        }
      }
    } catch (_) {
      close();
      rethrow;
    }
  }

  void _boundary(ForumBodyTextFlowBoundary unit) {
    final event = unit.event;
    switch (unit.kind) {
      case ForumBodyTextFlowBoundaryKind.openBlock:
        final node = event!.node as ForumBodyElement;
        if (!const {
          ForumBodyElementKind.container,
          ForumBodyElementKind.paragraph,
          ForumBodyElementKind.heading,
          ForumBodyElementKind.inline,
          ForumBodyElementKind.unknown,
        }.contains(node.kind)) {
          throw ForumBodyBlockFlowException(
            ForumBodyBlockFlowFailure.structure,
            node.path,
          );
        }
        _validateNormalFlow(node);
        final parent = _frames.lastOrNull;
        final box = ForumBodyBlockBox.resolve(
          style: event.style,
          containingWidth: parent?.box.contentWidth ?? width,
          containingDirection:
              parent?.event.style.textDirection ?? _rootDirection,
          rootFontSize: _rootFontSize,
        );
        final left = (parent?.contentLeft ?? 0) + box.contentLeft;
        if (!left.isFinite) {
          throw const ForumBodyBlockBoxException(
            ForumBodyBlockBoxFailure.geometry,
          );
        }
        _frames.add(_Frame(event, box, left));
        _pending.add(ForumBodyBlockFlowBoundary._(unit, box, left));
        _margin(box.margin.top);
        _padding(
          box.padding.top,
          ForumBodyBlockSpaceKind.paddingTop,
          node.path,
        );
      case ForumBodyTextFlowBoundaryKind.closeBlock:
        if (_frames.isEmpty ||
            !identical(_frames.last.event.node, event!.node)) {
          throw StateError('Unbalanced block flow');
        }
        final frame = _frames.removeLast();
        _padding(
          frame.box.padding.bottom,
          ForumBodyBlockSpaceKind.paddingBottom,
          event.node.path,
        );
        _margin(frame.box.margin.bottom);
        _pending.add(
          ForumBodyBlockFlowBoundary._(unit, frame.box, frame.contentLeft),
        );
      case ForumBodyTextFlowBoundaryKind.endDocument:
        if (_frames.isNotEmpty) throw StateError('Unclosed block flow');
        _flushMargins(endOfDocument: true);
        _pending.add(ForumBodyBlockFlowBoundary._(unit, null, 0));
    }
  }

  void _margin(double value) {
    _positiveMargin = math.max(_positiveMargin, value);
    _negativeMargin = math.min(_negativeMargin, value);
  }

  static void _validateNormalFlow(ForumBodyElement node) {
    // These properties change the adjoining-margin contract or require box
    // geometry not represented by this ordinary port. Do not silently apply
    // normal-flow collapse to a float, positioned box or fixed-height block.
    final effective = <String, ForumBodyDeclaration>{};
    for (final declaration in node.style.declarations) {
      final previous = effective[declaration.property];
      if (previous?.important != true || declaration.important) {
        effective[declaration.property] = declaration;
      }
    }
    for (final declaration in effective.values) {
      final name = declaration.property;
      final raw = declaration.value.trim().toLowerCase();
      final unsupported = switch (name) {
        'height' => raw != 'auto' && raw != 'initial' && raw != 'unset',
        'min-height' => !const {
          '0',
          '0px',
          'auto',
          'initial',
          'unset',
        }.contains(raw),
        'max-height' => !const {'none', 'initial', 'unset'}.contains(raw),
        'position' => !const {'static', 'initial', 'unset'}.contains(raw),
        'float' || 'clear' => !const {'none', 'initial', 'unset'}.contains(raw),
        'overflow' ||
        'overflow-x' ||
        'overflow-y' => !const {'visible', 'initial', 'unset'}.contains(raw),
        'display' => !const {
          'block',
          'inline',
          'none',
          'initial',
          'unset',
          'inherit',
        }.contains(raw),
        'writing-mode' => !const {
          'horizontal-tb',
          'initial',
          'unset',
        }.contains(raw),
        _ =>
          name == 'border' || name.startsWith('border-') || name == 'contain',
      };
      if (unsupported) {
        throw ForumBodyBlockFlowException(
          ForumBodyBlockFlowFailure.geometry,
          node.path,
        );
      }
    }
  }

  void _flushMargins({bool endOfDocument = false}) {
    final extent = _positiveMargin + _negativeMargin;
    _positiveMargin = _negativeMargin = 0;
    if (edgeMargins == ForumBodyBlockEdgeMargins.trim &&
        (!_hasFlowContent || endOfDocument)) {
      return;
    }
    if (extent != 0) {
      _pending.add(
        ForumBodyBlockFlowSpace._(
          identity,
          ForumBodyBlockSpaceKind.collapsedMargin,
          extent,
          null,
        ),
      );
    }
  }

  void _padding(double extent, ForumBodyBlockSpaceKind kind, String path) {
    if (extent == 0) return;
    _flushMargins();
    _hasFlowContent = true;
    _pending.add(ForumBodyBlockFlowSpace._(identity, kind, extent, path));
  }

  ({int eventsRead, bool hasOutput, bool isComplete}) _step(int read) =>
      (eventsRead: read, hasOutput: _current != null, isComplete: _complete);

  List<ForumBodyStyleIssue> takePendingIssues() {
    if (_closed) throw StateError('Block flow cursor is closed');
    final result = List<ForumBodyStyleIssue>.unmodifiable(_issues);
    _issues.clear();
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _flow.close();
    _frames.clear();
    _pending.clear();
    _issues.clear();
    _positiveMargin = _negativeMargin = 0;
    _current = null;
  }
}

final class _Frame {
  const _Frame(this.event, this.box, this.contentLeft);
  final ForumBodyStyledFlowEvent event;
  final ForumBodyBlockBox box;
  final double contentLeft;
}
