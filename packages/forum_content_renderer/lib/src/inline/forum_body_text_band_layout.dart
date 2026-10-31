import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_layout.dart';
import 'forum_body_text_band_content.dart';
import 'forum_body_text_band_paint.dart';

export 'forum_body_text_band_paint.dart' show ForumBodyTextBandPaint;

enum ForumBodyTextBandLayoutFailure { geometry, isolation }

final class ForumBodyTextBandLayoutException implements Exception {
  const ForumBodyTextBandLayoutException(this.failure, {this.requiredGutter});
  final ForumBodyTextBandLayoutFailure failure;

  /// A new bounded work unit may retry with this larger native-only separation.
  /// No implicit re-layout or fallback is performed by this synchronous port.
  final double? requiredGutter;
  @override
  String toString() => 'ForumBodyTextBandLayoutException(${failure.name})';
}

final class ForumBodyTextBandChildGeometry {
  const ForumBodyTextBandChildGeometry._(
    this.size,
    this.baseline,
    this.fontBounds,
    this._origin,
    this._clip,
  );
  final Size size;
  final double baseline;

  /// Local native font selection bounds together with the intrinsic line frame.
  final Rect fontBounds;
  final Offset _origin;
  final Rect _clip;
}

/// One TextPainter for bounded independent intrinsic text contexts. Virtual
/// separators have zero font metrics; transparent spacer rows isolate paint.
/// Each child is a source-bound view, never a separately shaped paragraph.
final class ForumBodyTextBandLayout {
  ForumBodyTextBandLayout._(
    this._painter,
    this.projection,
    this.children,
    this.gutter,
  ) : _paintStore = ForumBodyTextBandPaintStore(
        children.length,
        (canvas) => _painter.paint(canvas, Offset.zero),
      );
  static const revision = 1;
  factory ForumBodyTextBandLayout.create({
    required ForumBodyTextBandContent content,
    TextScaler textScaler = TextScaler.noScaling,
    double? gutter,
  }) {
    final scales = <double, double>{};
    for (final context in content.contexts) {
      final current = ForumBodyParagraphLayout.validateInputs(
        content: context,
        width: 16384,
        textScaler: textScaler,
      );
      for (final entry in current.entries) {
        if (scales.containsKey(entry.key) && scales[entry.key] != entry.value) {
          throw const ForumBodyParagraphLayoutException(
            ForumBodyParagraphLayoutFailure.scale,
          );
        }
        scales[entry.key] = entry.value;
      }
    }
    final separation =
        gutter ?? math.max(1.0, scales.values.reduce(math.max) * 2);
    if (!separation.isFinite || separation <= 0 || separation > 16384) {
      throw const ForumBodyTextBandLayoutException(
        ForumBodyTextBandLayoutFailure.geometry,
      );
    }
    final first = content.contexts.first;
    final painter = TextPainter(
      text: buildForumBodyTextBandSpan(content, separation),
      textAlign: first.style.textAlign,
      textDirection: first.style.textDirection,
      textScaler: textScaler,
      locale: first.style.textStyle.locale,
    );
    try {
      painter.layout(maxWidth: double.infinity);
      if (!painter.width.isFinite || painter.width > 16384) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.width,
        );
      }
      final metrics = painter.computeLineMetrics();
      if (metrics.length != content.contexts.length * 2 - 1 ||
          !painter.height.isFinite ||
          painter.height > 1048576) {
        throw const ForumBodyTextBandLayoutException(
          ForumBodyTextBandLayoutFailure.geometry,
        );
      }
      final origins = <Offset>[];
      final sizes = <Size>[];
      final baselines = <double>[];
      final bounds = <Rect>[];
      for (var i = 0; i < content.contexts.length; i++) {
        final window = content.projection.children[i];
        final metric = metrics[i * 2];
        final range = painter.getLineBoundary(
          TextPosition(offset: window.engineStartUtf16),
        );
        if (range.start != window.engineStartUtf16 ||
            (range.end != window.engineEndUtf16 &&
                !(i + 1 < content.contexts.length &&
                    range.end == window.engineEndUtf16 + 1))) {
          throw const ForumBodyTextBandLayoutException(
            ForumBodyTextBandLayoutFailure.geometry,
          );
        }
        // Native height rounds ascent+descent; LineMetrics.height additionally
        // clamps to one pixel. Standalone tiny lines can instead have height 0.
        // Its rounding delta belongs to the baseline, not the raw ascent.
        final height = (metric.ascent + metric.descent).roundToDouble();
        final baseline = height - metric.descent;
        final origin = Offset(metric.left, metric.baseline - baseline);
        var width = metric.width;
        final boxes = painter.getBoxesForSelection(
          TextSelection(
            baseOffset: window.engineStartUtf16,
            extentOffset: window.engineEndUtf16,
          ),
        );
        for (final box in boxes) {
          width = math.max(width, box.right - origin.dx);
        }
        final size = Size(width, height);
        var fontBounds = Offset.zero & size;
        for (final box in boxes) {
          fontBounds = fontBounds.expandToInclude(box.toRect().shift(-origin));
        }
        if (!origin.dx.isFinite ||
            !origin.dy.isFinite ||
            !baseline.isFinite ||
            !size.width.isFinite ||
            size.width < 0 ||
            size.width > 16384 ||
            !size.height.isFinite ||
            size.height < 0 ||
            !fontBounds.left.isFinite ||
            !fontBounds.right.isFinite ||
            !fontBounds.top.isFinite ||
            !fontBounds.bottom.isFinite) {
          throw const ForumBodyTextBandLayoutException(
            ForumBodyTextBandLayoutFailure.geometry,
          );
        }
        origins.add(origin);
        sizes.add(size);
        baselines.add(baseline);
        bounds.add(fontBounds);
      }
      final globals = [
        for (var i = 0; i < bounds.length; i++) bounds[i].shift(origins[i]),
      ];
      for (var i = 1; i < globals.length; i++) {
        final gap = globals[i].top - globals[i - 1].bottom;
        if (gap < 1) {
          throw ForumBodyTextBandLayoutException(
            ForumBodyTextBandLayoutFailure.isolation,
            requiredGutter: separation + 1 - gap,
          );
        }
      }
      final children = <ForumBodyTextBandChildGeometry>[];
      for (var i = 0; i < globals.length; i++) {
        final top = i == 0
            ? globals[i].top - separation / 2
            : (globals[i - 1].bottom + globals[i].top) / 2;
        final bottom = i + 1 == globals.length
            ? globals[i].bottom + separation / 2
            : (globals[i].bottom + globals[i + 1].top) / 2;
        // Keep horizontal overhang (e.g. italics) and a generous vertical strip,
        // while excluding every other child's font bounds and glyph baseline.
        final clip = Rect.fromLTRB(-16384, top, painter.width + 16384, bottom);
        children.add(
          ForumBodyTextBandChildGeometry._(
            sizes[i],
            baselines[i],
            bounds[i],
            origins[i],
            clip,
          ),
        );
      }
      return ForumBodyTextBandLayout._(
        painter,
        content.projection,
        List.unmodifiable(children),
        separation,
      );
    } catch (_) {
      painter.dispose();
      rethrow;
    }
  }

  final TextPainter _painter;
  final HtmlTextBandProjection projection;
  final List<ForumBodyTextBandChildGeometry> children;
  final double gutter;
  final ForumBodyTextBandPaintStore _paintStore;
  bool _disposed = false;
  bool get isDisposed => _disposed;
  int get preparedPictureCount => _paintStore.preparedCount;
  int get pendingPictureCount => _paintStore.pendingCount;

  /// Engine's approximate display-list allocation, not font/image/GPU memory.
  int get approximatePictureBytes => _paintStore.approximateBytes;
  int get lineCount => children.length * 2 - 1;
  void _ensureOpen() {
    if (_disposed) throw StateError('Text band is retired');
  }

  ForumBodyTextBandChildLayout view(int index) {
    _ensureOpen();
    RangeError.checkValidIndex(index, children, 'index');
    return ForumBodyTextBandChildLayout._(this, index);
  }

  bool isPaintPrepared(int index) =>
      !_disposed && _paintStore.isPrepared(index);

  /// Records one native drawing outside visible paint. Cache adapters inspect
  /// the ticket's cost and admit it in their shared budget before adoption.
  ForumBodyTextBandPaint recordPaint(int index) {
    _ensureOpen();
    RangeError.checkValidIndex(index, children, 'index');
    return _paintStore.record(index, children[index]._clip);
  }

  /// Consumes the ticket on success and failure; does not take a glyph lease.
  void adoptPaint(ForumBodyTextBandPaint ticket) {
    try {
      _ensureOpen();
      _paintStore.adopt(ticket);
    } catch (_) {
      ticket.close();
      rethrow;
    }
  }

  /// Standalone convenience; reading-cache adapters must admit costs first.
  bool preparePaint(int index) {
    _ensureOpen();
    if (isPaintPrepared(index)) return false;
    adoptPaint(recordPaint(index));
    return true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _paintStore.dispose();
    } finally {
      _painter.dispose();
    }
  }
}

