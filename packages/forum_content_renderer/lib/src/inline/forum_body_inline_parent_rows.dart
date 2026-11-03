import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_native_paint_clearance.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_row.dart';
import 'forum_body_emphasis_text_geometry.dart';

/// Paint-only physical strip. It creates no source window or child geometry;
/// a complete source group may contain several such physical rows.
final class ForumBodyInlineParentRowSelector {
  const ForumBodyInlineParentRowSelector._(
    this.selector,
    this.fontBounds,
    this.paintBounds,
  );
  final ForumBodyParagraphRowSelector selector;
  final Rect? fontBounds, paintBounds;
  bool get isEmpty => fontBounds == null;
}

/// Actual whole-source parent glyph strips. Fonts behind opaque child slots
/// never enter these envelopes. No cache, callback or native handle survives.
final class ForumBodyInlineParentRows {
  ForumBodyInlineParentRows._(
    this.geometry,
    List<ForumBodyInlineParentRowSelector> rows,
    this.fontClearance,
  ) : rows = UnmodifiableListView(rows);
  static const revision = 1;
  final ForumBodyInlineEmphasisTextGeometry geometry;
  final List<ForumBodyInlineParentRowSelector> rows;
  final double fontClearance;
}

/// Uses already captured complete parent glyph geometry. Each part consumes
/// one row, actual parent style, gap or selector. No shaping, native query,
/// recording or caller handle release occurs here.
final class ForumBodyInlineParentRowPreparation {
  ForumBodyInlineParentRowPreparation({
    required ForumBodyInlineParagraphLease parent,
    required ForumBodyInlineEmphasisTextGeometry geometry,
    required void Function() ensureOwner,
    this.maxLines = 4096,
  }) : _parent = parent,
       _geometry = geometry,
       _ensureOwner = ensureOwner {
    if (maxLines <= 0) throw ArgumentError.value(maxLines);
    try {
      _guard();
      _checkSource(parent, geometry);
      if (geometry.lineCount > maxLines) {
        _fail(ForumBodyParagraphRowFailure.limit);
      }
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int maxLines;
  ForumBodyInlineParagraphLease? _parent;
  ForumBodyInlineEmphasisTextGeometry? _geometry;
  void Function()? _ensureOwner;
  List<int>? _painted = [];
  List<Rect>? _envelopes = [];
  List<double>? _cuts = [];
  List<ForumBodyInlineParentRowSelector>? _rows = [];
  ForumBodyNativePaintClearance? _clearance;
  ForumBodyInlineParentRows? _result;
  int _font = 0, _style = -1, _envelope = 0, _gap = 0, _row = 0, _paintRow = 0;
  double _fontClearance = 0;
  bool _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Inline parent rows are reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        final geometry = _geometry!,
            parent = _parent!,
            content = parent.content;
        if (_font < geometry.lineCount) {
          final index = _font++, bounds = geometry.parentFontBounds[index];
          if (bounds != null) {
            if (!bounds.isFinite || bounds.width < 0 || bounds.height < 0) {
              _fail(ForumBodyParagraphRowFailure.geometry);
            }
            _fontClearance = math.max(_fontClearance, bounds.height);
            _painted!.add(index);
          }
        } else if (_clearance == null) {
          // Only actual parent glyph fonts count. A tall opaque child must not
          // become an invented parent font or force an unrelated paint pitch.
          _clearance = ForumBodyNativePaintClearance(_fontClearance);
        } else if (_painted!.isNotEmpty && _style < content.parentRuns.length) {
          final text = _style < 0
              ? content.style.textStyle
              : content.parentRuns[_style].style.textStyle;
          _style++;
          if (!_clearance!.include(text)) {
            _fail(ForumBodyParagraphRowFailure.geometry);
          }
        } else if (_envelope < _painted!.length) {
          final font = geometry.parentFontBounds[_painted![_envelope++]]!;
          final envelope = _clearance!.envelope(font);
          if (envelope == null || !envelope.isFinite) {
            _fail(ForumBodyParagraphRowFailure.geometry);
          }
          _envelopes!.add(envelope);
        } else if (_gap + 1 < _envelopes!.length) {
          final a = _envelopes![_gap], b = _envelopes![_gap + 1];
          final gap = b.top - a.bottom;
          if (gap < 1) {
            throw ForumBodyParagraphRowException(
              ForumBodyParagraphRowFailure.isolation,
              requiredPitch:
                  (parent.layout.rowIsolationPitch! + 1 - gap).ceilToDouble() +
                  1,
            );
          }
          _cuts!.add((a.bottom + b.top) / 2);
          _gap++;
        } else if (_row < geometry.lineCount) {
          final index = _row++, font = geometry.parentFontBounds[index];
          final pitch = parent.layout.rowIsolationPitch!;
          final paint = font == null ? null : _envelopes![_paintRow];
          final origin =
              font?.top.floorToDouble() ?? geometry.lines[index].baseline;
          _rows!.add(
            ForumBodyInlineParentRowSelector._(
              (
                startLine: index,
                endLine: index + 1,
                originY: origin,
                clipTop: paint == null
                    ? origin
                    : _paintRow == 0
                    ? paint.top - pitch / 2
                    : _cuts![_paintRow - 1],
                clipBottom: paint == null
                    ? origin
                    : _paintRow == _envelopes!.length - 1
                    ? paint.bottom + pitch / 2
                    : _cuts![_paintRow],
              ),
              font,
              paint,
            ),
          );
          if (font != null) _paintRow++;
        } else {
          _result = ForumBodyInlineParentRows._(
            geometry,
            _rows!,
            _fontClearance,
          );
          _rows = null;
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

  ForumBodyInlineParentRows takeRows() {
    if (_operating) throw StateError('Inline parent rows are reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Inline parent rows are incomplete');
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
    if (_closed) throw StateError('Inline parent rows are retired');
    _ensureOwner!();
    if (_closed || _parent?.isActive != true) {
      throw StateError('Inline parent row owner is retired');
    }
  }

  void close() {
    _closed = true;
    _parent = null;
    _geometry = null;
    _ensureOwner = null;
    _painted = null;
    _envelopes = null;
    _cuts = null;
    _rows = null;
    _clearance = null;
    _result = null;
  }
}

/// Borrows an actual prepared parent; it paints only parent glyph rows. Child
/// drawing, allocation, hit/selection and complete readable delivery stay with
/// their source-qualified containing format.
final class ForumBodyInlineParentRowView {
  ForumBodyInlineParentRowView.bind({
    required this.parent,
    required this.rows,
    required void Function() ensureOwner,
  }) : _ensureOwner = ensureOwner {
    _guard();
    _checkSource(parent, rows.geometry);
    _guard();
  }
  final ForumBodyInlineParagraphLease parent;
  final ForumBodyInlineParentRows rows;
  final void Function() _ensureOwner;
  bool _painting = false;
  bool get isPaintPrepared => parent.isActive && parent.layout.isPaintPrepared;
  void paintParentRow(Canvas canvas, Offset offset, int lineIndex) {
    if (_painting) throw StateError('Inline parent row paint is reentrant');
    _painting = true;
    try {
      _guard();
      RangeError.checkValidIndex(lineIndex, rows.rows, 'lineIndex');
      if (!offset.dx.isFinite || !offset.dy.isFinite) {
        throw ArgumentError.value(offset);
      }
      if (!isPaintPrepared) {
        throw StateError('Inline parent row paint is not prepared');
      }
      final row = rows.rows[lineIndex];
      if (row.isEmpty) return;
      final selector = row.selector;
      canvas.save();
      try {
        canvas.translate(offset.dx, offset.dy - selector.originY);
        canvas.clipRect(
          Rect.fromLTRB(
            -16384,
            selector.clipTop,
            parent.layout.width + 16384,
            selector.clipBottom,
          ),
          doAntiAlias: false,
        );
        parent.layout.paintParent(canvas, Offset.zero);
      } finally {
        canvas.restore();
      }
    } finally {
      _painting = false;
    }
  }

  void _guard() {
    _ensureOwner();
    if (!parent.isActive) {
      throw StateError('Inline parent row owner is retired');
    }
  }
}

void _checkSource(
  ForumBodyInlineParagraphLease parent,
  ForumBodyInlineEmphasisTextGeometry geometry,
) {
  if (!identical(parent.content, geometry.input.glyphInput.glyphs) ||
      parent.nativeInputIdentity != geometry.nativeInputIdentity ||
      !identical(parent.layout.lines, geometry.lines) ||
      parent.layout.rowIsolationPitch == null) {
    _fail(ForumBodyParagraphRowFailure.source);
  }
}

Never _fail(ForumBodyParagraphRowFailure failure) =>
    throw ForumBodyParagraphRowException(failure);
