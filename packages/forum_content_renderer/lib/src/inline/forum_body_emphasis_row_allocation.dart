import 'dart:collection';

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_line_frames.dart';
import '../paragraph/forum_body_paragraph_row.dart';
import '../paragraph/forum_body_paragraph_row_reference.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_text_request.dart';
import 'forum_body_emphasis_allocation_geometry.dart';

export 'forum_body_emphasis_allocation_geometry.dart'
    show
        ForumBodyEmphasisAllocationFailure,
        ForumBodyEmphasisAllocationException;

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
  });
  final ForumBodyParagraphPhysicalLineSelector physicalLine;
  final double flowTop, flowBottom, alphabeticBaseline;
  final Rect fontBounds, bounds;
  final Offset logicalOffset, glyphOffset;
}

/// Immutable allocation over measured source/font inputs. No native resource,
/// cache, callback, or live owner is retained. Current source/paint binding is
/// still required by a visible consumer, even after this plan survives eviction.
final class ForumBodyEmphasisRowAllocation {
  ForumBodyEmphasisRowAllocation._({
    required this.source,
    required this.reference,
    required List<ForumBodyEmphasisAllocatedRow> rows,
    required this.textScaler,
    required this.height,
    required this.fontBounds,
    required this.isolatedAlphabeticBaseline,
    required this.paintInput,
  }) : rows = UnmodifiableListView(rows);
  static const revision = 4;
  final ForumBodyParagraphRowMetrics source;
  final TextScaler textScaler;
  final ForumBodyParagraphRowReference reference;
  final List<ForumBodyEmphasisAllocatedRow> rows;
  final double height;
  final Rect fontBounds;
  final double isolatedAlphabeticBaseline;
  final ForumBodyParagraphPaintInput paintInput;

  /// All temporary fonts, including WHOLE parents for every paint phase.
  /// A final scene has its own input/lease admission in the visible transaction.
  Iterable<ForumBodyNativeRequestSlot> get nativeFootprint sync* {
    yield (
      request: ForumBodyTextRequest.paragraph(
        reference.content,
        rowIsolationPitch: reference.rowIsolationPitch,
      ),
      width: width,
      minimumLineCount: reference.lineCount,
    );
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
        width: width,
        minimumLineCount: reference.lineCount,
      );
    }
  }

  double get width => source.width;
  double get alphabeticBaseline => rows.first.alphabeticBaseline;
}

