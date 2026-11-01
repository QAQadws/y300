import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import '../paragraph/forum_body_native_paragraph_layout.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_inline_span_content.dart';

sealed class ForumBodyInlineHit {
  const ForumBodyInlineHit();
}

final class ForumBodyInlineTextHit extends ForumBodyInlineHit {
  const ForumBodyInlineTextHit(this.position);
  final HtmlProjectedSourcePosition position;
}

/// Resolve this local point with the actual, scope-matching child layout.
/// A parent placeholder cannot provide a precise child source coordinate.
final class ForumBodyInlineAtomHit extends ForumBodyInlineHit {
  const ForumBodyInlineAtomHit(this.index, this.offset);
  final int index;
  final Offset offset;
}

final class ForumBodyInlineAtomSelection {
  const ForumBodyInlineAtomSelection(
    this.index,
    this.startUtf16,
    this.endUtf16,
  );
  final int index;

  /// Parent display coordinates, not engine or child-local UTF-16 offsets.
  final int startUtf16;
  final int endUtf16;
}

final class ForumBodyInlineSelection {
  ForumBodyInlineSelection._(
    List<TextBox> textBoxes,
    List<ForumBodyInlineAtomSelection> atoms,
  ) : textBoxes = List.unmodifiable(textBoxes),
      atoms = List.unmodifiable(atoms);
  final List<TextBox> textBoxes;

  /// Child display windows, not rectangular placeholder selection substitutes.
  final List<ForumBodyInlineAtomSelection> atoms;
}

