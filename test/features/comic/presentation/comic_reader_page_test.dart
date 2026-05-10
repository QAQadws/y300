import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/comic/data/comic_download_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/presentation/comic_reader_page.dart';
import 'package:y300/features/comic/presentation/widgets/reader_zoomable_image.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> prepareLargeViewport(WidgetTester tester) async {
    // Keep a very tall viewport to make bottom reader controls consistently
    // hittable across different test environments and frame timings.
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('ComicReaderPage renders images and cache actions', (tester) async {
    await prepareLargeViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
          comicReaderServiceProvider.overrideWith((ref) async => _ReaderFakeService()),
          comicDownloadServiceProvider.overrideWithValue(_NoopComicDownloadService()),
        ],
        child: const MaterialApp(
          home: ComicReaderPage(comicId: 'yamibo:100', episodeId: 'yamibo:100:101'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comic-reader-image-list')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-center-tap-zone')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-top-overlay')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-bottom-overlay')), findsOneWidget);

    await tester.tap(find.byKey(const Key('comic-reader-center-tap-zone')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comic-reader-cache-episode')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-cache-unread')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-prev-episode-button')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-next-episode-button')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-mode-switch')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-progress-slider')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-current-page-label')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-total-page-label')), findsOneWidget);
  });

  testWidgets('ComicReaderPage uses paged renderer when persisted mode is ltr', (tester) async {
    await prepareLargeViewport(tester);
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'reader_pref_mode': 'ltr',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
          comicReaderServiceProvider.overrideWith((ref) async => _ReaderFakeService()),
          comicDownloadServiceProvider.overrideWithValue(_NoopComicDownloadService()),
        ],
        child: const MaterialApp(
          home: ComicReaderPage(comicId: 'yamibo:100', episodeId: 'yamibo:100:101'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comic-reader-page-view')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-image-list')), findsNothing);
  });

  testWidgets('ComicReaderPage switches from vertical to rtl mode via bottom switch', (tester) async {
    await prepareLargeViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
          comicReaderServiceProvider.overrideWith((ref) async => _ReaderFakeService()),
          comicDownloadServiceProvider.overrideWithValue(_NoopComicDownloadService()),
        ],
        child: const MaterialApp(
          home: ComicReaderPage(comicId: 'yamibo:100', episodeId: 'yamibo:100:101'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comic-reader-image-list')), findsOneWidget);

    await tester.tap(find.byKey(const Key('comic-reader-center-tap-zone')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('右到左'));
    await tester.tap(find.text('右到左'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comic-reader-page-view')), findsOneWidget);
  });

  testWidgets('ComicReaderPage updates progress labels after slider interaction', (tester) async {
    await prepareLargeViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
          comicReaderServiceProvider.overrideWith((ref) async => _ReaderFakeService()),
          comicDownloadServiceProvider.overrideWithValue(_NoopComicDownloadService()),
        ],
        child: const MaterialApp(
          home: ComicReaderPage(comicId: 'yamibo:100', episodeId: 'yamibo:100:101'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comic-reader-center-tap-zone')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comic-reader-current-page-label')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-total-page-label')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('comic-reader-progress-slider')));
    await tester.drag(
      find.byKey(const Key('comic-reader-progress-slider')),
      const Offset(300, 0),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comic-reader-current-page-label')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-total-page-label')), findsOneWidget);
  });

  testWidgets('ComicReaderPage renders zoomable image wrapper in reader content', (tester) async {
    await prepareLargeViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
          comicReaderServiceProvider.overrideWith((ref) async => _ReaderFakeService()),
          comicDownloadServiceProvider.overrideWithValue(_NoopComicDownloadService()),
        ],
        child: const MaterialApp(
          home: ComicReaderPage(comicId: 'yamibo:100', episodeId: 'yamibo:100:101'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(ReaderZoomableImage), findsWidgets);
  });

  testWidgets('ComicReaderPage reserves stable slots for vertical images', (tester) async {
    await prepareLargeViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
          comicReaderServiceProvider.overrideWith((ref) async => _ReaderFakeService()),
          comicDownloadServiceProvider.overrideWithValue(_NoopComicDownloadService()),
        ],
        child: const MaterialApp(
          home: ComicReaderPage(comicId: 'yamibo:100', episodeId: 'yamibo:100:101'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('comic-reader-image-slot-0')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('comic-reader-image-slot-1')), findsOneWidget);
    final slot = tester.widget<ConstrainedBox>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('comic-reader-image-slot-0')),
        matching: find.byType(ConstrainedBox),
      ).first,
    );
    expect(slot.constraints.minHeight, greaterThan(0));
  });

  testWidgets('ComicReaderPage keeps slider stable during jump commit', (tester) async {
    await prepareLargeViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
          comicReaderServiceProvider.overrideWith((ref) async => _ReaderFakeService()),
          comicDownloadServiceProvider.overrideWithValue(_NoopComicDownloadService()),
        ],
        child: const MaterialApp(
          home: ComicReaderPage(comicId: 'yamibo:100', episodeId: 'yamibo:100:101'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comic-reader-center-tap-zone')));
    await tester.pumpAndSettle();

    final sliderFinder = find.byKey(const Key('comic-reader-progress-slider'));
    expect(sliderFinder, findsOneWidget);

    await tester.ensureVisible(sliderFinder);
    await tester.drag(sliderFinder, const Offset(280, 0));
    await tester.pump();

    // During commit phase, slider and labels should remain stable and visible.
    expect(find.byKey(const Key('comic-reader-progress-slider')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-current-page-label')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-total-page-label')), findsOneWidget);
  });
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

