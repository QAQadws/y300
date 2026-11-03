part of 'forum_body_emphasis_text_geometry.dart';

/// Actual parent-only target geometry, retaining original units and opaque
/// native input identity. No borrowed handle, cache or owner survives capture.
final class ForumBodyInlineEmphasisTextGeometry {
  ForumBodyInlineEmphasisTextGeometry._(
    this.input,
    this.nativeInputIdentity,
    this.lineCount,
    List<ForumBodyEmphasisTargetGeometry> targets,
  ) : targets = UnmodifiableListView(targets);
  static const revision = 1;
  final ForumBodyInlineEmphasisTextInput input;
  final Object nativeInputIdentity;
  final int lineCount;
  final List<ForumBodyEmphasisTargetGeometry> targets;
}

/// Borrows the exact qualified parent. Each unit consumes one row, selection,
/// box, governing query or publication; it never releases the caller's lease.
final class ForumBodyInlineEmphasisGeometryPreparation {
  ForumBodyInlineEmphasisGeometryPreparation({
    required ForumBodyInlineEmphasisTextInput input,
    required ForumBodyInlineParagraphLease parent,
    required void Function() ensureOwner,
    this.maxBoxes = 4096,
  }) : _input = input,
       _parent = parent,
       _ensureOwner = ensureOwner {
    if (maxBoxes < 0) throw ArgumentError.value(maxBoxes);
    try {
      _guard();
      if (!identical(parent.content, input.glyphInput.glyphs)) {
        throw const ForumBodyEmphasisGeometryException(
          ForumBodyEmphasisGeometryFailure.source,
        );
      }
      _nativeInputIdentity = parent.nativeInputIdentity;
      _lineCount = parent.layout.lineCount;
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int maxBoxes;
  ForumBodyInlineEmphasisTextInput? _input;
  ForumBodyInlineParagraphLease? _parent;
  void Function()? _ensureOwner;
  Object? _nativeInputIdentity;
  int _lineCount = 0, _line = 0, _unit = 0, _box = 0, _boxCount = 0;
  int? _unitEndLine;
  List<TextBox>? _boxes;
  Rect? _bounds;
  ForumBodyParagraphGlyphGeometry? _governing;
  List<ForumBodyEmphasisTargetGeometry>? _targets = [];
  ForumBodyInlineEmphasisTextGeometry? _result;
  bool _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Inline emphasis geometry is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (used < maxParts && !isReady) {
        final input = _input!;
        if (_unit == input.units.length) {
          _result = ForumBodyInlineEmphasisTextGeometry._(
            input,
            _nativeInputIdentity!,
            _lineCount,
            _targets!,
          );
          _targets = null;
        } else {
          final unit = input.units[_unit];
          if (unit.startUtf16 >= _row(_line).coverageEndUtf16) {
            _line++;
          } else if (_unitEndLine == null) {
            _unitEndLine = _line;
          } else if (unit.endUtf16 > _row(_unitEndLine!).coverageEndUtf16) {
            _unitEndLine = _unitEndLine! + 1;
          } else if (_boxes == null) {
            if (unit.startUtf16 < _row(_line).coverageStartUtf16) {
              throw const ForumBodyEmphasisGeometryException(
                ForumBodyEmphasisGeometryFailure.line,
              );
            }
            final boxes = _parent!.layout.parentSelectionBoxes(
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
          } else if (_box < _boxes!.length) {
            final rect = _boxes![_box++].toRect();
            _checkInlineTargetRect(rect);
            _bounds = _bounds?.expandToInclude(rect) ?? rect;
          } else if (_governing == null) {
            if (_boxCount >= maxBoxes) {
              throw const ForumBodyEmphasisGeometryException(
                ForumBodyEmphasisGeometryFailure.limit,
              );
            }
            _boxCount++;
            // Map only the complete unit's legal start. Normalizing the actual
            // scalar could move a styled prepend query back to an earlier row.
            final layout = _parent!.layout;
            final start = layout.projection.engineAtDisplayUtf16(
              unit.startUtf16,
            );
            if (!start.isExact) {
              throw const ForumBodyEmphasisGeometryException(
                ForumBodyEmphasisGeometryFailure.source,
              );
            }
            final glyph = layout.glyphAtEngineUtf16(
              start.engineUtf16 + unit.governingUtf16 - unit.startUtf16,
            );
            _guard();
            if (glyph == null ||
                glyph.lineIndex < _line ||
                glyph.lineIndex > _unitEndLine!) {
              throw const ForumBodyEmphasisGeometryException(
                ForumBodyEmphasisGeometryFailure.boxes,
              );
            }
            _checkInlineTargetRect(glyph.fontBounds);
            _governing = glyph;
          } else {
            final governing = _governing!;
            _targets!.add(
              ForumBodyEmphasisTargetGeometry._(
                unit,
                governing.lineIndex,
                _row(governing.lineIndex).baseline,
                _bounds!,
                _boxes!,
                sourceStartLine: _line,
                sourceEndLine: _unitEndLine! + 1,
                governingFontBounds: governing.fontBounds,
              ),
            );
            _boxes = null;
            _bounds = null;
            _governing = null;
            _unitEndLine = null;
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

  ForumBodyParagraphLine _row(int index) {
    if (index < 0 || index >= _lineCount) {
      throw const ForumBodyEmphasisGeometryException(
        ForumBodyEmphasisGeometryFailure.line,
      );
    }
    return _parent!.layout.lines[index];
  }

  ForumBodyInlineEmphasisTextGeometry takeGeometry() {
    if (_operating) throw StateError('Inline emphasis geometry is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Inline emphasis geometry is incomplete');
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
    if (_closed) throw StateError('Inline emphasis geometry is retired');
    _ensureOwner!();
    if (_closed || !_parent!.isActive || _parent!.layout.isDisposed) {
      throw StateError('Inline emphasis geometry owner is retired');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _input = null;
    _parent = null;
    _ensureOwner = null;
    _nativeInputIdentity = null;
    _targets = null;
    _boxes = null;
    _bounds = null;
    _governing = null;
    _result = null;
  }
}

void _checkInlineTargetRect(Rect rect) {
  if (!rect.isFinite || rect.width < 0 || rect.height < 0) {
    throw const ForumBodyEmphasisGeometryException(
      ForumBodyEmphasisGeometryFailure.boxes,
    );
  }
}
