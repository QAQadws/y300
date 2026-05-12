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
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_reading_state_writer.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/presentation/comic_detail_page.dart';
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
    expect(find.byIcon(Icons.file_download), findsOneWidget);
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('unified-detail-chapter-comic:1:e1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey<String>('unified-detail-chapter-comic:1:e1')));
    // Reader content can keep an animated image placeholder alive while the
    // network image is unresolved in widget tests, so wait only for the route
    // transition frames instead of waiting for the whole tree to settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('comic-reader-image-list')), findsOneWidget);
  });
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
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    return const <ComicEpisodeLink>[];
  }
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
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<void> clearUnprotected() async {}
}

class _FakeComicRepository implements ComicRepository {
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
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) async => null;

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
