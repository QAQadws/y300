import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_line_frames.dart';
import '../paragraph/forum_body_paragraph_row.dart';
import '../paragraph/forum_body_paragraph_row_reference.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_text_request.dart';
import 'forum_body_emphasis_line_layout.dart';

enum ForumBodyEmphasisAllocationFailure { source, geometry, limit }

final class ForumBodyEmphasisAllocationException implements Exception {
  const ForumBodyEmphasisAllocationException(this.failure);
  final ForumBodyEmphasisAllocationFailure failure;
  @override
  String toString() => 'ForumBodyEmphasisAllocationException(${failure.name})';
}

/// One allocated physical row, still inside its COMPLETE legal source group.
/// Offsets translate whole-parent coordinates; strip origins are added only
/// when constructing actual draw commands. They authorize no source slicing.
final class ForumBodyEmphasisAllocatedRow {
  const ForumBodyEmphasisAllocatedRow._({
    required this.physicalLine,
    required this.flowTop,
    required this.flowBottom,
    required this.alphabeticBaseline,
    required this.fontBounds,
    required this.bounds,
    required this.logicalOffset,
    required this.glyphOffset,
    required this.sourceTranslationY,
  });
  final ForumBodyParagraphPhysicalLineSelector physicalLine;
  final double flowTop, flowBottom, alphabeticBaseline;
  final Rect fontBounds, bounds;
  final Offset logicalOffset, glyphOffset;

  /// Translates this row's original emphasis component geometry, including its
  /// positioned marks, to the allocated component. It is not a semantic offset.
  final double sourceTranslationY;
}

typedef ForumBodyEmphasisAllocatedMark = ({
  int markIndex,
  Offset offset,
  Rect fontBounds,
});

/// Immutable allocation over measured source/font inputs. No native resource,
/// cache, callback, or live owner is retained. Current source/paint binding is
/// still required by a visible consumer, even after this plan survives eviction.
final class ForumBodyEmphasisRowAllocation {
  ForumBodyEmphasisRowAllocation._({
    required this.source,
    required this.reference,
    required List<ForumBodyEmphasisAllocatedRow> rows,
    required List<ForumBodyEmphasisAllocatedMark> marks,
    required this.height,
    required this.fontBounds,
    required this.isolatedAlphabeticBaseline,
    ForumBodyParagraphPaintInput? paintInput,
  }) : rows = UnmodifiableListView(rows),
       marks = UnmodifiableListView(marks),
       _sharedPaintInput = paintInput;
  static const revision = 3;
  final ForumBodyEmphasisLineMetrics source;
  final ForumBodyParagraphRowReference reference;
  final List<ForumBodyEmphasisAllocatedRow> rows;
  final List<ForumBodyEmphasisAllocatedMark> marks;
  final double height;
  final Rect fontBounds;
  final double isolatedAlphabeticBaseline;
  final ForumBodyParagraphPaintInput? _sharedPaintInput;
  late final paintInput =
      _sharedPaintInput ?? ForumBodyParagraphPaintInput(reference.content);

  /// All temporary fonts, including WHOLE parents for every paint phase.
  /// A final scene has its own input/lease admission in the visible transaction.
  Iterable<ForumBodyNativeRequestSlot> get nativeFootprint sync* {
    yield* source.nativeFootprint;
    for (final content in [
      paintInput.background,
      paintInput.foreground,
      paintInput.decoration,
    ]) {
      yield (
        request: ForumBodyTextRequest.paragraph(
          content,
          rowIsolationPitch: reference.rowIsolationPitch,
        ),
        width: source.requestWidth,
        minimumLineCount: reference.lineCount,
      );
    }
  }

  double get width => source.width;
  double get alphabeticBaseline => rows.first.alphabeticBaseline;
}

