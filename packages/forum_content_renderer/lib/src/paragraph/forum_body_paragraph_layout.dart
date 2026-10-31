import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_paragraph_content.dart';

enum ForumBodyParagraphLayoutFailure {
  width,
  scale,
  indent,
  direction,
  noWrap,
  singleLine,
  coverage,
}

/// Logical hard-break flow can display the pre-break rows and the final empty
/// row separately, without shaping again or inventing a blank-line height.
enum ForumBodyParagraphWindow {
  full,
  beforeTerminalEmptyLine,
  terminalEmptyLine,
}

final class ForumBodyParagraphLayoutException implements Exception {
  const ForumBodyParagraphLayoutException(this.failure);
  final ForumBodyParagraphLayoutFailure failure;
  @override
  String toString() => 'ForumBodyParagraphLayoutException(${failure.name})';
}

/// Actual engine line geometry. Paint/hit ranges exclude terminating hard
/// breaks. Display coverage includes those breaks and partitions the projected
/// paragraph; it does not prove App semantic or persisted-anchor coverage.
/// A fallback grapheme can span physical rows: only boundaries marked legal
/// may start/end a fragment, so such rows stay together during pagination.
final class ForumBodyParagraphLine {
  const ForumBodyParagraphLine({
    required this.top,
    required this.bottom,
    required this.baseline,
    required this.left,
    required this.width,
    required this.startUtf16,
    required this.endUtf16,
    required this.coverageStartUtf16,
    required this.coverageEndUtf16,
    required this.canBreakBefore,
    required this.canBreakAfter,
  });
  final double top;
  final double bottom;
  final double baseline;
  final double left;
  final double width;
  final int startUtf16;
  final int endUtf16;
  final int coverageStartUtf16;
  final int coverageEndUtf16;
  final bool canBreakBefore;
  final bool canBreakAfter;
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
    this._paintScale,
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
    final fitted =
        content.layoutMode == ForumBodyParagraphLayoutMode.fitSingleLine;
    final painter = TextPainter(
      text: content.textSpan,
      textAlign: content.style.textAlign,
      textDirection: content.style.textDirection,
      textScaler: textScaler,
      locale: content.style.textStyle.locale,
      textWidthBasis: TextWidthBasis.parent,
    );
    try {
      // Shape at the selected font/scaler first. Fitting transforms that same
      // layout, rather than measuring repeatedly at guessed smaller font sizes.
      painter.layout(
        minWidth: width,
        maxWidth: fitted ? double.infinity : width,
      );
      final paintScale = fitted && painter.width > width
          ? width / painter.width
          : 1.0;
      if (!paintScale.isFinite || paintScale <= 0) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.scale,
        );
      }
      final metrics = painter.computeLineMetrics();
      if (fitted && metrics.length > 1) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.singleLine,
        );
      }
      final text = content.projection.text;
      final lines = <ForumBodyParagraphLine>[];
      var start = 0;
      for (final metric in metrics) {
        // Follow logical line boundaries. A visual midpoint can hit the same
        // fallback grapheme on two physical lines and repeat the earlier range.
        var range = painter.getLineBoundary(TextPosition(offset: start));
        if (range.start < 0 ||
            range.end < range.start ||
            range.end > text.length) {
          throw const ForumBodyParagraphLayoutException(
            ForumBodyParagraphLayoutFailure.coverage,
          );
        }
        // At the empty line after a terminal hard break, the engine may return
        // the previous line (including that break) for position == text.length.
        // Normalize this explicit empty-line case and any included separator;
        // do not infer arbitrary line boundaries from character counts.
        if (metric.lineNumber == metrics.length - 1 &&
            metric.width == 0 &&
            start == text.length &&
            text.isNotEmpty &&
            _isDisplayLineBreak(text.codeUnitAt(text.length - 1))) {
          range = TextRange.collapsed(text.length);
        } else if (metric.hardBreak &&
            range.end > range.start &&
            _isDisplayLineBreak(text.codeUnitAt(range.end - 1))) {
          range = TextRange(start: range.start, end: range.end - 1);
        }
        var end = range.end;
        if (metric.hardBreak &&
            end < text.length &&
            _isDisplayLineBreak(text.codeUnitAt(end))) {
          end++;
        }
        if (range.start != start ||
            range.end < start ||
            range.end > end ||
            end > text.length) {
          throw const ForumBodyParagraphLayoutException(
            ForumBodyParagraphLayoutFailure.coverage,
          );
        }
        lines.add(
          ForumBodyParagraphLine(
            top: (metric.baseline - metric.ascent) * paintScale,
            bottom: (metric.baseline + metric.descent) * paintScale,
            baseline: metric.baseline * paintScale,
            left: metric.left * paintScale,
            width: metric.width * paintScale,
            startUtf16: range.start,
            endUtf16: range.end,
            coverageStartUtf16: start,
            coverageEndUtf16: end,
            canBreakBefore:
                content.projection.sourceAtUtf16(start).displayUtf16 == start,
            canBreakAfter:
                content.projection.sourceAtUtf16(end).displayUtf16 == end,
          ),
        );
        start = end;
      }
      if (start != text.length) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.coverage,
        );
      }
      return ForumBodyParagraphLayout._(
        content,
        painter,
        width,
        painter.height * paintScale,
        paintScale,
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
    if (content.layoutMode == ForumBodyParagraphLayoutMode.fitSingleLine &&
        content.projection.text.runes.any(
          (rune) => _isDisplayLineBreak(rune) || rune == 0x0d || rune == 0x85,
        )) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.singleLine,
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
      if (style.whiteSpace == ForumBodyWhiteSpace.pre &&
          content.layoutMode != ForumBodyParagraphLayoutMode.fitSingleLine) {
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

  static const backendRevision = 3;
  static bool _isDisplayLineBreak(int codeUnit) =>
      codeUnit == 0x0a || codeUnit == 0x2028 || codeUnit == 0x2029;
  final ForumBodyIdentity identity;
  final String? path;
  final HtmlDisplayTextProjection projection;
  final TextPainter _painter;
  final double width;
  final double height;
  final double _paintScale;
  final List<ForumBodyParagraphLine> lines;
  bool _disposed = false;
  bool get isDisposed => _disposed;

  void _ensureOpen() {
    if (_disposed) throw StateError('Paragraph layout is disposed');
  }

  void paint(Canvas canvas, Offset offset) {
    _ensureOpen();
    if (_paintScale == 1) {
      _painter.paint(canvas, offset);
      return;
    }
    canvas.save();
    try {
      canvas.translate(offset.dx, offset.dy);
      canvas.scale(_paintScale, _paintScale);
      _painter.paint(canvas, Offset.zero);
    } finally {
      canvas.restore();
    }
  }

  HtmlProjectedSourcePosition sourceAt(Offset offset) {
    _ensureOpen();
    final position = _painter.getPositionForOffset(offset / _paintScale);
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
    final boxes = _painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    return List.unmodifiable([
      for (final box in boxes)
        if (_paintScale == 1)
          box
        else
          TextBox.fromLTRBD(
            box.left * _paintScale,
            box.top * _paintScale,
            box.right * _paintScale,
            box.bottom * _paintScale,
            box.direction,
          ),
    ]);
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
    if (!lines[startLine].canBreakBefore || !lines[endLine - 1].canBreakAfter) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.coverage,
      );
    }
    return ForumBodyParagraphFragment._(this, startLine, endLine);
  }

  /// Restricted windows over an already shaped paragraph, not a seek or HTML
  /// slicing API. Non-full windows require the actual terminal empty hard-break
  /// row. Its source coverage is empty; the preceding row owns the separator.
  ({int startLine, int endLine}) lineWindow(ForumBodyParagraphWindow window) {
    _ensureOpen();
    if (window == ForumBodyParagraphWindow.full) {
      return (startLine: 0, endLine: lines.length);
    }
    final length = projection.text.length;
    if (lines.length < 2 ||
        length == 0 ||
        !_isDisplayLineBreak(projection.text.codeUnitAt(length - 1)) ||
        lines.last.width != 0 ||
        lines.last.coverageStartUtf16 != length ||
        lines.last.coverageEndUtf16 != length) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.coverage,
      );
    }
    return window == ForumBodyParagraphWindow.beforeTerminalEmptyLine
        ? (startLine: 0, endLine: lines.length - 1)
        : (startLine: lines.length - 1, endLine: lines.length);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _painter.dispose();
  }
}

/// A line view borrows the existing paragraph; it never shapes page HTML.
/// Boundaries must contain complete display graphemes, possibly spanning rows.
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
  int get coverageStartUtf16 => _layout.lines[startLine].coverageStartUtf16;
  int get coverageEndUtf16 => _layout.lines[endLine - 1].coverageEndUtf16;

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
