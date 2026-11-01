import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../inline/forum_body_native_space_span.dart';
import 'forum_body_first_line_indent.dart';
import 'forum_body_paragraph_content.dart';
import 'forum_body_paragraph_geometry.dart';
import 'forum_body_native_paragraph_layout.dart';
import 'forum_body_text_layout.dart';

export 'forum_body_paragraph_geometry.dart'
    show
        ForumBodyParagraphLayoutFailure,
        ForumBodyParagraphLayoutException,
        ForumBodyParagraphWindow,
        ForumBodyParagraphLine;

/// Owns one TextPainter layout, shared by geometry, paint, hit-test and boxes.
/// No caller can mutate the painter. The owner must dispose it after all views
/// release it; a disposed view fails before touching an engine resource.
final class ForumBodyParagraphLayout
    implements ForumBodyNativeParagraphLayout, ForumBodyTextLayout {
  ForumBodyParagraphLayout._(
    ForumBodyParagraphContent content,
    this._painter,
    this.width,
    this.height,
    this._paintScale,
    this._engineProjection,
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
    final scales = validateInputs(
      content: content,
      width: width,
      textScaler: textScaler,
    );
    final indent = resolveForumBodyFirstLineIndent(content, width, scales);
    final engine = indent > 0 ? content.indentedProjection : null;
    final fitted =
        content.layoutMode == ForumBodyParagraphLayoutMode.fitSingleLine;
    final intrinsic =
        content.layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine;
    final painter = TextPainter(
      text: engine == null
          ? content.textSpan
          : TextSpan(
              style: content.style.textStyle,
              children: [
                ForumBodyNativeSpaceSpan.nonBreaking(indent),
                ...content.textSpan.children!,
              ],
            ),
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
        minWidth: intrinsic ? 0 : width,
        maxWidth: fitted || intrinsic ? double.infinity : width,
      );
      final layoutWidth = intrinsic ? painter.width : width;
      if (!layoutWidth.isFinite || layoutWidth < 0 || layoutWidth > 16384) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.width,
        );
      }
      final paintScale = fitted && painter.width > width
          ? width / painter.width
          : 1.0;
      if (!paintScale.isFinite || paintScale <= 0) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.scale,
        );
      }
      final metrics = painter.computeLineMetrics();
      if (engine != null) {
        _validateIndentAdvance(painter, engine.enginePrefix.length, indent);
      }
      if ((fitted || intrinsic) && metrics.length > 1) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.singleLine,
        );
      }
      final lines = forumBodyParagraphLines(
        painter: painter,
        display: content.projection,
        paintScale: paintScale,
        inline: engine,
      );
      if (engine != null &&
          lines.isNotEmpty &&
          lines.first.coverageEndUtf16 == 0) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.indent,
        );
      }
      return ForumBodyParagraphLayout._(
        content,
        painter,
        layoutWidth,
        painter.height * paintScale,
        paintScale,
        engine,
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
    final scales = <double, double>{};
    content.layoutInput.resolveScalesInto(scales, textScaler: textScaler);
    resolveForumBodyFirstLineIndent(content, width, scales);
    return scales;
  }

  static const backendRevision = 6;
  final ForumBodyIdentity identity;
  final String? path;
  @override
  final HtmlDisplayTextProjection projection;
  final TextPainter _painter;
  @override
  final double width;
  @override
  final double height;
  final double _paintScale;
  final HtmlInlineTextProjection? _engineProjection;
  final List<ForumBodyParagraphLine> lines;
  @override
  int get lineCount => lines.length;
  @override
  double get alphabeticBaseline {
    _ensureOpen();
    // An empty native paragraph has a real font baseline but no text rows.
    // Preserve that strut without introducing a synthetic row or glyph.
    return lines.isEmpty
        ? _painter.computeDistanceToActualBaseline(TextBaseline.alphabetic) *
              _paintScale
        : lines.first.baseline;
  }

  @override
  bool get isPaintPrepared => !isDisposed;
  bool _disposed = false;
  @override
  bool get isDisposed => _disposed;

  void _ensureOpen() {
    if (_disposed) throw StateError('Paragraph layout is disposed');
  }

  @override
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

  @override
  HtmlProjectedSourcePosition sourceAt(Offset offset) {
    _ensureOpen();
    final position = _painter.getPositionForOffset(offset / _paintScale);
    final affinity = position.affinity == TextAffinity.upstream
        ? HtmlProjectionAffinity.upstream
        : HtmlProjectionAffinity.downstream;
    final source =
        _engineProjection?.sourceAtEngineUtf16(
          position.offset,
          affinity: affinity,
        ) ??
        projection.sourceAtUtf16(position.offset, affinity: affinity);
    return projection.text.isEmpty
        ? HtmlProjectedSourcePosition(
            sourceRune: source.sourceRune,
            displayUtf16: source.displayUtf16,
            isExact: false,
          )
        : source;
  }

  @override
  List<TextBox> selectionBoxes(int startUtf16, int endUtf16) {
    _ensureOpen();
    RangeError.checkValueInInterval(startUtf16, 0, endUtf16, 'startUtf16');
    final start = projection
        .sourceAtUtf16(startUtf16, affinity: HtmlProjectionAffinity.upstream)
        .displayUtf16;
    final end = projection.sourceAtUtf16(endUtf16).displayUtf16;
    final boxes = _painter.getBoxesForSelection(
      TextSelection(
        baseOffset:
            _engineProjection?.engineAtDisplayUtf16(start).engineUtf16 ?? start,
        extentOffset:
            _engineProjection?.engineAtDisplayUtf16(end).engineUtf16 ?? end,
      ),
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
    return forumBodyParagraphLineWindow(
      lines: lines,
      displayText: projection.text,
      engineText: _engineProjection?.engineText ?? projection.text,
      window: window,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _painter.dispose();
  }
}

void _validateIndentAdvance(
  TextPainter painter,
  int prefixLength,
  double advance,
) {
  final boxes = painter.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: prefixLength),
  );
  var actual = 0.0;
  for (final box in boxes) {
    if (!box.left.isFinite ||
        !box.right.isFinite ||
        !box.top.isFinite ||
        !box.bottom.isFinite ||
        (box.bottom - box.top).abs() > 1e-3 ||
        box.right < box.left) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.indent,
      );
    }
    actual += box.right - box.left;
  }
  // Verify the bundled zero-ink font ABI instead of trusting a font name or
  // allowing native fallback metrics to alter an otherwise readable page.
  if (boxes.isEmpty || (actual - advance).abs() > 1e-3) {
    throw const ForumBodyParagraphLayoutException(
      ForumBodyParagraphLayoutFailure.indent,
    );
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
    // Tight line-height can put the previous row's glyphs inside this blank
    // row's clip. Empty coverage has no text of its own to paint.
    if (coverageStartUtf16 == coverageEndUtf16) return;
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
