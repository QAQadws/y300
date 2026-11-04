import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/painting.dart';

import 'forum_body_paragraph_cache.dart';
import 'forum_body_paragraph_row.dart';

/// Borrows one actual natural paragraph. Each part queries one row or consumes
/// one font box; a positive result requests the existing allocated-row path.
/// This probe neither changes geometry nor authorizes paint/source coverage.
final class ForumBodyParagraphFontOverflowPreparation {
  ForumBodyParagraphFontOverflowPreparation({
    required ForumBodyParagraphLease parent,
    required void Function() ensureOwner,
    int? maxLines,
    int? maxBoxes,
  }) : maxLines = maxLines ?? parent.layout.lineCount + 1,
       maxBoxes =
           maxBoxes ??
           parent.content.projection.text.length +
               parent.layout.lineCount +
               parent.content.runs.length,
       _parent = parent,
       _ensureOwner = ensureOwner {
    if (this.maxLines <= 0 || this.maxBoxes < 0) {
      throw ArgumentError('Invalid font-frame limit');
    }
    _guard();
    if (parent.layout.rowIsolationPitch != null) {
      throw const ForumBodyParagraphRowException(
        ForumBodyParagraphRowFailure.source,
      );
    }
    if (parent.layout.lineCount > this.maxLines) {
      throw const ForumBodyParagraphRowException(
        ForumBodyParagraphRowFailure.limit,
      );
    }
  }

  final int maxLines, maxBoxes;
  ForumBodyParagraphLease? _parent;
  void Function()? _ensureOwner;
  Iterator<TextBox>? _boxes;
  double _top = 0, _bottom = 0;
  int _row = 0, _groupStart = 0, _boxCount = 0;
  bool? _result;
  bool _closed = false;
  bool _operating = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Font-frame probe is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        final layout = _parent!.layout;
        if (_boxes case final boxes?) {
          if (!boxes.moveNext()) {
            _boxes = null;
          } else {
            final box = boxes.current;
            if (!box.top.isFinite ||
                !box.bottom.isFinite ||
                box.bottom < box.top) {
              throw const ForumBodyParagraphRowException(
                ForumBodyParagraphRowFailure.geometry,
              );
            }
            if (box.bottom > box.top &&
                (box.top < _top - precisionErrorTolerance ||
                    box.bottom > _bottom + precisionErrorTolerance)) {
              _result = true;
            }
          }
        } else if (_row < layout.lineCount) {
          final row = _row++, line = layout.lines[row];
          // Only legal page windows matter. A complete grapheme can span
          // several physical rows; do not probe it once per internal row.
          if (!line.canBreakAfter) {
            used++;
            _guard();
            continue;
          }
          final first = layout.lines[_groupStart];
          _top = _groupStart == 0 ? 0 : first.top;
          _bottom = row + 1 == layout.lineCount
              ? layout.height
              : layout.lines[row + 1].top;
          _groupStart = _row;
          // Native omitted trailing SPACE is not drawn. Hard separators retain
          // their existing row ownership without adding an invented font box.
          if (first.startUtf16 < line.unpaintedTrailingSpaceStartUtf16) {
            final boxes = layout.selectionBoxes(
              first.startUtf16,
              line.unpaintedTrailingSpaceStartUtf16,
            );
            _boxCount += boxes.length;
            if (_boxCount > maxBoxes) {
              throw const ForumBodyParagraphRowException(
                ForumBodyParagraphRowFailure.limit,
              );
            }
            _boxes = boxes.iterator;
          }
        } else {
          if (_groupStart != layout.lineCount) {
            throw const ForumBodyParagraphRowException(
              ForumBodyParagraphRowFailure.source,
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
    if (_operating) throw StateError('Font-frame probe is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Font-frame probe is incomplete');
      final result = _result!;
      close();
      return result;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_closed) throw StateError('Font-frame probe is retired');
    _ensureOwner!();
    if (_closed || _parent?.isActive != true) {
      throw StateError('Font-frame probe owner is retired');
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
