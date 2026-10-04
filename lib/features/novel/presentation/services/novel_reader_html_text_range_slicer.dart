import 'package:html/dom.dart' as html_dom;
import 'package:y300/core/html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_protected_inline_node_adapter.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// Preserves the prepared safe-HTML rune slicing entry point. The core owns
/// DOM slicing; semantic anchors are projected by the atom's Host separately.
final class NovelReaderHtmlTextRangeSlicer {
  const NovelReaderHtmlTextRangeSlicer({
    ForumHtmlFragmentCodec fragmentCodec =
        const HtmlPackageForumHtmlFragmentCodec(),
  }) : _fragmentCodec = fragmentCodec;

  final ForumHtmlFragmentCodec _fragmentCodec;

  NovelReaderHtmlTextRangeSliceSession prepare(String html) {
    return NovelReaderHtmlTextRangeSliceSession._(
      HtmlTextRangeSlicer(
        fragmentParser: _ForumFragmentParser(_fragmentCodec),
        protectedInlinePredicate: _isStableProtectedInline,
      ).prepare(html),
    );
  }

  String slice({required String html, required int start, required int end}) {
    return prepare(html).slice(start: start, end: end);
  }
}

final class NovelReaderHtmlTextRangeSliceSession {
  const NovelReaderHtmlTextRangeSliceSession._(this._session);

  final HtmlTextRangeSliceSession _session;

  String slice({required int start, required int end}) =>
      _session.slice(start: start, end: end);
}

bool _isStableProtectedInline(html_dom.Element element) =>
    const DefaultNovelReaderProtectedInlineNodeAdapter()
        .assess(element)
        .isStable;

final class _ForumFragmentParser implements HtmlFragmentParser {
  const _ForumFragmentParser(this.codec);
  final ForumHtmlFragmentCodec codec;

  @override
  html_dom.DocumentFragment parse(String html) => codec.parse(html);
}
