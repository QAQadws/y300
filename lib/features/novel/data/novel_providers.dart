import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/data/local_novel_repository.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/data/novel_thread_gateway.dart';
import 'package:y300/features/novel/domain/services/novel_episode_discovery_service.dart';

final novelEpisodeDiscoveryServiceProvider = Provider<NovelEpisodeDiscoveryService>((ref) {
  return const NovelEpisodeDiscoveryService();
});

final novelRepositoryProvider = Provider<NovelRepository>((ref) {
  return LocalNovelRepository(
    ComicLocalDb.open(),
    threadGateway: ref.watch(novelThreadGatewayProvider),
    discoveryService: ref.watch(novelEpisodeDiscoveryServiceProvider),
    imageCacheService: ref.watch(imageCacheServiceProvider),
  );
});

final novelCoverCacheWriterProvider = Provider<NovelCoverCacheWriter?>((ref) {
  final repository = ref.watch(novelRepositoryProvider);
  return repository is NovelCoverCacheWriter
      ? repository as NovelCoverCacheWriter
      : null;
});
