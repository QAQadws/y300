import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_inline_paragraph_layout.dart';
import 'forum_body_inline_span_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart'
    show ForumBodyParagraphLine;
import 'forum_body_ruby_group_layout.dart';
import 'forum_body_ruby_segment_layout.dart';

part 'forum_body_inline_ruby_binding.dart';
part 'forum_body_inline_view_assembly.dart';
part 'forum_body_inline_ruby_binding_work.dart';

enum ForumBodyInlineViewFailure { leases, coverage, identity, geometry }

final class ForumBodyInlineViewException implements Exception {
  const ForumBodyInlineViewException(this.failure);
  final ForumBodyInlineViewFailure failure;
  @override
  String toString() => 'ForumBodyInlineViewException(${failure.name})';
}

/// Complete readable line window: one parent and exactly its visible children.
/// No shape, recording, lookup or settings resolution happens in paint/hit.
/// The caller prepares this transaction using the reading owner's shared cache.
final class ForumBodyInlineParagraphView {
  ForumBodyInlineParagraphView._(
    this._parent,
    ForumBodyInlineParagraphFragment fragment,
    this._children,
  ) : _fragment = fragment,
      width = fragment.layout.width,
      height = fragment.height,
      startLine = fragment.startLine,
      endLine = fragment.endLine,
      coverageStartUtf16 = fragment.coverageStartUtf16,
      coverageEndUtf16 = fragment.coverageEndUtf16;

  ForumBodyInlineParagraphView._empty(ForumBodyInlineParagraphLease parent)
    : _parent = parent,
      _fragment = null,
      _children = const {},
      width = parent.layout.width,
      height = parent.layout.height,
      startLine = 0,
      endLine = 0,
      coverageStartUtf16 = 0,
      coverageEndUtf16 = 0;

  /// Consumes these handles on success AND failure. Column and segment indices
  /// must be disjoint and cover exactly the visible atoms; hidden children
  /// cannot silently pin an entire long paragraph.
  factory ForumBodyInlineParagraphView.adopt({
    required ForumBodyParagraphCache cache,
    required ForumBodyInlineParagraphLease parent,
    required int startLine,
    required int endLine,
    Map<int, ForumBodyRubyGroupLayout> rubyGroups = const {},
    Map<int, ForumBodyRubySegmentLayout> rubySegments = const {},
  }) {
    final assembly = ForumBodyInlineViewAssembly(
      cache: cache,
      parent: parent,
      startLine: startLine,
      endLine: endLine,
      rubyGroups: rubyGroups,
      rubySegments: rubySegments,
    );
    try {
      while (!assembly.isReady) {
        assembly.advance(maxParts: 32);
      }
      return assembly.takeView();
    } finally {
      assembly.close();
    }
  }

  ForumBodyInlineParagraphLease? _parent;
  ForumBodyInlineParagraphFragment? _fragment;
  Map<int, _RubyBinding> _children;
  bool get isActive =>
      _parent?.isActive == true &&
      !_parent!.layout.isDisposed &&
      _children.values.every((binding) => binding.isActive);
  final double width;
  final double height;
  final int startLine;
  final int endLine;
  final int coverageStartUtf16;
  final int coverageEndUtf16;
  ForumBodyInlineSpanContent get content {
    _ensureActive();
    return _parent!.content;
  }

  Iterable<int> get atomIndices => _children.keys;

