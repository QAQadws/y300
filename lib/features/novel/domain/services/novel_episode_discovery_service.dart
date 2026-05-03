import 'package:y300/features/novel/domain/models/novel_parsing_models.dart';

/// 章节发现服务占位实现（阶段0）。
class NovelEpisodeDiscoveryService {
  const NovelEpisodeDiscoveryService();

  NovelParsingDebugInfo buildInitialDebugInfo() {
    return const NovelParsingDebugInfo(
      totalAnchors: 0,
      totalOpPosts: 0,
      matchedChapterCandidates: 0,
      fallbackPagesVisited: 0,
      signals: <NovelParsingSignal>[
        NovelParsingSignal(stage: 'bootstrap', message: 'Novel discovery service initialized.'),
      ],
    );
  }
}
