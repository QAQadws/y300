import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

/// A declarative request from search/bookmark UI to the active reader surface.
/// It contains no PageController or widget reference. The surface scopes its
/// consumption to the reading owner and the currently live request.
@immutable
class NovelReaderAnchorNavigationRequest {
  const NovelReaderAnchorNavigationRequest({
    required this.requestId,
    required this.anchor,
  });

  final int requestId;
  final NovelReaderTextAnchor anchor;
}

/// A command result, never a reading position or permission to persist one.
enum NovelReaderNavigationOutcome { arrived, unavailable, retired }
