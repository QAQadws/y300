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
    this.isPageCountFinal = true,
    this.isReadOnlyCompatibilityRestore = false,
    this.hasUserNavigated = false,
    this.isBodyEndVisible = true,
    this.isWholeBodyVisible = true,
  });

  final String episodeId;
  final String paginationKey;
  final int pageIndex;
  final int pageCount;
  final NovelReaderTextAnchor anchor;
  final bool isPageCountFinal;
  final bool isReadOnlyCompatibilityRestore;
  final bool hasUserNavigated;
  final bool isBodyEndVisible;
  final bool isWholeBodyVisible;
}

@immutable
class NovelReaderPageSeekRequest {
  const NovelReaderPageSeekRequest({
    required this.requestId,
    required this.episodeId,
    required this.paginationKey,
    required this.pageIndex,
  });

  final int requestId;
  final String episodeId;
  final String paginationKey;
  final int pageIndex;
}
