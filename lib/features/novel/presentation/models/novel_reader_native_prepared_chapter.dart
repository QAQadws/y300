import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import 'novel_reader_native_anchor_map.dart';

/// Pure preparation results may cross isolates. Neither variant owns a native
/// layout, reading session, cache, conversion service or persisted position.
sealed class NovelReaderNativeChapterPreparation {
  const NovelReaderNativeChapterPreparation({
    required this.episodeId,
    required this.convertedTextNodeCount,
  });
  final String episodeId;
  final int convertedTextNodeCount;
  ForumBodyIdentity get identity;
}

final class NovelReaderNativePreparedChapter
    extends NovelReaderNativeChapterPreparation {
  const NovelReaderNativePreparedChapter({
    required super.episodeId,
    required super.convertedTextNodeCount,
    required this.document,
    required this.anchors,
  });
  final ForumBodyDocument document;
  final NovelReaderNativeAnchorMap anchors;
  @override
  ForumBodyIdentity get identity => document.identity;
}

/// An actually absent display input AND empty semantic body. This is not an
/// anchor map or a synthetic page0. Fallback paragraphs without DOM origins
/// cannot take this path, even if their original HTML was empty.
final class NovelReaderNativeEmptyChapter
    extends NovelReaderNativeChapterPreparation {
  const NovelReaderNativeEmptyChapter({
    required super.episodeId,
    required super.convertedTextNodeCount,
    required this.identity,
  });
  @override
  final ForumBodyIdentity identity;
}