class _ReaderFakeService implements ComicReaderService {
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
  Future<List<String>> fetchEpisodeImagesByTid(String tid) async {
    return const <String>[
      'https://img.test/101-1.jpg',
      'https://img.test/101-2.jpg',
    ];
  }

  @override
  Future<void> prefetchImages({required List<String> imageUrls}) async {}
}

class _ReaderFakeRepository implements ComicRepository {
  ComicReadingProgress? _progress;
  final Map<String, List<ComicEpisodeImageItem>> _episodeImages =
      <String, List<ComicEpisodeImageItem>>{
        'yamibo:100:101': const <ComicEpisodeImageItem>[
          ComicEpisodeImageItem(
            episodeId: 'yamibo:100:101',
            imageUrl: 'https://img.test/101-1.jpg',
            imageIndex: 0,
            cacheStatus: 'none',
          ),
          ComicEpisodeImageItem(
            episodeId: 'yamibo:100:101',
            imageUrl: 'https://img.test/101-2.jpg',
            imageIndex: 1,
            cacheStatus: 'none',
          ),
        ],
      };

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
  Future<String> createCategory({required String name}) async => 'mock';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async => null;

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({required String comicId, bool descending = true}) async {
    return const <ComicEpisodeItem>[
      ComicEpisodeItem(
        episodeId: 'yamibo:100:101',
        comicId: 'yamibo:100',
        episodeTitle: '第1话',
        sourceTid: '101',
        sourceUrl: 'thread-101-1-1.html',
        orderIndex: 0,
        publishTimeText: null,
      ),
    ];
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({required String episodeId}) async {
    return _episodeImages[episodeId] ?? const <ComicEpisodeImageItem>[];
  }

  @override
  Future<List<ComicShelfCategory>> getCategories() async => const <ComicShelfCategory>[];

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    return const ComicShelfDisplaySettings(gridColumnCount: 3);
  }

  @override
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) async => _progress;

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async => const <ComicShelfItem>[];

  @override
  Future<bool> isInShelf({required String comicId}) async => false;

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return const ComicEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 0);
  }

  @override
  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

  @override
  Future<void> saveEpisodeImages({required String episodeId, required List<String> imageUrls}) async {
    _episodeImages[episodeId] = imageUrls
        .asMap()
        .entries
        .map(
          (entry) => ComicEpisodeImageItem(
            episodeId: episodeId,
            imageUrl: entry.value,
            imageIndex: entry.key,
            cacheStatus: 'none',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> updateCustomCover({required String comicId, required String? customCoverImageUrl}) async {}

  @override
  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  }) async {
    final images = _episodeImages[episodeId];
    if (images == null) {
      return;
    }
    _episodeImages[episodeId] = images
        .map(
          (item) => item.imageUrl == imageUrl
              ? ComicEpisodeImageItem(
                  episodeId: item.episodeId,
                  imageUrl: item.imageUrl,
                  imageIndex: item.imageIndex,
                  cacheStatus: cacheStatus,
                  cacheLocalPath: cacheLocalPath,
                )
              : item,
        )
        .toList(growable: false);
  }

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
