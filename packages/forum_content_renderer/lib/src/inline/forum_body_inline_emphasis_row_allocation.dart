import 'dart:collection';

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import 'forum_body_emphasis_allocation_geometry.dart';
import 'forum_body_inline_emphasis_isolation_preparation.dart';
import 'forum_body_inline_parent_rows.dart';

part 'forum_body_inline_emphasis_native_frames.dart';

final class ForumBodyInlineEmphasisAllocatedRow {
  const ForumBodyInlineEmphasisAllocatedRow._({
    required this.line,
    required this.naturalOffset,
    required this.logicalOffset,
    required this.glyphOffset,
    required this.authoredAdvance,
    required this.isolatedGlyphBaseline,
    required this.parentFontBounds,
    required this.bounds,
    required this.paintBounds,
  });
  final ForumBodyParagraphLine line;

  /// Whole-parent coordinates to this allocation. These are physical, never
  /// source/display offsets. Parent glyph paint has its own native rounding.
  final Offset naturalOffset, logicalOffset, glyphOffset;
  final double authoredAdvance, isolatedGlyphBaseline;
  final Rect? parentFontBounds, bounds, paintBounds;
}

typedef ForumBodyInlineEmphasisAllocatedMark = ({
  int unitIndex,
  int lineIndex,
  int fontIndex,
  Offset offset,
  Rect fontBounds,
});
typedef ForumBodyInlineEmphasisAllocatedChild = ({
  int atomIndex,
  int lineIndex,
  Offset offset,
  Rect bounds,
});

/// Complete mixed physical allocation over the actual final natural/isolated
/// pair. Pure measured coordinates only; no source group is split and no live
/// child/mark/scene or readable page admission is established by this value.
final class ForumBodyInlineEmphasisRowAllocation {
  ForumBodyInlineEmphasisRowAllocation._(
    this.input,
    List<ForumBodyInlineEmphasisAllocatedRow> rows,
    List<ForumBodyInlineEmphasisAllocatedMark> marks,
    List<ForumBodyInlineEmphasisAllocatedChild?> children,
    this.height,
    this.paintBounds,
    this.requiresParentPaintPhases,
  ) : rows = UnmodifiableListView(rows),
      marks = UnmodifiableListView(marks),
      children = UnmodifiableListView(children);
  static const revision = 1;
  final ForumBodyInlineEmphasisIsolationMetrics input;
  final List<ForumBodyInlineEmphasisAllocatedRow> rows;
  final List<ForumBodyInlineEmphasisAllocatedMark> marks;

  /// Null only for a truly trimmed soft slot; original indices are retained.
  final List<ForumBodyInlineEmphasisAllocatedChild?> children;
  final double height;

  /// Conservative parent glyph paint envelope plus actual complete child and
  /// marker frames. It can overflow logical flow, as authored shadows do.
  final Rect? paintBounds;

  /// Logical backgrounds/decorations need their own physical paint offsets.
  final bool requiresParentPaintPhases;
  double get width => input.reference.width;
}

enum _AllocationPhase {
  naturalFrames,
  isolatedFrames,
  paintStyles,
  fonts,
  childBounds,
  markBounds,
  rows,
  marks,
  children,
  publish,
  ready,
  closed,
}

