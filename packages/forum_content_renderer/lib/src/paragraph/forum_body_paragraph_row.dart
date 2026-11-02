import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import 'forum_body_paragraph_cache.dart';
import 'forum_body_paragraph_content.dart';
import 'forum_body_paragraph_layout.dart';
import 'forum_body_text_layout.dart';

enum ForumBodyParagraphRowFailure { source, geometry, isolation, limit }

final class ForumBodyParagraphRowException implements Exception {
  const ForumBodyParagraphRowException(this.failure, {this.requiredPitch});
  final ForumBodyParagraphRowFailure failure;
  final double? requiredPitch;
  @override
  String toString() => 'ForumBodyParagraphRowException(${failure.name})';
}

/// Pure physical selector for a drawing from an already shaped paragraph.
/// It retains no source, callback, lease or native resource. Source binding is
/// separately checked by the actual row view before scene preparation.
typedef ForumBodyParagraphRowSelector = ({
  int startLine,
  int endLine,
  double originY,
  double clipTop,
  double clipBottom,
});

/// An explicit whole-source to row-window derivation, with actual native font
/// geometry. A legal complete grapheme may require several physical rows.
/// This snapshot is neither a live owner nor proof of painted coverage.
final class ForumBodyParagraphRowMetrics {
  const ForumBodyParagraphRowMetrics._({
    required this.parentContent,
    required this.content,
    required this.nativeInputIdentity,
    required this.selector,
    required this.startUtf16,
    required this.endUtf16,
    required this.width,
    required this.height,
    required this.alphabeticBaseline,
    required this.fontBounds,
  });
  static const revision = 1;
  final ForumBodyParagraphContent parentContent;
  final ForumBodyParagraphContent content;
  final Object nativeInputIdentity;
  final ForumBodyParagraphRowSelector selector;
  final int startUtf16, endUtf16;
  final double width, height, alphabeticBaseline;
  final Rect fontBounds;
  int get lineCount => selector.endLine - selector.startLine;
}

/// Borrows one current paragraph handle. Drawing reuses that entire native
/// resource inside a qualified strip; it never shapes or records a row image.
/// Scene preparation pins its own parent alias and records the final composition.
final class ForumBodyParagraphRowView implements ForumBodyTextLayout {
  ForumBodyParagraphRowView.bind({
    required this.parent,
    required this.metrics,
    required void Function() ensureOwner,
  }) : _ensureOwner = ensureOwner {
    _guard();
    if (!identical(parent.content, metrics.parentContent) ||
        parent.nativeInputIdentity != metrics.nativeInputIdentity) {
      throw const ForumBodyParagraphRowException(
        ForumBodyParagraphRowFailure.source,
      );
    }
    _guard();
  }
  final ForumBodyParagraphLease parent;
  final ForumBodyParagraphRowMetrics metrics;
  final void Function() _ensureOwner;
  ForumBodyParagraphContent get content => metrics.content;
  ForumBodyParagraphRowSelector get selector => metrics.selector;
  Object get nativeInputIdentity {
    _guard();
    return parent.nativeInputIdentity;
  }

  @override
  bool get isDisposed => !parent.isActive;
  @override
  bool get isPaintPrepared => !isDisposed && parent.layout.isPaintPrepared;
  @override
  double get width => metrics.width;
  @override
  double get height => metrics.height;
  @override
  double get alphabeticBaseline => metrics.alphabeticBaseline;
  @override
  HtmlDisplayTextProjection get projection => content.projection;

  void _guard() {
    _ensureOwner();
    if (!parent.isActive || parent.layout.isDisposed) {
      throw StateError('Paragraph row owner is retired');
    }
  }

  @override
  void paint(Canvas canvas, Offset offset) {
    _guard();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    if (!isPaintPrepared) {
      throw StateError('Paragraph row paint is not prepared');
    }
    // A real terminal empty row retains its font frame and source endpoint,
    // without accidentally drawing a neighbouring glyph through its strip.
    if (metrics.startUtf16 == metrics.endUtf16) return;
    canvas.save();
    try {
      canvas.translate(offset.dx, offset.dy - selector.originY);
      canvas.clipRect(
        Rect.fromLTRB(
          -16384,
          selector.clipTop,
          width + 16384,
          selector.clipBottom,
        ),
        doAntiAlias: false,
      );
      parent.layout.paint(canvas, Offset.zero);
    } finally {
      canvas.restore();
    }
  }

