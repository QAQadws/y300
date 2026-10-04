import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';

class NovelReaderTextAnchor {
  const NovelReaderTextAnchor({
    required this.episodeId,
    this.nodeId,
    this.textOffset = 0,
    this.pageIndex = 0,
    this.scrollOffset = 0,
    this.progressPercent = 0,
    this.formatVersion = NovelReaderAnchorFormat.legacyUnknown,
    this.textIdentity,
    this.isProgressPercentValid,
  });

  final String episodeId;
  final String? nodeId;
  final int textOffset;
  final int pageIndex;
  final double scrollOffset;
  final double progressPercent;
  final int formatVersion;
  final String? textIdentity;

  /// Null is legacy/unknown, false is unavailable, true describes this position.
  final bool? isProgressPercentValid;

  bool get hasCanonicalTextOffset =>
      NovelReaderAnchorFormat.isSupported(formatVersion, textIdentity);

  NovelReaderTextAnchor copyWith({
    String? episodeId,
    String? nodeId,
    bool clearNodeId = false,
    int? textOffset,
    int? pageIndex,
    double? scrollOffset,
    double? progressPercent,
    int? formatVersion,
    String? textIdentity,
    bool clearTextIdentity = false,
    bool? isProgressPercentValid,
    bool clearProgressPercentValidity = false,
  }) {
    return NovelReaderTextAnchor(
      episodeId: episodeId ?? this.episodeId,
      nodeId: clearNodeId ? null : (nodeId ?? this.nodeId),
      textOffset: textOffset ?? this.textOffset,
      pageIndex: pageIndex ?? this.pageIndex,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      progressPercent: progressPercent ?? this.progressPercent,
      formatVersion: formatVersion ?? this.formatVersion,
      textIdentity: clearTextIdentity
          ? null
          : (textIdentity ?? this.textIdentity),
      isProgressPercentValid: clearProgressPercentValidity
          ? null
          : (isProgressPercentValid ?? this.isProgressPercentValid),
    );
  }
}

class NovelReaderSearchResult {
  const NovelReaderSearchResult({
    required this.resultId,
    required this.keyword,
    required this.anchor,
    required this.snippet,
    required this.matchStart,
    required this.matchEnd,
    required this.nodeId,
  });

  final String resultId;
  final String keyword;
  final NovelReaderTextAnchor anchor;
  final String snippet;
  final int matchStart;
  final int matchEnd;
  final String nodeId;
}

class NovelReaderBookmark {
  const NovelReaderBookmark({
    required this.bookmarkId,
    required this.novelId,
    required this.episodeId,
    required this.anchor,
    required this.title,
    required this.snippet,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String bookmarkId;
  final String novelId;
  final String episodeId;
  final NovelReaderTextAnchor anchor;
  final String title;
  final String snippet;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
}
