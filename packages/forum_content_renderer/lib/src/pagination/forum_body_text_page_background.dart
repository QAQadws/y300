part of 'forum_body_text_page_composer.dart';

/// Paint-only border-box fragment. Margins are excluded, padding is included;
/// a continued box is sliced at the page edge without repeating its padding.
/// It has no text projection, glyph coverage or semantic reading position.
final class ForumBodyTextPageBackground {
  const ForumBodyTextPageBackground._(
    this.path,
    this.left,
    this.top,
    this.width,
    this.height,
    this.color,
    this.quoteDecoration,
    this.startsBox,
    this.endsBox,
  );
  final String path;
  final double left, top, width, height;
  final Color color;
  final ForumBodyQuoteDecoration? quoteDecoration;

  /// Corner eligibility for rounded chrome. Rectangular fills do not wait for
  /// an exact-edge close, since that boundary cannot affect their paint.
  final bool startsBox, endsBox;

  ForumBodyTextPageBackground _shift(Offset offset) =>
      ForumBodyTextPageBackground._(
        path,
        left + offset.dx,
        top + offset.dy,
        width,
        height,
        color,
        quoteDecoration,
        startsBox,
        endsBox,
      );
}

/// Bounded numeric block decoration state, independent of native resources.
/// First placement resolves collapsed top margins; closing uses the actual flow
/// end, which can precede occupied glyphs after a negative child margin.
final class _PageBackgrounds {
  static const maxDepth = 128;
  final _open = <_BackgroundBox>[];
  final _draft = <_BackgroundSlice>[];
  int _pendingRoundedEnds = 0;
  bool get needsEndBoundary => _pendingRoundedEnds > 0;
  bool get isBalanced => _open.isEmpty;
  int get itemCount => _draft.length;

  void open(
    String path,
    double left,
    double width,
    Color color,
    ForumBodyQuoteDecoration? quoteDecoration,
  ) {
    if (_open.length == maxDepth) {
      throw const ForumBodyTextPageException(
        ForumBodyTextPageFailure.backgroundDepth,
      );
    }
    _open.add(_BackgroundBox(path, left, width, color, quoteDecoration));
  }

  void close(String path, double flowEnd) {
    if (_open.isEmpty || _open.last.path != path) {
      throw StateError('Unbalanced page background');
    }
    final slice = _open.removeLast().current;
    if (slice != null) {
      slice.bottom = flowEnd;
      slice.closed = true;
      if (slice.box.quoteDecoration != null) _pendingRoundedEnds--;
    }
  }

  int touch(double top, int remainingItems) {
    var first = _open.length;
    while (first > 0 && _open[first - 1].current == null) {
      first--;
    }
    final count = _open.length - first;
    if (count > remainingItems) {
      throw const ForumBodyTextPageException(
        ForumBodyTextPageFailure.fragmentLimit,
      );
    }
    // Append ancestors first so a child's translucent background composites
    // over its parent, including when both start at the same collapsed edge.
    for (var i = first; i < _open.length; i++) {
      final box = _open[i];
      final slice = _BackgroundSlice(
        box,
        box.continued ? 0 : top,
        !box.continued,
      );
      box.current = slice;
      _draft.add(slice);
      if (box.quoteDecoration != null) _pendingRoundedEnds++;
    }
    return count;
  }

  List<ForumBodyTextPageBackground> seal(double pageHeight) {
    for (final box in _open) {
      if (box.current != null) {
        box.current!.bottom = pageHeight;
        box.current = null;
        box.continued = true;
      }
    }
    final result = [
      for (final slice in _draft)
        ForumBodyTextPageBackground._(
          slice.box.path,
          slice.box.left,
          slice.top,
          slice.box.width,
          math.max(0.0, slice.bottom! - slice.top),
          slice.box.color,
          slice.box.quoteDecoration,
          slice.startsBox,
          slice.closed,
        ),
    ];
    _draft.clear();
    _pendingRoundedEnds = 0;
    return result;
  }

  void clear() {
    _open.clear();
    _draft.clear();
    _pendingRoundedEnds = 0;
  }
}

final class _BackgroundBox {
  _BackgroundBox(
    this.path,
    this.left,
    this.width,
    this.color,
    this.quoteDecoration,
  );
  final String path;
  final double left, width;
  final Color color;
  final ForumBodyQuoteDecoration? quoteDecoration;
  bool continued = false;
  _BackgroundSlice? current;
}

final class _BackgroundSlice {
  _BackgroundSlice(this.box, this.top, this.startsBox);
  final _BackgroundBox box;
  final double top;
  final bool startsBox;
  bool closed = false;
  double? bottom;
}
