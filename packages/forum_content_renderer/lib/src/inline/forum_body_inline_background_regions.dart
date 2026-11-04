part of 'forum_body_inline_paragraph_view.dart';

/// Merge one source root once per actual native row, before any glyph paint.
/// Building is charged with each already-bounded visible atom binding.
final class _RubyBackgroundRegions {
  var _rects = <({Rect rect, ForumBodyRubyContainerFontBox font})>[];
  var _rows = <int>[];
  final _indices =
      <(String, int), ({int index, ForumBodyRubyContainerFontBox font})>{};
  void add(ForumBodyRubyContainerFontBox font, int row, Rect rect) {
    if (rect.isEmpty) return;
    final key = (font.background.rootPath, row);
    final old = _indices[key];
    if (old == null) {
      _indices[key] = (index: _rects.length, font: font);
      _rects.add((rect: rect, font: font));
      _rows.add(row);
    } else {
      if (old.font.background.color != font.background.color ||
          old.font.background.fontStrut.style.textStyle !=
              font.background.fontStrut.style.textStyle ||
          old.font.height != font.height ||
          old.font.alphabeticBaseline != font.alphabeticBaseline) {
        ForumBodyInlineParagraphView._fail(ForumBodyInlineViewFailure.identity);
      }
      _rects[old.index] = (
        rect: _rects[old.index].rect.expandToInclude(rect),
        font: font,
      );
    }
  }

  ({
    List<({Rect rect, ForumBodyRubyContainerFontBox font})> surfaces,
    List<int> rows,
  })
  take() {
    final result = (
      surfaces: UnmodifiableListView(_rects),
      rows: UnmodifiableListView(_rows),
    );
    _rects = [];
    _rows = [];
    _indices.clear();
    return result;
  }

  void clear() {
    _rects.clear();
    _rows.clear();
    _indices.clear();
  }
}
