import 'dart:collection';

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import '../style/forum_body_native_text_paint.dart';
import 'forum_body_emphasis_text_geometry.dart';
import 'forum_body_inline_span_content.dart';

/// Actual parent glyph frames and slot rows from a single native layout.
final class ForumBodyInlineFontGeometry {
  ForumBodyInlineFontGeometry._(
    this.content,
    this.nativeInputIdentity,
    this.lines,
    List<Rect?> parentFontBounds,
    List<int> atomLineIndices,
  ) : parentFontBounds = UnmodifiableListView(parentFontBounds),
      atomLineIndices = UnmodifiableListView(atomLineIndices);

  final ForumBodyInlineSpanContent content;
  final Object nativeInputIdentity;
  final List<ForumBodyParagraphLine> lines;
  int get lineCount => lines.length;

  /// Null means the row has no queried parent glyph. Children use their own
  /// measured boxes, including rows that only contain placeholders.
  final List<Rect?> parentFontBounds;

  /// Actual engine row of each slot, including any trimmed soft slots.
  final List<int> atomLineIndices;
}

/// Borrows the exact parent while capturing one row, slot or glyph per step.
final class ForumBodyInlineFontGeometryPreparation {
  ForumBodyInlineFontGeometryPreparation({
    required ForumBodyInlineSpanContent content,
    required ForumBodyInlineParagraphLease parent,
    required void Function() ensureOwner,
    this.maxGlyphQueries = 16384,
  }) : _parent = parent,
       _ensureOwner = ensureOwner {
    if (maxGlyphQueries < 0) {
      throw ArgumentError.value(maxGlyphQueries, 'maxGlyphQueries');
    }
    try {
      _guard();
      if (!identical(parent.content, content) ||
          content.paintLayer != ForumBodyParagraphPaintLayer.all) {
        throw const ForumBodyEmphasisGeometryException(
          ForumBodyEmphasisGeometryFailure.source,
        );
      }
      _lineCount = parent.layout.lineCount;
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }

  final int maxGlyphQueries;
  ForumBodyInlineParagraphLease? _parent;
  void Function()? _ensureOwner;
  late final int _lineCount;
  int _engine = -1, _atom = 0, _atomLine = 0, _glyphQueries = 0;
  List<Rect?>? _parentFontBounds = [];
  List<int>? _atomLines = [];
  ForumBodyInlineFontGeometry? _result;
  bool _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Inline font geometry is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (used < maxParts && !isReady) {
        _scanParent();
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
    final parent = _parent!, layout = parent.layout;
    final projection = layout.projection;
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
      _result = ForumBodyInlineFontGeometry._(
        parent.content,
        parent.nativeInputIdentity,
        layout.lines,
        _parentFontBounds!,
        _atomLines!,
      );
      _parentFontBounds = null;
      _atomLines = null;
      return;
    }
    if (_atom < projection.atoms.length &&
        projection.atoms[_atom].engineUtf16 == _engine) {
      final row = _row(_atomLine);
      if (_engine >= row.engineCoverageEndUtf16) {
        _atomLine++;
        return;
      }
      if (_engine < row.engineCoverageStartUtf16) {
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
      final rect = glyph.fontBounds;
      if (!rect.isFinite || rect.width < 0 || rect.height < 0) {
        throw const ForumBodyEmphasisGeometryException(
          ForumBodyEmphasisGeometryFailure.boxes,
        );
      }
      final index = glyph.lineIndex;
      final old = _parentFontBounds![index];
      _parentFontBounds![index] = old?.expandToInclude(rect) ?? rect;
    }
    // Native styled scalars can cross rows within one display grapheme.
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

  ForumBodyInlineFontGeometry takeGeometry() {
    if (_operating) throw StateError('Inline font geometry is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Inline font geometry is incomplete');
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
    if (_closed) throw StateError('Inline font geometry is retired');
    _ensureOwner!();
    if (_closed || !_parent!.isActive || _parent!.layout.isDisposed) {
      throw StateError('Inline font geometry owner is retired');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _parent = null;
    _ensureOwner = null;
    _parentFontBounds = null;
    _atomLines = null;
    _result = null;
  }
}
