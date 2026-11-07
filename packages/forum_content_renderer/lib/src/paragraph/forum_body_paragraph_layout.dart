import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_text.dart';

import '../document/forum_body_document.dart';
import 'forum_body_first_line_indent.dart';
import 'forum_body_indent_layout.dart';
import 'forum_body_horizontal_text_frame.dart';
import 'forum_body_paragraph_content.dart';
import 'forum_body_paragraph_geometry.dart';
import 'forum_body_native_paragraph_layout.dart';
import 'forum_body_text_layout.dart';
import 'forum_body_native_paragraph_painter.dart';

export 'forum_body_paragraph_geometry.dart'
    show
        ForumBodyParagraphLayoutFailure,
        ForumBodyParagraphLayoutException,
        ForumBodyParagraphWindow,
        ForumBodyFirstLineIndentGeometry,
        ForumBodyParagraphGlyphGeometry,
        ForumBodyParagraphMaximumLineFrame,
        ForumBodyParagraphLine;

/// Owns one native paragraph, shared by geometry, paint, hit-test and boxes.
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
    this._paintOrigin,
    this._engineProjection,
    this.firstLineIndent,
    this.rowIsolationPitch,
    this.nativeFontClearance,
    List<ForumBodyParagraphLine> lines,
  ) : lines = List.unmodifiable(lines),
      identity = content.identity,
      path = content.path,
      projection = content.projection;

  factory ForumBodyParagraphLayout.create({
    required ForumBodyParagraphContent content,
    required double width,
    TextScaler textScaler = TextScaler.noScaling,
    double? rowIsolationPitch,
  }) {
    final scales = validateInputs(
      content: content,
      width: width,
      textScaler: textScaler,
      rowIsolationPitch: rowIsolationPitch,
    );
    final fitted =
        content.layoutMode == ForumBodyParagraphLayoutMode.fitSingleLine;
    final intrinsic =
        content.layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine;
    final inset = content.horizontalInset;
    final innerWidth = intrinsic
        ? width
        : forumBodyInnerTextWidth(width, inset);
    final indent = resolveForumBodyFirstLineIndent(content, innerWidth, scales);
    final engine = indent > 0 ? content.indentedProjection : null;
    final painter = ForumBodyNativeParagraphPainter(
      text: content.textSpan,
      textAlign: content.style.textAlign,
      textDirection: content.style.textDirection,
      textScaler: textScaler,
      locale: content.style.textStyle.locale,
      // The requested separation is already physical; compensate only the
      // strut height for the actual scaled root font, leaving glyphs unchanged.
      strutStyle: rowIsolationPitch == null
          ? null
          : StrutStyle.fromTextStyle(
              content.style.textStyle,
              height:
                  rowIsolationPitch / scales[content.style.textStyle.fontSize]!,
              leading: 0,
              forceStrutHeight: true,
            ),
    );
    try {
      // Shape at the selected font/scaler first. Fitting transforms that same
      // layout, rather than measuring repeatedly at guessed smaller font sizes.
      final indentGeometry = engine == null
          ? const ForumBodyFirstLineIndentGeometry.none()
          : layoutForumBodyFirstLineIndentWithPainter(
              painter: painter,
              body: content.textSpan,
              projection: engine,
              width: innerWidth,
              requestedAdvance: indent,
              canReduce: content.style.indentFromReader,
            );
      if (engine == null) {
        painter.layout(
          minWidth: intrinsic ? 0 : innerWidth,
          maxWidth: fitted || intrinsic ? double.infinity : innerWidth,
        );
      }
      final nativeWidth = painter.width + 2 * inset;
      final layoutWidth = intrinsic ? nativeWidth : width;
      if (!layoutWidth.isFinite || layoutWidth < 0 || layoutWidth > 16384) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.width,
        );
      }
      final paintScale = fitted && nativeWidth > width
          ? width / nativeWidth
          : 1.0;
      if (!paintScale.isFinite || paintScale <= 0) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.scale,
        );
      }
      final metrics = painter.computeLineMetrics();
      var nativeFontClearance = scales.values.reduce((a, b) => a > b ? a : b);
      if (rowIsolationPitch != null) {
        // Qualify fallback fonts across the entire source once. A distant large
        // glyph must not escape an adjacent-row-only isolation check. These are
        // native font frames, not measured ink or a second per-row shape.
        for (final metric in metrics) {
          if (metric.unscaledAscent > nativeFontClearance) {
            nativeFontClearance = metric.unscaledAscent;
          }
        }
        for (final box in painter.getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset:
                engine?.engineText.length ?? content.projection.text.length,
          ),
        )) {
          if (!box.top.isFinite ||
              !box.bottom.isFinite ||
              box.bottom < box.top) {
            throw const ForumBodyParagraphLayoutException(
              ForumBodyParagraphLayoutFailure.isolation,
            );
          }
          if (box.bottom - box.top > nativeFontClearance) {
            nativeFontClearance = box.bottom - box.top;
          }
        }
      }
      if (rowIsolationPitch != null &&
          (!painter.height.isFinite || painter.height > 1048576)) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.isolation,
        );
      }
      if ((fitted || intrinsic) && metrics.length > 1) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.singleLine,
        );
      }
      final nativeLines = forumBodyParagraphLinesWithPainter(
        painter: painter,
        display: content.projection,
        paintScale: paintScale,
        inline: engine,
      );
      final horizontalInset = inset * paintScale;
      var lines = horizontalInset == 0
          ? nativeLines
          : [
              for (final line in nativeLines)
                line.shift(Offset(horizontalInset, 0)),
            ];
      var height = painter.height * paintScale;
      var paintTop = 0.0;
      if (fitted && lines.isNotEmpty) {
        // A fitted notice is one physical row. Its fallback font boxes can
        // extend beyond the nominal line height even after width fitting.
        final line = lines.single;
        var top = 0.0;
        var bottom = height;
        for (final box in painter.getBoxesForSelection(
          TextSelection(
            baseOffset: line.engineStartUtf16,
            extentOffset: line.engineUnpaintedTrailingSpaceStartUtf16,
          ),
        )) {
          final boxTop = box.top * paintScale;
          final boxBottom = box.bottom * paintScale;
          if (boxTop < top) top = boxTop;
          if (boxBottom > bottom) bottom = boxBottom;
        }
        if (top < 0 || bottom > height) {
          paintTop = -top;
          height = bottom + paintTop;
          lines = [
            line.withVerticalFrame(
              top: 0,
              bottom: height,
              baseline: line.baseline + paintTop,
            ),
          ];
        }
      }
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
        height,
        paintScale,
        Offset(horizontalInset, paintTop),
        engine,
        indentGeometry,
        rowIsolationPitch,
        nativeFontClearance,
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
    double? rowIsolationPitch,
  }) {
    if (!width.isFinite || width <= 0 || width > 16384) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.width,
      );
    }
    if (rowIsolationPitch != null &&
        (!rowIsolationPitch.isFinite ||
            rowIsolationPitch <= 0 ||
            rowIsolationPitch > 16384 ||
            content.layoutMode != ForumBodyParagraphLayoutMode.wrap)) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.isolation,
      );
    }
    final scales = <double, double>{};
    content.layoutInput.resolveScalesInto(scales, textScaler: textScaler);
    final innerWidth =
        content.layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine
        ? width
        : forumBodyInnerTextWidth(width, content.horizontalInset);
    resolveForumBodyFirstLineIndent(content, innerWidth, scales);
    return scales;
  }

  static const backendRevision = 13;

  /// Native-only requested baseline separation, in logical pixels after actual
  /// font scaling. It is neither the author's line height nor page allocation.
  /// Consumers must derive row placement and safe paint clips from this actual
  /// layout; ordinary fragments cannot consume an isolated paragraph.
  final double? rowIsolationPitch;

  /// Whole-source native font-frame clearance, including fallback glyphs. Row
  /// isolation uses this guard without resampling a caller's scaler or querying
  /// the entire source again for every visible row.
  final double nativeFontClearance;

  /// Physical edge reserve shared by paint, hit testing, lines and boxes.
  double get horizontalInset => _paintOrigin.dx;
  final Offset _paintOrigin;
  final ForumBodyFirstLineIndentGeometry firstLineIndent;
  final ForumBodyIdentity identity;
  final String? path;
  @override
  final HtmlDisplayTextProjection projection;
  final ForumBodyNativeParagraphPainter _painter;
  @override
  final double width;
  @override
  final double height;
  final double _paintScale;

  /// The actual uniform single-line fitting transform, after per-size scaling.
  /// Decorations must share this value rather than infer it from text width.
  double get paintScale => _paintScale;

  /// Before any single-line fit transform, from the same native paragraph.
  ({double minimum, double preferred}) get intrinsicWidths =>
      _painter.intrinsicWidths(inset: horizontalInset / _paintScale);
  final HtmlInlineTextProjection? _engineProjection;
  final List<ForumBodyParagraphLine> lines;
  @override
  int get lineCount => lines.length;

  /// One full native geometry query, without shaping or paint preparation.
  /// Records remain in native order, including duplicate boxes within a row.
  /// They alone do not identify source ranges or authorize physical slicing.
  List<ForumBodyParagraphMaximumLineFrame> queryMaximumLineFrames() {
    _ensureOpen();
    return List.unmodifiable([
      for (final frame in _painter.maximumLineFrames(
        _engineProjection?.engineText.length ?? projection.text.length,
      ))
        (
          top: frame.top * _paintScale + _paintOrigin.dy,
          bottom: frame.bottom * _paintScale + _paintOrigin.dy,
        ),
    ]);
  }

  bool get hasTerminalEmptyLine {
    _ensureOpen();
    return forumBodyHasTerminalEmptyLine(
      lines: lines,
      displayText: projection.text,
      engineText: _engineProjection?.engineText ?? projection.text,
    );
  }

  /// Native paragraph's first-line metric before paint rounding. This can
  /// differ from the logical first LineMetrics baseline exposed by this layout.
  double get nativeAlphabeticBaseline {
    _ensureOpen();
    final baseline = _painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    return baseline * _paintScale + _paintOrigin.dy;
  }

  @override
  double get alphabeticBaseline {
    _ensureOpen();
    // An empty native paragraph has a real font baseline but no text rows.
    // Preserve that strut without introducing a synthetic row or glyph.
    return lines.isEmpty ? nativeAlphabeticBaseline : lines.first.baseline;
  }

  @override
  bool get isPaintPrepared =>
      !isDisposed && (rowIsolationPitch == null || _isolationPaintPrepared);
  bool _isolationPaintPrepared = false;
  bool _preparingPaint = false;

  /// Stage the native paragraph's first drawing outside visible paint. Some
  /// fallback-font shadows differ on that first recording; subsequent drawing
  /// must use the qualified native state, not publish the transient picture.
  /// The reading cache counts this as one recording and retains no picture.
  bool preparePaint() {
    _ensureOpen();
    if (_preparingPaint) {
      throw StateError('Paragraph paint preparation is reentrant');
    }
    if (isPaintPrepared) return false;
    _preparingPaint = true;
    ui.PictureRecorder? recorder;
    ui.Picture? picture;
    try {
      recorder = ui.PictureRecorder();
      _painter.paint(Canvas(recorder), _paintOrigin);
      picture = recorder.endRecording();
      recorder = null;
      _ensureOpen();
      final finished = picture;
      picture = null;
      finished.dispose();
      _ensureOpen();
      _isolationPaintPrepared = true;
      return true;
    } finally {
      try {
        if (recorder != null && recorder.isRecording) {
          recorder.endRecording().dispose();
        }
        picture?.dispose();
      } finally {
        _preparingPaint = false;
      }
    }
  }

  bool _disposed = false;
  @override
  bool get isDisposed => _disposed;

  void _ensureOpen() {
    if (_disposed) throw StateError('Paragraph layout is disposed');
  }

  @override
  void paint(Canvas canvas, Offset offset) {
    _ensureOpen();
    if (!isPaintPrepared) {
      throw StateError('Isolated paragraph paint is not prepared');
    }
    if (_paintScale == 1) {
      _painter.paint(canvas, offset + _paintOrigin);
      return;
    }
    canvas.save();
    try {
      canvas.translate(
        offset.dx + _paintOrigin.dx,
        offset.dy + _paintOrigin.dy,
      );
      canvas.scale(_paintScale, _paintScale);
      _painter.paint(canvas, Offset.zero);
    } finally {
      canvas.restore();
    }
  }

  @override
  HtmlProjectedSourcePosition sourceAt(Offset offset) {
    _ensureOpen();
    final position = _painter.getPositionForOffset(
      (offset - _paintOrigin) / _paintScale,
    );
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
        if (_paintScale == 1 && _paintOrigin == Offset.zero)
          box
        else
          TextBox.fromLTRBD(
            box.left * _paintScale + horizontalInset,
            box.top * _paintScale + _paintOrigin.dy,
            box.right * _paintScale + horizontalInset,
            box.bottom * _paintScale + _paintOrigin.dy,
            box.direction,
          ),
    ]);
  }

  /// Query the actual governing scalar inside a complete source grapheme.
  /// Ordinary paragraphs only add an optional mechanical prefix: do not use
  /// the source projection's legal-boundary normalization to move this query
  /// back to an earlier format/control scalar or a different physical row.
  ForumBodyParagraphGlyphGeometry? glyphAtDisplayUtf16(int displayUtf16) {
    _ensureOpen();
    RangeError.checkValidIndex(displayUtf16, projection.text, 'displayUtf16');
    final engineOffset =
        displayUtf16 + (_engineProjection?.enginePrefix.length ?? 0);
    final glyph = _painter.glyphInfoAt(engineOffset);
    final line = _painter.getLineNumberAt(engineOffset);
    if (glyph == null || line == null) return null;
    final range = glyph.graphemeClusterCodeUnitRange;
    if (line < 0 ||
        line >= lines.length ||
        range.start > engineOffset ||
        range.end <= engineOffset) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.coverage,
      );
    }
    final rect = glyph.graphemeClusterLayoutBounds;
    return ForumBodyParagraphGlyphGeometry(
      lineIndex: line,
      fontBounds: Rect.fromLTRB(
        rect.left * _paintScale + horizontalInset,
        rect.top * _paintScale + _paintOrigin.dy,
        rect.right * _paintScale + horizontalInset,
        rect.bottom * _paintScale + _paintOrigin.dy,
      ),
      engineClusterRange: range,
      direction: glyph.writingDirection,
    );
  }

  ForumBodyParagraphFragment fragment(int startLine, int endLine) {
    _ensureOpen();
    if (rowIsolationPitch != null) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.isolation,
      );
    }
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
    if (rowIsolationPitch != null) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.isolation,
      );
    }
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
