import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/favorite_first_sync_request_governor.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_download_service.dart';
import 'package:y300/features/novel/data/novel_reader_cache_service.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';

void main() {
  test('cacheCurrentEpisode downloads chapter and marks downloaded', () async {
    final repository = _NovelCacheRepositoryFake();
    final downloadService = _RecordingNovelDownloadService();
    final stateRepository = _MemoryLibraryStateRepository();
    final service = _service(
      repository: repository,
      downloadService: downloadService,
      stateRepository: stateRepository,
    );

    final result = await service.cacheCurrentEpisode(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );

    expect(result.successCount, 1);
    expect(downloadService.downloadedEpisodeIds, <String>['novel:49:100:5001']);
    final state = await stateRepository.getEpisodeState(
      moduleKey: LibraryModuleKey.novel,
      episodeId: 'novel:49:100:5001',
    );
    expect(state?.isDownloaded, isTrue);
  });

  test('cacheFollowingEpisodes runs in order and keeps going after failure', () async {
    final repository = _NovelCacheRepositoryFake();
    final downloadService = _RecordingNovelDownloadService(
      failingEpisodeIds: <String>{'novel:49:100:5002'},
    );
    final stateRepository = _MemoryLibraryStateRepository();
    final progress = <String>[];
    final service = _service(
      repository: repository,
      downloadService: downloadService,
      stateRepository: stateRepository,
    );

    final result = await service.cacheFollowingEpisodes(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
      count: 5,
      onProgress: (current, total) => progress.add('$current/$total'),
    );

    expect(
      downloadService.downloadAttempts,
      <String>['novel:49:100:5002', 'novel:49:100:5003'],
    );
    expect(result.successCount, 1);
    expect(result.failureCount, 1);
    expect(result.failedEpisodeIds, <String>['novel:49:100:5002']);
    expect(progress, <String>['0/2', '1/2', '2/2']);
    expect(
      await service.getDownloadedEpisodeIds(
        novelId: 'novel:49:100',
        episodeIds: repository.episodes.map((episode) => episode.episodeId),
      ),
      <String>{'novel:49:100:5003'},
    );
  });

  test('deleteCurrentEpisodeCache deletes file and clears downloaded state', () async {
    final repository = _NovelCacheRepositoryFake();
    final downloadService = _RecordingNovelDownloadService();
    final stateRepository = _MemoryLibraryStateRepository();
    await stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.novel,
      episodeId: 'novel:49:100:5001',
      workId: 'novel:49:100',
      isDownloaded: true,
      downloadedAt: DateTime(2026, 6, 8),
    );
    final service = _service(
      repository: repository,
      downloadService: downloadService,
      stateRepository: stateRepository,
    );

    final result = await service.deleteCurrentEpisodeCache(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );

    expect(result.successCount, 1);
    expect(downloadService.deletedEpisodeIds, <String>['novel:49:100:5001']);
    final state = await stateRepository.getEpisodeState(
      moduleKey: LibraryModuleKey.novel,
      episodeId: 'novel:49:100:5001',
    );
    expect(state?.isDownloaded, isFalse);
    expect(state?.downloadedAt, isNull);
  });

  test('missing current episode returns failure and does not write state', () async {
    final repository = _NovelCacheRepositoryFake();
    final downloadService = _RecordingNovelDownloadService();
    final stateRepository = _MemoryLibraryStateRepository();
    final service = _service(
      repository: repository,
      downloadService: downloadService,
      stateRepository: stateRepository,
    );

    final result = await service.cacheCurrentEpisode(
      novelId: 'novel:49:100',
      episodeId: 'missing',
    );

    expect(result.failureCount, 1);
    expect(downloadService.downloadAttempts, isEmpty);
    expect(await stateRepository.countDownloadedEpisodes(
      moduleKey: LibraryModuleKey.novel,
      workId: 'novel:49:100',
    ), 0);
  });
}

DefaultNovelReaderCacheService _service({
  required _NovelCacheRepositoryFake repository,
  required _RecordingNovelDownloadService downloadService,
  required _MemoryLibraryStateRepository stateRepository,
}) {
  return DefaultNovelReaderCacheService(
    downloadService: downloadService,
    repository: repository,
    stateRepository: stateRepository,
  );
}

class _RecordingNovelDownloadService implements NovelDownloadService {
  _RecordingNovelDownloadService({
    this.failingEpisodeIds = const <String>{},
  });

  final Set<String> failingEpisodeIds;
  final downloadAttempts = <String>[];
  final downloadedEpisodeIds = <String>[];
  final deletedEpisodeIds = <String>[];

  @override
  Future<void> deleteChapterDownload({
    required String novelId,
    required String episodeId,
  }) async {
    deletedEpisodeIds.add(episodeId);
  }

  @override
  Future<DownloadedNovelChapter> downloadChapter({
    required String novelId,
    required String episodeId,
  }) async {
    downloadAttempts.add(episodeId);
    if (failingEpisodeIds.contains(episodeId)) {
      throw StateError('download failed');
    }
    downloadedEpisodeIds.add(episodeId);
    return DownloadedNovelChapter(
      novelId: novelId,
      episodeId: episodeId,
      chapterPath: '/tmp/$episodeId.json',
    );
  }

