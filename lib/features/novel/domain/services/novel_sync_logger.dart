import 'dart:developer' as developer;

import 'package:y300/features/novel/domain/models/novel_parsing_models.dart';

/// Unified logger for novel sync/parsing flow.
///
/// Phase 0 only logs structured parsing signals and summary to developer log.
/// Future phases can swap to persistent sinks without changing call sites.
class NovelSyncLogger {
  const NovelSyncLogger();

  void logParsing({
    required String tid,
    required NovelParsingDebugInfo debugInfo,
  }) {
    for (final signal in debugInfo.signals) {
      developer.log(
        '[tid=$tid] ${signal.toString()}',
        name: 'NovelSyncLogger',
      );
    }

    developer.log(
      '[tid=$tid] summary anchors=${debugInfo.totalAnchors}, opPosts=${debugInfo.totalOpPosts}, candidates=${debugInfo.matchedChapterCandidates}, fallbackPages=${debugInfo.fallbackPagesVisited}',
      name: 'NovelSyncLogger',
    );
  }
}
