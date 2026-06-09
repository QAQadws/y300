import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_download_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_reader_exit_result.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_reading_state_writer.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/presentation/comic_detail_page.dart';
import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';

void main() {
  testWidgets('ComicDetailPage renders unified detail header and chapter list', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          comicEpisodeRefreshServiceProvider.overrideWithValue(_FakeComicEpisodeRefreshService()),
          comicDownloadServiceProvider.overrideWithValue(_NoopComicDownloadService()),
          comicReadingStateWriterProvider.overrideWithValue(_NoopReadingStateWriter()),
          comicReaderServiceProvider.overrideWith((ref) async => _FakeComicReaderService()),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
        ],
        child: const MaterialApp(home: ComicDetailPage(comicId: 'comic:1')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Test Comic'), findsAtLeastNWidgets(1));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('unified-detail-chapter-comic:1:e1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-comic:1:e1')), findsOneWidget);
    expect(find.byIcon(Icons.file_download), findsAtLeastNWidgets(1));
  });

  testWidgets('ComicDetailPage can open reader from chapter row', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          comicEpisodeRefreshServiceProvider.overrideWithValue(_FakeComicEpisodeRefreshService()),
          comicDownloadServiceProvider.overrideWithValue(_NoopComicDownloadService()),
          comicReadingStateWriterProvider.overrideWithValue(_NoopReadingStateWriter()),
          comicReaderServiceProvider.overrideWith((ref) async => _FakeComicReaderService()),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
        ],
        child: const MaterialApp(home: ComicDetailPage(comicId: 'comic:1')),
      ),
    );

    await tester.pumpAndSettle();
    await _scrollFirstChapterIntoTapArea(tester);
    await tester.tap(find.text('Episode 1'));
    // Reader content can keep an animated image placeholder alive while the
    // network image is unresolved in widget tests, so wait only for the route
    // transition frames instead of waiting for the whole tree to settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('comic-reader-image-list')), findsOneWidget);
  });

  testWidgets('ComicDetailPage does not reopen reader on normal reader exit', (tester) async {
    final observer = _CountingNavigatorObserver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          comicEpisodeRefreshServiceProvider.overrideWithValue(_FakeComicEpisodeRefreshService()),
          comicDownloadServiceProvider.overrideWithValue(_NoopComicDownloadService()),
          comicReadingStateWriterProvider.overrideWithValue(_NoopReadingStateWriter()),
          comicReaderServiceProvider.overrideWith((ref) async => _FakeComicReaderService()),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
        ],
        child: MaterialApp(
          navigatorObservers: [observer],
          home: const ComicDetailPage(comicId: 'comic:1'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await _scrollFirstChapterIntoTapArea(tester);
    await tester.tap(find.text('Episode 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(observer.pushCount, 2);

    Navigator.of(tester.element(find.byKey(const Key('comic-reader-image-list')))).pop(
      const ComicReaderExitResult(
        comicId: 'comic:1',
        lastReadEpisodeId: 'comic:1:e2',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(observer.pushCount, 2);
    expect(find.byType(ComicDetailPage), findsOneWidget);
  });

  testWidgets('ComicReaderPage completion reloads detail with read chapter dimmed', (tester) async {
    final stateRepository = _MutableLibraryStateRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          comicEpisodeRefreshServiceProvider.overrideWithValue(_FakeComicEpisodeRefreshService()),
          comicDownloadServiceProvider.overrideWithValue(_NoopComicDownloadService()),
          comicReadingStateWriterProvider.overrideWithValue(
            _RecordingReadingStateWriter(stateRepository),
          ),
          comicReaderServiceProvider.overrideWith((ref) async => _FakeComicReaderService()),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
          libraryStateRepositoryProvider.overrideWithValue(stateRepository),
        ],
        child: const MaterialApp(home: ComicDetailPage(comicId: 'comic:1')),
      ),
    );

    await tester.pumpAndSettle();
    await _scrollFirstChapterIntoTapArea(tester);
    expect(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-read-badge-comic:1:e1'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Episode 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final readerElement = tester.element(find.byKey(const Key('comic-reader-image-list')));
    final readerProviderContainer = ProviderScope.containerOf(readerElement);
    const readerArgs = ComicReaderArgs(
      comicId: 'comic:1',
      episodeId: 'comic:1:e1',
    );
    await readerProviderContainer.read(comicReaderControllerProvider(readerArgs).future);
    final readerController = readerProviderContainer.read(
      comicReaderControllerProvider(readerArgs).notifier,
    );
    await readerController.onImageVisible(0);
    await readerController.onImageResolved(
      imageIndex: 0,
      imageUrl: 'https://img.test/e1-1.jpg',
      width: 900,
      height: 1600,
    );
    Navigator.of(readerElement).pop(
      const ComicReaderExitResult(
        comicId: 'comic:1',
        lastReadEpisodeId: 'comic:1:e1',
        completedEpisodeIds: <String>['comic:1:e1'],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(stateRepository.markedReadEpisodeIds, contains('comic:1:e1'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('unified-detail-chapter-comic:1:e1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-read-badge-comic:1:e1'),
      ),
      findsOneWidget,
    );
  });
}

class _CountingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

class _FakeComicReaderService implements ComicReaderService {
  @override
  Future<ComicImageCacheResult> cacheImage({
    required String imageUrl,
    String? cacheKey,
    ImageCacheOwnerType? ownerType,
    String? ownerId,
    ImageCacheRole role = ImageCacheRole.comicPage,
    String? episodeId,
    int? imageIndex,
    bool protected = false,
  }) async {
    return ComicImageCacheResult(success: true, localPath: '/cache/mock.jpg', cacheKey: cacheKey);
  }

  @override
  Future<List<String>> fetchEpisodeImagesByTid(String tid) async => const <String>[];

  @override
  Future<void> prefetchImages({required List<String> imageUrls}) async {}
}

class _NoopReadingStateWriter implements ComicReadingStateWriter {
  @override
  Future<bool> isEpisodeRead({
    required String comicId,
    required String episodeId,
  }) async {
    return false;
  }

  @override
  Future<bool> isEpisodeBookmarked({
    required String comicId,
    required String episodeId,
  }) async {
    return false;
  }

  @override
  Future<void> markEpisodeCompleted({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
    required DateTime completedAt,
  }) async {}

  @override
  Future<void> saveProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {}

  @override
  Future<void> setEpisodeBookmarked({
    required String comicId,
    required String episodeId,
    required bool isBookmarked,
  }) async {}

  @override
  Future<void> setEpisodeRead({
    required String comicId,
    required String episodeId,
    required bool isRead,
    DateTime? readAt,
  }) async {}
}

class _FakeComicEpisodeRefreshService implements ComicEpisodeRefreshService {
  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  ) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
    );
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    return const <ComicEpisodeLink>[];
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
    );
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
    );
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    return const <ComicEpisodeLink>[];
  }
}