  @override
  HtmlProjectedSourcePosition sourceAt(Offset offset) {
    _guard();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    final whole = parent.layout.sourceAt(offset + Offset(0, selector.originY));
    final selected = whole.displayUtf16.clamp(
      metrics.startUtf16,
      metrics.endUtf16,
    );
    final localOffset = selected - metrics.startUtf16;
    var local = projection.sourceAtUtf16(localOffset);
    if (local.sourceRune != whole.sourceRune) {
      final upstream = projection.sourceAtUtf16(
        localOffset,
        affinity: HtmlProjectionAffinity.upstream,
      );
      if (upstream.sourceRune == whole.sourceRune) local = upstream;
    }
    return HtmlProjectedSourcePosition(
      sourceRune: local.sourceRune,
      displayUtf16: local.displayUtf16,
      isExact:
          whole.isExact &&
          local.isExact &&
          selected == whole.displayUtf16 &&
          local.sourceRune == whole.sourceRune,
    );
  }

  @override
  List<TextBox> selectionBoxes(int startUtf16, int endUtf16) {
    _guard();
    RangeError.checkValueInInterval(
      endUtf16,
      0,
      projection.text.length,
      'endUtf16',
    );
    RangeError.checkValueInInterval(startUtf16, 0, endUtf16, 'startUtf16');
    return List.unmodifiable([
      for (final box in parent.layout.selectionBoxes(
        startUtf16 + metrics.startUtf16,
        endUtf16 + metrics.startUtf16,
      ))
        TextBox.fromLTRBD(
          box.left,
          box.top - selector.originY,
          box.right,
          box.bottom - selector.originY,
          box.direction,
        ),
    ]);
  }

  ForumBodyParagraphGlyphGeometry? glyphAtDisplayUtf16(int displayUtf16) {
    _guard();
    RangeError.checkValidIndex(displayUtf16, projection.text, 'displayUtf16');
    final glyph = parent.layout.glyphAtDisplayUtf16(
      displayUtf16 + metrics.startUtf16,
    );
    if (glyph == null) return null;
    if (glyph.lineIndex < selector.startLine ||
        glyph.lineIndex >= selector.endLine) {
      throw const ForumBodyParagraphRowException(
        ForumBodyParagraphRowFailure.source,
      );
    }
    return ForumBodyParagraphGlyphGeometry(
      lineIndex: glyph.lineIndex - selector.startLine,
      fontBounds: glyph.fontBounds.shift(Offset(0, -selector.originY)),
      engineClusterRange: glyph.engineClusterRange,
      direction: glyph.direction,
    );
  }
}

