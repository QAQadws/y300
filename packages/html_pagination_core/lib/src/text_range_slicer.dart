import 'package:html/dom.dart' as html_dom;

import 'dom_text_index.dart';
import 'ports.dart';

/// Uses local DOM source runes, including one newline for each inline BR.
/// Persisted or semantic offsets must be projected by the Host separately.
final class HtmlTextRangeSlicer {
  const HtmlTextRangeSlicer({
    HtmlFragmentParser fragmentParser = const DefaultHtmlFragmentParser(),
    this.protectedInlinePredicate = _notProtectedInline,
  }) : _fragmentParser = fragmentParser;

  final HtmlFragmentParser _fragmentParser;
  final HtmlProtectedInlinePredicate protectedInlinePredicate;

  HtmlTextRangeSliceSession prepare(String html) {
    return HtmlTextRangeSliceSession._(
      HtmlDomTextIndex.parse(
        html,
        fragmentParser: _fragmentParser,
        protectedInlinePredicate: protectedInlinePredicate,
      ),
    );
  }

  String slice({required String html, required int start, required int end}) =>
      prepare(html).slice(start: start, end: end);
}

final class HtmlTextRangeSliceSession {
  const HtmlTextRangeSliceSession._(this._index);

  final HtmlDomTextIndex _index;

  int get runeLength => _index.runeLength;
  int get graphemeLength => _index.graphemeLength;

  int sourceRuneAtGraphemeBoundary(int offset) =>
      _index.sourceRuneAtGraphemeBoundary(offset);

  /// Preserves the existing rune slicer's clamped upper-range behavior.
  String slice({required int start, required int end}) {
    if (start < 0 || end < start) {
      throw RangeError.range(start, 0, end, 'start');
    }
    final clampedStart = start.clamp(0, runeLength).toInt();
    final clampedEnd = end.clamp(0, runeLength).toInt();
    return _index.sliceRunes(start: clampedStart, end: clampedEnd).html;
  }

  HtmlDomTextSlice sliceRunes({required int start, required int end}) =>
      _index.sliceRunes(start: start, end: end);

  HtmlDomTextSlice sliceGraphemes({required int start, required int end}) =>
      _index.sliceGraphemes(start: start, end: end);
}

bool _notProtectedInline(html_dom.Element element) => false;
