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
  }) : _painter = painter;
  static const revision = 1;

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
    final painter = TextPainter(
      text: content.textSpan,
      textAlign: content.style.textAlign,
      textDirection: content.style.textDirection,
      textScaler: textScaler,
      locale: content.style.textStyle.locale,
      textWidthBasis: TextWidthBasis.parent,
    )..setPlaceholderDimensions(snapshot);
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
      final boxes = List<TextBox>.unmodifiable(
        painter.inlinePlaceholderBoxes ?? const [],
      );
      if (boxes.length != snapshot.length ||
          !painter.height.isFinite ||
          painter.height < 0) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.coverage,
        );
      }
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
            !box.bottom.isFinite ||
            (box.right - box.left - dimension.size.width).abs() > 1e-3 ||
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
      }
      return ForumBodyInlineParagraphLayout._(
        projection: content.projection,
        painter: painter,
        width: layoutWidth,
        height: painter.height,
        lines: lines,
        atomBoxes: boxes,
        dimensions: snapshot,
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
        dimensions.any((dimension) => dimension.size.width > width)) {
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
    _painter.paint(canvas, offset);
  }

  ForumBodyInlineHit hitAt(Offset offset) {
    _ensureOpen();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    for (var i = 0; i < atomBoxes.length; i++) {
      final rect = atomBoxes[i].toRect();
      if (rect.contains(offset)) {
        return ForumBodyInlineAtomHit(i, offset - rect.topLeft);
      }
    }
    final position = _painter.getPositionForOffset(offset);
    return ForumBodyInlineTextHit(
      projection.sourceAtEngineUtf16(
        position.offset,
        affinity: position.affinity == TextAffinity.upstream
            ? HtmlProjectionAffinity.upstream
            : HtmlProjectionAffinity.downstream,
      ),
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
        _painter.getBoxesForSelection(
          TextSelection(
            baseOffset: projection.engineAtDisplayUtf16(from).engineUtf16,
            extentOffset: projection.engineAtDisplayUtf16(to).engineUtf16,
          ),
        ),
      );
    }

    var cursor = start;
    for (final atom in projection.atoms) {
      if (atom.displayEndUtf16 <= start) continue;
      if (atom.displayStartUtf16 >= end) break;
      text(cursor, atom.displayStartUtf16.clamp(start, end));
      selectedAtoms.add(
        ForumBodyInlineAtomSelection(
          atom.index,
          atom.displayStartUtf16.clamp(start, end),
          atom.displayEndUtf16.clamp(start, end),
        ),
      );
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
  double get top => startLine == 0 ? 0 : layout.lines[startLine].top;
  double get bottom => endLine == layout.lines.length
      ? layout.height
      : layout.lines[endLine].top;
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
          atom.engineUtf16 < engineCoverageEndUtf16) {
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
        Rect.fromLTWH(offset.dx, offset.dy, layout.width, height),
      );
      layout.paintParent(canvas, offset - Offset(0, top));
    } finally {
      canvas.restore();
    }
  }

  ForumBodyInlineHit hitAt(Offset offset) =>
      layout.hitAt(offset + Offset(0, top));
}