/// Allocates actual authored advances plus enough room for each row's measured
/// fonts and emphasis marks. Geometry and paint share this single frozen plan.
/// Local native ascent is stable even when subtracting large global native
/// baseline/box coordinates would lose the fraction near a rounding threshold.
/// This defines a NEW allocated baseline, not reconstruction of an original
/// paragraph's hidden rounded glyph origin. Glyphs and logical paint each get
/// an explicit translation; neither is rounded again by the allocation.
final class ForumBodyEmphasisRowAllocationPreparation {
  ForumBodyEmphasisRowAllocationPreparation({
    required ForumBodyEmphasisLineMetrics source,
    required ForumBodyParagraphRowReference reference,
    required ForumBodyParagraphLineFrames naturalFrames,
    required ForumBodyParagraphLineFrames isolatedFrames,
    required List<ForumBodyParagraphPhysicalLineSelector> physicalLines,
    required void Function() ensureOwner,
    ForumBodyParagraphPaintInput? paintInput,
    this.maxLines = 64,
    this.maxMarks = 512,
    this.maxHeight = 1048576,
  }) : _source = source,
       _reference = reference,
       _natural = naturalFrames,
       _isolated = isolatedFrames,
       _ensureOwner = ensureOwner,
       _paintInput = paintInput {
    if (maxLines <= 0 ||
        maxMarks < 0 ||
        !maxHeight.isFinite ||
        maxHeight <= 0) {
      throw ArgumentError('Invalid emphasis allocation budget');
    }
    try {
      _guard();
      final row = source.rowInput?.row;
      if (row == null ||
          (paintInput != null &&
              !identical(paintInput.original, reference.content)) ||
          reference.content.paintLayer != ForumBodyParagraphPaintLayer.all ||
          !identical(row.parentContent, reference.content) ||
          row.nativeInputIdentity != reference.isolatedInputIdentity ||
          !identical(naturalFrames.content, reference.content) ||
          !identical(isolatedFrames.content, reference.content) ||
          naturalFrames.nativeInputIdentity != reference.naturalInputIdentity ||
          isolatedFrames.nativeInputIdentity !=
              reference.isolatedInputIdentity ||
          !identical(naturalFrames.lines, reference.naturalLines) ||
          !identical(isolatedFrames.lines, reference.isolatedLines) ||
          row.rowIsolationPitch != reference.rowIsolationPitch ||
          physicalLines.length != row.lineCount) {
        _fail(ForumBodyEmphasisAllocationFailure.source);
      }
      if (physicalLines.length > maxLines || source.marks.length > maxMarks) {
        _fail(ForumBodyEmphasisAllocationFailure.limit);
      }
      // This copy is bounded by the admitted complete group. Mutable caller
      // lists cannot replace a qualified physical selector during preparation.
      _lines = List.unmodifiable(physicalLines);
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int maxLines, maxMarks;
  final double maxHeight;
  ForumBodyEmphasisLineMetrics? _source;
  ForumBodyParagraphRowReference? _reference;
  ForumBodyParagraphPaintInput? _paintInput;
  ForumBodyParagraphLineFrames? _natural, _isolated;
  List<ForumBodyParagraphPhysicalLineSelector>? _lines;
  void Function()? _ensureOwner;
  List<Rect>? _fonts = [], _extents = [];
  List<ForumBodyEmphasisAllocatedRow>? _rows = [];
  List<ForumBodyEmphasisAllocatedMark>? _marks = [];
  ForumBodyEmphasisRowAllocation? _result;
  Rect? _envelope;
  int _font = 0, _mark = 0, _row = 0, _placedMark = 0;
  double _height = 0;
  bool _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Emphasis allocation is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (used < maxParts && !isReady) {
        final source = _source!, group = source.rowInput!.row;
        if (_font < _lines!.length) {
          final index = _font++, physical = _lines![index];
          if (physical.lineIndex != group.selector.startLine + index ||
              !physical.matchesInput(
                nativeInputIdentity: group.nativeInputIdentity,
                group: group.selector,
              )) {
            _fail(ForumBodyEmphasisAllocationFailure.source);
          }
          final font = physical.fontBounds.shift(
            source.baseOffset - Offset(0, group.selector.originY),
          );
          _rect(font);
          _fonts!.add(font);
          _extents!.add(font);
        } else if (_mark < source.marks.length) {
          final mark = source.marks[_mark++];
          if (mark.lineIndex < 0 || mark.lineIndex >= _lines!.length) {
            _fail(ForumBodyEmphasisAllocationFailure.source);
          }
          _rect(mark.fontBounds);
          _offset(mark.offset);
          _extents![mark.lineIndex] = _extents![mark.lineIndex].expandToInclude(
            mark.fontBounds,
          );
        } else if (_row < _lines!.length) {
          _allocate(_row++);
        } else if (_placedMark < source.marks.length) {
          final index = _placedMark++, mark = source.marks[index];
          final offset = Offset(0, _rows![mark.lineIndex].sourceTranslationY);
          _marks!.add((
            markIndex: index,
            offset: mark.offset + offset,
            fontBounds: mark.fontBounds.shift(offset),
          ));
        } else {
          _result = ForumBodyEmphasisRowAllocation._(
            source: source,
            reference: _reference!,
            rows: _rows!,
            marks: _marks!,
            height: _height,
            fontBounds: _envelope!,
            isolatedAlphabeticBaseline: _isolated!.nativeAlphabeticBaseline,
            paintInput: _paintInput,
          );
          _rows = null;
          _marks = null;
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
    final source = _source!, group = source.rowInput!.row;
    final absolute = group.selector.startLine + index;
    final natural = _reference!.naturalLines[absolute];
    final isolated = _reference!.isolatedLines[absolute];
    final frame = _natural!.frames[absolute];
    final ascent = natural.baseline - natural.top;
    final originalBaseline =
        isolated.baseline - group.selector.originY + source.baseOffset.dy;
    final extent = _extents![index];
    final top = extent.top - originalBaseline,
        bottom = extent.bottom - originalBaseline;
    final relativeBaseline = math.max(ascent, -top);
    final authoredAdvance = frame.flowBottom - frame.flowTop;
    final height = math.max(
      authoredAdvance + relativeBaseline - ascent,
      relativeBaseline + bottom,
    );
    final baseline = _height + relativeBaseline;
    final delta = baseline - originalBaseline;
    if (![
          ascent,
          relativeBaseline,
          authoredAdvance,
          height,
          baseline,
          delta,
        ].every((v) => v.isFinite) ||
        authoredAdvance < 0 ||
        height < 0) {
      _fail(ForumBodyEmphasisAllocationFailure.geometry);
    }
    if (_height + height > maxHeight) {
      _fail(ForumBodyEmphasisAllocationFailure.limit);
    }
    final shift = Offset(0, delta), bounds = extent.shift(shift);
    final isolatedGlyph =
        _isolated!.frames[absolute].flowTop +
        _isolated!.nativeAlphabeticBaseline.roundToDouble();
    _rows!.add(
      ForumBodyEmphasisAllocatedRow._(
        physicalLine: _lines![index],
        flowTop: _height,
        flowBottom: _height + height,
        alphabeticBaseline: baseline,
        fontBounds: _fonts![index].shift(shift),
        bounds: bounds,
        logicalOffset: Offset(
          source.baseOffset.dx,
          baseline - isolated.baseline,
        ),
        glyphOffset: Offset(source.baseOffset.dx, baseline - isolatedGlyph),
        sourceTranslationY: delta,
      ),
    );
    _envelope = _envelope?.expandToInclude(bounds) ?? bounds;
    // Only FINAL allocated advances accumulate here; native positions always
    // come from their measured tables, never a sum of tight metric heights.
    _height += height;
  }

  ForumBodyEmphasisRowAllocation takeAllocation() {
    if (_operating) throw StateError('Emphasis allocation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Emphasis allocation is incomplete');
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
    if (_closed) throw StateError('Emphasis allocation is retired');
    _ensureOwner!();
    if (_closed) throw StateError('Emphasis allocation is retired');
  }

  void close() {
    _closed = true;
    _source = null;
    _reference = null;
    _paintInput = null;
    _natural = null;
    _isolated = null;
    _lines = null;
    _ensureOwner = null;
    _fonts = null;
    _extents = null;
    _rows = null;
    _marks = null;
    _result = null;
    _envelope = null;
  }
}

void _offset(Offset value) {
  if (!value.dx.isFinite || !value.dy.isFinite) {
    _fail(ForumBodyEmphasisAllocationFailure.geometry);
  }
}

void _rect(Rect value) {
  if (!value.left.isFinite ||
      !value.top.isFinite ||
      !value.right.isFinite ||
      !value.bottom.isFinite ||
      value.width < 0 ||
      value.height < 0) {
    _fail(ForumBodyEmphasisAllocationFailure.geometry);
  }
}

Never _fail(ForumBodyEmphasisAllocationFailure failure) =>
    throw ForumBodyEmphasisAllocationException(failure);
