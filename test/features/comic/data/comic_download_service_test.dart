import 'dart:io' as io;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/comic/data/comic_download_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/storage/data/storage_location_repository.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

void main() {
  test('downloadEpisode writes meta and cbz with numbered image names', () async {
    final temp = await io.Directory.systemTemp.createTemp('y300-comic-download-test-');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final image1 = io.File(p.join(temp.path, 'source-1.jpg'))..writeAsBytesSync(<int>[1, 2, 3]);
    final image2 = io.File(p.join(temp.path, 'source-2.png'))..writeAsBytesSync(<int>[4, 5, 6]);
    final repository = _ComicDownloadRepositoryFake();
    final service = DefaultComicDownloadService(
      repository: repository,
      readerServiceFuture: Future<ComicReaderService>.value(
        _ComicReaderServiceFake(<String, String>{
          'https://img.test/1.jpg': image1.path,
          'https://img.test/2.png': image2.path,
        }),
      ),
      storageService: DefaultDownloadStorageService(
        locationRepository: _FakeStorageLocationRepository(temp.path),
      ),
    );

    final result = await service.downloadEpisode(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:101',
    );

    expect(await io.File(result.cbzPath).exists(), isTrue);
    final archive = ZipDecoder().decodeBytes(await io.File(result.cbzPath).readAsBytes());
    expect(archive.files.map((file) => file.name), containsAll(<String>['001.jpg', '002.png']));

    final meta = await io.File(p.join(
      temp.path,
      'comics',
      '测试漫画-${_fnv('yamibo:100')}',
      'meta.json',
    )).readAsString();
    expect(meta, contains('"contentType": "comic"'));
    expect(meta, contains('"cbzFile": "001-第1话.cbz"'));
    expect(repository.cacheWrites.where((item) => item.cacheStatus == 'done'), hasLength(2));
  });
}

String _fnv(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0').substring(0, 8);
}

class _FakeStorageLocationRepository implements StorageLocationRepository {
  _FakeStorageLocationRepository(this.path);

  final String path;

  @override
  Future<String?> getCustomStorageRoot() async => path;
  @override
  Future<String> getDefaultStorageRoot() async => path;
  @override
  Future<String?> pickDirectory() async => path;
  @override
  Future<void> setCustomStorageRoot(String? path) async {}
}

class _ComicReaderServiceFake implements ComicReaderService {
  _ComicReaderServiceFake(this.pathsByUrl);

  final Map<String, String> pathsByUrl;

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
    return ComicImageCacheResult(
      success: true,
      localPath: pathsByUrl[imageUrl],
      cacheKey: cacheKey,
      bytes: io.File(pathsByUrl[imageUrl]!).lengthSync(),
    );
  }

  @override
  Future<ComicEpisodeImagesFetchResult> fetchEpisodeImages(String tid) async =>
      const ComicEpisodeImagesFetched(<String>[]);

  @override
  // ignore: deprecated_member_use
  Future<List<String>> fetchEpisodeImagesByTid(String tid) async =>
      (await fetchEpisodeImages(tid)).imageUrlsOrEmpty;

  @override
  Future<void> prefetchImages({required List<String> imageUrls}) async {}
}

class _CacheWrite {
  const _CacheWrite(this.cacheStatus);

  final String cacheStatus;
}

class _ComicDownloadRepositoryFake implements ComicRepository, ComicEpisodeImageCacheMetadataWriter {
  final List<_CacheWrite> cacheWrites = <_CacheWrite>[];

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    return ComicDetail(
      comicId: comicId,
      sourceTid: '100',
      sourceFid: '30',
      sourceTypeId: '398',
      sourceTagName: '韩国漫画',
      title: '测试漫画',
      author: '作者',
      translationGroup: '组',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 5, 10),
      episodeCount: 1,
    );
  }

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
    return const <ComicEpisodeImageItem>[
      ComicEpisodeImageItem(
        episodeId: 'yamibo:100:101',
        imageUrl: 'https://img.test/1.jpg',
        imageIndex: 0,
        cacheStatus: 'none',
      ),
      ComicEpisodeImageItem(
        episodeId: 'yamibo:100:101',
        imageUrl: 'https://img.test/2.png',
        imageIndex: 1,
        cacheStatus: 'none',
      ),
    ];
  }

  @override
  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  }) async {
    cacheWrites.add(_CacheWrite(cacheStatus));
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
  }) async {}

  @override
  Future<void> addToShelf({required String comicId, required String tid, required String fid, String? sourceTypeId, String? sourceTagName, required String title, required ParsedComicPost parsedPost}) async {}
  @override
  Future<void> removeFromShelf({required String comicId}) async {}

  @override
  Future<void> purgeWork({required String comicId}) async {}
  @override
  Future<String> createCategory({required String name}) async => 'c1';
  @override
  Future<void> clearEpisodeImageCache({required String episodeId}) async {}
  @override
  Future<void> deleteCategory({required String categoryId}) async {}
  @override
  Future<List<ComicShelfCategory>> getCategories() async => const <ComicShelfCategory>[];
  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async => const ComicShelfDisplaySettings(gridColumnCount: 3);
  @override
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) async => null;
  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async => const <ComicShelfItem>[];
  @override
  Future<bool> isInShelf({required String comicId}) async => true;
  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({required String comicId, required List<ComicEpisodeLink> episodeLinks, required String fallbackSourceTid}) async => const ComicEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 1);
  @override
  Future<void> moveComicToCategory({required String comicId, required String fromCategoryId, required String toCategoryId}) async {}
  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}
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
  Future<void> updateGridColumnCount({required int columnCount}) async {}
  @override
  Future<void> updateLastReadProgress({required String comicId, required String episodeId, required int imageIndex, required double scrollOffset}) async {}
  @override
  Future<void> updateCatalogUrl({required String comicId, required String catalogUrl}) async {}

  @override
  Future<Set<String>> getKnownEpisodeTids({required String comicId}) async => <String>{};
}