Future<void> _scrollFirstChapterIntoTapArea(WidgetTester tester) async {
  final chapterFinder = find.byKey(
    const ValueKey<String>('unified-detail-chapter-comic:1:e1'),
  );
  await tester.scrollUntilVisible(
    chapterFinder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
  await tester.pumpAndSettle();
}

class _NoopComicDownloadService implements ComicDownloadService {
  @override
  Future<void> deleteEpisodeDownload({required String comicId, required String episodeId}) async {}

  @override
  Future<DownloadedComicEpisode> downloadEpisode({required String comicId, required String episodeId}) {
    throw UnimplementedError();
  }

  @override
  Future<List<ComicEpisodeImageItem>> getDownloadedEpisodeImages({
    required String comicId,
    required String episodeId,
  }) async {
    return const <ComicEpisodeImageItem>[];
  }
}

class _FakeImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: 'memory://${request.cacheKey}',
      fromCache: true,
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: request.sourcePath,
      fromCache: true,
    );
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<void> clearUnprotected() async {}
}

class _FakeComicRepository implements ComicRepository {
  ComicReadingProgress? _progress;

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
  Future<void> removeFromShelf({required String comicId}) async {}

  @override
  Future<void> purgeWork({required String comicId}) async {}

  @override
  Future<String> createCategory({required String name}) async => 'created';