/// One native parent paragraph, containing ordinary text and opaque inline
/// slots. Owns only its parent TextPainter; children are prepared separately.
/// Engine and display coordinates remain explicit in every line/fragment.
final class ForumBodyInlineParagraphLayout
    implements ForumBodyNativeParagraphLayout {
  ForumBodyInlineParagraphLayout._({
    required this.projection,
    required TextPainter painter,
    required this.width,
    required this.height,
    required this.lines,
    required this.atomBoxes,
    required this.dimensions,
    required Offset paintOffset,
    required Float64List frameTops,
    required Float64List frameBottoms,
    Uint8List? trimmedAtoms,
    Float64List? spaceAllocations,
  }) : _painter = painter,
       _frameTops = frameTops,
       _frameBottoms = frameBottoms,
       _paintOffset = paintOffset,
       _trimmedAtoms = trimmedAtoms,
       _spaceAllocations = spaceAllocations;
  static const revision = 4;

  factory ForumBodyInlineParagraphLayout.create({
    required ForumBodyInlineSpanContent content,
    required double width,
    required List<PlaceholderDimensions> dimensions,
    TextScaler textScaler = TextScaler.noScaling,
    ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) {
    final snapshot = List<PlaceholderDimensions>.unmodifiable(dimensions);
    validateInputs(
      content: content,
      width: width,
      dimensions: snapshot,
      textScaler: textScaler,
      layoutMode: layoutMode,
    );
    final intrinsic =
        layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine;
    final painter =
        TextPainter(
          text: content.projection.hasSoftSpaces
              ? content.textSpanWithDimensions(snapshot)
              : content.textSpan,
          textAlign: content.style.textAlign,
          textDirection: content.style.textDirection,
          textScaler: textScaler,
          locale: content.style.textStyle.locale,
          textWidthBasis: TextWidthBasis.parent,
        )..setPlaceholderDimensions(
          content.projection.hasSoftSpaces
              ? [
                  for (final (i, atom) in content.projection.atoms.indexed)
                    if (!atom.isSoftSpace) snapshot[i],
                ]
              : snapshot,
        );
    try {
      painter.layout(
        minWidth: intrinsic ? 0 : width,
        maxWidth: intrinsic ? double.infinity : width,
      );
      final layoutWidth = intrinsic ? painter.width : width;
      if (!layoutWidth.isFinite || layoutWidth < 0 || layoutWidth > 16384) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.width,
        );
      }
      final lines = forumBodyParagraphLines(
        painter: painter,
        display: content.projection.display,
        inline: content.projection,
      );
      if (intrinsic && lines.length > 1) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.singleLine,
        );
      }
      final nativeBoxes = List<TextBox>.unmodifiable(
        painter.inlinePlaceholderBoxes ?? const [],
      );
      final slots = _inlineSlots(
        painter,
        content,
        snapshot,
        lines,
        nativeBoxes,
      );
      final boxes = slots.boxes;
      if (boxes.length != snapshot.length ||
          !painter.height.isFinite ||
          painter.height < 0) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.coverage,
        );
      }
      final frameTops = Float64List(lines.length)
        ..fillRange(0, lines.length, double.infinity);
      final frameBottoms = Float64List(lines.length)
        ..fillRange(0, lines.length, double.negativeInfinity);
      var lineIndex = 0;
      for (var i = 0; i < boxes.length; i++) {
        final box = boxes[i];
        final dimension = snapshot[i];
        final atom = content.projection.atoms[i];
        while (lineIndex < lines.length &&
            lines[lineIndex].engineCoverageEndUtf16 <= atom.engineUtf16) {
          lineIndex++;
        }
        if (lineIndex >= lines.length ||
            !box.left.isFinite ||
            !box.top.isFinite ||
            !box.right.isFinite ||
            !box.bottom.isFinite) {
          throw const ForumBodyParagraphLayoutException(
            ForumBodyParagraphLayoutFailure.coverage,
          );
        }
        if (slots.trimmed?[i] == 1) continue;
        if ((box.right - box.left - dimension.size.width).abs() > 1e-3 ||
            (box.bottom - box.top - dimension.size.height).abs() > 1e-3 ||
            (box.top + dimension.baselineOffset! - lines[lineIndex].baseline)
                    .abs() >
                1e-3 ||
            box.top < lines[lineIndex].top - 1e-3 ||
            box.bottom > lines[lineIndex].bottom + 1e-3) {
          throw const ForumBodyParagraphLayoutException(
            ForumBodyParagraphLayoutFailure.coverage,
          );
        }
        if (box.top < frameTops[lineIndex]) frameTops[lineIndex] = box.top;
        final childBottom = box.top + dimension.size.height;
        if (box.bottom > frameBottoms[lineIndex]) {
          frameBottoms[lineIndex] = box.bottom;
        }
        if (childBottom > frameBottoms[lineIndex]) {
          frameBottoms[lineIndex] = childBottom;
        }
      }
      // Native paragraph height rounds independently of placeholder metrics.
      // Keep the actual shaped baselines and reserve any outer slot overhang,
      // translating paint, hit tests, lines and boxes by the same frame origin.
      var top = 0.0;
      var bottom = painter.height;
      for (var i = 0; i < boxes.length; i++) {
        if (slots.trimmed?[i] == 1) continue;
        final box = boxes[i];
        if (box.top < top) top = box.top;
        if (box.bottom > bottom) bottom = box.bottom;
        final childBottom = box.top + snapshot[i].size.height;
        if (childBottom > bottom) bottom = childBottom;
      }
      final paintOffset = Offset(0, -top);
      // Adjacent native row intervals can overlap at fractional slot edges.
      // Monotone envelopes contain every owned child in O(1) per fragment;
      // baselines and full-paragraph geometry are never rounded or summed.
      var minTop = double.infinity;
      for (var i = lines.length - 1; i >= 0; i--) {
        if (frameTops[i] < minTop) minTop = frameTops[i];
        final logical = i == 0 ? top : lines[i].top;
        frameTops[i] = (minTop < logical ? minTop : logical) - top;
      }
      var maxBottom = double.negativeInfinity;
      for (var i = 0; i < lines.length; i++) {
        if (frameBottoms[i] > maxBottom) maxBottom = frameBottoms[i];
        final logical = i + 1 == lines.length ? bottom : lines[i + 1].top;
        frameBottoms[i] = (maxBottom > logical ? maxBottom : logical) - top;
      }
      return ForumBodyInlineParagraphLayout._(
        projection: content.projection,
        painter: painter,
        width: layoutWidth,
        height: bottom - top,
        lines: paintOffset == Offset.zero
            ? lines
            : List.unmodifiable(lines.map((line) => line.shift(paintOffset))),
        atomBoxes: paintOffset == Offset.zero
            ? boxes
            : List.unmodifiable(
                boxes.map((box) => _shiftBox(box, paintOffset)),
              ),
        dimensions: snapshot,
        paintOffset: paintOffset,
        frameTops: frameTops,
        frameBottoms: frameBottoms,
        trimmedAtoms: slots.trimmed,
        spaceAllocations: slots.allocations,
      );
    } catch (_) {
      painter.dispose();
      rethrow;
    }
  }

  /// Warm-cache admission uses exactly the same effective parent inputs.
  static Map<double, double> validateInputs({
    required ForumBodyInlineSpanContent content,
    required double width,
    required List<PlaceholderDimensions> dimensions,
    required TextScaler textScaler,
    ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) {
    if (!width.isFinite || width <= 0 || width > 16384) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.width,
      );
    }
    if (layoutMode == ForumBodyParagraphLayoutMode.fitSingleLine) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.singleLine,
      );
    }
    final intrinsic =
        layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine;
    if (!intrinsic && content.style.indent.value != 0) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.indent,
      );
    }
    content.validateDimensions(dimensions);
    if (!intrinsic &&
        dimensions.indexed.any(
          (item) =>
              !content.projection.atoms[item.$1].isSoftSpace &&
              item.$2.size.width > width,
        )) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.width,
      );
    }
    final scales = <double, double>{};
    for (final style in [
      content.style,
      ...content.parentRuns.map((run) => run.style),
    ]) {
      if (style.textDirection != content.style.textDirection) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.direction,
        );
      }
      if (!intrinsic && style.whiteSpace == ForumBodyWhiteSpace.pre) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.noWrap,
        );
      }
      final size = style.textStyle.fontSize!;
      final scaled = scales.putIfAbsent(size, () => textScaler.scale(size));
      if (!scaled.isFinite || scaled <= 0 || scaled > 4096) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.scale,
        );
      }
    }
    return scales;
  }

  /// Native source coordinates only. Current child style/interaction metadata
  /// belongs to the typed lease, not a reused engine's original input object.
  final HtmlInlineTextProjection projection;
  final TextPainter _painter;
  final Offset _paintOffset;
  final Float64List _frameTops;
  final Float64List _frameBottoms;
  final Uint8List? _trimmedAtoms;
  final Float64List? _spaceAllocations;
  int get fragmentFrameBytes =>
      _frameTops.lengthInBytes +
      _frameBottoms.lengthInBytes +
      (_trimmedAtoms?.lengthInBytes ?? 0) +
      (_spaceAllocations?.lengthInBytes ?? 0);

  bool isAtomTrimmed(int index) {
    _ensureOpen();
    RangeError.checkValidIndex(index, projection.atoms, 'index');
    return _trimmedAtoms?[index] == 1;
  }

  Iterable<int> get trimmedAtomIndices sync* {
    _ensureOpen();
    final mask = _trimmedAtoms;
    if (mask == null) return;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 1) yield i;
    }
  }

  final double width;
  final double height;
  final List<ForumBodyParagraphLine> lines;
  @override
  int get lineCount => lines.length;
  final List<TextBox> atomBoxes;
  final List<PlaceholderDimensions> dimensions;
  bool _disposed = false;
  @override
  bool get isDisposed => _disposed;
  void _ensureOpen() {
    if (_disposed) throw StateError('Inline parent layout is disposed');
  }

  /// Paint only the ordinary parent glyphs. The consumer must paint prepared
  /// children at atomBoxes; this method alone is not a readable page delivery.
  void paintParent(Canvas canvas, Offset offset) {
    _ensureOpen();
    _painter.paint(canvas, offset + _paintOffset);
  }

  ForumBodyInlineHit hitAt(Offset offset) => _hitAt(offset);

  ForumBodyInlineHit _hitAt(
    Offset offset, {
    int engineStart = 0,
    int? engineEnd,
  }) {
    _ensureOpen();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    for (var i = 0; i < atomBoxes.length; i++) {
      final atom = projection.atoms[i];
      if (_trimmedAtoms?[i] == 1) continue;
      if (atom.engineUtf16 < engineStart ||
          (engineEnd != null && atom.engineUtf16 >= engineEnd)) {
        continue;
      }
      final box = atomBoxes[i];
      final rect = atom.isSoftSpace
          ? Rect.fromLTRB(
              _spaceAllocations![i * 2],
              box.top,
              _spaceAllocations[i * 2 + 1],
              box.bottom,
            )
          : box.toRect();
      if (rect.contains(offset)) {
        return ForumBodyInlineAtomHit(i, offset - box.toRect().topLeft);
      }
    }
    final position = _painter.getPositionForOffset(offset - _paintOffset);
    final source = projection.sourceAtEngineUtf16(
      position.offset,
      affinity: position.affinity == TextAffinity.upstream
          ? HtmlProjectionAffinity.upstream
          : HtmlProjectionAffinity.downstream,
    );
    final adjacentSpace =
        projection.hasSoftSpaces &&
        projection.atoms.any(
          (atom) =>
              atom.isSoftSpace &&
              position.offset >= atom.engineUtf16 &&
              position.offset <= atom.engineEndUtf16,
        );
    return ForumBodyInlineTextHit(
      adjacentSpace
          ? HtmlProjectedSourcePosition(
              sourceRune: source.sourceRune,
              displayUtf16: source.displayUtf16,
              isExact: false,
            )
          : source,
    );
  }

  ForumBodyInlineSelection selection(int startUtf16, int endUtf16) {
    _ensureOpen();
    final display = projection.display;
    RangeError.checkValidRange(startUtf16, endUtf16, display.text.length);
    if (startUtf16 == endUtf16) {
      return ForumBodyInlineSelection._(const [], const []);
    }
    final start = display
        .sourceAtUtf16(startUtf16, affinity: HtmlProjectionAffinity.upstream)
        .displayUtf16;
    final end = display.sourceAtUtf16(endUtf16).displayUtf16;
    final boxes = <TextBox>[];
    final selectedAtoms = <ForumBodyInlineAtomSelection>[];
    void text(int from, int to) {
      if (from >= to) return;
      boxes.addAll(
        _painter
            .getBoxesForSelection(
              TextSelection(
                baseOffset: projection.engineAtDisplayUtf16(from).engineUtf16,
                extentOffset: projection.engineAtDisplayUtf16(to).engineUtf16,
              ),
            )
            .map((box) => _shiftBox(box, _paintOffset)),
      );
    }

    var cursor = start;
    for (final atom in projection.atoms) {
      if (atom.displayEndUtf16 <= start) continue;
      if (atom.displayStartUtf16 >= end) break;
      text(cursor, atom.displayStartUtf16.clamp(start, end));
      if (_trimmedAtoms?[atom.index] != 1) {
        selectedAtoms.add(
          ForumBodyInlineAtomSelection(
            atom.index,
            atom.displayStartUtf16.clamp(start, end),
            atom.displayEndUtf16.clamp(start, end),
          ),
        );
      }
      cursor = atom.displayEndUtf16.clamp(start, end);
    }
    text(cursor, end);
    return ForumBodyInlineSelection._(boxes, selectedAtoms);
  }

  ({int startLine, int endLine}) lineWindow(ForumBodyParagraphWindow window) {
    _ensureOpen();
    return forumBodyParagraphLineWindow(
      lines: lines,
      displayText: projection.display.text,
      engineText: projection.engineText,
      window: window,
    );
  }

  ForumBodyInlineParagraphFragment fragment(int startLine, int endLine) {
    _ensureOpen();
    RangeError.checkValueInInterval(
      startLine,
      0,
      lines.length - 1,
      'startLine',
    );
    RangeError.checkValueInInterval(
      endLine,
      startLine + 1,
      lines.length,
      'endLine',
    );
    if (!lines[startLine].canBreakBefore || !lines[endLine - 1].canBreakAfter) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.coverage,
      );
    }
    return ForumBodyInlineParagraphFragment._(this, startLine, endLine);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _painter.dispose();
  }
}