/// Prepares one complete legal row group and its two neighbours. Every work
/// unit consumes one style, physical row, native box query or individual box.
/// No full-context reshaping, native image, cache or implicit retry is created.
final class ForumBodyParagraphRowPreparation {
  ForumBodyParagraphRowPreparation({
    required ForumBodyParagraphLease parent,
    required int startLine,
    required void Function() ensureOwner,
    this.maxLines = 64,
    this.maxBoxes = 4096,
  }) : _parent = parent,
       _startLine = startLine,
       _endLine = startLine,
       _ensureOwner = ensureOwner {
    if (maxLines <= 0 || maxBoxes < 0) {
      throw ArgumentError('Invalid row budget');
    }
    try {
      _guard();
      final layout = parent.layout;
      RangeError.checkValidIndex(startLine, layout.lines, 'startLine');
      if (parent.content.isSourceFree ||
          layout.rowIsolationPitch == null ||
          !layout.lines[startLine].canBreakBefore) {
        throw const ForumBodyParagraphRowException(
          ForumBodyParagraphRowFailure.source,
        );
      }
      _nativeKey = parent.nativeInputIdentity;
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int maxLines, maxBoxes;
  final int _startLine;
  int _endLine, _style = -1, _query = 0, _box = 0, _boxCount = 0;
  ForumBodyParagraphLease? _parent;
  void Function()? _ensureOwner;
  Object? _nativeKey;
  final _bounds = <Rect?>[null, null, null];
  List<TextBox>? _boxes;
  ForumBodyParagraphRowMetrics? _result;
  double _shadowTop = 0, _shadowBottom = 0, _shadowHorizontal = 0;
  double _decorationGuard = 0;
  bool _groupReady = false, _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Paragraph row preparation is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (used < maxParts && !isReady) {
        final parent = _parent!, layout = parent.layout;
        if (_style < parent.content.runs.length) {
          final style = _style < 0
              ? parent.content.style
              : parent.content.runs[_style].style;
          _style++;
          final text = style.textStyle;
          final thickness = text.decorationThickness ?? 1;
          if (!thickness.isFinite || thickness < 0) {
            throw const ForumBodyParagraphRowException(
              ForumBodyParagraphRowFailure.geometry,
            );
          }
          _decorationGuard = math.max(
            _decorationGuard,
            layout.nativeFontClearance * math.max(1, thickness),
          );
          for (final paint in [text.foreground, text.background]) {
            if (paint != null &&
                (paint.style != PaintingStyle.fill ||
                    paint.maskFilter != null ||
                    paint.imageFilter != null)) {
              throw const ForumBodyParagraphRowException(
                ForumBodyParagraphRowFailure.geometry,
              );
            }
          }
          for (final shadow in text.shadows ?? const <Shadow>[]) {
            final reach = 3 * shadow.blurSigma + 1;
            final top = reach - shadow.offset.dy,
                bottom = reach + shadow.offset.dy;
            if (!top.isFinite ||
                !bottom.isFinite ||
                reach + shadow.offset.dx.abs() + _decorationGuard > 16384 ||
                shadow.offset.dy.abs() > 16384) {
              throw const ForumBodyParagraphRowException(
                ForumBodyParagraphRowFailure.geometry,
              );
            }
            _shadowTop = math.max(_shadowTop, top);
            _shadowBottom = math.max(_shadowBottom, bottom);
            _shadowHorizontal = math.max(
              _shadowHorizontal,
              reach + shadow.offset.dx.abs(),
            );
          }
        } else if (!_groupReady) {
          if (_endLine - _startLine >= maxLines) {
            throw const ForumBodyParagraphRowException(
              ForumBodyParagraphRowFailure.limit,
            );
          }
          final line = layout.lines[_endLine++];
          _bounds[0] = _union(_bounds[0], _frame(line, layout.width));
          _groupReady = line.canBreakAfter;
          if (!_groupReady && _endLine == layout.lineCount) {
            throw const ForumBodyParagraphRowException(
              ForumBodyParagraphRowFailure.source,
            );
          }
        } else if (_query < 3) {
          final start = switch (_query) {
            0 => _startLine,
            1 => _startLine - 1,
            _ => _endLine,
          };
          final end = _query == 0 ? _endLine : start + 1;
          if (start < 0 || start >= layout.lineCount) {
            _query++;
          } else if (_boxes == null) {
            _bounds[_query] = _union(
              _bounds[_query],
              _frame(layout.lines[start], layout.width),
            );
            final boxes = layout.selectionBoxes(
              layout.lines[start].coverageStartUtf16,
              layout.lines[end - 1].coverageEndUtf16,
            );
            if (boxes.length > maxBoxes - _boxCount) {
              throw const ForumBodyParagraphRowException(
                ForumBodyParagraphRowFailure.limit,
              );
            }
            _boxCount += boxes.length;
            _boxes = boxes;
            _box = 0;
          } else if (_box < _boxes!.length) {
            final rect = _boxes![_box++].toRect();
            _validateRect(rect);
            _bounds[_query] = _union(_bounds[_query], rect);
          } else {
            _boxes = null;
            _query++;
          }
        } else {
          _finish();
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

  Rect _envelope(Rect bounds) {
    // Native selection bounds are font frames, not ink. Keep one actual maximum
    // font size of clearance plus all admitted shadow support before clipping.
    final guard = _decorationGuard;
    if (guard + _shadowHorizontal > 16384) {
      throw const ForumBodyParagraphRowException(
        ForumBodyParagraphRowFailure.geometry,
      );
    }
    return Rect.fromLTRB(
      bounds.left - guard,
      bounds.top - guard - _shadowTop,
      bounds.right + guard,
      bounds.bottom + guard + _shadowBottom,
    );
  }

  void _finish() {
    final parent = _parent!,
        layout = parent.layout,
        pitch = layout.rowIsolationPitch!;
    final font = _bounds[0]!, own = _envelope(font);
    final previous = _bounds[1] == null ? null : _envelope(_bounds[1]!);
    final next = _bounds[2] == null ? null : _envelope(_bounds[2]!);
    final gap = math.min(
      previous == null ? double.infinity : own.top - previous.bottom,
      next == null ? double.infinity : next.top - own.bottom,
    );
    if (gap < 1) {
      throw ForumBodyParagraphRowException(
        ForumBodyParagraphRowFailure.isolation,
        // Engine strut baselines use finite-precision native coordinates. Ask
        // for a whole extra pixel rather than weakening the verified 1px gap.
        requiredPitch: (pitch + 1 - gap).ceilToDouble() + 1,
      );
    }
    final origin = font.top.floorToDouble();
    final start = layout.lines[_startLine].coverageStartUtf16;
    final end = layout.lines[_endLine - 1].coverageEndUtf16;
    _result = ForumBodyParagraphRowMetrics._(
      parentContent: parent.content,
      content: parent.content
          .displayWindow(startUtf16: start, endUtf16: end)
          .withFirstLineIndent(
            _startLine == 0 && parent.content.appliesFirstLineIndent,
          ),
      nativeInputIdentity: _nativeKey!,
      selector: (
        startLine: _startLine,
        endLine: _endLine,
        originY: origin,
        clipTop: previous == null
            ? own.top - pitch / 2
            : (previous.bottom + own.top) / 2,
        clipBottom: next == null
            ? own.bottom + pitch / 2
            : (own.bottom + next.top) / 2,
      ),
      startUtf16: start,
      endUtf16: end,
      width: layout.width,
      height: font.bottom.ceilToDouble() - origin,
      alphabeticBaseline: layout.lines[_startLine].baseline - origin,
      fontBounds: font.shift(Offset(0, -origin)),
    );
  }

  ForumBodyParagraphRowMetrics takeMetrics() {
    if (_operating) throw StateError('Paragraph row preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Paragraph row preparation is incomplete');
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
    if (_closed) throw StateError('Paragraph row preparation is retired');
    _ensureOwner!();
    if (_closed || _parent?.isActive != true || _parent!.layout.isDisposed) {
      throw StateError('Paragraph row owner is retired');
    }
  }

  void close() {
    _closed = true;
    _parent = null;
    _ensureOwner = null;
    _nativeKey = null;
    _boxes = null;
    _result = null;
  }
}

Rect _union(Rect? a, Rect b) => a?.expandToInclude(b) ?? b;
Rect _frame(ForumBodyParagraphLine line, double width) {
  final rect = Rect.fromLTRB(0, line.top, width, line.bottom);
  _validateRect(rect);
  if (!line.baseline.isFinite) {
    throw const ForumBodyParagraphRowException(
      ForumBodyParagraphRowFailure.geometry,
    );
  }
  return rect;
}

void _validateRect(Rect rect) {
  if (!rect.left.isFinite ||
      !rect.top.isFinite ||
      !rect.right.isFinite ||
      !rect.bottom.isFinite ||
      rect.width < 0 ||
      rect.height < 0) {
    throw const ForumBodyParagraphRowException(
      ForumBodyParagraphRowFailure.geometry,
    );
  }
}
