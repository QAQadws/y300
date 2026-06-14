import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/bulk_download_use_case_impl.dart';
import 'package:y300/features/comic/data/comic_download_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';

void main() {
  test('downloads every episode once and writes downloaded state', () async {
    final repository = _FakeComicRepository(
      episodesByComicId: <String, List<ComicEpisodeItem>>{
        'comic:1': _episodes('comic:1', 2),
      },
    );
    final downloadService = _FakeComicDownloadService();
    final stateRepository = _RecordingLibraryStateRepository();
    final hub = DefaultLibraryTaskProgressHub();
    addTearDown(hub.dispose);
    final bus = LibraryShelfRefreshBus();
    addTearDown(bus.dispose);
    final capturedProgress = <LibraryShelfTaskProgress?>[];
    hub.progressFor(LibraryModuleKey.comic).addListener(() {
      capturedProgress.add(hub.progressFor(LibraryModuleKey.comic).value);
    });
    final useCase = DefaultBulkDownloadUseCase(
      comicRepository: repository,
      downloadService: downloadService,
      libraryStateRepository: stateRepository,
      taskProgressHub: hub,
      shelfRefreshBus: bus,
    );

    final result = await useCase.downloadComics(<String>{'comic:1'});

    expect(downloadService.calls, <String>[
      'comic:1/comic:1:1',
      'comic:1/comic:1:2',
    ]);
    expect(stateRepository.downloadedEpisodeIds, <String>[
      'comic:1:1',
      'comic:1:2',
    ]);
    expect(result.completedComicIds, <String>['comic:1']);
    expect(result.failedComicIds, isEmpty);
    expect(result.downloadedEpisodeCount, 2);
    expect(capturedProgress.whereType<LibraryShelfTaskProgress>(), isNotEmpty);
    expect(capturedProgress.whereType<LibraryShelfTaskProgress>().last.current, 2);
    expect(hub.progressFor(LibraryModuleKey.comic).value, isNull);
    expect(bus.signal.value?.source, LibraryMutationSource.bulkDownload);
    expect(bus.signal.value?.reason, 'comic_bulk_download_completed');
    expect(bus.signal.value?.payload['downloadedEpisodeCount'], 2);
  });

  test('downloads multiple comics in request order', () async {
    final repository = _FakeComicRepository(
      episodesByComicId: <String, List<ComicEpisodeItem>>{
        'comic:1': _episodes('comic:1', 1),
        'comic:2': _episodes('comic:2', 1),
      },
    );
    final downloadService = _FakeComicDownloadService();
    final useCase = _buildUseCase(
      repository: repository,
      downloadService: downloadService,
    );

    final result = await useCase.downloadComics(<String>{'comic:1', 'comic:2'});

    expect(downloadService.calls, <String>[
      'comic:1/comic:1:1',
      'comic:2/comic:2:1',
    ]);
    expect(result.requestedComicIds, <String>['comic:1', 'comic:2']);
    expect(result.completedComicIds, <String>['comic:1', 'comic:2']);
  });

  test('episode failure does not stop remaining downloads', () async {
    final repository = _FakeComicRepository(
      episodesByComicId: <String, List<ComicEpisodeItem>>{
        'comic:1': _episodes('comic:1', 3),
      },
    );
    final downloadService = _FakeComicDownloadService(
      failingEpisodeIds: <String>{'comic:1:2'},
    );
    final stateRepository = _RecordingLibraryStateRepository();
    final bus = LibraryShelfRefreshBus();
    addTearDown(bus.dispose);
    final useCase = _buildUseCase(
      repository: repository,
      downloadService: downloadService,
      stateRepository: stateRepository,
      shelfRefreshBus: bus,
    );

    final result = await useCase.downloadComics(<String>{'comic:1'});

    expect(downloadService.calls, <String>[
      'comic:1/comic:1:1',
      'comic:1/comic:1:2',
      'comic:1/comic:1:3',
    ]);
    expect(stateRepository.downloadedEpisodeIds, <String>[
      'comic:1:1',
      'comic:1:3',
    ]);
    expect(result.completedComicIds, isEmpty);
    expect(result.failedComicIds, <String>['comic:1']);
    expect(result.downloadedEpisodeCount, 2);
    expect(bus.signal.value?.reason, 'comic_bulk_download_partially_completed');
  });

  test('empty or fully failed comics do not emit refresh bus without success', () async {
    final repository = _FakeComicRepository(
      episodesByComicId: <String, List<ComicEpisodeItem>>{
        'comic:empty': const <ComicEpisodeItem>[],
        'comic:failed': _episodes('comic:failed', 1),
      },
    );
    final downloadService = _FakeComicDownloadService(
      failingEpisodeIds: <String>{'comic:failed:1'},
    );
    final bus = LibraryShelfRefreshBus();
    addTearDown(bus.dispose);
    final useCase = _buildUseCase(
      repository: repository,
      downloadService: downloadService,
      shelfRefreshBus: bus,
    );

    final result = await useCase.downloadComics(<String>{
      'comic:empty',
      'comic:failed',
    });

    expect(result.completedComicIds, isEmpty);
    expect(result.failedComicIds, <String>['comic:empty', 'comic:failed']);
    expect(result.downloadedEpisodeCount, 0);
    expect(bus.signal.value, isNull);
  });

  test('rejects reentrant download calls', () async {
    final gate = Completer<void>();
    final repository = _FakeComicRepository(
      episodesByComicId: <String, List<ComicEpisodeItem>>{
        'comic:1': _episodes('comic:1', 1),
      },
    );
    final downloadService = _FakeComicDownloadService(gate: gate);
    final useCase = _buildUseCase(
      repository: repository,
      downloadService: downloadService,
    );

    final first = useCase.downloadComics(<String>{'comic:1'});
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      useCase.downloadComics(<String>{'comic:1'}),
      throwsStateError,
    );

    gate.complete();
    await first;
  });
}

