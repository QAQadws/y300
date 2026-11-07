import 'dart:collection';

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import '../paragraph/forum_body_paragraph_row.dart';
import '../paragraph/forum_body_text_layout.dart';
import 'forum_body_emphasis_row_input.dart';
import 'forum_body_emphasis_text_input.dart';

enum ForumBodyEmphasisGeometryFailure { source, line, boxes, limit }

final class ForumBodyEmphasisGeometryException implements Exception {
  const ForumBodyEmphasisGeometryException(this.failure);
  final ForumBodyEmphasisGeometryFailure failure;
  @override
  String toString() => 'ForumBodyEmphasisGeometryException(${failure.name})';
}

/// The original whole-grapheme selection in the actual base layout. These are
/// native font selection bounds, not measured ink or a new source coordinate.
final class ForumBodyEmphasisTargetGeometry {
  ForumBodyEmphasisTargetGeometry._(
    this.unit,
    this.lineIndex,
    this.baseline,
    this.fontBounds,
    List<TextBox> boxes, {
    int? sourceStartLine,
    int? sourceEndLine,
    Rect? governingFontBounds,
  }) : boxes = UnmodifiableListView(boxes),
       sourceStartLine = sourceStartLine ?? lineIndex,
       sourceEndLine = sourceEndLine ?? lineIndex + 1,
       governingFontBounds = governingFontBounds ?? fontBounds;
  final ForumBodyEmphasisTextUnit unit;

  /// Governing row in this geometry's context. A complete source unit may
  /// start on an earlier row when a format/prepend scalar precedes its base.
  final int lineIndex;

  /// Half-open physical row span of the entire original display grapheme.
  final int sourceStartLine, sourceEndLine;
  final double baseline;

  /// Union of the complete unit's native selection boxes, across all its rows.
  final Rect fontBounds;

  /// Row inputs query the actual governing scalar. Whole/band inputs preserve
  /// their existing complete-unit bounds; these are font frames, not ink.
  final Rect governingFontBounds;
  final List<TextBox> boxes;
}

/// Numeric geometry with an explicit original input and opaque native key.
/// This snapshot is not a live owner, painted coverage or source qualification.
final class ForumBodyEmphasisTextGeometry {
  ForumBodyEmphasisTextGeometry._(
    this.input,
    this.nativeInputIdentity,
    this.lineCount,
    List<ForumBodyEmphasisTargetGeometry> targets,
    this.rowInput,
  ) : targets = UnmodifiableListView(targets);
  static const revision = 2;
  final ForumBodyEmphasisTextInput input;
  final Object nativeInputIdentity;
  final int lineCount;
  final List<ForumBodyEmphasisTargetGeometry> targets;
  final ForumBodyEmphasisRowInput? rowInput;
}

/// Borrows the caller's actual base lease. One part advances a physical line,
/// obtains one complete unit's boxes, consumes one box or publishes one result.
/// It never shapes, paints, acquires resources or owns the caller's handle.
final class ForumBodyEmphasisGeometryPreparation {
  ForumBodyEmphasisGeometryPreparation({
    required ForumBodyEmphasisTextInput input,
    required ForumBodyTextLease base,
    required void Function() ensureOwner,
    int maxBoxes = 4096,
  }) : this._(
         input: input,
         base: base,
         ensureOwner: ensureOwner,
         maxBoxes: maxBoxes,
       );

  ForumBodyEmphasisGeometryPreparation.row({
    required ForumBodyEmphasisRowInput input,
    required ForumBodyParagraphRowView base,
    required void Function() ensureOwner,
    int maxBoxes = 4096,
  }) : this._(
         input: input.text,
         base: base.parent,
         row: base,
         rowInput: input,
         ensureOwner: ensureOwner,
         maxBoxes: maxBoxes,
       );