/// The whitespace marker has no ink or vertical metrics. Only actual neighbour
/// rows decide whether it survives; a trimmed marker never grows a page frame.
({List<TextBox> boxes, Uint8List? trimmed, Float64List? allocations})
_inlineSlots(
  TextPainter painter,
  ForumBodyInlineSpanContent content,
  List<PlaceholderDimensions> dimensions,
  List<ForumBodyParagraphLine> lines,
  List<TextBox> nativeBoxes,
) {
  final projection = content.projection;
  if (!projection.hasSoftSpaces) {
    return (boxes: nativeBoxes, trimmed: null, allocations: null);
  }
  final atoms = projection.atoms;
  final rows = Int32List(atoms.length);
  final trimmed = Uint8List(atoms.length);
  final allocations = Float64List(atoms.length * 2);
  final boxes = List<TextBox>.filled(
    atoms.length,
    TextBox.fromLTRBD(0, 0, 0, 0, content.style.textDirection),
  );
  var row = 0;
  var native = 0;
  Never invalid() => throw const ForumBodyParagraphLayoutException(
    ForumBodyParagraphLayoutFailure.coverage,
  );
  for (final atom in atoms) {
    while (row < lines.length &&
        atom.engineUtf16 >= lines[row].engineCoverageEndUtf16) {
      row++;
    }
    if (row == lines.length ||
        atom.engineUtf16 < lines[row].engineCoverageStartUtf16) {
      invalid();
    }
    rows[atom.index] = row;
    if (!atom.isSoftSpace) {
      if (native == nativeBoxes.length) invalid();
      boxes[atom.index] = nativeBoxes[native++];
    }
  }
  if (native != nativeBoxes.length) invalid();
  for (final atom in atoms) {
    if (!atom.isSoftSpace) continue;
    final i = atom.index;
    final line = lines[rows[i]];
    if (rows[i - 1] != rows[i + 1] || rows[i] != rows[i - 1]) {
      trimmed[i] = 1;
      boxes[i] = TextBox.fromLTRBD(
        0,
        line.baseline,
        0,
        line.baseline,
        content.style.textDirection,
      );
      continue;
    }
    final d = dimensions[i];
    final nativeSpace = painter.getBoxesForSelection(
      TextSelection(
        baseOffset: atom.engineUtf16,
        extentOffset: atom.engineEndUtf16,
      ),
    );
    TextBox allocation;
    if (nativeSpace.isEmpty && d.size.width == 0) {
      final left = boxes[i - 1].right < boxes[i + 1].right
          ? boxes[i - 1].right
          : boxes[i + 1].right;
      allocation = TextBox.fromLTRBD(
        left,
        line.baseline,
        left,
        line.baseline,
        content.style.textDirection,
      );
    } else {
      if (nativeSpace.length != 1) invalid();
      allocation = nativeSpace.single;
    }
    // Detect a missing/replaced private font or changed native spacing instead
    // of silently accepting the platform's ordinary SPACE fallback metrics.
    final allocatedWidth = allocation.right - allocation.left;
    if (!allocatedWidth.isFinite ||
        allocatedWidth < d.size.width - 1e-3 ||
        (content.style.textAlign != TextAlign.justify &&
            (allocatedWidth - d.size.width).abs() > 1e-3) ||
        (allocation.top - line.baseline).abs() > 1e-3 ||
        (allocation.bottom - line.baseline).abs() > 1e-3) {
      invalid();
    }
    allocations[i * 2] = allocation.left;
    allocations[i * 2 + 1] = allocation.right;
    final left = allocation.left + (allocatedWidth - d.size.width) / 2;
    final top = line.baseline - d.baselineOffset!;
    boxes[i] = TextBox.fromLTRBD(
      left,
      top,
      left + d.size.width,
      top + d.size.height,
      allocation.direction,
    );
  }
  return (
    boxes: List.unmodifiable(boxes),
    trimmed: trimmed,
    allocations: allocations,
  );
}

