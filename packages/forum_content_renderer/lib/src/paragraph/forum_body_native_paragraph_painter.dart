import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'forum_body_paragraph_geometry.dart';
import 'forum_body_paragraph_painter.dart';

/// One owned native paragraph, using the public TextSpan/TextStyle builder
/// contracts. Fixed/wrapping and intrinsic/fitted layouts share this resource.
/// Parent width and alignment offsets follow the same native inputs as Flutter.
final class ForumBodyNativeParagraphPainter
    implements ForumBodyParagraphPainter {
  ForumBodyNativeParagraphPainter({
    required TextSpan text,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    this.locale,
    this.strutStyle,
  }) : _text = text;
  TextSpan _text;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final StrutStyle? strutStyle;
  ui.Paragraph? _paragraph;
  List<ui.LineMetrics>? _metrics;
  List<ForumBodyParagraphLineRange>? _ranges;
  double? _width;
  Offset _paintOffset = Offset.zero;
  bool _disposed = false;
  bool _layingOut = false;

  void _ensureOpen() {
    if (_disposed) throw StateError('Native paragraph painter is disposed');
  }

  ui.Paragraph get _laidOut {
    _ensureOpen();
    if (_width == null) throw StateError('Native paragraph is not laid out');
    return _paragraph!;
  }

  @override
  set text(TextSpan value) {
    _ensureOpen();
    if (_layingOut) throw StateError('Native paragraph layout is reentrant');
    if (identical(value, _text)) return;
    _text = value;
    _width = null;
    _metrics = null;
    _ranges = null;
    final previous = _paragraph;
    _paragraph = null;
    previous?.dispose();
  }

  double get _alignment => switch ((textAlign, textDirection)) {
    (TextAlign.left, _) => 0,
    (TextAlign.right, _) => 1,
    (TextAlign.center, _) => .5,
    (TextAlign.start || TextAlign.justify, TextDirection.ltr) => 0,
    (TextAlign.start || TextAlign.justify, TextDirection.rtl) => 1,
    (TextAlign.end, TextDirection.ltr) => 1,
    (TextAlign.end, TextDirection.rtl) => 0,
  };

  @override
  void layout({double minWidth = 0, double maxWidth = double.infinity}) {
    _ensureOpen();
    if (_layingOut) throw StateError('Native paragraph layout is reentrant');
    if (!minWidth.isFinite ||
        minWidth < 0 ||
        maxWidth.isNaN ||
        maxWidth < minWidth) {
      throw ArgumentError('Invalid native paragraph width');
    }
    _layingOut = true;
    _width = null;
    _metrics = null;
    _ranges = null;
    try {
      if (_paragraph == null) {
        final builder = ui.ParagraphBuilder(
          (_text.style ?? const TextStyle()).getParagraphStyle(
            textAlign: textAlign,
            textDirection: textDirection,
            textScaler: textScaler,
            locale: locale,
            strutStyle: strutStyle,
          ),
        );
        _text.build(builder, textScaler: textScaler);
        final built = builder.build();
        if (_disposed) {
          built.dispose();
          _ensureOpen();
        }
        _paragraph = built;
      }
      final paragraph = _paragraph!;
      paragraph.layout(ui.ParagraphConstraints(width: maxWidth));
      final width = paragraph.maxIntrinsicWidth
          .clamp(minWidth, maxWidth)
          .toDouble();
      final alignment = _alignment;
      if (!maxWidth.isFinite && alignment != 0) {
        // Reflow the same shaped paragraph to a finite intrinsic extent. An
        // infinite aligned paragraph otherwise has an infinite paint origin.
        paragraph.layout(
          ui.ParagraphConstraints(width: paragraph.maxIntrinsicWidth),
        );
      }
      _paintOffset = alignment == 0
          ? Offset.zero
          : Offset(alignment * (width - paragraph.width), 0);
      _width = width;
    } finally {
      _layingOut = false;
    }
  }

  double get width {
    _laidOut;
    return _width!;
  }

  double get height => _laidOut.height;
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      switch (baseline) {
        TextBaseline.alphabetic => _laidOut.alphabeticBaseline,
        TextBaseline.ideographic => _laidOut.ideographicBaseline,
      };

  @override
  List<ui.LineMetrics> computeLineMetrics() {
    final paragraph = _laidOut;
    return _metrics ??= List.unmodifiable([
      for (final row in paragraph.computeLineMetrics())
        ui.LineMetrics(
          hardBreak: row.hardBreak,
          ascent: row.ascent,
          descent: row.descent,
          unscaledAscent: row.unscaledAscent,
          height: row.height,
          width: row.width,
          left: row.left + _paintOffset.dx,
          baseline: row.baseline,
          lineNumber: row.lineNumber,
        ),
    ]);
  }

  int? getLineNumberAt(int codeUnitOffset) =>
      _laidOut.getLineNumberAt(codeUnitOffset);

  @override
  ForumBodyParagraphLineRange lineBoundaryForRow(
    int lineNumber,
    int startUtf16,
  ) {
    final paragraph = _laidOut;
    final ranges = _ranges ??= _readLineRanges(
      paragraph,
      computeLineMetrics(),
      _text.toPlainText(includeSemanticsLabels: false),
    );
    RangeError.checkValidIndex(lineNumber, ranges, 'lineNumber');
    final range = ranges[lineNumber];
    if (range.range.start != startUtf16) _coverage();
    // Preparation publishes its own immutable rows. Retire this scratch index
    // after the final row instead of retaining a second boundary table per lease.
    if (lineNumber == ranges.length - 1) _ranges = null;
    return range;
  }

  // getLineBoundary can recompute native line metrics for every call.
  // Invert native logical line numbers instead; no visual coordinate or guessed
  // character capacity is used to authorize a source boundary.
  static List<ForumBodyParagraphLineRange> _readLineRanges(
    ui.Paragraph paragraph,
    List<ui.LineMetrics> metrics,
    String text,
  ) {
    final result = <ForumBodyParagraphLineRange>[];
    var start = 0;
    for (var i = 0; i < metrics.length; i++) {
      // This backend has no maxLines/ellipsis: its final physical row owns the
      // known source EOF, including trailing controls and the real empty row.
      var end = text.length;
      if (i + 1 < metrics.length) {
        if (start >= text.length || paragraph.getLineNumberAt(start) != i) {
          _coverage();
        }
        var low = start + 1, high = text.length;
        while (low < high) {
          final middle = low + (high - low) ~/ 2;
          final row = paragraph.getLineNumberAt(middle);
          if (row == null || row > i) {
            high = middle;
          } else if (row == i) {
            low = middle + 1;
          } else {
            _coverage();
          }
        }
        end = low;
      }
      var paintedEnd = end;
      if (metrics[i].hardBreak &&
          end > start &&
          forumBodyIsDisplayLineBreak(text.codeUnitAt(end - 1))) {
        paintedEnd--;
      }
      result.add((
        range: TextRange(start: start, end: paintedEnd),
        coverageEndUtf16: end,
      ));
      start = end;
    }
    return List.unmodifiable(result);
  }

  @override
  List<TextBox> getBoxesForSelection(TextSelection selection) {
    final paragraph = _laidOut;
    if (!selection.isValid) return const [];
    return [
      for (final box in paragraph.getBoxesForRange(
        selection.start,
        selection.end,
      ))
        TextBox.fromLTRBD(
          box.left + _paintOffset.dx,
          box.top,
          box.right + _paintOffset.dx,
          box.bottom,
          box.direction,
        ),
    ];
  }

  TextPosition getPositionForOffset(Offset offset) =>
      _laidOut.getPositionForOffset(offset - _paintOffset);
  ui.GlyphInfo? glyphInfoAt(int offset) {
    final glyph = _laidOut.getGlyphInfoAt(offset);
    return glyph == null
        ? null
        : ui.GlyphInfo(
            glyph.graphemeClusterLayoutBounds.shift(_paintOffset),
            glyph.graphemeClusterCodeUnitRange,
            glyph.writingDirection,
          );
  }

  void paint(Canvas canvas, Offset offset) =>
      canvas.drawParagraph(_laidOut, offset + _paintOffset);
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final paragraph = _paragraph;
    _paragraph = null;
    _metrics = null;
    _ranges = null;
    _width = null;
    paragraph?.dispose();
  }

  static Never _coverage() => throw const ForumBodyParagraphLayoutException(
    ForumBodyParagraphLayoutFailure.coverage,
  );
}