  ForumBodyEmphasisGeometryPreparation._({
    required ForumBodyEmphasisTextInput input,
    required ForumBodyTextLease base,
    required void Function() ensureOwner,
    required this.maxBoxes,
    ForumBodyParagraphRowView? row,
    ForumBodyEmphasisRowInput? rowInput,
  }) : _input = input,
       _base = base,
       _row = row,
       _rowInput = rowInput,
       _ensureOwner = ensureOwner {
    if (maxBoxes < 0) throw ArgumentError.value(maxBoxes);
    try {
      _guard();
      // Same text, equal metrics or an equal native key cannot establish the
      // explicit derivation from the original author-emphasis source input.
      if (row == null
          ? !identical(base.content, input.glyphInput.glyphs)
          : !identical(row.metrics, rowInput!.row) ||
                !identical(base.content, rowInput.parentGlyphInput.glyphs)) {
        throw const ForumBodyEmphasisGeometryException(
          ForumBodyEmphasisGeometryFailure.source,
        );
      }
      _nativeInputIdentity = base.nativeInputIdentity;
      _lineCount =
          row?.metrics.lineCount ??
          switch (base) {
            ForumBodyParagraphLease() => base.layout.lineCount,
            ForumBodyTextBandChildLease() =>
              base.content.projection.text.isEmpty ? 0 : 1,
          };
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int maxBoxes;
  ForumBodyEmphasisTextInput? _input;
  ForumBodyTextLease? _base;
  ForumBodyParagraphRowView? _row;
  ForumBodyEmphasisRowInput? _rowInput;
  void Function()? _ensureOwner;
  Object? _nativeInputIdentity;
  var _lineCount = 0, _line = 0, _unit = 0, _box = 0, _boxCount = 0;
  int? _unitEndLine;
  ForumBodyParagraphGlyphGeometry? _governing;
  List<TextBox>? _boxes;
  Rect? _bounds;
  List<ForumBodyEmphasisTargetGeometry>? _targets = [];
  ForumBodyEmphasisTextGeometry? _result;
  bool _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Emphasis geometry is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (used < maxParts && !isReady) {
        _guard();
        final input = _input!;
        if (_unit == input.units.length) {
          _result = ForumBodyEmphasisTextGeometry._(
            input,
            _nativeInputIdentity!,
            _lineCount,
            _targets!,
            _rowInput,
          );
          _targets = null;
        } else {
          final unit = input.units[_unit];
          final end = _lineEnd(_line);
          if (unit.startUtf16 >= end) {
            _line++;
          } else if (_row != null && _unitEndLine == null) {
            _unitEndLine = _line;
          } else if (_row != null && unit.endUtf16 > _lineEnd(_unitEndLine!)) {
            _unitEndLine = _unitEndLine! + 1;
          } else if (_boxes == null) {
            if (unit.startUtf16 < _lineStart(_line) ||
                unit.endUtf16 > _lineEnd(_unitEndLine ?? _line)) {
              throw const ForumBodyEmphasisGeometryException(
                ForumBodyEmphasisGeometryFailure.line,
              );
            }
            final boxes = _selectionLayout.selectionBoxes(
              unit.startUtf16,
              unit.endUtf16,
            );
            _guard();
            if (boxes.isEmpty) {
              throw const ForumBodyEmphasisGeometryException(
                ForumBodyEmphasisGeometryFailure.boxes,
              );
            }
            if (boxes.length > maxBoxes - _boxCount) {
              throw const ForumBodyEmphasisGeometryException(
                ForumBodyEmphasisGeometryFailure.limit,
              );
            }
            _boxCount += boxes.length;
            _boxes = boxes;
            _box = 0;
            _bounds = null;
          } else if (_box < _boxes!.length) {
            final rect = _boxes![_box++].toRect();
            if (!rect.left.isFinite ||
                !rect.top.isFinite ||
                !rect.right.isFinite ||
                !rect.bottom.isFinite ||
                rect.width < 0 ||
                rect.height < 0) {
              throw const ForumBodyEmphasisGeometryException(
                ForumBodyEmphasisGeometryFailure.boxes,
              );
            }
            _bounds = _bounds?.expandToInclude(rect) ?? rect;
          } else if (_row != null && _governing == null) {
            if (_boxCount >= maxBoxes) {
              throw const ForumBodyEmphasisGeometryException(
                ForumBodyEmphasisGeometryFailure.limit,
              );
            }
            _boxCount++;
            final glyph = _row!.glyphAtDisplayUtf16(unit.governingUtf16);
            _guard();
            if (glyph == null ||
                glyph.lineIndex < _line ||
                glyph.lineIndex > _unitEndLine!) {
              throw const ForumBodyEmphasisGeometryException(
                ForumBodyEmphasisGeometryFailure.boxes,
              );
            }
            final rect = glyph.fontBounds;
            if (!rect.left.isFinite ||
                !rect.top.isFinite ||
                !rect.right.isFinite ||
                !rect.bottom.isFinite ||
                rect.width < 0 ||
                rect.height < 0) {
              throw const ForumBodyEmphasisGeometryException(
                ForumBodyEmphasisGeometryFailure.boxes,
              );
            }
            _governing = glyph;
          } else {
            final governingLine = _governing?.lineIndex ?? _line;
            _targets!.add(
              ForumBodyEmphasisTargetGeometry._(
                unit,
                governingLine,
                _baseline(governingLine),
                _bounds!,
                _boxes!,
                sourceStartLine: _line,
                sourceEndLine: (_unitEndLine ?? _line) + 1,
                governingFontBounds: _governing?.fontBounds,
              ),
            );
            _boxes = null;
            _bounds = null;
            _unitEndLine = null;
            _governing = null;
            _unit++;
          }
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

  ForumBodyEmphasisTextGeometry takeGeometry() {
    if (_operating) throw StateError('Emphasis geometry is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Emphasis geometry is incomplete');
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
    if (_closed) throw StateError('Emphasis geometry is retired');
    _ensureOwner!();
    if (_closed || !_base!.isActive || _base!.layout.isDisposed) {
      throw StateError('Emphasis geometry owner is retired');
    }
    final row = _row;
    if (row != null) {
      row.nativeInputIdentity;
      if (_closed) throw StateError('Emphasis row geometry owner is retired');
    }
  }

  ForumBodyTextLayout get _selectionLayout => _row ?? _base!.layout;
  int _lineStart(int line) {
    final actual = _paragraphLine(line);
    return actual == null
        ? 0
        : actual.coverageStartUtf16 - (_row?.metrics.startUtf16 ?? 0);
  }

  int _lineEnd(int line) {
    final actual = _paragraphLine(line);
    return actual == null
        ? _base!.content.projection.text.length
        : actual.coverageEndUtf16 - (_row?.metrics.startUtf16 ?? 0);
  }

  double _baseline(int line) {
    final actual = _paragraphLine(line);
    return actual == null
        ? _base!.layout.alphabeticBaseline
        : actual.baseline - (_row?.selector.originY ?? 0);
  }

  ForumBodyParagraphLine? _paragraphLine(int line) {
    if (line < 0 || line >= _lineCount) {
      throw const ForumBodyEmphasisGeometryException(
        ForumBodyEmphasisGeometryFailure.line,
      );
    }
    final base = _base!;
    if (base is! ForumBodyParagraphLease) return null;
    return base.layout.lines[line + (_row?.selector.startLine ?? 0)];
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _input = null;
    _base = null;
    _row = null;
    _rowInput = null;
    _ensureOwner = null;
    _nativeInputIdentity = null;
    _targets = null;
    _boxes = null;
    _bounds = null;
    _governing = null;
    _result = null;
  }
}
