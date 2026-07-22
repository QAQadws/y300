import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/comic/data/services/comic_download_service.dart';
import 'package:y300/features/comic/domain/services/comic_download_execution.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_unavailable.dart';
import 'package:y300/features/comic/domain/services/comic_episode_sequence.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_reading_state_writer.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('repository exposes the expected episode fixture order', () async {
    final repository = _ReaderRepoForControllerTest();
    final episodes = await repository.getComicEpisodes(
      comicId: 'yamibo:100',
      descending: false,
    );

    expect(episodes.first.episodeId, 'yamibo:100:101');
    expect(episodes.last.episodeId, 'yamibo:100:103');
  });

  test('opening a chapter restores that chapter progress', () async {
    final repository = _ReaderRepoForControllerTest(
      readingProgresses: <ComicReadingProgress>[
        ComicReadingProgress(
          comicId: 'yamibo:100',
          episodeId: 'yamibo:100:101',
          imageIndex: 4,
          scrollOffset: 80,
          updatedAt: DateTime(2026, 7, 15, 12),
        ),
        ComicReadingProgress(
          comicId: 'yamibo:100',
          episodeId: 'yamibo:100:102',
          imageIndex: 2,
          scrollOffset: 35,
          updatedAt: DateTime(2026, 7, 14, 12),
        ),
      ],
    );
    final service = _ReaderServiceSpy();
    final writer = _ReadingStateWriterSpy(repository);
    final container = ProviderContainer(
      overrides: [
        comicRepositoryProvider.overrideWithValue(repository),
        comicReadingStateWriterProvider.overrideWithValue(writer),
        comicReaderServiceProvider.overrideWith((ref) async => service),
        comicDownloadServiceProvider.overrideWithValue(
          _NoopComicDownloadService(),
        ),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
      ],
    );
    addTearDown(container.dispose);

    const args = ComicReaderArgs(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:102',
    );
    final state = await container.read(
      comicReaderControllerProvider(args).future,
    );

    expect(state.episodeId, 'yamibo:100:102');
    expect(state.currentImageIndex, 2);
    expect(state.lastScrollOffset, 35);
  });

  test('opening a read chapter starts at the first image', () async {
    final repository = _ReaderRepoForControllerTest(
      readingProgresses: <ComicReadingProgress>[
        ComicReadingProgress(
          comicId: 'yamibo:100',
          episodeId: 'yamibo:100:102',
          imageIndex: 4,
          scrollOffset: 180,
          updatedAt: DateTime(2026, 7, 15, 12),
        ),
      ],
    );
    final writer = _ReadingStateWriterSpy(repository)
      ..initiallyReadEpisodeIds.add('yamibo:100:102');
    final container = ProviderContainer(
      overrides: [
        comicRepositoryProvider.overrideWithValue(repository),
        comicReadingStateWriterProvider.overrideWithValue(writer),
        comicReaderServiceProvider.overrideWith(
          (ref) async => _ReaderServiceSpy(),
        ),
        comicDownloadServiceProvider.overrideWithValue(
          _NoopComicDownloadService(),
        ),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
      ],
    );
    addTearDown(container.dispose);

    const args = ComicReaderArgs(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:102',
    );
    final state = await container.read(
      comicReaderControllerProvider(args).future,
    );

    expect(state.isCurrentEpisodeRead, isTrue);
    expect(state.currentImageIndex, 0);
    expect(state.lastScrollOffset, 0);
  });

  test(
    'page visibility and jumps leave image preparation to shared engine',
    () async {
      final repository = _ReaderRepoForControllerTest(imageCount: 10);
      final service = _ReaderServiceSpy();
      final writer = _ReadingStateWriterSpy(repository);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final args = const ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      final subscription = container.listen<AsyncValue<ComicReaderViewState>>(
        comicReaderControllerProvider(args),
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final initialState = await container.read(
        comicReaderControllerProvider(args).future,
      );

      final controller = container.read(
        comicReaderControllerProvider(args).notifier,
      );
      await controller.onImageVisible(3);
      await controller.jumpToImageIndex(6, scrollOffset: 120);

      expect(service.cachedImageUrls, isEmpty);
      expect(service.fetchEpisodeImagesCalls, isEmpty);
      expect(repository.cacheStatusWrites, isEmpty);
      expect(repository.progressWrites.last.imageIndex, 6);
      expect(initialState.nextChapter?.episodeId, 'yamibo:100:102');
    },
  );

  test('onScrollProgress persists with debounce', () async {
    final repository = _ReaderRepoForControllerTest();
    final service = _ReaderServiceSpy();
    final writer = _ReadingStateWriterSpy(repository);
    final container = ProviderContainer(
      overrides: [
        comicRepositoryProvider.overrideWithValue(repository),
        comicReadingStateWriterProvider.overrideWithValue(writer),
        comicReaderServiceProvider.overrideWith((ref) async => service),
        comicDownloadServiceProvider.overrideWithValue(
          _NoopComicDownloadService(),
        ),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
      ],
    );
    addTearDown(container.dispose);

    final args = const ComicReaderArgs(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:101',
    );
    final subscription = container.listen<AsyncValue<ComicReaderViewState>>(
      comicReaderControllerProvider(args),
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(comicReaderControllerProvider(args).future);

    final notifier = container.read(
      comicReaderControllerProvider(args).notifier,
    );
    await notifier.onScrollProgress(currentIndex: 1, scrollOffset: 30);
    await notifier.onScrollProgress(currentIndex: 2, scrollOffset: 60);
    await notifier.onScrollProgress(currentIndex: 3, scrollOffset: 90);

    // Allow debounce timer callback to run.
    await Future<void>.delayed(const Duration(milliseconds: 260));

    expect(repository.progressWrites, isNotEmpty);
    expect(repository.progressWrites.last.imageIndex, 3);
    expect(repository.progressWrites.last.scrollOffset, 90);
  });

  test(
    'loadState prefers downloaded CBZ images before repository cache',
    () async {
      final repository = _ReaderRepoForControllerTest();
      final service = _ReaderServiceSpy();
      final writer = _ReadingStateWriterSpy(repository);
      final downloadService =
          _DownloadedComicServiceFake(const <ComicEpisodeImageItem>[
            ComicEpisodeImageItem(
              episodeId: 'yamibo:100:101',
              imageUrl: 'downloaded://001.jpg',
              imageIndex: 0,
              cacheStatus: 'downloaded',
              localPath: '/storage/001.jpg',
            ),
          ]);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(downloadService),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final args = const ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      final state = await container.read(
        comicReaderControllerProvider(args).future,
      );

      expect(state.images, hasLength(1));
      expect(state.images.first.localPath, '/storage/001.jpg');
      expect(service.cachedImageUrls, isEmpty);
    },
  );

  test('last page visibility marks current episode completed once', () async {
    final repository = _ReaderRepoForControllerTest();
    final service = _ReaderServiceSpy();
    final writer = _ReadingStateWriterSpy(repository);
    final container = ProviderContainer(
      overrides: [
        comicRepositoryProvider.overrideWithValue(repository),
        comicReadingStateWriterProvider.overrideWithValue(writer),
        comicReaderServiceProvider.overrideWith((ref) async => service),
        comicDownloadServiceProvider.overrideWithValue(
          _NoopComicDownloadService(),
        ),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
      ],
    );
    addTearDown(container.dispose);

    final args = const ComicReaderArgs(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:101',
    );
    await container.read(comicReaderControllerProvider(args).future);

    final notifier = container.read(
      comicReaderControllerProvider(args).notifier,
    );
    await notifier.onImageVisible(3);
    expect(writer.completedEpisodeIds, isEmpty);

    await notifier.onImageVisible(4);
    await notifier.onImageResolved(
      imageIndex: 4,
      imageUrl: 'https://img.test/101-5.jpg',
      width: 900,
      height: 1600,
    );
    await notifier.onImageVisible(4);

    expect(writer.completedEpisodeIds, <String>['yamibo:100:101']);
    expect(repository.progressWrites.last.imageIndex, 4);
  });

  test(
    'preloaded last image resolution does not complete an unseen episode',
    () async {
      final repository = _ReaderRepoForControllerTest();
      final service = _ReaderServiceSpy();
      final writer = _ReadingStateWriterSpy(repository);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      const args = ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      await container.read(comicReaderControllerProvider(args).future);

      final notifier = container.read(
        comicReaderControllerProvider(args).notifier,
      );
      await notifier.onImageResolved(
        imageIndex: 4,
        imageUrl: 'https://img.test/101-5.jpg',
        width: 900,
        height: 1600,
      );

      expect(writer.completedEpisodeIds, isEmpty);
      expect(repository.progressWrites, isEmpty);
    },
  );

  test(
    'last page visibility waits for image resolution before completion',
    () async {
      final repository = _ReaderRepoForControllerTest();
      final service = _ReaderServiceSpy();
      final writer = _ReadingStateWriterSpy(repository);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final args = const ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      await container.read(comicReaderControllerProvider(args).future);

      final notifier = container.read(
        comicReaderControllerProvider(args).notifier,
      );
      await notifier.onImageVisible(4);
      expect(writer.completedEpisodeIds, isEmpty);

      await notifier.onImageResolved(
        imageIndex: 4,
        imageUrl: 'https://img.test/101-5.jpg',
        width: 900,
        height: 1600,
      );

      expect(writer.completedEpisodeIds, <String>['yamibo:100:101']);
      expect(repository.imageMetadataWrites.last.width, 900);
      expect(repository.imageMetadataWrites.last.height, 1600);
    },
  );

  test(
    'persisted dimensions alone do not complete last page before display resolves',
    () async {
      final repository = _ReaderRepoForControllerTest(
        lastImageWidth: 900,
        lastImageHeight: 1600,
      );
      final service = _ReaderServiceSpy();
      final writer = _ReadingStateWriterSpy(repository);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final args = const ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      await container.read(comicReaderControllerProvider(args).future);

      final notifier = container.read(
        comicReaderControllerProvider(args).notifier,
      );
      await notifier.onImageVisible(4);

      expect(writer.completedEpisodeIds, isEmpty);

      await notifier.onImageResolved(
        imageIndex: 4,
        imageUrl: 'https://img.test/101-5.jpg',
        width: 900,
        height: 1600,
      );

      expect(writer.completedEpisodeIds, <String>['yamibo:100:101']);
    },
  );

  test(
    'stale image resolution callback is ignored when url no longer matches slot',
    () async {
      final repository = _ReaderRepoForControllerTest();
      final service = _ReaderServiceSpy();
      final writer = _ReadingStateWriterSpy(repository);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final args = const ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      await container.read(comicReaderControllerProvider(args).future);

      final notifier = container.read(
        comicReaderControllerProvider(args).notifier,
      );
      await notifier.onImageVisible(4);
      await notifier.onImageResolved(
        imageIndex: 4,
        imageUrl: 'https://img.test/stale.jpg',
        width: 900,
        height: 1600,
      );
      await notifier.onImageVisible(4);

      expect(writer.completedEpisodeIds, isEmpty);
      expect(repository.imageMetadataWrites, isEmpty);
    },
  );

  test(
    'display failed image writes failed status and blocks completion',
    () async {
      final repository = _ReaderRepoForControllerTest();
      final service = _ReaderServiceSpy();
      final writer = _ReadingStateWriterSpy(repository);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final args = const ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      await container.read(comicReaderControllerProvider(args).future);

      final notifier = container.read(
        comicReaderControllerProvider(args).notifier,
      );
      await notifier.onImageVisible(4);
      await notifier.onImageDisplayFailed(
        imageIndex: 4,
        imageUrl: 'https://img.test/101-5.jpg',
      );

      expect(writer.completedEpisodeIds, isEmpty);
      expect(
        repository.cacheStatusWrites,
        contains(
          isA<_CacheStatusWrite>()
              .having(
                (item) => item.imageUrl,
                'imageUrl',
                'https://img.test/101-5.jpg',
              )
              .having((item) => item.cacheStatus, 'cacheStatus', 'failed'),
        ),
      );
      final state = await container.read(
        comicReaderControllerProvider(args).future,
      );
      expect(state.failedImageCount, greaterThanOrEqualTo(1));
    },
  );

  test(
    'resolved image clears previous display failure and can complete episode',
    () async {
      final repository = _ReaderRepoForControllerTest();
      final service = _ReaderServiceSpy();
      final writer = _ReadingStateWriterSpy(repository);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final args = const ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      await container.read(comicReaderControllerProvider(args).future);

      final notifier = container.read(
        comicReaderControllerProvider(args).notifier,
      );
      await notifier.onImageVisible(4);
      await notifier.onImageDisplayFailed(
        imageIndex: 4,
        imageUrl: 'https://img.test/101-5.jpg',
      );
      await notifier.onImageResolved(
        imageIndex: 4,
        imageUrl: 'https://img.test/101-5.jpg',
        width: 900,
        height: 1600,
      );

      expect(writer.completedEpisodeIds, <String>['yamibo:100:101']);
      expect(
        repository.cacheStatusWrites,
        contains(
          isA<_CacheStatusWrite>()
              .having(
                (item) => item.imageUrl,
                'imageUrl',
                'https://img.test/101-5.jpg',
              )
              .having((item) => item.cacheStatus, 'cacheStatus', 'none'),
        ),
      );
      final state = await container.read(
        comicReaderControllerProvider(args).future,
      );
      expect(state.failedImageCount, 0);
    },
  );

  test(
    'single page chapter completes only after image becomes visible',
    () async {
      final repository = _ReaderRepoForControllerTest(singlePage: true);
      final service = _ReaderServiceSpy();
      final writer = _ReadingStateWriterSpy(repository);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final args = const ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      await container.read(comicReaderControllerProvider(args).future);
      expect(writer.completedEpisodeIds, isEmpty);

      final notifier = container.read(
        comicReaderControllerProvider(args).notifier,
      );
      await notifier.onImageVisible(0);
      await notifier.onImageResolved(
        imageIndex: 0,
        imageUrl: 'https://img.test/101-1.jpg',
        width: 900,
        height: 1600,
      );

      expect(writer.completedEpisodeIds, <String>['yamibo:100:101']);
    },
  );

  test(
    'strict complete flag disabled allows last visible page without decode gate',
    () async {
      final repository = _ReaderRepoForControllerTest();
      final service = _ReaderServiceSpy();
      final writer = _ReadingStateWriterSpy(repository);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderFeatureFlagsProvider.overrideWithValue(
            ComicReaderFeatureFlags.defaults.copyWith(
              readerStrictCompleteRead: false,
            ),
          ),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final args = const ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      await container.read(comicReaderControllerProvider(args).future);

      await container
          .read(comicReaderControllerProvider(args).notifier)
          .onImageVisible(4);

      expect(writer.completedEpisodeIds, <String>['yamibo:100:101']);
    },
  );

  test('toggleBookmark persists bookmark state', () async {
    final repository = _ReaderRepoForControllerTest();
    final service = _ReaderServiceSpy();
    final writer = _ReadingStateWriterSpy(repository);
    final container = ProviderContainer(
      overrides: [
        comicRepositoryProvider.overrideWithValue(repository),
        comicReadingStateWriterProvider.overrideWithValue(writer),
        comicReaderServiceProvider.overrideWith((ref) async => service),
        comicDownloadServiceProvider.overrideWithValue(
          _NoopComicDownloadService(),
        ),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
      ],
    );
    addTearDown(container.dispose);

    final args = const ComicReaderArgs(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:101',
    );
    await container.read(comicReaderControllerProvider(args).future);

    final message = await container
        .read(comicReaderControllerProvider(args).notifier)
        .toggleBookmark();

    final state = container.read(comicReaderControllerProvider(args)).value!;
    expect(state.isBookmarked, isTrue);
    expect(writer.bookmarkedEpisodeIds, contains('yamibo:100:101'));
    expect(message, '已添加书签');
  });

  test('setCurrentEpisodeRead updates current chapter state', () async {
    final repository = _ReaderRepoForControllerTest();
    final service = _ReaderServiceSpy();
    final writer = _ReadingStateWriterSpy(repository);
    final container = ProviderContainer(
      overrides: [
        comicRepositoryProvider.overrideWithValue(repository),
        comicReadingStateWriterProvider.overrideWithValue(writer),
        comicReaderServiceProvider.overrideWith((ref) async => service),
        comicDownloadServiceProvider.overrideWithValue(
          _NoopComicDownloadService(),
        ),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
      ],
    );
    addTearDown(container.dispose);

    final args = const ComicReaderArgs(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:101',
    );
    await container.read(comicReaderControllerProvider(args).future);

    final message = await container
        .read(comicReaderControllerProvider(args).notifier)
        .setCurrentEpisodeRead(true);

    final state = container.read(comicReaderControllerProvider(args)).value!;
    expect(state.isCurrentEpisodeRead, isTrue);
    expect(state.chapters.first.isRead, isTrue);
    expect(message, '本章已标记为已读');
  });

  test(
    'setCurrentImageAsCover copies current page into protected cover cache',
    () async {
      final repository = _ReaderRepoForControllerTest();
      final service = _ReaderServiceSpy();
      final writer = _ReadingStateWriterSpy(repository);
      final imageCache = _FakeImageCacheService();
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(imageCache),
        ],
      );
      addTearDown(container.dispose);

      final args = const ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      await container.read(comicReaderControllerProvider(args).future);

      final message = await container
          .read(comicReaderControllerProvider(args).notifier)
          .setCurrentImageAsCover();

      expect(imageCache.lastLocalCopyRequest?.role, ImageCacheRole.customCover);
      expect(repository.lastCustomCoverLocalPath, '/protected/cover.jpg');
      expect(message, '封面已更新');
    },
  );

  test(
    'openEpisode switches reader state without rebuilding provider args',
    () async {
      final repository = _ReaderRepoForControllerTest();
      final service = _ReaderServiceSpy();
      final writer = _ReadingStateWriterSpy(repository);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final args = const ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      final subscription = container.listen<AsyncValue<ComicReaderViewState>>(
        comicReaderControllerProvider(args),
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(comicReaderControllerProvider(args).future);

      final switched = await container
          .read(comicReaderControllerProvider(args).notifier)
          .openEpisode(episodeId: 'yamibo:100:102');

      final state = container.read(comicReaderControllerProvider(args)).value!;
      expect(switched, isTrue);
      expect(state.episodeId, 'yamibo:100:102');
      expect(state.episodeTitle, '第2话');
      expect(state.images.first.imageUrl, 'https://img.test/102-1.jpg');
      expect(
        state.chapters
            .singleWhere((chapter) => chapter.episodeId == 'yamibo:100:102')
            .isCurrent,
        isTrue,
      );
      expect(state.hint, isNull);
    },
  );

  test('reader navigation uses numeric source tid order', () async {
    final repository = _ReaderRepoForControllerTest(
      episodes: const <ComicEpisodeItem>[
        ComicEpisodeItem(
          episodeId: 'yamibo:100:120',
          comicId: 'yamibo:100',
          episodeTitle: '第120话',
          sourceTid: '120',
          sourceUrl: 'thread-120-1-1.html',
          orderIndex: 0,
          publishTimeText: null,
        ),
        ComicEpisodeItem(
          episodeId: 'yamibo:100:90',
          comicId: 'yamibo:100',
          episodeTitle: '第90话',
          sourceTid: '90',
          sourceUrl: 'thread-90-1-1.html',
          orderIndex: 1,
          publishTimeText: null,
        ),
        ComicEpisodeItem(
          episodeId: 'yamibo:100:105',
          comicId: 'yamibo:100',
          episodeTitle: '第105话',
          sourceTid: '105',
          sourceUrl: 'thread-105-1-1.html',
          orderIndex: 2,
          publishTimeText: null,
        ),
      ],
    );
    final writer = _ReadingStateWriterSpy(repository);
    final container = ProviderContainer(
      overrides: [
        comicRepositoryProvider.overrideWithValue(repository),
        comicReadingStateWriterProvider.overrideWithValue(writer),
        comicReaderServiceProvider.overrideWith(
          (ref) async => _ReaderServiceSpy(),
        ),
        comicDownloadServiceProvider.overrideWithValue(
          _NoopComicDownloadService(),
        ),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
      ],
    );
    addTearDown(container.dispose);

    const args = ComicReaderArgs(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:90',
    );
    final state = await container.read(
      comicReaderControllerProvider(args).future,
    );
    final controller = container.read(
      comicReaderControllerProvider(args).notifier,
    );

    expect(state.chapters.map((chapter) => chapter.sourceTid), <String>[
      '90',
      '105',
      '120',
    ]);
    expect(state.nextChapter?.sourceTid, '105');
    expect(
      await controller.openAdjacentEpisode(
        sourceEpisodeId: 'yamibo:100:90',
        direction: ComicEpisodeDirection.previous,
      ),
      isFalse,
    );
    expect(
      await controller.openAdjacentEpisode(
        sourceEpisodeId: 'yamibo:100:90',
        direction: ComicEpisodeDirection.next,
      ),
      isTrue,
    );
    expect(
      container.read(comicReaderControllerProvider(args)).value?.episodeId,
      'yamibo:100:105',
    );

    expect(await controller.openEpisode(episodeId: 'yamibo:100:120'), isTrue);
    expect(
      container.read(comicReaderControllerProvider(args)).value?.hint,
      isNull,
    );
  });

  test(
    'comment tail opens the validated TID successor at its first image',
    () async {
      final repository = _ReaderRepoForControllerTest(
        episodes: const <ComicEpisodeItem>[
          ComicEpisodeItem(
            episodeId: 'yamibo:100:120',
            comicId: 'yamibo:100',
            episodeTitle: '第120话',
            sourceTid: '120',
            sourceUrl: 'thread-120-1-1.html',
            orderIndex: 0,
            publishTimeText: null,
          ),
          ComicEpisodeItem(
            episodeId: 'yamibo:100:90',
            comicId: 'yamibo:100',
            episodeTitle: '第90话',
            sourceTid: '90',
            sourceUrl: 'thread-90-1-1.html',
            orderIndex: 1,
            publishTimeText: null,
          ),
          ComicEpisodeItem(
            episodeId: 'yamibo:100:105',
            comicId: 'yamibo:100',
            episodeTitle: '第105话',
            sourceTid: '105',
            sourceUrl: 'thread-105-1-1.html',
            orderIndex: 2,
            publishTimeText: null,
          ),
        ],
        readingProgresses: <ComicReadingProgress>[
          ComicReadingProgress(
            comicId: 'yamibo:100',
            episodeId: 'yamibo:100:105',
            imageIndex: 3,
            scrollOffset: 240,
            updatedAt: DateTime(2026, 7, 20),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(
            _ReadingStateWriterSpy(repository),
          ),
          comicReaderServiceProvider.overrideWith(
            (ref) async => _ReaderServiceSpy(),
          ),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      const args = ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:90',
      );
      await container.read(comicReaderControllerProvider(args).future);
      final controller = container.read(
        comicReaderControllerProvider(args).notifier,
      );

      expect(
        await controller.openAdjacentEpisode(
          sourceEpisodeId: 'yamibo:100:90',
          direction: ComicEpisodeDirection.next,
        ),
        isTrue,
      );

      final state = container.read(comicReaderControllerProvider(args)).value!;
      expect(state.episodeId, 'yamibo:100:105');
      expect(state.currentImageIndex, 0);
      expect(state.lastScrollOffset, 0);

      // A late callback from the old chapter cannot navigate again after the
      // controller has committed the new owner.
      expect(
        await controller.openAdjacentEpisode(
          sourceEpisodeId: 'yamibo:100:90',
          direction: ComicEpisodeDirection.next,
        ),
        isFalse,
      );
    },
  );

  test(
    'stale reader progress callbacks cannot update the new episode',
    () async {
      final repository = _ReaderRepoForControllerTest(
        episodes: const <ComicEpisodeItem>[
          ComicEpisodeItem(
            episodeId: 'yamibo:100:90',
            comicId: 'yamibo:100',
            episodeTitle: '第90话',
            sourceTid: '90',
            sourceUrl: 'thread-90-1-1.html',
            orderIndex: 0,
            publishTimeText: null,
          ),
          ComicEpisodeItem(
            episodeId: 'yamibo:100:105',
            comicId: 'yamibo:100',
            episodeTitle: '第105话',
            sourceTid: '105',
            sourceUrl: 'thread-105-1-1.html',
            orderIndex: 1,
            publishTimeText: null,
          ),
        ],
      );
      final writer = _ReadingStateWriterSpy(repository);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith(
            (ref) async => _ReaderServiceSpy(),
          ),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      const args = ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:90',
      );
      await container.read(comicReaderControllerProvider(args).future);
      final controller = container.read(
        comicReaderControllerProvider(args).notifier,
      );

      expect(await controller.openEpisode(episodeId: 'yamibo:100:105'), isTrue);
      await controller.onScrollProgress(
        currentIndex: 4,
        scrollOffset: 240,
        expectedEpisodeId: 'yamibo:100:90',
      );

      final state = container.read(comicReaderControllerProvider(args)).value!;
      expect(state.episodeId, 'yamibo:100:105');
      expect(state.currentImageIndex, 0);
      expect(repository.progressWrites, isEmpty);
    },
  );

  test(
    '_ensureEpisodeImages 在 fetch 失败时把 AsyncValue 推入 error 态而非"空列表"',
    () async {
      final repository = _ReaderRepoForControllerTest(
        emptyEpisodeIds: const <String>{'yamibo:100:101'},
      );
      final service = _ReaderServiceSpy()
        ..fetchResultBuilder = (_) => const ComicEpisodeImagesFetchFailed(
          reason: ComicEpisodeImagesFetchFailureReason.network,
          message: '模拟超时',
        );
      final writer = _ReadingStateWriterSpy(repository);
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(writer),
          comicReaderServiceProvider.overrideWith((ref) async => service),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
      );
      addTearDown(container.dispose);

      const args = ComicReaderArgs(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
      );
      final subscription = container.listen<AsyncValue<ComicReaderViewState>>(
        comicReaderControllerProvider(args),
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      // 等待 AsyncValue 落定为 error；不要直接 await `.future`——
      // 那条路径在某些 riverpod 版本上对 build() 的 throw 不会立即 reject。
      await _waitForCondition(
        () => container.read(comicReaderControllerProvider(args)).hasError,
        label: 'reader controller surfaces fetch failure as AsyncError',
      );

      final asyncValue = container.read(comicReaderControllerProvider(args));
      final error = asyncValue.error;
      expect(error, isA<ComicEpisodeImagesUnavailable>());
      final unavailable = error as ComicEpisodeImagesUnavailable;
      expect(unavailable.reason, ComicEpisodeImagesFetchFailureReason.network);
      expect(unavailable.isRetryable, isTrue);
      expect(unavailable.message, '模拟超时');

      // 失败也得有源头记录，避免静默吞错。
      expect(service.fetchEpisodeImagesCalls, <String>['101']);
      // DB 没有写入，且不会留下脏数据。
      expect(repository.savedImageUrlsByEpisode, isEmpty);
    },
  );

  test('_ensureEpisodeImages 拉取成功时把图片落库且 AsyncData 携带新图', () async {
    const fetchedUrls = <String>[
      'https://img.test/101-network-1.jpg',
      'https://img.test/101-network-2.jpg',
    ];
    final repository = _ReaderRepoForControllerTest(
      emptyEpisodeIds: const <String>{'yamibo:100:101'},
    );
    final service = _ReaderServiceSpy()
      ..fetchResultBuilder = (_) =>
          const ComicEpisodeImagesFetched(fetchedUrls);
    final writer = _ReadingStateWriterSpy(repository);
    final container = ProviderContainer(
      overrides: [
        comicRepositoryProvider.overrideWithValue(repository),
        comicReadingStateWriterProvider.overrideWithValue(writer),
        comicReaderServiceProvider.overrideWith((ref) async => service),
        comicDownloadServiceProvider.overrideWithValue(
          _NoopComicDownloadService(),
        ),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
      ],
    );
    addTearDown(container.dispose);

    const args = ComicReaderArgs(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:101',
    );
    final subscription = container.listen<AsyncValue<ComicReaderViewState>>(
      comicReaderControllerProvider(args),
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final viewState = await container.read(
      comicReaderControllerProvider(args).future,
    );

    expect(
      viewState.images.map((image) => image.imageUrl).toList(),
      fetchedUrls,
    );
    // 关键点：落库不能跟 controller 生命周期耦合——这是 bug 修复的核心。
    expect(repository.savedImageUrlsByEpisode['yamibo:100:101'], fetchedUrls);
  });

  test('_ensureEpisodeImages 拉取成功但首楼真无图时 AsyncData 为空列表（不进 error 态）', () async {
    final repository = _ReaderRepoForControllerTest(
      emptyEpisodeIds: const <String>{'yamibo:100:101'},
    );
    final service = _ReaderServiceSpy()
      ..fetchResultBuilder = (_) => const ComicEpisodeImagesFetched(<String>[]);
    final writer = _ReadingStateWriterSpy(repository);
    final container = ProviderContainer(
      overrides: [
        comicRepositoryProvider.overrideWithValue(repository),
        comicReadingStateWriterProvider.overrideWithValue(writer),
        comicReaderServiceProvider.overrideWith((ref) async => service),
        comicDownloadServiceProvider.overrideWithValue(
          _NoopComicDownloadService(),
        ),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
      ],
    );
    addTearDown(container.dispose);

    const args = ComicReaderArgs(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:101',
    );
    final subscription = container.listen<AsyncValue<ComicReaderViewState>>(
      comicReaderControllerProvider(args),
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final viewState = await container.read(
      comicReaderControllerProvider(args).future,
    );

    // 这是合法空态——UI 仍然走"当前章节没有可阅读图片"的提示，但不会抛错。
    expect(viewState.images, isEmpty);
    // 真空时不应该有任何持久化写入（避免污染 DB）。
    expect(repository.savedImageUrlsByEpisode, isEmpty);
  });
}

class _NoopComicDownloadService implements ComicDownloadService {
  @override
  Future<void> deleteEpisodeDownload({
    required String comicId,
    required String episodeId,
  }) async {}

  @override
  Future<DownloadedComicEpisode> downloadEpisode({
    required String comicId,
    required String episodeId,
    ComicDownloadProgressObserver? observer,
    ComicDownloadCancellationToken? cancellationToken,
  }) {
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

class _DownloadedComicServiceFake extends _NoopComicDownloadService {
  _DownloadedComicServiceFake(this.images);

  final List<ComicEpisodeImageItem> images;

  @override
  Future<List<ComicEpisodeImageItem>> getDownloadedEpisodeImages({
    required String comicId,
    required String episodeId,
  }) async {
    return images;
  }
}

class _ReaderServiceSpy implements ComicReaderService {
  final List<String> cachedImageUrls = <String>[];
  final List<List<String>> prefetchedBatches = <List<String>>[];
  final List<String> fetchEpisodeImagesCalls = <String>[];

  /// 测试可注入的拉取结果——空时默认返回 `Fetched([])`，等价于"成功但首楼无图"。
  ComicEpisodeImagesFetchResult Function(String tid)? fetchResultBuilder;

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
    cachedImageUrls.add(imageUrl);
    return ComicImageCacheResult(
      success: true,
      localPath: '/cache/mock.jpg',
      cacheKey: cacheKey,
    );
  }

  @override
  Future<ComicEpisodeImagesFetchResult> fetchEpisodeImages(String tid) async {
    fetchEpisodeImagesCalls.add(tid);
    final builder = fetchResultBuilder;
    if (builder != null) {
      return builder(tid);
    }
    return const ComicEpisodeImagesFetched(<String>[]);
  }

  @override
  // ignore: deprecated_member_use
  Future<List<String>> fetchEpisodeImagesByTid(String tid) async =>
      (await fetchEpisodeImages(tid)).imageUrlsOrEmpty;

  @override
  Future<void> prefetchImages({required List<String> imageUrls}) async {
    prefetchedBatches.add(imageUrls);
  }
}

class _FakeImageCacheService implements ImageCacheService {
  ImageCacheLocalCopyRequest? lastLocalCopyRequest;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    lastLocalCopyRequest = request;
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: '/protected/cover.jpg',
    );
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: '/cache/mock.jpg',
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}
}

class _ProgressWrite {
  const _ProgressWrite({required this.imageIndex, required this.scrollOffset});

  final int imageIndex;
  final double scrollOffset;
}

class _CacheStatusWrite {
  const _CacheStatusWrite({
    required this.episodeId,
    required this.imageUrl,
    required this.cacheStatus,
    this.cacheLocalPath,
  });

  final String episodeId;
  final String imageUrl;
  final String cacheStatus;
  final String? cacheLocalPath;
}

class _ImageMetadataWrite {
  const _ImageMetadataWrite({
    required this.episodeId,
    required this.imageUrl,
    this.width,
    this.height,
  });

  final String episodeId;
  final String imageUrl;
  final int? width;
  final int? height;
}

class _ReadingStateWriterSpy implements ComicReadingStateWriter {
  _ReadingStateWriterSpy(this.repository);

  final _ReaderRepoForControllerTest repository;
  final List<String> completedEpisodeIds = <String>[];
  final Set<String> initiallyReadEpisodeIds = <String>{};
  final Set<String> bookmarkedEpisodeIds = <String>{};

  @override
  Future<bool> isEpisodeRead({
    required String comicId,
    required String episodeId,
  }) async {
    return initiallyReadEpisodeIds.contains(episodeId);
  }

  @override
  Future<bool> isEpisodeBookmarked({
    required String comicId,
    required String episodeId,
  }) async {
    return bookmarkedEpisodeIds.contains(episodeId);
  }

  @override
  Future<void> saveProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) {
    return repository.updateLastReadProgress(
      comicId: comicId,
      episodeId: episodeId,
      imageIndex: imageIndex,
      scrollOffset: scrollOffset,
    );
  }

  @override
  Future<void> markEpisodeCompleted({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
    required DateTime completedAt,
  }) async {
    completedEpisodeIds.add(episodeId);
    await saveProgress(
      comicId: comicId,
      episodeId: episodeId,
      imageIndex: imageIndex,
      scrollOffset: scrollOffset,
    );
  }

  @override
  Future<void> setEpisodeRead({
    required String comicId,
    required String episodeId,
    required bool isRead,
    DateTime? readAt,
  }) async {
    if (isRead) {
      initiallyReadEpisodeIds.add(episodeId);
    } else {
      initiallyReadEpisodeIds.remove(episodeId);
    }
  }

  @override
  Future<void> setEpisodeBookmarked({
    required String comicId,
    required String episodeId,
    required bool isBookmarked,
  }) async {
    if (isBookmarked) {
      bookmarkedEpisodeIds.add(episodeId);
    } else {
      bookmarkedEpisodeIds.remove(episodeId);
    }
  }
}

/// Lightweight fake to document expected episode ordering in controller tests.
class _ReaderRepoForControllerTest
    implements
        ComicRepository,
        ComicCoverCacheWriter,
        ComicEpisodeImageCacheMetadataWriter {
  _ReaderRepoForControllerTest({
    this.singlePage = false,
    this.lastImageWidth,
    this.lastImageHeight,
    this.imageCount = 5,
    this.emptyEpisodeIds = const <String>{},
    this.readingProgresses = const <ComicReadingProgress>[],
    this.episodes,
  });

  final bool singlePage;
  final int? lastImageWidth;
  final int? lastImageHeight;
  final int imageCount;
  final List<ComicReadingProgress> readingProgresses;
  final List<ComicEpisodeItem>? episodes;

  /// 这些 episode 在 fetch+save 之前，DB 视为空。用来模拟"首次进入未缓存"。
  final Set<String> emptyEpisodeIds;
  final List<_ProgressWrite> progressWrites = <_ProgressWrite>[];
  final List<_CacheStatusWrite> cacheStatusWrites = <_CacheStatusWrite>[];
  final List<_ImageMetadataWrite> imageMetadataWrites = <_ImageMetadataWrite>[];

  /// 追踪每个 episode 通过 [saveEpisodeImages] 持久化的 URL，做断言用。
  final Map<String, List<String>> savedImageUrlsByEpisode =
      <String, List<String>>{};
  String? lastCustomCoverLocalPath;
  double? lastCustomCoverFocusX;
  double? lastCustomCoverFocusY;

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
  Future<void> clearEpisodeImageCache({required String episodeId}) async {}

  @override
  Future<void> updateCoverCache({
    required String comicId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) async {
    lastCustomCoverLocalPath = customCoverLocalPath;
  }

  @override
  Future<void> updateCustomCoverFromLocalFile({
    required String comicId,
    required String localCoverPath,
    String? sourceEpisodeId,
    int? sourceImageIndex,
    String? sourceImageUrl,
    double? focusX,
    double? focusY,
  }) async {
    lastCustomCoverLocalPath = localCoverPath;
    lastCustomCoverFocusX = focusX;
    lastCustomCoverFocusY = focusY;
  }

  @override
  Future<void> updateCustomCoverFocus({
    required String comicId,
    required double? focusX,
    required double? focusY,
  }) async {
    lastCustomCoverFocusX = focusX;
    lastCustomCoverFocusY = focusY;
  }

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    return ComicDetail(
      comicId: comicId,
      sourceTid: '100',
      sourceFid: '30',
      title: '测试漫画',
      author: null,
      translationGroup: null,
      coverImageUrl: null,
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: 3,
    );
  }

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
  }) async {
    final list =
        <ComicEpisodeItem>[
          ...(episodes ?? const <ComicEpisodeItem>[]),
          const ComicEpisodeItem(
            episodeId: 'yamibo:100:101',
            comicId: 'yamibo:100',
            episodeTitle: '第1话',
            sourceTid: '101',
            sourceUrl: 'thread-101-1-1.html',
            orderIndex: 0,
            publishTimeText: null,
          ),
          const ComicEpisodeItem(
            episodeId: 'yamibo:100:102',
            comicId: 'yamibo:100',
            episodeTitle: '第2话',
            sourceTid: '102',
            sourceUrl: 'thread-102-1-1.html',
            orderIndex: 1,
            publishTimeText: null,
          ),
          const ComicEpisodeItem(
            episodeId: 'yamibo:100:103',
            comicId: 'yamibo:100',
            episodeTitle: '第3话',
            sourceTid: '103',
            sourceUrl: 'thread-103-1-1.html',
            orderIndex: 2,
            publishTimeText: null,
          ),
        ]..removeWhere(
          (episode) =>
              episodes != null &&
              !episodes!.any((item) => item.episodeId == episode.episodeId),
        );
    list.sort(
      (a, b) => descending
          ? b.orderIndex.compareTo(a.orderIndex)
          : a.orderIndex.compareTo(b.orderIndex),
    );
    return list;
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({
    required String episodeId,
  }) async {
    // 模拟"DB 起初无图，等 saveEpisodeImages 写入后再有图"——用来跑
    // _ensureEpisodeImages 的 fetch+save 路径。
    if (emptyEpisodeIds.contains(episodeId)) {
      final saved = savedImageUrlsByEpisode[episodeId];
      if (saved == null || saved.isEmpty) {
        return const <ComicEpisodeImageItem>[];
      }
      return List<ComicEpisodeImageItem>.generate(saved.length, (index) {
        return ComicEpisodeImageItem(
          episodeId: episodeId,
          imageUrl: saved[index],
          imageIndex: index,
          cacheStatus: 'none',
        );
      });
    }
    if (singlePage) {
      return const <ComicEpisodeImageItem>[
        ComicEpisodeImageItem(
          episodeId: 'yamibo:100:101',
          imageUrl: 'https://img.test/101-1.jpg',
          imageIndex: 0,
          cacheStatus: 'none',
        ),
      ];
    }
    final sourceTid = episodeId.split(':').last;
    return List<ComicEpisodeImageItem>.generate(imageCount, (index) {
      final page = index + 1;
      return ComicEpisodeImageItem(
        episodeId: episodeId,
        imageUrl: 'https://img.test/$sourceTid-$page.jpg',
        imageIndex: index,
        cacheStatus: 'none',
        width: index == imageCount - 1 ? lastImageWidth : null,
        height: index == imageCount - 1 ? lastImageHeight : null,
      );
    });
  }

  @override
  Future<List<ComicShelfCategory>> getCategories() async =>
      const <ComicShelfCategory>[];

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    return const ComicShelfDisplaySettings(gridColumnCount: 3);
  }

  @override
  Future<ComicReadingProgress?> getLastReadProgress({
    required String comicId,
  }) async {
    return readingProgresses.firstOrNull;
  }

  @override
  Future<ComicReadingProgress?> getReadingProgressForEpisode({
    required String comicId,
    required String episodeId,
  }) async => readingProgresses
      .where((progress) => progress.episodeId == episodeId)
      .firstOrNull;

  @override
  Future<List<ComicReadingProgress>> getReadingProgresses({
    required String comicId,
  }) async => List<ComicReadingProgress>.unmodifiable(readingProgresses);

  @override
  Future<List<ComicShelfItem>> getShelfItems({
    String categoryId = 'default',
  }) async => const <ComicShelfItem>[];

  @override
  Future<bool> isInShelf({required String comicId}) async => false;

  @override
  Future<void> purgeWork({required String comicId}) async {}

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return const ComicEpisodeRefreshResult(
      insertedCount: 0,
      updatedCount: 0,
      totalCount: 0,
    );
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
  Future<void> saveEpisodeImages({
    required String episodeId,
    required List<String> imageUrls,
  }) async {
    savedImageUrlsByEpisode[episodeId] = List<String>.unmodifiable(imageUrls);
  }

  @override
  Future<void> updateCustomCover({
    required String comicId,
    required String? customCoverImageUrl,
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
  Future<void> clearCustomMetadata({
    required String comicId,
    bool title = false,
    bool author = false,
    bool translationGroup = false,
    bool searchTitle = false,
  }) async {}

  @override
  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  }) async {
    cacheStatusWrites.add(
      _CacheStatusWrite(
        episodeId: episodeId,
        imageUrl: imageUrl,
        cacheStatus: cacheStatus,
        cacheLocalPath: cacheLocalPath,
      ),
    );
  }

  @override
  Future<void> updateEpisodeImageCacheMetadata({
    required String episodeId,
    required String imageUrl,
    String? stableCacheKey,
    String? lastSourceUrl,
    String? localPath,
    int? width,
    int? height,
    int? bytes,
    String? mimeType,
    DateTime? lastAccessedAt,
    bool? protected,
  }) async {
    imageMetadataWrites.add(
      _ImageMetadataWrite(
        episodeId: episodeId,
        imageUrl: imageUrl,
        width: width,
        height: height,
      ),
    );
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
    progressWrites.add(
      _ProgressWrite(imageIndex: imageIndex, scrollOffset: scrollOffset),
    );
  }

  @override
  Future<void> updateCatalogUrl({
    required String comicId,
    required String catalogUrl,
  }) async {}

  @override
  Future<Set<String>> getKnownEpisodeTids({required String comicId}) async =>
      <String>{};
}

Future<void> _waitForCondition(
  bool Function() isReady, {
  required String label,
  int attempts = 80,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (isReady()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for $label');
}
