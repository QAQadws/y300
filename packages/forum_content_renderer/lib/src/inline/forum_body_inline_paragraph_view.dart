import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_inline_paragraph_layout.dart';
import 'forum_body_inline_span_content.dart';
import 'forum_body_ruby_group_layout.dart';

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

  /// Consumes these handles on success AND failure. Non-visible groups are
  /// rejected, so one view cannot silently pin an entire long paragraph.
  factory ForumBodyInlineParagraphView.adopt({
    required ForumBodyParagraphCache cache,
    required ForumBodyInlineParagraphLease parent,
    required int startLine,
    required int endLine,
    required Map<int, ForumBodyRubyGroupLayout> rubyGroups,
  }) {
    try {
      if (!cache.ownsLease(parent) ||
          parent.layout.isDisposed ||
          rubyGroups.values.any((group) => !group.isOwnedBy(cache)) ||
          (Set<ForumBodyRubyGroupLayout>.identity()..addAll(rubyGroups.values))
                  .length !=
              rubyGroups.length) {
        _fail(ForumBodyInlineViewFailure.leases);
      }
      final fragment = parent.layout.fragment(startLine, endLine);
      final indices = fragment.atomIndices.toList(growable: false);
      if (indices.length != rubyGroups.length ||
          indices.any((index) => !rubyGroups.containsKey(index))) {
        _fail(ForumBodyInlineViewFailure.coverage);
      }
      final bindings = <int, _RubyBinding>{};
      final content = parent.content;
      final contexts =
          Map<ForumBodyParagraphContent, ForumBodyInlineContext?>.identity();
      for (final context in content.contexts) {
        contexts[context.content] = contexts.containsKey(context.content)
            ? null
            : context;
      }
      for (final index in indices) {
        final group = rubyGroups[index]!;
        final atom = content.projection.atoms[index];
        final base = group.contentFor(ForumBodyRubyPart.base);
        final annotation = group.contentFor(ForumBodyRubyPart.annotation);
        final baseWindow = contexts[base];
        final annotationWindow = group.hasAnnotation
            ? contexts[annotation]
            : null;
        if (baseWindow == null ||
            (group.hasAnnotation && annotationWindow == null)) {
          _fail(ForumBodyInlineViewFailure.identity);
        }
        if (baseWindow.startUtf16 != atom.displayStartUtf16 ||
            baseWindow.endUtf16 !=
                (annotationWindow?.startUtf16 ?? atom.displayEndUtf16) ||
            (annotationWindow != null &&
                annotationWindow.endUtf16 != atom.displayEndUtf16)) {
          _fail(ForumBodyInlineViewFailure.coverage);
        }
        final dimension = parent.layout.dimensions[index];
        if ((dimension.size.width - group.size.width).abs() > 1e-4 ||
            (dimension.size.height - group.size.height).abs() > 1e-4 ||
            (dimension.baselineOffset! - group.baseline).abs() > 1e-4) {
          _fail(ForumBodyInlineViewFailure.geometry);
        }
        bindings[index] = _RubyBinding(group, baseWindow, annotationWindow);
      }
      return ForumBodyInlineParagraphView._(
        parent,
        fragment,
        Map.unmodifiable(bindings),
      );
    } catch (_) {
      for (final group in rubyGroups.values) {
        group.close();
      }
      parent.release();
      rethrow;
    }
  }

  ForumBodyInlineParagraphLease? _parent;
  ForumBodyInlineParagraphFragment? _fragment;
  Map<int, _RubyBinding> _children;
  bool get isActive =>
      _parent?.isActive == true &&
      !_parent!.layout.isDisposed &&
      _children.values.every((binding) => binding.group.isActive);
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
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_parent,
    for (final binding in _children.values) ...binding.group.nativeLeases,
  ];

  void paint(Canvas canvas, Offset offset) {
    _ensureActive();
    canvas.save();
    try {
      canvas.clipRect(offset & Size(width, height));
      _fragment!.paintParent(canvas, offset);
      for (final entry in _children.entries) {
        entry.value.group.paint(canvas, offset + _origin(entry.key));
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
      final child = binding.group.sourceAt(hit.offset);
      final window = child.part == ForumBodyRubyPart.base
          ? binding.base
          : binding.annotation!;
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
  List<TextBox> selectionBoxes(int startUtf16, int endUtf16) {
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
      final rect = box
          .toRect()
          .shift(translation)
          .intersect(Offset.zero & Size(width, height));
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
      for (final part in ForumBodyRubyPart.values) {
        final window = part == ForumBodyRubyPart.base
            ? binding.base
            : binding.annotation;
        if (window == null) continue;
        final from =
            atom.startUtf16.clamp(window.startUtf16, window.endUtf16) -
            window.startUtf16;
        final to =
            atom.endUtf16.clamp(window.startUtf16, window.endUtf16) -
            window.startUtf16;
        if (from >= to) continue;
        for (final box in binding.group.selectionBoxes(
          part: part,
          startUtf16: from,
          endUtf16: to,
        )) {
          add(box, _origin(atom.index));
        }
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
      binding.group.close();
    }
    _children = const {};
    _fragment = null;
    parent.release();
  }
}

final class _RubyBinding {
  const _RubyBinding(this.group, this.base, this.annotation);
  final ForumBodyRubyGroupLayout group;
  final ForumBodyInlineContext base;
  final ForumBodyInlineContext? annotation;
}
