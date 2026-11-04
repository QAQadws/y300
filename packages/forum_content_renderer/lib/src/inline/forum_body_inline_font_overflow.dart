import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';

/// Borrows one actual natural parent; no source parsing, shaping, recording or
/// ownership transfer. Every part scans one row/slot, queries one native text
/// gap, or consumes one box. Opaque child fonts never masquerade as parent ink.
final class ForumBodyInlineFontOverflowPreparation {
  ForumBodyInlineFontOverflowPreparation({
    required ForumBodyInlineParagraphLease parent,
    required void Function() ensureOwner,
  }) : _parent = parent,
       _ensureOwner = ensureOwner,
       _maxBoxes =
           parent.layout.projection.engineText.length +
           parent.layout.lineCount +
           parent.content.runs.length +
           parent.layout.projection.atoms.length {
    _guard();
    if (parent.layout.rowIsolationPitch != null) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.isolation,
      );
    }
  }
  ForumBodyInlineParagraphLease? _parent;
  void Function()? _ensureOwner;
  final int _maxBoxes;
  Iterator<TextBox>? _boxes;
  int _row = 0, _first = 0, _atom = 0, _cursor = 0, _end = 0, _boxCount = 0;
  double _top = 0, _bottom = 0, _baseline = 0;
  bool _range = false, _closed = false, _operating = false;
  bool? _result;
  bool get isReady => _result != null;
  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Mixed font probe is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        final layout = _parent!.layout;
        if (_boxes case final boxes?) {
          if (boxes.moveNext()) {
            final box = boxes.current;
            if (!box.toRect().isFinite || box.bottom < box.top) {
              throw const ForumBodyParagraphLayoutException(
                ForumBodyParagraphLayoutFailure.coverage,
              );
            }
            // Native boxes are Float32; logical row baselines are doubles.
            // Use the existing native rounding bound, not a tiny double epsilon
            // that would allocate fitting ruby paragraphs for harmless ULPs.
            final tolerance = forumBodyNativeVerticalBoxTolerance(
              box,
              _baseline,
            );
            if (!box.toRect().isEmpty &&
                (box.top < _top - tolerance ||
                    box.bottom > _bottom + tolerance)) {
              _result = true;
            }
          } else {
            _boxes = null;
          }
        } else if (_range) {
          final atoms = layout.projection.atoms;
          if (_cursor >= _end) {
            _range = false;
          } else if (_atom < atoms.length &&
              atoms[_atom].engineEndUtf16 <= _cursor) {
            _atom++;
          } else if (_atom < atoms.length &&
              atoms[_atom].engineUtf16 <= _cursor) {
            // Keep a slot until a later native range starts after its end;
            // source-free glue may straddle a physical row boundary.
            _cursor = atoms[_atom].engineEndUtf16;
          } else {
            final end = _atom < atoms.length && atoms[_atom].engineUtf16 < _end
                ? atoms[_atom].engineUtf16
                : _end;
            final boxes = layout.parentFontBoxesAtEngineRange(_cursor, end);
            _cursor = end;
            _boxCount += boxes.length;
            if (_boxCount > _maxBoxes) {
              throw const ForumBodyParagraphLayoutException(
                ForumBodyParagraphLayoutFailure.coverage,
              );
            }
            _boxes = boxes.iterator;
          }
        } else if (_row < layout.lineCount) {
          final row = _row++, line = layout.lines[row];
          if (line.canBreakAfter) {
            final first = layout.lines[_first];
            _top = _first == 0 ? 0 : first.top;
            _bottom = _row == layout.lineCount
                ? layout.height
                : layout.lines[_row].top;
            _baseline = line.baseline;
            _cursor =
                first.engineStartUtf16 < layout.projection.enginePrefix.length
                ? layout.projection.enginePrefix.length
                : first.engineStartUtf16;
            _end = line.engineUnpaintedTrailingSpaceStartUtf16;
            _first = _row;
            _range = true;
          }
        } else {
          if (_first != layout.lineCount) {
            throw const ForumBodyParagraphLayoutException(
              ForumBodyParagraphLayoutFailure.coverage,
            );
          }
          _result = false;
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

  bool take() {
    _guard();
    if (_operating || !isReady) {
      throw StateError('Mixed font probe is incomplete');
    }
    final result = _result!;
    close();
    return result;
  }

  void _guard() {
    if (_closed) throw StateError('Mixed font probe is retired');
    _ensureOwner!();
    if (_closed || _parent?.isActive != true) {
      throw StateError('Mixed font owner is retired');
    }
  }

  void close() {
    _closed = true;
    _parent = null;
    _ensureOwner = null;
    _boxes = null;
    _result = null;
  }
}
