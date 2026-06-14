import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_reader_cache_service.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

abstract interface class NovelReaderSupplementalHydrationService {
  Future<List<NovelReaderBookmark>> loadBookmarks({
    required String novelId,
  });

  Future<Set<String>> loadDownloadedEpisodeIds({
    required String novelId,
    required Iterable<String> episodeIds,
  });

  Future<NovelItem?> loadNovel({
    required String novelId,
  });
}

class DefaultNovelReaderSupplementalHydrationService
    implements NovelReaderSupplementalHydrationService {
  const DefaultNovelReaderSupplementalHydrationService({
    required NovelRepository repository,
    required NovelReaderCacheService cacheService,
  }) : _repository = repository,
       _cacheService = cacheService;

  final NovelRepository _repository;
  final NovelReaderCacheService _cacheService;

  @override
  Future<List<NovelReaderBookmark>> loadBookmarks({
    required String novelId,
  }) {
    return _repository.listReaderBookmarks(novelId: novelId);
  }

  @override
  Future<Set<String>> loadDownloadedEpisodeIds({
    required String novelId,
    required Iterable<String> episodeIds,
  }) {
    return _cacheService.getDownloadedEpisodeIds(
      novelId: novelId,
      episodeIds: episodeIds,
    );
  }

  @override
  Future<NovelItem?> loadNovel({
    required String novelId,
  }) async {
    try {
      return await _repository.getDetail(novelId: novelId);
    } catch (_) {
      return null;
    }
  }
}
