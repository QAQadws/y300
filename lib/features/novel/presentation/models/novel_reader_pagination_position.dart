import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

@immutable
class NovelReaderPaginationPosition {
  const NovelReaderPaginationPosition({
    required this.episodeId,
    required this.paginationKey,
    required this.pageIndex,
    required this.pageCount,
    required this.anchor,
  });

  final String episodeId;
  final String paginationKey;
  final int pageIndex;
  final int pageCount;
  final NovelReaderTextAnchor anchor;
}