  @override
  Future<void> clearEpisodeImageCache({required String episodeId}) async {}

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<ComicShelfCategory>> getCategories() async => const [];

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    return ComicDetail(
      comicId: comicId,
      sourceTid: '100',
      sourceFid: '30',
      sourceTypeId: '398',
      sourceTagName: '韩国漫画',
      title: 'Test Comic',
      author: 'Author A',
      translationGroup: 'Group A',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: 1,
    );
  }

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({required String comicId, bool descending = true}) async {
    return const [
      ComicEpisodeItem(
        episodeId: 'comic:1:e1',
        comicId: 'comic:1',
        sourceTid: '100',
        sourceUrl: 'thread-100-1-1.html',
        orderIndex: 0,
        episodeTitle: 'Episode 1',
        publishTimeText: '2026-01-01',
      ),
    ];
  }

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async =>
      const ComicShelfDisplaySettings(gridColumnCount: 3);

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({required String episodeId}) async {
    return const <ComicEpisodeImageItem>[
      ComicEpisodeImageItem(
        episodeId: 'comic:1:e1',
        imageUrl: 'https://img.test/e1-1.jpg',
        imageIndex: 0,
        cacheStatus: 'none',
      ),
    ];
  }

  @override
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) async => _progress;

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async => const [];

  @override
  Future<bool> isInShelf({required String comicId}) async => true;

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return const ComicEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 1);
  }

  @override
  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<void> saveEpisodeImages({required String episodeId, required List<String> imageUrls}) async {}

  @override
  Future<void> updateCustomCover({required String comicId, required String? customCoverImageUrl}) async {}
  @override
  Future<void> updateCustomCoverFromLocalFile({required String comicId, required String localCoverPath, String? sourceEpisodeId, int? sourceImageIndex, String? sourceImageUrl}) async {}
  @override
  Future<void> updateCustomMetadata({required String comicId, String? customTitle, String? customAuthor, String? customTranslationGroup, String? customSearchTitle}) async {}
  @override
  Future<void> clearCustomMetadata({required String comicId, bool title = false, bool author = false, bool translationGroup = false, bool searchTitle = false}) async {}

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
  }) async {
    _progress = ComicReadingProgress(
      comicId: comicId,
      episodeId: episodeId,
      imageIndex: imageIndex,
      scrollOffset: scrollOffset,
      updatedAt: DateTime(2026, 1, 1),
    );
  }
}

class _FakeLibraryStateRepository implements LibraryStateRepository {
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
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<void> purgeWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {}

  @override
  Future<void> setWorksReadState({
    required LibraryModuleKey moduleKey,
    required Set<String> workIds,
    required bool isRead,
    DateTime? readAt,
  }) async {}

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
  }) async {
    return null;
  }

  @override
  Future<List<LibraryTag>> getTags() async => const [];

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return null;
  }

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return const [];
  }

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return false;
  }

  @override
  Future<void> renameTag({
    required String tagId,
    required String newName,
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
  }) async {}

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

class _MutableLibraryStateRepository extends _FakeLibraryStateRepository {
  final Map<String, LibraryEpisodeState> _states = <String, LibraryEpisodeState>{};
  final Set<String> markedReadEpisodeIds = <String>{};

  @override
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async {
    return _states[episodeId];
  }

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
    final existing = _states[episodeId];
    if (isRead == true) {
      markedReadEpisodeIds.add(episodeId);
    }
    _states[episodeId] = LibraryEpisodeState(
      moduleKey: moduleKey,
      episodeId: episodeId,
      workId: workId,
      isRead: isRead ?? existing?.isRead ?? false,
      isDownloaded: isDownloaded ?? existing?.isDownloaded ?? false,
      isBookmarked: isBookmarked ?? existing?.isBookmarked ?? false,
      readAt: readAt,
      downloadedAt: downloadedAt,
    );
  }
}

class _RecordingReadingStateWriter implements ComicReadingStateWriter {
  const _RecordingReadingStateWriter(this.stateRepository);

  final _MutableLibraryStateRepository stateRepository;

  @override
  Future<bool> isEpisodeBookmarked({
    required String comicId,
    required String episodeId,
  }) async {
    return (await stateRepository.getEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: episodeId,
        ))
            ?.isBookmarked ??
        false;
  }

  @override
  Future<bool> isEpisodeRead({
    required String comicId,
    required String episodeId,
  }) async {
    return (await stateRepository.getEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: episodeId,
        ))
            ?.isRead ??
        false;
  }

  @override
  Future<void> markEpisodeCompleted({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
    required DateTime completedAt,
  }) {
    return setEpisodeRead(
      comicId: comicId,
      episodeId: episodeId,
      isRead: true,
      readAt: completedAt,
    );
  }

  @override
  Future<void> saveProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {}

  @override
  Future<void> setEpisodeBookmarked({
    required String comicId,
    required String episodeId,
    required bool isBookmarked,
  }) {
    return stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.comic,
      episodeId: episodeId,
      workId: comicId,
      isBookmarked: isBookmarked,
    );
  }

  @override
  Future<void> setEpisodeRead({
    required String comicId,
    required String episodeId,
    required bool isRead,
    DateTime? readAt,
  }) {
    return stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.comic,
      episodeId: episodeId,
      workId: comicId,
      isRead: isRead,
      readAt: isRead ? readAt ?? DateTime(2026, 1, 1) : null,
    );
  }
}