/// Allocates authored advances and enough room for each measured font frame.
/// Geometry and paint share this single frozen plan.
/// Local native ascent is stable even when subtracting large global native
/// baseline/box coordinates would lose the fraction near a rounding threshold.
/// This defines a NEW allocated baseline, not reconstruction of an original
/// paragraph's hidden rounded glyph origin. Glyphs and logical paint each get
/// an explicit translation; neither is rounded again by the allocation.
final class ForumBodyEmphasisRowAllocationPreparation {
  ForumBodyEmphasisRowAllocationPreparation({
    required ForumBodyParagraphRowMetrics source,
    required this.textScaler,
    required ForumBodyParagraphRowReference reference,
    required ForumBodyParagraphLineFrames naturalFrames,
    required ForumBodyParagraphLineFrames isolatedFrames,
    required List<ForumBodyParagraphPhysicalLineSelector> physicalLines,
    required void Function() ensureOwner,
    required ForumBodyParagraphPaintInput paintInput,
    this.maxLines = 64,
    this.maxHeight = 1048576,
  }) : _source = source,
       _reference = reference,
       _natural = naturalFrames,
       _isolated = isolatedFrames,
       _ensureOwner = ensureOwner,
       _paintInput = paintInput {
    if (maxLines <= 0 || !maxHeight.isFinite || maxHeight <= 0) {
      throw ArgumentError('Invalid emphasis allocation budget');
    }
    try {
      _guard();
      if (!identical(paintInput.original, reference.content) ||
          reference.content.paintLayer != ForumBodyParagraphPaintLayer.all ||
          !identical(source.parentContent, reference.content) ||
          source.nativeInputIdentity != reference.isolatedInputIdentity ||
          !identical(naturalFrames.content, reference.content) ||
          !identical(isolatedFrames.content, reference.content) ||
          naturalFrames.nativeInputIdentity != reference.naturalInputIdentity ||
          isolatedFrames.nativeInputIdentity !=
              reference.isolatedInputIdentity ||
          !identical(naturalFrames.lines, reference.naturalLines) ||
          !identical(isolatedFrames.lines, reference.isolatedLines) ||
          source.rowIsolationPitch != reference.rowIsolationPitch ||
          physicalLines.length != source.lineCount) {
        _fail(ForumBodyEmphasisAllocationFailure.source);
      }
      if (physicalLines.length > maxLines) {
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
  final int maxLines;
  final double maxHeight;
  final TextScaler textScaler;
  ForumBodyParagraphRowMetrics? _source;
  ForumBodyParagraphRowReference? _reference;
  ForumBodyParagraphPaintInput? _paintInput;
  ForumBodyParagraphLineFrames? _natural, _isolated;
  List<ForumBodyParagraphPhysicalLineSelector>? _lines;
  void Function()? _ensureOwner;
  List<ForumBodyEmphasisAllocatedRow>? _rows = [];
  ForumBodyEmphasisRowAllocation? _result;
  Rect? _envelope;
  int _row = 0;
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
        if (_row < _lines!.length) {
          _allocate(_row++);
        } else {
          _result = ForumBodyEmphasisRowAllocation._(
            source: _source!,
            reference: _reference!,
            rows: _rows!,
            textScaler: textScaler,
            height: _height,
            fontBounds: _envelope!,
            isolatedAlphabeticBaseline: _isolated!.nativeAlphabeticBaseline,
            paintInput: _paintInput!,
          );
          _rows = null;
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
    final group = _source!, physical = _lines![index];
    final absolute = group.selector.startLine + index;
    if (physical.lineIndex != absolute ||
        !physical.matchesInput(
          nativeInputIdentity: group.nativeInputIdentity,
          group: group.selector,
        )) {
      _fail(ForumBodyEmphasisAllocationFailure.source);
    }
    final extent = physical.fontBounds.shift(
      Offset(0, -group.selector.originY),
    );
    _rect(extent);
    final natural = _reference!.naturalLines[absolute];
    final isolated = _reference!.isolatedLines[absolute];
    final frame = _natural!.frames[absolute];
    final ascent = natural.baseline - natural.top;
    final originalBaseline = isolated.baseline - group.selector.originY;
    final authoredAdvance = frame.flowBottom - frame.flowTop;
    final allocated = forumBodyAllocateEmphasisRowFrame(
      ascent: ascent,
      authoredAdvance: authoredAdvance,
      originalBaseline: originalBaseline,
      extentTop: extent.top,
      extentBottom: extent.bottom,
      flowTop: _height,
      maxHeight: maxHeight,
    );
    final height = allocated.height,
        baseline = allocated.baseline,
        delta = allocated.translationY;
    final shift = Offset(0, delta), bounds = extent.shift(shift);
    final isolatedGlyph =
        _isolated!.frames[absolute].flowTop +
        _isolated!.nativeAlphabeticBaseline.roundToDouble();
    _rows!.add(
      ForumBodyEmphasisAllocatedRow._(
        physicalLine: physical,
        flowTop: _height,
        flowBottom: _height + height,
        alphabeticBaseline: baseline,
        fontBounds: bounds,
        bounds: bounds,
        logicalOffset: Offset(0, baseline - isolated.baseline),
        glyphOffset: Offset(0, baseline - isolatedGlyph),
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
    _rows = null;
    _result = null;
    _envelope = null;
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