/// Borrows the qualified current native pair to capture actual flow frames.
/// Every part queries once, visits one native box/row/child/marker, or publishes.
/// No cache acquire, shaping, recording or caller handle release occurs here.
final class ForumBodyInlineEmphasisRowAllocationPreparation {
  ForumBodyInlineEmphasisRowAllocationPreparation({
    required ForumBodyInlineEmphasisIsolationMetrics input,
    required ForumBodyInlineParagraphLease natural,
    required ForumBodyInlineParagraphLease isolated,
    required void Function() ensureOwner,
    this.maxLines = 4096,
    this.maxAtoms = 512,
    this.maxMarks = 32768,
    this.maxBoxes = 32768,
    this.maxHeight = 1048576,
  }) : _input = input,
       _natural = natural,
       _isolated = isolated,
       _ensureOwner = ensureOwner {
    if (maxLines <= 0 ||
        maxAtoms < 0 ||
        maxMarks < 0 ||
        maxBoxes < 0 ||
        !maxHeight.isFinite ||
        maxHeight <= 0) {
      throw ArgumentError('Invalid mixed row allocation budget');
    }
    try {
      _guard();
      final ref = input.reference, reflow = input.natural.reflow;
      if (!natural.hasSameSourceAndInputsExceptRowIsolation(isolated) ||
          natural.nativeInputIdentity != ref.naturalInputIdentity ||
          isolated.nativeInputIdentity != ref.isolatedInputIdentity ||
          !identical(natural.layout.lines, ref.naturalLines) ||
          !identical(isolated.layout.lines, ref.isolatedLines) ||
          !identical(reflow.finalLines, ref.naturalLines) ||
          !identical(input.geometry.lines, ref.isolatedLines)) {
        _source();
      }
      final page = input.natural.page, placement = reflow.children.placement;
      if (ref.lineCount > maxLines ||
          page.rubyAtoms.length > maxAtoms ||
          placement.marks.length > maxMarks) {
        _limit();
      }
      if (input.rows.rows.length != ref.lineCount ||
          input.natural.geometry.parentFontBounds.length != ref.lineCount ||
          page.rubyAtoms.length != ref.atomLineIndices.length ||
          placement.marks.length != input.natural.text.units.length) {
        _source();
      }
      _framesWork = _NativeFrames(natural, _guard, maxLines, maxBoxes);
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int maxLines, maxAtoms, maxMarks, maxBoxes;
  final double maxHeight;
  ForumBodyInlineEmphasisIsolationMetrics? _input;
  ForumBodyInlineParagraphLease? _natural, _isolated;
  void Function()? _ensureOwner;
  _NativeFrames? _framesWork;
  _NativeFlowFrames? _naturalFrames, _isolatedFrames;
  List<Rect?> _extents = [];
  List<ForumBodyInlineEmphasisAllocatedRow> _rows = [];
  List<ForumBodyInlineEmphasisAllocatedMark> _marks = [];
  List<ForumBodyInlineEmphasisAllocatedChild?> _children = [];
  ForumBodyInlineEmphasisRowAllocation? _result;
  var _phase = _AllocationPhase.naturalFrames;
  int _index = 0;
  double _height = 0;
  Rect? _paintBounds;
  bool _operating = false;
  bool _requiresParentPaintPhases = false;
  bool get isReady => _phase == _AllocationPhase.ready;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Mixed row allocation is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        _guard();
        final input = _input!,
            reflow = input.natural.reflow,
            placement = reflow.children.placement,
            page = input.natural.page;
        switch (_phase) {
          case _AllocationPhase.naturalFrames:
          case _AllocationPhase.isolatedFrames:
            final work = _framesWork!;
            used += work.advance(maxParts - used);
            _guard();
            if (work.isReady) {
              final value = work.takeFrames();
              _framesWork = null;
              if (_phase == _AllocationPhase.naturalFrames) {
                _naturalFrames = value;
                _framesWork = _NativeFrames(
                  _isolated!,
                  _guard,
                  maxLines,
                  maxBoxes,
                );
                _phase = _AllocationPhase.isolatedFrames;
              } else {
                _isolatedFrames = value;
                _phase = _AllocationPhase.paintStyles;
                _index = -1;
              }
            }
            continue;
          case _AllocationPhase.paintStyles:
            final content = _isolated!.content;
            if (_index < content.parentRuns.length) {
              final style = _index < 0
                  ? content.style.textStyle
                  : content.parentRuns[_index].style.textStyle;
              _requiresParentPaintPhases |=
                  style.background != null ||
                  style.backgroundColor != null ||
                  (style.decoration != null &&
                      style.decoration != TextDecoration.none);
              _index++;
            } else {
              _next(_AllocationPhase.fonts);
            }
          case _AllocationPhase.fonts:
            if (_index < input.reference.lineCount) {
              final font = input.natural.geometry.parentFontBounds[_index++];
              if (font != null) _rect(font);
              _extents.add(font);
            } else {
              _next(_AllocationPhase.childBounds);
            }
          case _AllocationPhase.childBounds:
            if (_index < page.rubyAtoms.length) {
              final atom = _index++;
              if (!page.trimmedAtomIndices.contains(atom)) {
                _include(
                  input.reference.atomLineIndices[atom],
                  _childBounds(atom),
                );
              }
            } else {
              _next(_AllocationPhase.markBounds);
            }
          case _AllocationPhase.markBounds:
            if (_index < placement.marks.length) {
              final mark = placement.marks[_index++];
              if (mark.unitIndex != _index - 1 ||
                  mark.lineIndex !=
                      input
                          .natural
                          .geometry
                          .targets[mark.unitIndex]
                          .lineIndex) {
                _source();
              }
              _include(
                mark.lineIndex,
                mark.fontBounds.shift(
                  Offset(0, reflow.baselineDeltas[mark.lineIndex]),
                ),
              );
            } else {
              _next(_AllocationPhase.rows);
            }
          case _AllocationPhase.rows:
            if (_index < input.reference.lineCount) {
              _allocate(_index++);
            } else {
              _next(_AllocationPhase.marks);
            }
          case _AllocationPhase.marks:
            if (_index < placement.marks.length) {
              final mark = placement.marks[_index++],
                  row = _rows[mark.lineIndex];
              final shift = Offset(
                0,
                reflow.baselineDeltas[mark.lineIndex] + row.naturalOffset.dy,
              );
              final bounds = mark.fontBounds.shift(shift);
              _rect(bounds);
              _marks.add((
                unitIndex: mark.unitIndex,
                lineIndex: mark.lineIndex,
                fontIndex: mark.fontIndex,
                offset: mark.baselineOrigin + mark.fontOffset + shift,
                fontBounds: bounds,
              ));
              _paintBounds = _union(_paintBounds, bounds);
            } else {
              _next(_AllocationPhase.children);
            }
          case _AllocationPhase.children:
            if (_index < page.rubyAtoms.length) {
              final atom = _index++;
              if (page.trimmedAtomIndices.contains(atom)) {
                _children.add(null);
              } else {
                final line = input.reference.atomLineIndices[atom],
                    row = _rows[line];
                final bounds = _childBounds(atom).shift(row.naturalOffset);
                _children.add((
                  atomIndex: atom,
                  lineIndex: line,
                  offset:
                      input.reference.naturalAtomBoxes[atom].toRect().topLeft +
                      row.naturalOffset,
                  bounds: bounds,
                ));
                _paintBounds = _union(_paintBounds, bounds);
              }
            } else {
              _next(_AllocationPhase.publish);
            }
          case _AllocationPhase.publish:
            _result = ForumBodyInlineEmphasisRowAllocation._(
              input,
              _rows,
              _marks,
              _children,
              _height,
              _paintBounds,
              _requiresParentPaintPhases,
            );
            _rows = [];
            _marks = [];
            _children = [];
            _phase = _AllocationPhase.ready;
          case _AllocationPhase.ready:
          case _AllocationPhase.closed:
            throw StateError('Mixed row allocation is retired');
        }
        used++;
        _guard();
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _allocate(int index) {
    final input = _input!,
        source = input.reference.naturalLines[index],
        isolated = input.reference.isolatedLines[index],
        extent = _extents[index];
    final advance = _naturalFrames!.ends[index] - _naturalFrames!.starts[index];
    final allocated = forumBodyAllocateEmphasisRowFrame(
      ascent: source.baseline - source.top,
      authoredAdvance: advance,
      originalBaseline: source.baseline,
      extentTop: extent?.top ?? source.baseline,
      extentBottom: extent?.bottom ?? source.baseline,
      flowTop: _height,
      maxHeight: maxHeight,
    );
    final naturalOffset = Offset(0, allocated.translationY),
        glyphBaseline =
            _isolatedFrames!.starts[index] +
            _isolatedFrames!.nativeAlphabeticBaseline.roundToDouble(),
        glyphOffset = Offset(0, allocated.baseline - glyphBaseline),
        selector = input.rows.rows[index],
        paintBounds = selector.paintBounds?.shift(glyphOffset);
    final font = input.natural.geometry.parentFontBounds[index];
    _rows.add(
      ForumBodyInlineEmphasisAllocatedRow._(
        line: source.withVerticalFrame(
          top: _height,
          bottom: _height + allocated.height,
          baseline: allocated.baseline,
        ),
        naturalOffset: naturalOffset,
        logicalOffset: Offset(0, allocated.baseline - isolated.baseline),
        glyphOffset: glyphOffset,
        authoredAdvance: advance,
        isolatedGlyphBaseline: glyphBaseline,
        parentFontBounds: font?.shift(naturalOffset),
        bounds: extent?.shift(naturalOffset),
        paintBounds: paintBounds,
      ),
    );
    if (paintBounds != null) _paintBounds = _union(_paintBounds, paintBounds);
    _height += allocated.height;
  }

  Rect _childBounds(int atom) {
    final input = _input!,
        raw = input.reference.naturalAtomBoxes[atom].toRect(),
        size = input.natural.page.dimensions[atom].size;
    final bounds = raw.expandToInclude(
      Rect.fromLTWH(raw.left, raw.top, size.width, size.height),
    );
    _rect(bounds);
    return bounds;
  }

  void _include(int line, Rect bounds) {
    if (line < 0 || line >= _extents.length) _source();
    _rect(bounds);
    _extents[line] = _union(_extents[line], bounds);
  }

  void _next(_AllocationPhase phase) {
    _index = 0;
    _phase = phase;
  }

  ForumBodyInlineEmphasisRowAllocation takeAllocation() {
    if (_operating) throw StateError('Mixed row allocation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Mixed row allocation is incomplete');
      final result = _result!;
      close();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _AllocationPhase.closed) {
      throw StateError('Mixed row allocation is retired');
    }
    _ensureOwner!();
    if (_phase == _AllocationPhase.closed ||
        _natural?.isActive != true ||
        _isolated?.isActive != true) {
      throw StateError('Mixed row allocation owner is retired');
    }
  }

  void close() {
    _phase = _AllocationPhase.closed;
    _framesWork?.close();
    _framesWork = null;
    _input = null;
    _natural = null;
    _isolated = null;
    _ensureOwner = null;
    _naturalFrames = null;
    _isolatedFrames = null;
    _extents = [];
    _rows = [];
    _marks = [];
    _children = [];
    _result = null;
    _paintBounds = null;
  }
}

/// Borrows the current already-prepared isolated parent. Replays only its
/// ordinary glyph strips at the allocated native glyph offsets. Actual child
/// and marker bindings plus background/decorative phase order are still needed.
final class ForumBodyInlineEmphasisAllocatedParentView {
  ForumBodyInlineEmphasisAllocatedParentView.bind({
    required this.parent,
    required this.allocation,
    required void Function() ensureOwner,
  }) : _ensureOwner = ensureOwner {
    _guard();
    final input = allocation.input;
    if (!identical(parent.layout.lines, input.reference.isolatedLines) ||
        parent.nativeInputIdentity != input.reference.isolatedInputIdentity ||
        !identical(parent.content, input.natural.text.glyphInput.glyphs) ||
        allocation.requiresParentPaintPhases) {
      _source();
    }
    _view = ForumBodyInlineParentRowView.bind(
      parent: parent,
      rows: input.rows,
      ensureOwner: _guard,
    );
  }
  final ForumBodyInlineParagraphLease parent;
  final ForumBodyInlineEmphasisRowAllocation allocation;
  final void Function() _ensureOwner;
  late final ForumBodyInlineParentRowView _view;
  bool _painting = false;
  void paintParentRow(Canvas canvas, Offset offset, int index) {
    if (_painting) {
      throw StateError('Allocated mixed parent paint is reentrant');
    }
    _painting = true;
    try {
      _guard();
      RangeError.checkValidIndex(index, allocation.rows);
      final row = allocation.rows[index],
          selector = allocation.input.rows.rows[index].selector;
      _view.paintParentRow(
        canvas,
        offset + row.glyphOffset + Offset(0, selector.originY),
        index,
      );
    } finally {
      _painting = false;
    }
  }

  void _guard() {
    _ensureOwner();
    if (!parent.isActive) {
      throw StateError('Allocated mixed parent owner is retired');
    }
  }
}

Rect _union(Rect? a, Rect b) => a?.expandToInclude(b) ?? b;
void _rect(Rect rect) {
  if (!rect.isFinite || rect.width < 0 || rect.height < 0) {
    throw const ForumBodyEmphasisAllocationException(
      ForumBodyEmphasisAllocationFailure.geometry,
    );
  }
}

Never _source() => throw const ForumBodyEmphasisAllocationException(
  ForumBodyEmphasisAllocationFailure.source,
);
Never _limit() => throw const ForumBodyEmphasisAllocationException(
  ForumBodyEmphasisAllocationFailure.limit,
);