  /// Actual visible native rows in this view's physical coordinates. Returning
  /// immutable row values neither borrows paint ownership nor proves coverage.
  Iterable<ForumBodyParagraphLine> get lines {
    _ensureActive();
    final fragment = _fragment;
    if (fragment == null) return const [];
    final top = fragment.top;
    return fragment.layout.lines
        .getRange(startLine, endLine)
        .map((line) => line.shift(Offset(0, -top)));
  }

  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_parent,
    for (final binding in _children.values) ...binding.nativeLeases,
  ];

  void paint(Canvas canvas, Offset offset) {
    _ensureActive();
    if (_fragment == null) return;
    canvas.save();
    try {
      // Child pictures already contain their native edge coverage. A second
      // antialiased rectangular viewport compounds alpha at fractional edges.
      canvas.clipRect(offset & Size(width, height), doAntiAlias: false);
      _fragment!.paintParent(canvas, offset);
      for (final entry in _children.entries) {
        entry.value.paint(canvas, offset + _origin(entry.key));
      }
    } finally {
      canvas.restore();
    }
  }

  Offset _origin(int index) =>
      _fragment!.layout.atomBoxes[index].toRect().topLeft -
      Offset(0, _fragment!.top);

  /// Returns parent display coordinates and the ACTUAL child's source point.
  /// Off-window points clamp to this view and remain approximate, never borrow
  /// a hidden sibling's native hit or fabricate an inner placeholder offset.
  HtmlProjectedSourcePosition sourceAt(Offset offset) {
    _ensureActive();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    if (_fragment == null || coverageStartUtf16 == coverageEndUtf16) {
      final empty = content.projection.display.sourceAtUtf16(
        coverageStartUtf16,
      );
      return HtmlProjectedSourcePosition(
        sourceRune: empty.sourceRune,
        displayUtf16: empty.displayUtf16,
        isExact: false,
      );
    }
    final point = Offset(
      offset.dx.clamp(0, width),
      offset.dy.clamp(0, height > 1e-7 ? height - 1e-7 : 0),
    );
    final hit = _fragment!.hitAt(point);
    final display = content.projection.display;
    HtmlProjectedSourcePosition position;
    if (hit is ForumBodyInlineAtomHit) {
      final binding = _children[hit.index];
      if (binding == null) _fail(ForumBodyInlineViewFailure.coverage);
      final child = binding.sourceAt(hit.offset);
      final window = child.window;
      final parentDisplay = window.startUtf16 + child.position.displayUtf16;
      final parent = display.sourceAtUtf16(parentDisplay);
      position = HtmlProjectedSourcePosition(
        sourceRune: child.position.sourceRune,
        displayUtf16: parentDisplay,
        isExact:
            child.position.isExact &&
            parent.isExact &&
            child.position.sourceRune == parent.sourceRune,
      );
    } else {
      position = (hit as ForumBodyInlineTextHit).position;
    }
    final within = position.displayUtf16.clamp(
      coverageStartUtf16,
      coverageEndUtf16,
    );
    if (within != position.displayUtf16) {
      final projected = display.sourceAtUtf16(within);
      return HtmlProjectedSourcePosition(
        sourceRune: projected.sourceRune,
        displayUtf16: projected.displayUtf16,
        isExact: false,
      );
    }
    return HtmlProjectedSourcePosition(
      sourceRune: position.sourceRune,
      displayUtf16: position.displayUtf16,
      isExact: position.isExact && point == offset && height > 0,
    );
  }

  /// Resolves partial base/RT selections through the child's actual text
  /// geometry. A placeholder rectangle is never substituted for glyph boxes.
  List<TextBox> selectionBoxes(
    int startUtf16,
    int endUtf16, {
    bool clipToView = true,
  }) {
    _ensureActive();
    RangeError.checkValidRange(
      startUtf16,
      endUtf16,
      content.projection.display.text.length,
    );
    final start = startUtf16.clamp(coverageStartUtf16, coverageEndUtf16);
    final end = endUtf16.clamp(coverageStartUtf16, coverageEndUtf16);
    if (start >= end) return const [];
    final selected = _fragment!.layout.selection(start, end);
    final result = <TextBox>[];
    void add(TextBox box, Offset translation) {
      final raw = box.toRect().shift(translation);
      final rect = clipToView
          ? raw.intersect(Offset.zero & Size(width, height))
          : raw;
      if (!rect.isEmpty) {
        result.add(
          TextBox.fromLTRBD(
            rect.left,
            rect.top,
            rect.right,
            rect.bottom,
            box.direction,
          ),
        );
      }
    }

    for (final box in selected.textBoxes) {
      add(box, Offset(0, -_fragment!.top));
    }
    for (final atom in selected.atoms) {
      final binding = _children[atom.index];
      if (binding == null) _fail(ForumBodyInlineViewFailure.coverage);
      for (final box in binding.selectionBoxes(
        atom.startUtf16,
        atom.endUtf16,
      )) {
        add(box, _origin(atom.index));
      }
    }
    return List.unmodifiable(result);
  }

  void _ensureActive() {
    if (!isActive) throw StateError('Inline paragraph view is retired');
  }

  static Never _fail(ForumBodyInlineViewFailure failure) =>
      throw ForumBodyInlineViewException(failure);
  void close() {
    final parent = _parent;
    if (parent == null) return;
    _parent = null;
    for (final binding in _children.values) {
      binding.close();
    }
    _children = const {};
    _fragment = null;
    parent.release();
  }
}
