import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../contracts/forum_collapse_header_metrics.dart';
import '../document/forum_body_collapse_layout.dart';
import '../document/forum_body_document.dart';
import '../inline/forum_body_ruby_content.dart';
import '../inline/forum_body_inline_image_input.dart';
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

/// Resolve intrinsic marker width before advancing into this item's children.
final class ForumBodyBlockFlowListItemStart extends ForumBodyBlockFlowUnit {
  ForumBodyBlockFlowListItemStart._(
    super.identity,
    this.marker,
    this.availableGutter,
  ) : super._();
  final ForumBodyListItemMarker marker;
  final double availableGutter;
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
    this.listMarkers,
  ) : super._(paragraph.identity);
  final ForumBodyTextFlowParagraph paragraph;
  final double contentLeft;
  final double contentWidth;
  final List<ForumBodyListItemMarker> listMarkers;
}

final class ForumBodyBlockFlowInline extends ForumBodyBlockFlowUnit {
  ForumBodyBlockFlowInline._(
    this.paragraph,
    this.contentLeft,
    this.contentWidth,
    this.listMarkers,
  ) : super._(paragraph.identity);
  final ForumBodyTextFlowInline paragraph;
  final double contentLeft;
  final double contentWidth;
  final List<ForumBodyListItemMarker> listMarkers;
}

final class ForumBodyBlockFlowImage extends ForumBodyBlockFlowUnit {
  ForumBodyBlockFlowImage._(
    this.image,
    this.contentLeft,
    this.contentWidth,
    this.listMarkers,
  ) : super._(image.identity);
  final ForumBodyTextFlowImage image;
  final double contentLeft, contentWidth;
  final List<ForumBodyListItemMarker> listMarkers;
}

/// A first-content marker specification tied to the actual owning item.
/// It has no paragraph projection, source coordinate or measured glyph box.
final class ForumBodyListItemMarker {
  ForumBodyListItemMarker._({
    required this.listPath,
    required this.itemPath,
    required this.ordinal,
    required this.style,
    required this.contentLeft,
    required this.contentWidth,
  }) : text = style.listStyle.labelFor(ordinal);
  final String? listPath;
  final String itemPath;
  final int ordinal;
  final ForumBodyResolvedStyle style;
  final String? text;
  final double contentLeft;
  final double contentWidth;
}

/// A normal-flow thematic break. It has no text/source projection or native
/// paragraph. Width and margins use the same resolved box as adjacent text.
final class ForumBodyBlockFlowRule extends ForumBodyBlockFlowUnit {
  const ForumBodyBlockFlowRule._(
    super.identity,
    this.path,
    this.left,
    this.width,
    this.color,
  ) : super._();
  final String path;
  final double left;
  final double width;
  final Color color;
  double get thickness => 1;
}

/// Structural controls carry resolved horizontal geometry, not a final border
/// rectangle. Adjoining child margins can still move a parent's first content;
/// the page composer resolves its actual background start and continuation.
final class ForumBodyBlockFlowBoundary extends ForumBodyBlockFlowUnit {
  ForumBodyBlockFlowBoundary._(
    this.boundary,
    this.box,
    this.contentLeft, {
    this.collapseTitle,
  }) : super._(boundary.identity);
  final ForumBodyTextFlowBoundary boundary;
  final ForumBodyBlockBox? box;
  final double contentLeft;
  final ForumBodyCollapseSection? collapseTitle;
}

