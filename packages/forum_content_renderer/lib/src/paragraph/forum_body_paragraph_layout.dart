import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_paragraph_content.dart';

enum ForumBodyParagraphLayoutFailure { width, scale, indent, direction, noWrap }

final class ForumBodyParagraphLayoutException implements Exception {
  const ForumBodyParagraphLayoutException(this.failure);
  final ForumBodyParagraphLayoutFailure failure;
  @override
  String toString() => 'ForumBodyParagraphLayoutException(${failure.name})';
}

/// Actual engine line geometry. Text ranges exclude the terminating hard break;
/// these are not sufficient by themselves to confirm a page's source coverage.
final class ForumBodyParagraphLine {
  const ForumBodyParagraphLine({
    required this.top,
    required this.bottom,
    required this.baseline,
    required this.left,
    required this.width,
    required this.startUtf16,
    required this.endUtf16,
  });
  final double top;
  final double bottom;
  final double baseline;
  final double left;
  final double width;
  final int startUtf16;
  final int endUtf16;
}

/// Owns one TextPainter layout, shared by geometry, paint, hit-test and boxes.
/// No caller can mutate the painter. The owner must dispose it after all views
/// release it; a disposed view fails before touching an engine resource.
final class ForumBodyParagraphLayout {
  ForumBodyParagraphLayout._(
    ForumBodyParagraphContent content,
    this._painter,
    this.width,
    this.height,
    List<ForumBodyParagraphLine> lines,
  ) : lines = List.unmodifiable(lines),
      identity = content.identity,
      path = content.path,
      projection = content.projection;

  factory ForumBodyParagraphLayout.create({
    required ForumBodyParagraphContent content,
    required double width,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    validateInputs(content: content, width: width, textScaler: textScaler);
    final painter = TextPainter(
      text: content.textSpan,
      textAlign: content.style.textAlign,
      textDirection: content.style.textDirection,
      textScaler: textScaler,
      locale: content.style.textStyle.locale,
      textWidthBasis: TextWidthBasis.parent,
    );
    try {
      // A fixed content width also avoids TextPainter's alignment resize path.
      painter.layout(minWidth: width, maxWidth: width);
      final lines = <ForumBodyParagraphLine>[];
      for (final metric in painter.computeLineMetrics()) {
        final position = painter.getPositionForOffset(
          Offset(
            metric.left + metric.width / 2,
            metric.baseline - metric.ascent / 2,
          ),
        );
        final range = painter.getLineBoundary(position);
        lines.add(
          ForumBodyParagraphLine(
            top: metric.baseline - metric.ascent,
            bottom: metric.baseline + metric.descent,
            baseline: metric.baseline,
            left: metric.left,
            width: metric.width,
            startUtf16: range.start,
            endUtf16: range.end,
          ),
        );
      }
      return ForumBodyParagraphLayout._(
        content,
        painter,
        width,
        painter.height,
        lines,
      );
    } catch (_) {
      painter.dispose();
      rethrow;
    }
  }

  /// Also used before a cache lookup so warm hits cannot bypass admission.
  static Map<double, double> validateInputs({
    required ForumBodyParagraphContent content,
    required double width,
    required TextScaler textScaler,
  }) {
    if (!width.isFinite || width <= 0 || width > 16384) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.width,
      );
    }
    if (content.style.indent.value != 0) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.indent,
      );
    }
    final scales = <double, double>{};
    for (final style in [
      content.style,
      ...content.runs.map((run) => run.style),
    ]) {
      if (style.textDirection != content.style.textDirection) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.direction,
        );
      }
      if (style.whiteSpace == ForumBodyWhiteSpace.pre) {
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

  static const backendRevision = 1;
  final ForumBodyIdentity identity;
  final String? path;
  final HtmlDisplayTextProjection projection;
  final TextPainter _painter;
  final double width;
  final double height;
  final List<ForumBodyParagraphLine> lines;
  bool _disposed = false;
  bool get isDisposed => _disposed;

  void _ensureOpen() {
    if (_disposed) throw StateError('Paragraph layout is disposed');
  }

  void paint(Canvas canvas, Offset offset) {
    _ensureOpen();
    _painter.paint(canvas, offset);
  }

  HtmlProjectedSourcePosition sourceAt(Offset offset) {
    _ensureOpen();
    final position = _painter.getPositionForOffset(offset);
    return projection.sourceAtUtf16(
      position.offset,
      affinity: position.affinity == TextAffinity.upstream
          ? HtmlProjectionAffinity.upstream
          : HtmlProjectionAffinity.downstream,
    );
  }

  List<TextBox> selectionBoxes(int startUtf16, int endUtf16) {
    _ensureOpen();
    RangeError.checkValueInInterval(startUtf16, 0, endUtf16, 'startUtf16');
    final start = projection
        .sourceAtUtf16(startUtf16, affinity: HtmlProjectionAffinity.upstream)
        .displayUtf16;
    final end = projection.sourceAtUtf16(endUtf16).displayUtf16;
    return List.unmodifiable(
      _painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      ),
    );
  }

  ForumBodyParagraphFragment fragment(int startLine, int endLine) {
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
    return ForumBodyParagraphFragment._(this, startLine, endLine);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _painter.dispose();
  }
}

/// A line view borrows the existing paragraph; it never shapes page HTML.
final class ForumBodyParagraphFragment {
  const ForumBodyParagraphFragment._(
    this._layout,
    this.startLine,
    this.endLine,
  );
  final ForumBodyParagraphLayout _layout;
  final int startLine;
  final int endLine;
  ForumBodyParagraphLayout get layout => _layout;
  double get top => startLine == 0 ? 0 : _layout.lines[startLine].top;
  double get bottom => endLine == _layout.lines.length
      ? _layout.height
      : _layout.lines[endLine].top;
  double get height => bottom - top;
  int get startUtf16 => _layout.lines[startLine].startUtf16;
  int get endUtf16 => _layout.lines[endLine - 1].endUtf16;

  void paint(Canvas canvas, Offset offset) {
    _layout._ensureOpen();
    canvas.save();
    try {
      canvas.clipRect(
        Rect.fromLTWH(offset.dx, offset.dy, _layout.width, height),
      );
      _layout.paint(canvas, offset - Offset(0, top));
    } finally {
      canvas.restore();
    }
  }

  HtmlProjectedSourcePosition sourceAt(Offset offset) =>
      _layout.sourceAt(offset + Offset(0, top));
}