/// An independently disposable view borrowing its band's one native resource.
/// Source coordinates remain this child's actual projection, not band offsets.
final class ForumBodyTextBandChildLayout {
  ForumBodyTextBandChildLayout._(this._band, this.index);
  final ForumBodyTextBandLayout _band;
  final int index;
  bool _disposed = false;
  bool get isDisposed => _disposed || _band.isDisposed;
  bool get isPaintPrepared => !isDisposed && _band.isPaintPrepared(index);
  ForumBodyTextBandChildGeometry get geometry => _band.children[index];
  HtmlDisplayTextProjection get projection =>
      _band.projection.children[index].display;
  double get width => geometry.size.width;
  double get height => geometry.size.height;
  double get alphabeticBaseline => geometry.baseline;
  void _ensureOpen() {
    if (isDisposed) throw StateError('Text band child is retired');
  }

  void paint(Canvas canvas, Offset offset) {
    _ensureOpen();
    _band._paintStore.paint(index, canvas, offset - geometry._origin);
  }

  HtmlProjectedSourcePosition sourceAt(Offset offset) {
    _ensureOpen();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    // This is one intrinsic line. A glyph can extend outside a tight line
    // frame; its y must not accidentally select a neighbouring spacer row.
    final position = _band._painter.getPositionForOffset(
      Offset(offset.dx + geometry._origin.dx, geometry._origin.dy + height / 2),
    );
    final window = _band.projection.children[index];
    if (height == 0 ||
        position.offset < window.engineStartUtf16 ||
        position.offset > window.engineEndUtf16) {
      return _sourceAtCaret(offset.dx);
    }
    return _band.projection.sourceAtChildEngineUtf16(
      index,
      position.offset,
      affinity: position.affinity == TextAffinity.upstream
          ? HtmlProjectionAffinity.upstream
          : HtmlProjectionAffinity.downstream,
    );
  }

