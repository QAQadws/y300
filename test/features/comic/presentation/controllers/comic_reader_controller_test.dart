import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('controller helper APIs return episode ids by sequence', () async {
    final repository = _ReaderRepoForControllerTest();
    final episodes = await repository.getComicEpisodes(
      comicId: 'yamibo:100',
      descending: false,
    );

    expect(episodes.first.episodeId, 'yamibo:100:101');
    expect(episodes.last.episodeId, 'yamibo:100:103');
  });

  test('jumpToImageIndex prefetches around target index', () async {
    final repository = _ReaderRepoForControllerTest();
    final service = _ReaderServiceSpy();
    final container = ProviderContainer(
      overrides: [
        comicRepositoryProvider.overrideWithValue(repository),
        comicReaderServiceProvider.overrideWith((ref) async => service),
      ],
    );
    addTearDown(container.dispose);

    final args = const ComicReaderArgs(comicId: 'yamibo:100', episodeId: 'yamibo:100:101');
    await container.read(comicReaderControllerProvider(args).future);

    await container
        .read(comicReaderControllerProvider(args).notifier)
        .jumpToImageIndex(3, scrollOffset: 120);

    expect(service.prefetchedBatches, isNotEmpty);
    expect(service.prefetchedBatches.last.length, greaterThanOrEqualTo(3));
  });

  test('onScrollProgress persists with debounce', () async {
    final repository = _ReaderRepoForControllerTest();
    final service = _ReaderServiceSpy();
    final container = ProviderContainer(
      overrides: [
        comicRepositoryProvider.overrideWithValue(repository),
        comicReaderServiceProvider.overrideWith((ref) async => service),
      ],
    );
    addTearDown(container.dispose);

    final args = const ComicReaderArgs(comicId: 'yamibo:100', episodeId: 'yamibo:100:101');
    final subscription = container.listen<AsyncValue<ComicReaderViewState>>(
      comicReaderControllerProvider(args),
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(comicReaderControllerProvider(args).future);

    final notifier = container.read(comicReaderControllerProvider(args).notifier);
    await notifier.onScrollProgress(currentIndex: 1, scrollOffset: 30);
    await notifier.onScrollProgress(currentIndex: 2, scrollOffset: 60);
    await notifier.onScrollProgress(currentIndex: 3, scrollOffset: 90);

    // Allow debounce timer callback to run.
    await Future<void>.delayed(const Duration(milliseconds: 260));

    expect(repository.progressWrites, isNotEmpty);
    expect(repository.progressWrites.last.imageIndex, 3);
    expect(repository.progressWrites.last.scrollOffset, 90);
  });

  test('cacheCurrentEpisode persists local file path from cache service', () async {
    final repository = _ReaderRepoForControllerTest();
    final service = _ReaderServiceSpy();
    final container = ProviderContainer(
      overrides: [
        comicRepositoryProvider.overrideWithValue(repository),
        comicReaderServiceProvider.overrideWith((ref) async => service),
      ],
    );
    addTearDown(container.dispose);

    final args = const ComicReaderArgs(comicId: 'yamibo:100', episodeId: 'yamibo:100:101');
    await container.read(comicReaderControllerProvider(args).future);

    await container.read(comicReaderControllerProvider(args).notifier).cacheCurrentEpisode();

    expect(repository.cacheStatusWrites, isNotEmpty);
    final doneWrite = repository.cacheStatusWrites.firstWhere(
      (item) => item.cacheStatus == 'done',
    );
    expect(doneWrite.cacheLocalPath, '/cache/mock.jpg');
  });
}

class _ReaderServiceSpy implements ComicReaderService {
  final List<List<String>> prefetchedBatches = <List<String>>[];

  @override
  Future<ComicImageCacheResult> cacheImage({required String imageUrl}) async {
    return const ComicImageCacheResult(success: true, localPath: '/cache/mock.jpg');
  }

  @override
  Future<List<String>> fetchEpisodeImagesByTid(String tid) async {
    return const <String>[];
  }

  @override
  Future<void> prefetchImages({required List<String> imageUrls}) async {
    prefetchedBatches.add(imageUrls);
  }
}

class _ProgressWrite {
  const _ProgressWrite({
    required this.imageIndex,
    required this.scrollOffset,
  });

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

/// Lightweight fake to document expected episode ordering in controller tests.
class _ReaderRepoForControllerTest implements ComicRepository {
  final List<_ProgressWrite> progressWrites = <_ProgressWrite>[];
  final List<_CacheStatusWrite> cacheStatusWrites = <_CacheStatusWrite>[];

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
  Future<String> createCategory({required String name}) async => 'mock';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async => null;

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({required String comicId, bool descending = true}) async {
    final list = <ComicEpisodeItem>[
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
    ];
    list.sort((a, b) => descending ? b.orderIndex.compareTo(a.orderIndex) : a.orderIndex.compareTo(b.orderIndex));
    return list;
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({required String episodeId}) async {
    return const <ComicEpisodeImageItem>[
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
      ComicEpisodeImageItem(
        episodeId: 'yamibo:100:101',
        imageUrl: 'https://img.test/101-3.jpg',
        imageIndex: 2,
        cacheStatus: 'none',
      ),
      ComicEpisodeImageItem(
        episodeId: 'yamibo:100:101',
        imageUrl: 'https://img.test/101-4.jpg',
        imageIndex: 3,
        cacheStatus: 'none',
      ),
      ComicEpisodeImageItem(
        episodeId: 'yamibo:100:101',
        imageUrl: 'https://img.test/101-5.jpg',
        imageIndex: 4,
        cacheStatus: 'none',
      ),
    ];
  }

  @override
  Future<List<ComicShelfCategory>> getCategories() async => const <ComicShelfCategory>[];

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    return const ComicShelfDisplaySettings(gridColumnCount: 3);
  }

  @override
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) async {
    return null;
  }

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
  Future<void> saveEpisodeImages({required String episodeId, required List<String> imageUrls}) async {}

  @override
  Future<void> updateCustomCover({required String comicId, required String? customCoverImageUrl}) async {}

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
  Future<void> updateGridColumnCount({required int columnCount}) async {}

  @override
  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {
    progressWrites.add(_ProgressWrite(imageIndex: imageIndex, scrollOffset: scrollOffset));
  }
}