  @override
  Future<NovelChapterContent?> getDownloadedChapterContent({
    required String novelId,
    required String episodeId,
  }) async {
    return null;
  }
}

class _NovelCacheRepositoryFake implements NovelRepository {
  final episodes = const <NovelEpisodeItem>[
    NovelEpisodeItem(
      episodeId: 'novel:49:100:5001',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5001',
      sourcePage: 1,
      episodeTitle: '第1章',
      orderIndex: 0,
    ),
    NovelEpisodeItem(
      episodeId: 'novel:49:100:5002',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5002',
      sourcePage: 1,
      episodeTitle: '第2章',
      orderIndex: 1,
    ),
    NovelEpisodeItem(
      episodeId: 'novel:49:100:5003',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5003',
      sourcePage: 1,
      episodeTitle: '第3章',
      orderIndex: 2,
    ),
  ];

  @override
  Future<String> createCategory({required String name}) async => 'default';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return const <NovelShelfCategory>[];
  }

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async {
    return NovelChapterContent(
      episodeId: episodeId,
      rawHtml: '<p>$episodeId</p>',
      plainText: episodeId,
      paragraphs: <String>[episodeId],
    );
  }

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    return NovelItem(
      novelId: novelId,
      sourceTid: '100',
      sourceFid: '49',
      title: '测试小说',
      updatedAt: DateTime(2026, 6, 8),
      episodeCount: episodes.length,
    );
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    return descending ? episodes.reversed.toList(growable: false) : episodes;
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async {
    return NovelReaderPreferences.defaults();
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async {
    return null;
  }

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async {
    return const <NovelItem>[];
  }

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    return NovelEpisodeRefreshResult(
      insertedCount: 0,
      updatedCount: 0,
      totalCount: episodes.length,
    );
  }

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    String? anchorNodeId,
    double progressPercent = 0,
  }) async {}

  @override
  Future<void> upsertNovelBySeed({
    required NovelRefreshSeed seed,
    FavoriteSyncExecutionContext? executionContext,
  }) async {}

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {}

  @override
  Future<void> addReaderBookmark({required NovelReaderBookmark bookmark}) async {}

  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async {
    return const <NovelReaderBookmark>[];
  }

  @override
  Future<void> removeReaderBookmark({required String bookmarkId}) async {}

  @override
  Future<void> toggleEpisodeBookmark({
    required String novelId,
    required String episodeId,
    required bool isBookmarked,
  }) async {}
}

class _MemoryLibraryStateRepository implements LibraryStateRepository {
  final Map<String, LibraryEpisodeState> _episodeStates =
      <String, LibraryEpisodeState>{};

  @override
  Future<void> upsertEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
    required String workId,
    bool? isRead,
    bool? isDownloaded,
    bool? isBookmarked,
    DateTime? readAt,
    DateTime? downloadedAt,
  }) async {
    final old = _episodeStates[episodeId];
    _episodeStates[episodeId] = LibraryEpisodeState(
      moduleKey: moduleKey,
      episodeId: episodeId,
      workId: workId,
      isRead: isRead ?? old?.isRead ?? false,
      isDownloaded: isDownloaded ?? old?.isDownloaded ?? false,
      isBookmarked: isBookmarked ?? old?.isBookmarked ?? false,
      readAt: isRead == false ? null : readAt ?? old?.readAt,
      downloadedAt: isDownloaded == false
          ? null
          : downloadedAt ?? old?.downloadedAt,
    );
  }

  @override
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async {
    final state = _episodeStates[episodeId];
    return state?.moduleKey == moduleKey ? state : null;
  }

  @override
  Future<int> countDownloadedEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return _episodeStates.values
        .where(
          (state) =>
              state.moduleKey == moduleKey &&
              state.workId == workId &&
              state.isDownloaded,
        )
        .length;
  }

  @override
  Future<void> upsertWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
    String? lastReadEpisodeId,
    DateTime? lastReadAt,
    DateTime? checkUpdatedAt,
    DateTime? fetchedUpdatedAt,
    String? introText,
  }) async {}

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return null;
  }

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<void> setWorksReadState({
    required LibraryModuleKey moduleKey,
    required Set<String> workIds,
    required bool isRead,
    DateTime? readAt,
  }) async {}

  @override
  Future<void> purgeWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {}

  @override
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {}

  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
  }) async {
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: defaultDisplayMode,
      gridColumns: 3,
      updatedAt: DateTime(2026, 6, 8),
    );
  }

  @override
  Future<String> createTag({required String name}) async => 'tag';

  @override
  Future<List<LibraryTag>> getTags() async => const <LibraryTag>[];

  @override
  Future<void> renameTag({required String tagId, required String newName}) async {}

  @override
  Future<void> deleteTag({required String tagId}) async {}

  @override
  Future<void> bindTagToWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<void> unbindTagFromWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return const <LibraryTag>[];
  }

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return false;
  }
}