  HtmlProjectedSourcePosition _sourceAtCaret(double x) {
    final start = _band.projection.children[index].engineStartUtf16;
    var best = double.infinity;
    var selected = 0;
    var selectedAffinity = HtmlProjectionAffinity.downstream;
    var ambiguous = false;
    final boundaries = [
      0,
      for (final range in projection.graphemeRanges(
        startUtf16: 0,
        endUtf16: projection.text.length,
      ))
        range.endUtf16,
    ];
    for (final boundary in boundaries) {
      for (final affinity in TextAffinity.values) {
        if ((boundary == 0 && affinity == TextAffinity.upstream) ||
            (boundary == projection.text.length &&
                affinity == TextAffinity.downstream)) {
          continue;
        }
        final caret = _band._painter.getOffsetForCaret(
          TextPosition(offset: start + boundary, affinity: affinity),
          Rect.zero,
        );
        final distance = (caret.dx - geometry._origin.dx - x).abs();
        if (distance < best - 1e-6) {
          best = distance;
          selected = boundary;
          ambiguous = false;
          selectedAffinity = affinity == TextAffinity.upstream
              ? HtmlProjectionAffinity.upstream
              : HtmlProjectionAffinity.downstream;
        } else if ((distance - best).abs() <= 1e-6 && selected != boundary) {
          ambiguous = true;
        }
      }
    }
    final source = projection.sourceAtUtf16(
      selected,
      affinity: selectedAffinity,
    );
    return HtmlProjectedSourcePosition(
      sourceRune: source.sourceRune,
      displayUtf16: source.displayUtf16,
      isExact: source.isExact && !ambiguous,
    );
  }

  List<TextBox> selectionBoxes(int startUtf16, int endUtf16) {
    _ensureOpen();
    final range = _band.projection.engineRangeForChildSelection(
      index,
      startUtf16: startUtf16,
      endUtf16: endUtf16,
    );
    return List.unmodifiable([
      for (final box in _band._painter.getBoxesForSelection(
        TextSelection(
          baseOffset: range.startUtf16,
          extentOffset: range.endUtf16,
        ),
      ))
        TextBox.fromLTRBD(
          box.left - geometry._origin.dx,
          box.top - geometry._origin.dy,
          box.right - geometry._origin.dx,
          box.bottom - geometry._origin.dy,
          box.direction,
        ),
    ]);
  }

  void dispose() {
    _disposed = true;
  }
}
