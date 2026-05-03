import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_parsing_models.dart';
import 'package:y300/features/novel/domain/services/novel_episode_discovery_service.dart';

void main() {
  test('NovelEpisodeDiscoveryService builds phase0 debug snapshot', () {
    const service = NovelEpisodeDiscoveryService();
    final info = service.buildInitialDebugInfo();

    expect(info.totalAnchors, 0);
    expect(info.totalOpPosts, 0);
    expect(info.matchedChapterCandidates, 0);
    expect(info.fallbackPagesVisited, 0);
    expect(info.signals, isNotEmpty);
    expect(info.signals.first.stage, 'bootstrap');
  });

  test('NovelParsingSignal toString formats stage and message', () {
    const signal = NovelParsingSignal(stage: 'anchor', message: 'candidate found');
    expect(signal.toString(), '[anchor] candidate found');
  });
}
