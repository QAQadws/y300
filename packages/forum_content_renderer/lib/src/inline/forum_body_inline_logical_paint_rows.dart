import 'dart:collection';

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_native_paint_clearance.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_row.dart';
import 'forum_body_emphasis_text_geometry.dart';

/// A physical background/decoration strip, including native placeholder paint.
/// It creates no text window, font measurement or child/source coverage claim.
typedef ForumBodyInlineLogicalPaintRow = ({
  ForumBodyParagraphRowSelector selector,
  Rect? bounds,
  Rect? paintBounds,
});

final class ForumBodyInlineLogicalPaintRows {
  ForumBodyInlineLogicalPaintRows._(
    this.geometry,
    List<ForumBodyInlineLogicalPaintRow> rows,
    this.hasLogicalPaint,
  ) : rows = UnmodifiableListView(rows);
  static const revision = 1;
  final ForumBodyInlineEmphasisTextGeometry geometry;
  final List<ForumBodyInlineLogicalPaintRow> rows;

  /// Source styles require logical layers, even when their ink is transparent.
  final bool hasLogicalPaint;
}

/// Borrows the current isolated source parent. Native logical row metrics,
/// complete slot frames and actual parent font bounds reserve logical paint;
/// unlike glyph strips, an opaque-only row must not be skipped. Each part
/// visits one style, row, slot or gap. No native query/acquire/record occurs.
final class ForumBodyInlineLogicalPaintRowPreparation {
  ForumBodyInlineLogicalPaintRowPreparation({
    required ForumBodyInlineParagraphLease parent,
    required ForumBodyInlineEmphasisTextGeometry geometry,
    required void Function() ensureOwner,
    this.maxLines = 4096,
    this.maxAtoms = 512,
  }) : _parent = parent,
       _geometry = geometry,
       _ensureOwner = ensureOwner {
    if (maxLines <= 0 || maxAtoms < 0) {
      throw ArgumentError('Invalid inline logical paint budget');
    }
    try {
      _guard();
      if (!identical(parent.content, geometry.input.glyphInput.glyphs) ||
          parent.nativeInputIdentity != geometry.nativeInputIdentity ||
          !identical(parent.layout.lines, geometry.lines) ||
          parent.layout.rowIsolationPitch == null) {
        _fail(ForumBodyParagraphRowFailure.source);
      }
      if (geometry.lineCount > maxLines ||
          parent.layout.atomBoxes.length > maxAtoms) {
        _fail(ForumBodyParagraphRowFailure.limit);
      }
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }

  final int maxLines, maxAtoms;
  ForumBodyInlineParagraphLease? _parent;
  ForumBodyInlineEmphasisTextGeometry? _geometry;
  void Function()? _ensureOwner;
  ForumBodyNativePaintClearance? _clearance;
  List<Rect?> _bounds = [];
  List<Rect> _envelopes = [];
  List<double> _cuts = [];
  List<ForumBodyInlineLogicalPaintRow> _rows = [];
  ForumBodyInlineLogicalPaintRows? _result;
  int _style = -1, _paintStyle = -1, _line = 0, _atom = 0;
  int _envelope = 0, _gap = 0, _row = 0, _paintRow = 0;
  bool _logical = false, _decoration = false;
  bool _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Inline logical paint is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        final geometry = _geometry!,
            parent = _parent!,
            content = parent.content;
        TextStyle style(int i) => i < 0
            ? content.style.textStyle
            : content.parentRuns[i].style.textStyle;
        if (_style < content.parentRuns.length) {
          final text = style(_style++);
          _decoration |=
              text.decoration != null && text.decoration != TextDecoration.none;
          _logical |=
              text.background != null ||
              text.backgroundColor != null ||
              _decoration;
        } else if (_clearance == null) {
          // This is conservative paint reach, not a parent glyph font. Native
          // decorations can inherit onto a slot; its measured frame therefore
          // participates here while staying out of the glyph-only envelope.
          _clearance = ForumBodyNativePaintClearance(
            _decoration ? parent.layout.nativeFontClearance : 0,
          );
        } else if (_logical && _paintStyle < content.parentRuns.length) {
          if (!_clearance!.include(
            style(_paintStyle++).copyWith(shadows: const []),
          )) {
            _fail(ForumBodyParagraphRowFailure.geometry);
          }
        } else if (_line < geometry.lineCount) {
          final index = _line++, line = geometry.lines[index];
          Rect? bounds;
          if (_logical && line.engineStartUtf16 < line.engineEndUtf16) {
            // Native ascent/descent include styled run/placeholder metrics;
            // forced-strut flow height is deliberately not this envelope.
            bounds = Rect.fromLTRB(
              line.left,
              line.top,
              line.left + line.width,
              line.bottom,
            );
            final font = geometry.parentFontBounds[index];
            if (font != null) bounds = bounds.expandToInclude(font);
            _rect(bounds);
          }
          _bounds.add(bounds);
        } else if (_logical && _atom < parent.layout.atomBoxes.length) {
          final atom = _atom++;
          if (!parent.layout.isAtomTrimmed(atom)) {
            final row = geometry.atomLineIndices[atom];
            if (row < 0 || row >= _bounds.length || _bounds[row] == null) {
              _fail(ForumBodyParagraphRowFailure.source);
            }
            final box = parent.layout.atomBoxes[atom].toRect(),
                size = parent.layout.dimensions[atom].size;
            final complete = box.expandToInclude(
              Rect.fromLTWH(box.left, box.top, size.width, size.height),
            );
            _rect(complete);
            _bounds[row] = _bounds[row]!.expandToInclude(complete);
          }
        } else if (_envelope < _bounds.length) {
          final index = _envelope++, bounds = _bounds[index];
          if (bounds != null) {
            final paint = _clearance!.envelope(bounds)?.inflate(1);
            if (paint == null) _fail(ForumBodyParagraphRowFailure.geometry);
            _rect(paint);
            _envelopes.add(paint);
          }
        } else if (_gap + 1 < _envelopes.length) {
          final a = _envelopes[_gap], b = _envelopes[_gap + 1];
          final gap = b.top - a.bottom;
          if (gap < 1) {
            throw ForumBodyParagraphRowException(
              ForumBodyParagraphRowFailure.isolation,
              requiredPitch:
                  (parent.layout.rowIsolationPitch! + 1 - gap).ceilToDouble() +
                  1,
            );
          }
          _cuts.add((a.bottom + b.top) / 2);
          _gap++;
        } else if (_row < geometry.lineCount) {
          final index = _row++,
              bounds = _bounds[index],
              paint = bounds == null ? null : _envelopes[_paintRow],
              origin =
                  bounds?.top.floorToDouble() ?? geometry.lines[index].baseline,
              pitch = parent.layout.rowIsolationPitch!;
          _rows.add((
            selector: (
              startLine: index,
              endLine: index + 1,
              originY: origin,
              clipTop: paint == null
                  ? origin
                  : _paintRow == 0
                  ? paint.top - pitch / 2
                  : _cuts[_paintRow - 1],
              clipBottom: paint == null
                  ? origin
                  : _paintRow == _envelopes.length - 1
                  ? paint.bottom + pitch / 2
                  : _cuts[_paintRow],
            ),
            bounds: bounds,
            paintBounds: paint,
          ));
          if (bounds != null) _paintRow++;
        } else {
          _result = ForumBodyInlineLogicalPaintRows._(
            geometry,
            _rows,
            _logical,
          );
          _rows = [];
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

  ForumBodyInlineLogicalPaintRows takeRows() {
    if (_operating) throw StateError('Inline logical paint is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Inline logical paint is incomplete');
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
    if (_closed) throw StateError('Inline logical paint is retired');
    _ensureOwner!();
    if (_closed || _parent?.isActive != true) {
      throw StateError('Inline logical paint owner is retired');
    }
  }

  void close() {
    _closed = true;
    _parent = null;
    _geometry = null;
    _ensureOwner = null;
    _clearance = null;
    _bounds = [];
    _envelopes = [];
    _cuts = [];
    _rows = [];
    _result = null;
  }
}

void _rect(Rect value) {
  if (!value.isFinite || value.width < 0 || value.height < 0) {
    _fail(ForumBodyParagraphRowFailure.geometry);
  }
}

Never _fail(ForumBodyParagraphRowFailure failure) =>
    throw ForumBodyParagraphRowException(failure);
