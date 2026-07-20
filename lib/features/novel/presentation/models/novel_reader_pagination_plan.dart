import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';

@immutable
class NovelReaderPaginationPlan {
  NovelReaderPaginationPlan({
    required this.key,
    required this.episodeId,
    required List<NovelReaderPageFragment> pages,
  }) : pages = List<NovelReaderPageFragment>.unmodifiable(pages);

  final NovelReaderPaginationKey key;
  final String episodeId;
  final List<NovelReaderPageFragment> pages;

  int get pageCount => pages.length;

  bool get hasOverflowFallback => pages.any((page) => page.hasOverflow);

  NovelReaderPageFragment? pageAt(int index) {
    if (index < 0 || index >= pages.length) {
      return null;
    }
    return pages[index];
  }

  int? pageIndexForAnchor(NovelReaderTextAnchor anchor) {
    if (anchor.episodeId != episodeId) {
      return null;
    }
    for (final page in pages) {
      final ranges = page.anchorRanges.isEmpty
          ? <NovelReaderPageAnchorRange>[
              NovelReaderPageAnchorRange(
                start: page.startAnchor,
                end: page.endAnchor,
              ),
            ]
          : page.anchorRanges;
      for (final range in ranges) {
        if (_contains(
          range.start,
          range.end,
          anchor,
          isLastPage: page.index == pages.length - 1,
        )) {
          return page.index;
        }
      }
    }
    return null;
  }

  bool _contains(
    NovelReaderTextAnchor start,
    NovelReaderTextAnchor end,
    NovelReaderTextAnchor target, {
    required bool isLastPage,
  }) {
    if (start.nodeId != target.nodeId || end.nodeId != target.nodeId) {
      return false;
    }
    final startOffset = start.textOffset;
    final endOffset = end.textOffset < startOffset
        ? startOffset
        : end.textOffset;
    return target.textOffset >= startOffset &&
        (target.textOffset < endOffset || isLastPage);
  }
}