/// Normal-flow geometry over the sole text cursor. Adjoining signed margins
/// accumulate as max-positive + min-negative across empty blocks and ancestors;
/// real line content or nonzero padding separates groups. Only active frames,
/// one margin strut and at most five pending units are retained. No measuring,
/// native resource, HTML slice, persistent anchor or page publication is owned.
/// Edit notices use the text cursor's fitted format. Mixed inline inputs retain
/// the same block geometry without entering the ordinary shaping port. Other semantic containers
/// and resources require their own format handlers and fail
/// explicitly instead of being treated as empty/transparent ordinary blocks.
final class ForumBodyBlockFlowCursor {
  ForumBodyBlockFlowCursor({
    required ForumBodyDocument document,
    required ForumBodyReaderStyle reader,
    required this.width,
    this.edgeMargins = ForumBodyBlockEdgeMargins.trim,
    ForumBodyParagraphContentBuilder paragraphBuilder =
        const ForumBodyParagraphContentBuilder(),
    ForumBodyRubyContentLimits rubyLimits = const ForumBodyRubyContentLimits(),
    ForumBodyInlineImageResolver? inlineImageResolver,
    ForumBodyCollapseLayout? collapses,
    ForumBodyElement? contentRoot,
  }) : _flow = ForumBodyTextFlowCursor(
         document: document,
         reader: reader,
         paragraphBuilder: paragraphBuilder,
         rubyLimits: rubyLimits,
         inlineImageResolver: inlineImageResolver,
         collapses: collapses,
         contentRoot: contentRoot,
       ),
       _collapses = collapses,
       _rootFontSize = reader.textStyle.fontSize! {
    if (!width.isFinite || width <= 0) {
      _flow.close();
      throw ArgumentError.value(width, 'width');
    }
  }
  static const revision = 12;
  final double width;
  final ForumBodyBlockEdgeMargins edgeMargins;
  final double _rootFontSize;
  TextDirection get _rootDirection => _flow.rootStyle.textDirection;
  final ForumBodyTextFlowCursor _flow;
  ForumBodyCollapseLayout? _collapses;
  final _frames = <_Frame>[];
  final _rootListCounter = _ListCounter(1, 1);
  final _pending = Queue<ForumBodyBlockFlowUnit>();
  final _issues = <ForumBodyStyleIssue>[];
  double _positiveMargin = 0;
  double _negativeMargin = 0;
  ForumBodyBlockFlowUnit? _current;
  bool _complete = false;
  bool _closed = false;
  bool _hasFlowContent = false;
  bool _waitingListGutter = false;

  ForumBodyIdentity get identity => _flow.identity;
  String get fontRevision => _flow.fontRevision;
  int get styleRevision => _flow.styleRevision;
  int get resolvedNodeCount => _flow.resolvedNodeCount;
  ForumBodyBlockFlowUnit? get current => _current;
  bool get isComplete => _complete;
  bool get isClosed => _closed;

