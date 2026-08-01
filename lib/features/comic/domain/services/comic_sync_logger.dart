import 'dart:developer' as developer;

import 'package:y300/features/comic/domain/models/comic_parsing_debug_models.dart';

/// Unified logger for comic sync/parsing flow.
///
/// Phase 0 keeps it simple and optional: by default it logs to `dart:developer`.
/// Later phases can add file persistence without changing call sites.
class ComicSyncLogger {
  const ComicSyncLogger();

  void logParsing({
    required String tid,
    required ComicParsingDebugInfo debugInfo,
  }) {
    for (final signal in debugInfo.signals) {
      developer.log('[tid=$tid] ${signal.toString()}', name: 'ComicSyncLogger');
    }

    developer.log(
      '[tid=$tid] summary anchors=${debugInfo.totalAnchors}, episodes=${debugInfo.totalEpisodeLinks}, catalog=${debugInfo.catalogUrl ?? 'none'}',
      name: 'ComicSyncLogger',
    );
  }
}
