import 'package:y300/features/novel/presentation/services/novel_reader_html_dom_text_index.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_fragment_codec.dart';

/// Slices prepared safe HTML by readable-text rune offsets.
///
/// Complex HTML uses the same DOM index through its grapheme-based session;
/// keeping this rune facade preserves existing TextPainter source offsets.
final class NovelReaderHtmlTextRangeSlicer {
  const NovelReaderHtmlTextRangeSlicer({
    ForumHtmlFragmentCodec fragmentCodec =
        const HtmlPackageForumHtmlFragmentCodec(),
  }) : _fragmentCodec = fragmentCodec;

  final ForumHtmlFragmentCodec _fragmentCodec;

  NovelReaderHtmlTextRangeSliceSession prepare(String html) {
    return NovelReaderHtmlTextRangeSliceSession._(
      NovelReaderHtmlDomTextIndex.parse(html, fragmentCodec: _fragmentCodec),
    );
  }

  String slice({required String html, required int start, required int end}) {
    return prepare(html).slice(start: start, end: end);
  }
}

final class NovelReaderHtmlTextRangeSliceSession {
  const NovelReaderHtmlTextRangeSliceSession._(this._index);

  final NovelReaderHtmlDomTextIndex _index;

  String slice({required int start, required int end}) {
    if (start < 0 || end < start) {
      throw RangeError.range(start, 0, end, 'start');
    }
    final clampedStart = start.clamp(0, _index.runeLength).toInt();
    final clampedEnd = end.clamp(0, _index.runeLength).toInt();
    return _index.sliceRunes(start: clampedStart, end: clampedEnd).html;
  }
}
