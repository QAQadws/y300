import 'dart:collection';

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
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
    List<TextBox> boxes,
  ) : boxes = UnmodifiableListView(boxes);
  final ForumBodyEmphasisTextUnit unit;
  final int lineIndex;
  final double baseline;
  final Rect fontBounds;
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
  ) : targets = UnmodifiableListView(targets);
  static const revision = 1;
  final ForumBodyEmphasisTextInput input;
  final Object nativeInputIdentity;
  final int lineCount;
  final List<ForumBodyEmphasisTargetGeometry> targets;
}

/// Borrows the caller's actual base lease. One part advances a physical line,
/// obtains one complete unit's boxes, consumes one box or publishes one result.
/// It never shapes, paints, acquires resources or owns the caller's handle.
final class ForumBodyEmphasisGeometryPreparation {
  ForumBodyEmphasisGeometryPreparation({
    required ForumBodyEmphasisTextInput input,
    required ForumBodyTextLease base,
    required void Function() ensureOwner,
    this.maxBoxes = 4096,
  }) : _input = input,
       _base = base,
       _ensureOwner = ensureOwner {
    if (maxBoxes < 0) throw ArgumentError.value(maxBoxes);
    try {
      _guard();
      // Same text, equal metrics or an equal native key cannot establish the
      // explicit derivation from the original author-emphasis source input.
      if (!identical(base.content, input.glyphInput.glyphs)) {
        throw const ForumBodyEmphasisGeometryException(
          ForumBodyEmphasisGeometryFailure.source,
        );
      }
      _nativeInputIdentity = base.nativeInputIdentity;
      _lineCount = switch (base) {
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
  void Function()? _ensureOwner;
  Object? _nativeInputIdentity;
  var _lineCount = 0, _line = 0, _unit = 0, _box = 0, _boxCount = 0;
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
        final input = _input!, base = _base!;
        if (_unit == input.units.length) {
          _result = ForumBodyEmphasisTextGeometry._(
            input,
            _nativeInputIdentity!,
            _lineCount,
            _targets!,
          );
          _targets = null;
        } else {
          final unit = input.units[_unit];
          final end = switch (base) {
            ForumBodyParagraphLease() when _line < _lineCount =>
              base.layout.lines[_line].coverageEndUtf16,
            ForumBodyTextBandChildLease() when _line == 0 =>
              base.content.projection.text.length,
            _ => throw const ForumBodyEmphasisGeometryException(
              ForumBodyEmphasisGeometryFailure.line,
            ),
          };
          if (unit.startUtf16 >= end) {
            _line++;
          } else if (_boxes == null) {
            final start = base is ForumBodyParagraphLease
                ? base.layout.lines[_line].coverageStartUtf16
                : 0;
            if (unit.startUtf16 < start || unit.endUtf16 > end) {
              throw const ForumBodyEmphasisGeometryException(
                ForumBodyEmphasisGeometryFailure.line,
              );
            }
            final boxes = base.layout.selectionBoxes(
              unit.startUtf16,
              unit.endUtf16,
            );
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
          } else {
            _targets!.add(
              ForumBodyEmphasisTargetGeometry._(
                unit,
                _line,
                base is ForumBodyParagraphLease
                    ? base.layout.lines[_line].baseline
                    : base.layout.alphabeticBaseline,
                _bounds!,
                _boxes!,
              ),
            );
            _boxes = null;
            _bounds = null;
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
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _input = null;
    _base = null;
    _ensureOwner = null;
    _nativeInputIdentity = null;
    _targets = null;
    _boxes = null;
    _bounds = null;
    _result = null;
  }
}