DefaultBulkDownloadUseCase _buildUseCase({
  required _FakeComicRepository repository,
  required _FakeComicDownloadService downloadService,
  _RecordingLibraryStateRepository? stateRepository,
  LibraryShelfRefreshBus? shelfRefreshBus,
}) {
  return DefaultBulkDownloadUseCase(
    comicRepository: repository,
    downloadService: downloadService,
    libraryStateRepository: stateRepository ?? _RecordingLibraryStateRepository(),
    taskProgressHub: DefaultLibraryTaskProgressHub(),
    shelfRefreshBus: shelfRefreshBus ?? LibraryShelfRefreshBus(),
  );
}

List<ComicEpisodeItem> _episodes(String comicId, int count) {
  return List<ComicEpisodeItem>.generate(count, (index) {
    final number = index + 1;
    return ComicEpisodeItem(
      episodeId: '$comicId:$number',
      comicId: comicId,
      episodeTitle: '第$number话',
      sourceTid: '$number',
      sourceUrl: 'thread-$number-1-1.html',
      orderIndex: index,
      publishTimeText: null,
    );
  });
}

class _FakeComicDownloadService implements ComicDownloadService {
  _FakeComicDownloadService({
    this.failingEpisodeIds = const <String>{},
    this.gate,
  });

  final Set<String> failingEpisodeIds;
  final Completer<void>? gate;
  final List<String> calls = <String>[];

  @override
  Future<void> deleteEpisodeDownload({
    required String comicId,
    required String episodeId,
  }) async {}

  @override
  Future<DownloadedComicEpisode> downloadEpisode({
    required String comicId,
    required String episodeId,
  }) async {
    calls.add('$comicId/$episodeId');
    final pendingGate = gate;
    if (pendingGate != null && !pendingGate.isCompleted) {
      await pendingGate.future;
    }
    if (failingEpisodeIds.contains(episodeId)) {
      throw StateError('download failed');
    }
    return DownloadedComicEpisode(
      workId: comicId,
      episodeId: episodeId,
      cbzPath: '/tmp/$episodeId.cbz',
      imageFiles: const <String>['001.jpg'],
    );
  }

  @override
  Future<List<ComicEpisodeImageItem>> getDownloadedEpisodeImages({
    required String comicId,
    required String episodeId,
  }) async => const <ComicEpisodeImageItem>[];
}

