import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/services/novel_download_service.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/storage/data/storage_location_repository.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

void main() {
  test('downloadChapter writes meta, chapter json, and can read it back', () async {
    final temp = await io.Directory.systemTemp.createTemp('y300-novel-download-test-');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final service = DefaultNovelDownloadService(
      repository: _NovelDownloadRepositoryFake(),
      storageService: DefaultDownloadStorageService(
        locationRepository: _FakeStorageLocationRepository(temp.path),
      ),
    );

    final result = await service.downloadChapter(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );

    final chapterFile = io.File(result.chapterPath);
    expect(await chapterFile.exists(), isTrue);
    final chapter = jsonDecode(await chapterFile.readAsString()) as Map<String, Object?>;
    expect(chapter['title'], '序章');
    expect(chapter['paragraphs'], <String>['第一段。', '第二段。']);
    expect(chapter['images'], isEmpty);

    final novelDir = chapterFile.parent.parent;
    expect(await io.File(p.join(novelDir.path, '.nomedia')).exists(), isTrue);
    expect(await io.Directory(p.join(novelDir.path, 'images')).exists(), isTrue);

    final meta = jsonDecode(await io.File(p.join(novelDir.path, 'meta.json')).readAsString())
        as Map<String, Object?>;
    expect(meta['contentType'], 'novel');
    final chapters = meta['chapters'] as List<dynamic>;
    expect(chapters.single, containsPair('file', 'chapters/001-序章.json'));

    final restored = await service.getDownloadedChapterContent(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    expect(restored?.plainText, '第一段。\n第二段。');
    expect(restored?.paragraphs, <String>['第一段。', '第二段。']);
  });
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

class _NovelDownloadRepositoryFake implements NovelRepository {
  @override
  Future<String> createCategory({required String name}) async => 'default';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return <NovelShelfCategory>[
      NovelShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 5, 10),
      ),
    ];
  }

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async {
    return NovelChapterContent(
      episodeId: episodeId,
      rawHtml: '<p>第一段。</p><p>第二段。</p>',
      plainText: '第一段。\n第二段。',
      paragraphs: const <String>['第一段。', '第二段。'],
    );
  }

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    return NovelItem(
      novelId: novelId,
      sourceTid: '100',
      sourceFid: '49',
      sourceTypeId: '293',
      sourceTagName: '原创',
      title: '测试小说',
      author: '作者',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 5, 10),
      episodeCount: 1,
    );
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    return const <NovelEpisodeItem>[
      NovelEpisodeItem(
        episodeId: 'novel:49:100:5001',
        novelId: 'novel:49:100',
        sourceTid: '100',
        sourcePid: '5001',
        sourcePage: 1,
        episodeTitle: '序章',
        orderIndex: 0,
        datelineText: '2026-05-10',
      ),
    ];
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async {
    return NovelReaderPreferences.defaults();
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async => null;

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
  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
    NovelEpisodeRefreshMode mode = NovelEpisodeRefreshMode.full,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    return const NovelEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 1);
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

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