TextBox _shiftBox(TextBox box, Offset offset) => offset == Offset.zero
    ? box
    : TextBox.fromLTRBD(
        box.left + offset.dx,
        box.top + offset.dy,
        box.right + offset.dx,
        box.bottom + offset.dy,
        box.direction,
      );

/// A verified line window borrowing one parent engine; never shapes again.
final class ForumBodyInlineParagraphFragment {
  const ForumBodyInlineParagraphFragment._(
    this.layout,
    this.startLine,
    this.endLine,
  );
  final ForumBodyInlineParagraphLayout layout;
  final int startLine;
  final int endLine;
  double get top => layout._frameTops[startLine];
  double get bottom => layout._frameBottoms[endLine - 1];
  double get height => bottom - top;
  int get coverageStartUtf16 => layout.lines[startLine].coverageStartUtf16;
  int get coverageEndUtf16 => layout.lines[endLine - 1].coverageEndUtf16;
  int get engineCoverageStartUtf16 =>
      layout.lines[startLine].engineCoverageStartUtf16;
  int get engineCoverageEndUtf16 =>
      layout.lines[endLine - 1].engineCoverageEndUtf16;

  Iterable<int> get atomIndices sync* {
    layout._ensureOpen();
    for (final atom in layout.projection.atoms) {
      if (atom.engineUtf16 >= engineCoverageStartUtf16 &&
          atom.engineUtf16 < engineCoverageEndUtf16 &&
          !layout.isAtomTrimmed(atom.index)) {
        yield atom.index;
      }
    }
  }

  void paintParent(Canvas canvas, Offset offset) {
    layout._ensureOpen();
    if (coverageStartUtf16 == coverageEndUtf16 &&
        engineCoverageStartUtf16 == engineCoverageEndUtf16) {
      return;
    }
    canvas.save();
    try {
      canvas.clipRect(
        // Expanded child frames must not expose ordinary text outside the
        // original parent row window. Children are painted independently.
        Rect.fromLTRB(
          offset.dx,
          offset.dy + (startLine == 0 ? 0 : layout.lines[startLine].top) - top,
          offset.dx + layout.width,
          offset.dy +
              (endLine == layout.lines.length
                  ? layout.height
                  : layout.lines[endLine].top) -
              top,
        ),
      );
      layout.paintParent(canvas, offset - Offset(0, top));
    } finally {
      canvas.restore();
    }
  }

  ForumBodyInlineHit hitAt(Offset offset) => layout._hitAt(
    offset + Offset(0, top),
    engineStart: engineCoverageStartUtf16,
    engineEnd: engineCoverageEndUtf16,
  );
}