  ({int eventsRead, int workDone, bool hasOutput, bool isComplete}) advance({
    required int maxEvents,
  }) {
    if (_closed) throw StateError('Block flow cursor is closed');
    if (_waitingListGutter) {
      throw StateError('List marker gutter is unresolved');
    }
    if (maxEvents <= 0) throw ArgumentError.value(maxEvents, 'maxEvents');
    _current = null;
    if (_complete) return _step(0, 0);
    var read = 0;
    var work = 0;
    try {
      while (true) {
        if (_pending.isNotEmpty) {
          _current = _pending.removeFirst();
          final unit = _current;
          if (unit is ForumBodyBlockFlowListItemStart) {
            _waitingListGutter = true;
          }
          if (unit is ForumBodyBlockFlowBoundary &&
              unit.boundary.kind == ForumBodyTextFlowBoundaryKind.endDocument) {
            _complete = true;
          }
          return _step(read, work);
        }
        if (work >= maxEvents) return _step(read, work);
        final step = _flow.advance(maxEvents: maxEvents - work);
        read += step.eventsRead;
        work += step.workDone;
        _issues.addAll(_flow.takePendingIssues());
        final unit = _flow.current;
        if (unit == null) continue;
        switch (unit) {
          case ForumBodyTextFlowImage():
            _flushMargins();
            _hasFlowContent = true;
            _pending.add(
              ForumBodyBlockFlowImage._(
                unit,
                _frames.last.contentLeft,
                _frames.last.contentWidth,
                _takeListMarkers(),
              ),
            );
          case ForumBodyTextFlowParagraph():
            _flushMargins();
            _hasFlowContent = true;
            _pending.add(
              ForumBodyBlockFlowParagraph._(
                unit,
                _frames.isEmpty ? 0 : _frames.last.contentLeft,
                _frames.isEmpty ? width : _frames.last.contentWidth,
                _takeListMarkers(),
              ),
            );
          case ForumBodyTextFlowInline():
            _flushMargins();
            _hasFlowContent = true;
            _pending.add(
              ForumBodyBlockFlowInline._(
                unit,
                _frames.isEmpty ? 0 : _frames.last.contentLeft,
                _frames.isEmpty ? width : _frames.last.contentWidth,
                _takeListMarkers(),
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
        final section = _collapses?.sectionFor(node);
        final title = identical(section?.title, node) ? section : null;
        if (!const {
              ForumBodyElementKind.container,
              ForumBodyElementKind.paragraph,
              ForumBodyElementKind.heading,
              ForumBodyElementKind.quote,
              ForumBodyElementKind.list,
              ForumBodyElementKind.listItem,
              ForumBodyElementKind.rule,
              ForumBodyElementKind.editStatus,
              ForumBodyElementKind.code,
              ForumBodyElementKind.image,
              ForumBodyElementKind.inline,
              ForumBodyElementKind.unknown,
            }.contains(node.kind) &&
            section == null) {
          throw ForumBodyBlockFlowException(
            ForumBodyBlockFlowFailure.structure,
            node.path,
          );
        }
        _validateNormalFlow(node);
        final parent = _frames.lastOrNull;
        const leading = ForumCollapseHeaderMetrics.titleStart;
        const trailing = ForumCollapseHeaderMetrics.inset;
        final ltr = event.style.textDirection == TextDirection.ltr;
        final chromePadding = title != null
            ? EdgeInsets.only(
                left: ltr ? leading : trailing,
                right: ltr ? trailing : leading,
              )
            : identical(section?.body, node)
            ? const EdgeInsets.symmetric(horizontal: trailing)
            : EdgeInsets.zero;
        final box = ForumBodyBlockBox.resolve(
          style: event.style,
          containingWidth: parent?.contentWidth ?? width,
          containingDirection:
              parent?.event.style.textDirection ?? _rootDirection,
          rootFontSize: _rootFontSize,
          blockifyInline: node.kind == ForumBodyElementKind.image,
          extraPadding: chromePadding,
        );
        final left = (parent?.contentLeft ?? 0) + box.contentLeft;
        if (!left.isFinite) {
          throw const ForumBodyBlockBoxException(
            ForumBodyBlockBoxFailure.geometry,
          );
        }
        final frame = _Frame(event, box, left);
        if (node.kind == ForumBodyElementKind.list) {
          final start = node.tag == 'ol'
              ? _ordinalAttribute(node, 'start')
              : null;
          final reversed =
              node.tag == 'ol' && node.attributes.containsKey('reversed');
          // An implicit reversed count needs a bounded rendered-item prepass.
          // Never guess a starting value or synchronously scan the subtree.
          if (reversed && start == null) {
            throw ForumBodyBlockFlowException(
              ForumBodyBlockFlowFailure.structure,
              node.path,
            );
          }
          frame.counter = _ListCounter(start ?? 1, reversed ? -1 : 1);
        }
        if (event.style.display == ForumBodyDisplay.listItem) {
          final owner = _frames.reversed
              .where((frame) => frame.counter != null)
              .firstOrNull;
          final counter =
              owner?.counter ??
              (parent == null ? _rootListCounter : parent.implicitCounter);
          final ordinal = counter.take(
            node.tag == 'li' ? _ordinalAttribute(node, 'value') : null,
          );
          if (ordinal == null) {
            throw ForumBodyBlockFlowException(
              ForumBodyBlockFlowFailure.geometry,
              node.path,
            );
          }
          frame.marker = ForumBodyListItemMarker._(
            listPath: owner?.event.node.path,
            itemPath: node.path,
            ordinal: ordinal,
            style: event.style,
            contentLeft: left,
            contentWidth: box.contentWidth,
          );
        }
        _frames.add(frame);
        _pending.add(
          ForumBodyBlockFlowBoundary._(unit, box, left, collapseTitle: title),
        );
        if (frame.marker case final marker?) {
          final owner = _frames.reversed
              .skip(1)
              .where((frame) => frame.counter != null)
              .firstOrNull;
          final edgeLeft = owner == null
              ? 0.0
              : owner.contentLeft -
                    owner.box.padding.left -
                    owner.box.leftBorder;
          final edgeRight = owner == null
              ? width
              : edgeLeft + owner.box.borderBoxWidth;
          final available = marker.style.textDirection == TextDirection.ltr
              ? left - edgeLeft
              : edgeRight - left - box.contentWidth;
          _pending.add(
            ForumBodyBlockFlowListItemStart._(
              identity,
              marker,
              math.max(0, available),
            ),
          );
        }
        _margin(box.margin.top);
        _padding(
          box.padding.top,
          ForumBodyBlockSpaceKind.paddingTop,
          node.path,
        );
        if (node.kind == ForumBodyElementKind.rule) {
          if (event.style.textStyle.foreground != null) {
            throw ForumBodyBlockFlowException(
              ForumBodyBlockFlowFailure.geometry,
              node.path,
            );
          }
          _flushMargins();
          _hasFlowContent = true;
          _pending.add(
            ForumBodyBlockFlowRule._(
              identity,
              node.path,
              left,
              box.contentWidth,
              event.style.visibilityHidden
                  ? const Color(0x00000000)
                  : event.style.textStyle.color ?? const Color(0xff000000),
            ),
          );
        }
      case ForumBodyTextFlowBoundaryKind.closeBlock:
        if (_frames.isEmpty ||
            !identical(_frames.last.event.node, event!.node)) {
          throw StateError('Unbalanced block flow');
        }
        final frame = _frames.removeLast();
        final section = _collapses?.sectionFor(event.node as ForumBodyElement);
        _padding(
          frame.box.padding.bottom,
          ForumBodyBlockSpaceKind.paddingBottom,
          event.node.path,
        );
        _margin(frame.box.margin.bottom);
        _pending.add(
          ForumBodyBlockFlowBoundary._(
            unit,
            frame.box,
            frame.contentLeft,
            collapseTitle: identical(section?.title, event.node)
                ? section
                : null,
          ),
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

  void resolveListItemGutter(
    ForumBodyBlockFlowListItemStart item,
    double requiredGutter,
  ) {
    if (_closed ||
        !_waitingListGutter ||
        !identical(item, _current) ||
        !requiredGutter.isFinite ||
        requiredGutter < 0) {
      throw StateError('List marker gutter does not match pending item');
    }
    final frame = _frames.last;
    final extra = math.max(0.0, requiredGutter - item.availableGutter);
    if (extra >= frame.box.contentWidth) {
      throw ForumBodyBlockFlowException(
        ForumBodyBlockFlowFailure.geometry,
        item.marker.itemPath,
      );
    }
    frame.extraGutter = extra;
    final marker = item.marker;
    frame.marker = ForumBodyListItemMarker._(
      listPath: marker.listPath,
      itemPath: marker.itemPath,
      ordinal: marker.ordinal,
      style: marker.style,
      contentLeft: frame.contentLeft,
      contentWidth: frame.contentWidth,
    );
    _waitingListGutter = false;
  }

  List<ForumBodyListItemMarker> _takeListMarkers() {
    final result = <ForumBodyListItemMarker>[];
    for (final frame in _frames) {
      if (frame.marker case final marker?) {
        result.add(marker);
        frame.marker = null;
      }
    }
    return List.unmodifiable(result);
  }

  static final _integerPrefix = RegExp(r'^[\t\n\f\r ]*([+-]?[0-9]+)');
  static int? _ordinalAttribute(ForumBodyElement node, String attribute) {
    final raw = node.attributes[attribute];
    if (raw == null) return null;
    final token = _integerPrefix.firstMatch(raw)?.group(1);
    if (token == null) return null;
    final value = int.tryParse(token, radix: 10);
    if (value == null) {
      throw ForumBodyBlockFlowException(
        ForumBodyBlockFlowFailure.geometry,
        node.path,
      );
    }
    return value;
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
          'list-item',
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
    if (_closed) throw StateError('Block flow cursor is closed');
    final result = List<ForumBodyStyleIssue>.unmodifiable(_issues);
    _issues.clear();
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _flow.close();
    _collapses = null;
    _frames.clear();
    _pending.clear();
    _issues.clear();
    _positiveMargin = _negativeMargin = 0;
    _current = null;
  }
}

final class _Frame {
  _Frame(this.event, this.box, this._baseLeft);
  final ForumBodyStyledFlowEvent event;
  final ForumBodyBlockBox box;
  final double _baseLeft;
  double extraGutter = 0;
  double get contentLeft =>
      _baseLeft +
      (event.style.textDirection == TextDirection.ltr ? extraGutter : 0);
  double get contentWidth => box.contentWidth - extraGutter;
  _ListCounter? counter;
  _ListCounter? _implicitCounter;
  _ListCounter get implicitCounter => _implicitCounter ??= _ListCounter(1, 1);
  ForumBodyListItemMarker? marker;
}

final class _ListCounter {
  _ListCounter(this._next, this.step);
  int? _next;
  final int step;
  int? take(int? explicit) {
    final value = explicit ?? _next;
    if (value == null) return null;
    final next = value + step;
    // Overflow retires only the next automatic ordinal. A later explicit LI
    // value may legitimately reset it; the final valid item does not fail.
    _next = step > 0 && next <= value || step < 0 && next >= value
        ? null
        : next;
    return value;
  }
}