class _FakeComicRepository implements ComicRepository {
  _FakeComicRepository({
    required this.episodesByComicId,
  });

  final Map<String, List<ComicEpisodeItem>> episodesByComicId;

  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    String? sourceTypeId,
    String? sourceTagName,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {}

  @override
  Future<void> clearCustomMetadata({
    required String comicId,
    bool title = false,
    bool author = false,
    bool translationGroup = false,
    bool searchTitle = false,
  }) async {}

  @override
  Future<void> clearEpisodeImageCache({required String episodeId}) async {}

  @override
  Future<String> createCategory({required String name}) async => 'category';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<ComicShelfCategory>> getCategories() async => const <ComicShelfCategory>[];

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    return ComicDetail(
      comicId: comicId,
      sourceTid: comicId,
      sourceFid: '30',
      title: 'Title $comicId',
      author: null,
      coverImageUrl: null,
      translationGroup: null,
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: episodesByComicId[comicId]?.length ?? 0,
    );
  }

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
  }) async => episodesByComicId[comicId] ?? const <ComicEpisodeItem>[];

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    return const ComicShelfDisplaySettings(gridColumnCount: 3);
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({
    required String episodeId,
  }) async => const <ComicEpisodeImageItem>[];

  @override
  Future<ComicReadingProgress?> getLastReadProgress({
    required String comicId,
  }) async => null;

  @override
  Future<List<ComicShelfItem>> getShelfItems({
    String categoryId = 'default',
  }) async => const <ComicShelfItem>[];

  @override
  Future<bool> isInShelf({required String comicId}) async => true;

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return ComicEpisodeRefreshResult(
      insertedCount: episodeLinks.length,
      updatedCount: 0,
      totalCount: episodeLinks.length,
    );
  }

  @override
  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> purgeWork({required String comicId}) async {}

  @override
  Future<void> removeFromShelf({required String comicId}) async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<void> saveEpisodeImages({
    required String episodeId,
    required List<String> imageUrls,
  }) async {}

  @override
  Future<void> updateCustomCover({
    required String comicId,
    required String? customCoverImageUrl,
  }) async {}

  @override
  Future<void> updateCustomCoverFromLocalFile({
    required String comicId,
    required String localCoverPath,
    String? sourceEpisodeId,
    int? sourceImageIndex,
    String? sourceImageUrl,
  }) async {}

  @override
  Future<void> updateCustomMetadata({
    required String comicId,
    String? customTitle,
    String? customAuthor,
    String? customTranslationGroup,
    String? customSearchTitle,
  }) async {}

  @override
  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  }) async {}

  @override
  Future<void> updateGridColumnCount({required int columnCount}) async {}

  @override
  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {}

  @override
  Future<void> updateCatalogUrl({required String comicId, required String catalogUrl}) async {}

  @override
  Future<Set<String>> getKnownEpisodeTids({required String comicId}) async => <String>{};
}

class _RecordingLibraryStateRepository implements LibraryStateRepository {
  final List<String> downloadedEpisodeIds = <String>[];

  @override
  Future<void> bindTagToWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<int> countDownloadedEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => 0;

  @override
  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => 0;

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => 0;

  @override
  Future<String> createTag({required String name}) async => 'tag-1';

  @override
  Future<void> deleteTag({required String tagId}) async {}

  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
  }) async {
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: defaultDisplayMode,
      gridColumns: 3,
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async => null;

  @override
  Future<List<LibraryTag>> getTags() async => const <LibraryTag>[];

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => null;

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => const <LibraryTag>[];

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => false;

  @override
  Future<void> purgeWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {}

  @override
  Future<void> renameTag({
    required String tagId,
    required String newName,
  }) async {}

  @override
  Future<void> setWorksReadState({
    required LibraryModuleKey moduleKey,
    required Set<String> workIds,
    required bool isRead,
    DateTime? readAt,
  }) async {}

  @override
  Future<void> unbindTagFromWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {}

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
    if (isDownloaded == true) {
      downloadedEpisodeIds.add(episodeId);
    }
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
}
