import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

/// A declarative request from search/bookmark UI to the active reader surface.
/// It contains no PageController or widget reference and can be replayed after
/// a pagination plan is rebuilt.
@immutable
class NovelReaderAnchorNavigationRequest {
  const NovelReaderAnchorNavigationRequest({
    required this.requestId,
    required this.anchor,
  });

  final int requestId;
  final NovelReaderTextAnchor anchor;
}
