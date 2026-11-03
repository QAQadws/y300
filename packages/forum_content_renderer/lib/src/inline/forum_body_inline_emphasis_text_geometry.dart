part of 'forum_body_emphasis_text_geometry.dart';

/// Actual parent-only targets, physical glyph fonts and child-slot rows,
/// retaining original units and opaque native input identity. No borrowed
/// handle, cache or owner survives capture.
final class ForumBodyInlineEmphasisTextGeometry {
  ForumBodyInlineEmphasisTextGeometry._(
    this.input,
    this.nativeInputIdentity,
    this.lines,
    List<Rect?> parentFontBounds,
    List<int> atomLineIndices,
    List<ForumBodyEmphasisTargetGeometry> targets,
  ) : parentFontBounds = UnmodifiableListView(parentFontBounds),
      atomLineIndices = UnmodifiableListView(atomLineIndices),
      targets = UnmodifiableListView(targets);
  static const revision = 2;
  final ForumBodyInlineEmphasisTextInput input;
  final Object nativeInputIdentity;
  final List<ForumBodyParagraphLine> lines;
  int get lineCount => lines.length;

  /// Actual ordinary-parent glyph envelopes, including unmarked text. Null
  /// means no queried parent glyph on that row, not a zero-sized root font.
  /// Child bases/annotations and empty font struts must be combined separately.
  final List<Rect?> parentFontBounds;

  /// Actual engine row of each original opaque/glue slot. Trimmed soft slots
  /// still have an engine row; these indices do not qualify child visibility.
  final List<int> atomLineIndices;
  final List<ForumBodyEmphasisTargetGeometry> targets;
}

/// Borrows the exact qualified parent. Each unit consumes one row, selection,
/// box, scalar font query, governing query or publication. Child content and
/// mechanical prefixes are skipped; the caller's lease is never released.
final class ForumBodyInlineEmphasisGeometryPreparation {
  ForumBodyInlineEmphasisGeometryPreparation({
    required ForumBodyInlineEmphasisTextInput input,
    required ForumBodyInlineParagraphLease parent,
    required void Function() ensureOwner,
    this.maxBoxes = 4096,
    this.maxGlyphQueries = 16384,
  }) : _input = input,
       _parent = parent,
       _ensureOwner = ensureOwner {
    if (maxBoxes < 0 || maxGlyphQueries < 0) {
      throw ArgumentError('Invalid inline geometry budget');
    }
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
  final int maxBoxes, maxGlyphQueries;
  ForumBodyInlineEmphasisTextInput? _input;
  ForumBodyInlineParagraphLease? _parent;
  void Function()? _ensureOwner;
  Object? _nativeInputIdentity;
  int _lineCount = 0, _line = 0, _unit = 0, _box = 0, _boxCount = 0;
  int _engine = -1, _atom = 0, _atomLine = 0, _glyphQueries = 0;
  List<Rect?>? _parentFontBounds = [];
  List<int>? _atomLines = [];
  bool _parentScanned = false;
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
        if (!_parentScanned) {
          _scanParent();
        } else if (_unit == input.units.length) {
          _result = ForumBodyInlineEmphasisTextGeometry._(
            input,
            _nativeInputIdentity!,
            _parent!.layout.lines,
            _parentFontBounds!,
            _atomLines!,
            _targets!,
          );
          _parentFontBounds = null;
          _atomLines = null;
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

  void _scanParent() {
    if (_parentFontBounds!.length < _lineCount) {
      _parentFontBounds!.add(null);
      return;
    }
    final layout = _parent!.layout, projection = layout.projection;
    if (_engine < 0) {
      _engine = projection.enginePrefix.length;
      return;
    }
    if (_engine == projection.engineText.length) {
      if (_atom != projection.atoms.length) {
        throw const ForumBodyEmphasisGeometryException(
          ForumBodyEmphasisGeometryFailure.source,
        );
      }
      _parentScanned = true;
      return;
    }
    if (_atom < projection.atoms.length &&
        projection.atoms[_atom].engineUtf16 == _engine) {
      if (_engine >= _row(_atomLine).engineCoverageEndUtf16) {
        _atomLine++;
        return;
      }
      if (_engine < _row(_atomLine).engineCoverageStartUtf16) {
        throw const ForumBodyEmphasisGeometryException(
          ForumBodyEmphasisGeometryFailure.line,
        );
      }
      _atomLines!.add(_atomLine);
      _engine = projection.atoms[_atom++].engineEndUtf16;
      return;
    }
    if (_glyphQueries >= maxGlyphQueries) {
      throw const ForumBodyEmphasisGeometryException(
        ForumBodyEmphasisGeometryFailure.limit,
      );
    }
    _glyphQueries++;
    final glyph = layout.glyphAtEngineUtf16(_engine);
    _guard();
    if (glyph != null) {
      _checkInlineTargetRect(glyph.fontBounds);
      final index = glyph.lineIndex, old = _parentFontBounds![glyph.lineIndex];
      _parentFontBounds![index] =
          old?.expandToInclude(glyph.fontBounds) ?? glyph.fontBounds;
    }
    // Advance a raw engine scalar, not a normalized display grapheme. Styled
    // prepend/combining scalars can have distinct native rows within one unit.
    final text = projection.engineText, first = text.codeUnitAt(_engine);
    final pair =
        first >= 0xd800 &&
        first <= 0xdbff &&
        _engine + 1 < text.length &&
        text.codeUnitAt(_engine + 1) >= 0xdc00 &&
        text.codeUnitAt(_engine + 1) <= 0xdfff;
    _engine += pair ? 2 : 1;
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
    _parentFontBounds = null;
    _atomLines = null;
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
