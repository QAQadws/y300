part of 'forum_body_inline_span_content.dart';

final class _InlineParentPiece {
  const _InlineParentPiece.text(this.startUtf16, this.endUtf16, this.runIndex)
    : atomIndex = null;
  const _InlineParentPiece.atom(this.atomIndex)
    : startUtf16 = 0,
      endUtf16 = 0,
      runIndex = null;
  final int startUtf16, endUtf16;
  final int? runIndex, atomIndex;
}

/// Shared by the native span builder and cooperative glyph derivation. A part
/// hidden behind one atom still costs one scan step; no whole skip loop occurs.
final class _InlineParentCursor {
  _InlineParentCursor(this.projection);
  final HtmlInlineTextProjection projection;
  var _part = 0, _atom = 0, _offset = 0;
  bool get isComplete => _offset == projection.display.text.length;

  _InlineParentPiece? advance() {
    if (isComplete) throw StateError('Inline parent cursor is complete');
    final atoms = projection.atoms;
    if (_atom < atoms.length && _offset == atoms[_atom].displayStartUtf16) {
      _offset = atoms[_atom].displayEndUtf16;
      return _InlineParentPiece.atom(_atom++);
    }
    final part = projection.display.parts[_part];
    final end = part.utf16Start + part.text.length;
    if (end <= _offset) {
      _part++;
      return null;
    }
    final boundary =
        _atom < atoms.length && atoms[_atom].displayStartUtf16 < end
        ? atoms[_atom].displayStartUtf16
        : end;
    final result = _InlineParentPiece.text(_offset, boundary, part.runIndex);
    _offset = boundary;
    return result;
  }
}
