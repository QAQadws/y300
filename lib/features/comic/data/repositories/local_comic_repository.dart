import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_cover_store.dart';
import 'package:y300/features/comic/data/local/comic_detail_store.dart';
import 'package:y300/features/comic/data/local/comic_duplicate_merge_store.dart';
import 'package:y300/features/comic/data/local/comic_episode_store.dart';
import 'package:y300/features/comic/data/local/comic_reading_progress_store.dart';
import 'package:y300/features/comic/data/local/comic_shelf_store.dart';
import 'package:y300/features/comic/data/local/comic_snapshot_store.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_single_thread_episode_namer.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

/// SQLite-backed comic repository facade.
class LocalComicRepository
    implements
        ComicRepository,
        ComicFavoriteIngestRepository,
        ComicReadingProgressResetter,
        ComicWorkReadingStateResetter,
        ComicCatalogOverrideRepository,
        ComicShelfSnapshotRepository,
        ComicShelfStatsRepository,
        ComicCoverCacheWriter,
        ComicFirstEpisodeCoverWriter,
        ComicDuplicateMergeRepository,
        ComicEpisodeImageCacheMetadataWriter {
  LocalComicRepository(
    this._dbFuture, {
    ComicSubjectParser? subjectParser,
    ComicSingleThreadEpisodeNamer? singleThreadEpisodeNamer,
  }) : _subjectParser = subjectParser ?? const RuleBasedComicSubjectParser(),
       _singleThreadEpisodeNamer =
           singleThreadEpisodeNamer ??
           const DefaultComicSingleThreadEpisodeNamer() {
    _shelfStore = ComicShelfStore(
      _dbFuture,
      defaultCategoryId: _defaultCategoryId,
    );
    _detailStore = ComicDetailStore(_dbFuture, subjectParser: _subjectParser);
    _coverStore = ComicCoverStore(_dbFuture);
    _episodeStore = ComicEpisodeStore(
      _dbFuture,
      coverStore: _coverStore,
      subjectParser: _subjectParser,
    );
    _readingProgressStore = ComicReadingProgressStore(_dbFuture);
    _duplicateMergeStore = ComicDuplicateMergeStore(
      _dbFuture,
      coverStore: _coverStore,
    );
    _snapshotStore = ComicSnapshotStore(_dbFuture);
  }

  static const String _defaultCategoryId = 'default';

  final Future<Database> _dbFuture;
  final ComicSubjectParser _subjectParser;
  final ComicSingleThreadEpisodeNamer _singleThreadEpisodeNamer;

  late final ComicShelfStore _shelfStore;
  late final ComicDetailStore _detailStore;
  late final ComicCoverStore _coverStore;
  late final ComicEpisodeStore _episodeStore;
  late final ComicReadingProgressStore _readingProgressStore;
  late final ComicDuplicateMergeStore _duplicateMergeStore;
  late final ComicSnapshotStore _snapshotStore;

  @override
  Future<List<ComicShelfCategory>> getCategories() {
    return _shelfStore.getCategories();
  }

  @override
  Future<String> createCategory({required String name}) {
    return _shelfStore.createCategory(name: name);
  }

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) {
    return _shelfStore.renameCategory(categoryId: categoryId, newName: newName);
  }

  @override
  Future<void> deleteCategory({required String categoryId}) {
    return _shelfStore.deleteCategory(categoryId: categoryId);
  }

  @override
  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) {
    return _shelfStore.moveComicToCategory(
      comicId: comicId,
      fromCategoryId: fromCategoryId,
      toCategoryId: toCategoryId,
    );
  }

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() {
    return _shelfStore.getDisplaySettings();
  }

  @override
  Future<void> updateGridColumnCount({required int columnCount}) {
    return _shelfStore.updateGridColumnCount(columnCount: columnCount);
  }

  @override
  Future<void> updateCustomCover({
    required String comicId,
    required String? customCoverImageUrl,
  }) {
    return _detailStore.updateCustomCover(
      comicId: comicId,
      customCoverImageUrl: customCoverImageUrl,
    );
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
  }) {
    return _detailStore.updateCustomCoverFromLocalFile(
      comicId: comicId,
      localCoverPath: localCoverPath,
      sourceEpisodeId: sourceEpisodeId,
      sourceImageIndex: sourceImageIndex,
      sourceImageUrl: sourceImageUrl,
      focusX: focusX,
      focusY: focusY,
    );
  }

  @override
  Future<void> updateCustomCoverFocus({
    required String comicId,
    required double? focusX,
    required double? focusY,
  }) {
    return _detailStore.updateCustomCoverFocus(
      comicId: comicId,
      focusX: focusX,
      focusY: focusY,
    );
  }

  @override
  Future<void> updateCustomMetadata({
    required String comicId,
    String? customTitle,
    String? customAuthor,
    String? customTranslationGroup,
    String? customSearchTitle,
  }) {
    return _detailStore.updateCustomMetadata(
      comicId: comicId,
      customTitle: customTitle,
      customAuthor: customAuthor,
      customTranslationGroup: customTranslationGroup,
      customSearchTitle: customSearchTitle,
    );
  }

  @override
  Future<void> clearCustomMetadata({
    required String comicId,
    bool title = false,
    bool author = false,
    bool translationGroup = false,
    bool searchTitle = false,
  }) {
    return _detailStore.clearCustomMetadata(
      comicId: comicId,
      title: title,
      author: author,
      translationGroup: translationGroup,
      searchTitle: searchTitle,
    );
  }

  @override
  Future<void> updateCoverCache({
    required String comicId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) {
    return _coverStore.updateCoverCache(
      comicId: comicId,
      coverImageUrl: coverImageUrl,
      coverLocalPath: coverLocalPath,
      customCoverLocalPath: customCoverLocalPath,
    );
  }

  @override
  Future<bool> promoteFirstEpisodeCover({
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) {
    return _coverStore.promoteFirstEpisodeCover(
      comicId: comicId,
      episodeId: episodeId,
      imageUrl: imageUrl,
    );
  }

  @override
  Future<bool> isInShelf({required String comicId}) {
    return _shelfStore.isInShelf(comicId: comicId);
  }

  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    String? sourceTypeId,
    String? sourceTagName,
    required String title,
    required ParsedComicPost parsedPost,
  }) {
    return _addToShelf(
      comicId: comicId,
      tid: tid,
      fid: fid,
      sourceTypeId: sourceTypeId,
      sourceTagName: sourceTagName,
      title: title,
      parsedPost: parsedPost,
      addedAt: DateTime.now(),
    );
  }

  @override
  Future<void> addFavoriteToShelf({
    required String comicId,
    required String tid,
    required String fid,
    String? sourceTypeId,
    String? sourceTagName,
    required String title,
    required ParsedComicPost parsedPost,
    required DateTime favoriteAddedAt,
  }) {
    return _addToShelf(
      comicId: comicId,
      tid: tid,
      fid: fid,
      sourceTypeId: sourceTypeId,
      sourceTagName: sourceTagName,
      title: title,
      parsedPost: parsedPost,
      addedAt: favoriteAddedAt,
    );
  }

  Future<void> _addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    String? sourceTypeId,
    String? sourceTagName,
    required String title,
    required ParsedComicPost parsedPost,
    required DateTime addedAt,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await _detailStore.upsertComicFromParsedPostInTxn(
        txn,
        comicId: comicId,
        tid: tid,
        fid: fid,
        sourceTypeId: sourceTypeId,
        sourceTagName: sourceTagName,
        rawTitle: title,
        parsedPost: parsedPost,
        now: now,
      );
      await _episodeStore.upsertParsedEpisodeLinksInTxn(
        txn,
        comicId: comicId,
        fallbackSourceTid: tid,
        episodeLinks: parsedPost.episodeLinks,
      );
      // 仅在「单帖漫画」语义下种入唯一一话——即 catalog 解析未抓到任何章节
      // 链接。否则让 upsertParsedEpisodeLinksInTxn 主导章节列表，避免给纯
      // 目录贴留下永远拉不到内容的孤儿记录（sourceUrl 空、orderIndex<0）。
      if (parsedPost.episodeLinks.isEmpty) {
        await _episodeStore.seedSingleThreadEpisodeInTxn(
          txn,
          comicId: comicId,
          sourceTid: tid,
          episodeTitle: _singleThreadEpisodeNamer.resolve(
            metadata: parsedPost.subjectMetadata,
            fallbackComicTitle: title,
          ),
          imageUrls: parsedPost.imageUrls,
        );
      }
      await _shelfStore.ensureShelfItemExistsInTxn(
        txn,
        categoryId: _defaultCategoryId,
        comicId: comicId,
        addedAt: addedAt.millisecondsSinceEpoch,
      );
    });
  }

  @override
  Future<void> removeFromShelf({required String comicId}) {
    return _shelfStore.removeFromShelf(comicId: comicId);
  }

  @override
  Future<void> purgeWork({required String comicId}) async {
    final db = await _dbFuture;
    await db.delete(
      ComicLocalDb.comicsTable,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  @override
  Future<List<ComicShelfItem>> getShelfItems({
    String categoryId = _defaultCategoryId,
  }) {
    return _shelfStore.getShelfItems(categoryId: categoryId);
  }

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) {
    return _detailStore.getComicDetail(comicId: comicId);
  }

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
  }) {
    return _episodeStore.getComicEpisodes(
      comicId: comicId,
      descending: descending,
    );
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({
    required String episodeId,
  }) {
    return _episodeStore.getEpisodeImages(episodeId: episodeId);
  }

  @override
  Future<void> saveEpisodeImages({
    required String episodeId,
    required List<String> imageUrls,
  }) {
    return _episodeStore.saveEpisodeImages(
      episodeId: episodeId,
      imageUrls: imageUrls,
    );
  }

  @override
  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  }) {
    return _episodeStore.updateEpisodeImageCacheStatus(
      episodeId: episodeId,
      imageUrl: imageUrl,
      cacheStatus: cacheStatus,
      cacheLocalPath: cacheLocalPath,
    );
  }

  @override
  Future<void> clearEpisodeImageCache({required String episodeId}) {
    return _episodeStore.clearEpisodeImageCache(episodeId: episodeId);
  }

  @override
  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) {
    return _readingProgressStore.updateLastReadProgress(
      comicId: comicId,
      episodeId: episodeId,
      imageIndex: imageIndex,
      scrollOffset: scrollOffset,
    );
  }

  @override
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) {
    return _readingProgressStore.getLastReadProgress(comicId: comicId);
  }

  @override
  Future<ComicReadingProgress?> getReadingProgressForEpisode({
    required String comicId,
    required String episodeId,
  }) {
    return _readingProgressStore.getReadingProgressForEpisode(
      comicId: comicId,
      episodeId: episodeId,
    );
  }

  @override
  Future<void> clearReadingProgress({
    required String comicId,
    required String episodeId,
  }) {
    return _readingProgressStore.clearReadingProgress(
      comicId: comicId,
      episodeId: episodeId,
    );
  }

  @override
  Future<void> resetComicReadingState({required String comicId}) {
    return _readingProgressStore.resetComicReadingState(comicId: comicId);
  }

  @override
  Future<List<ComicReadingProgress>> getReadingProgresses({
    required String comicId,
  }) {
    return _readingProgressStore.getReadingProgresses(comicId: comicId);
  }

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) {
    return _episodeStore.mergeEpisodesFromLinks(
      comicId: comicId,
      episodeLinks: episodeLinks,
      fallbackSourceTid: fallbackSourceTid,
    );
  }

  @override
  Future<void> updateCatalogUrl({
    required String comicId,
    required String catalogUrl,
  }) {
    return _detailStore.updateCatalogUrl(
      comicId: comicId,
      catalogUrl: catalogUrl,
    );
  }

  @override
  Future<void> updateCustomCatalogUrl({
    required String comicId,
    required String? catalogUrl,
  }) {
    return _detailStore.updateCustomCatalogUrl(
      comicId: comicId,
      catalogUrl: catalogUrl,
    );
  }

  @override
  Future<Set<String>> getKnownEpisodeTids({required String comicId}) async {
    final episodes = await _episodeStore.getComicEpisodes(
      comicId: comicId,
      descending: false,
    );
    return episodes.map((e) => e.sourceTid).toSet();
  }

  @override
  Future<LibraryShelfSnapshot> queryShelfSnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) {
    return _snapshotStore.queryShelfSnapshot(
      filters: filters,
      sortOption: sortOption,
      keyword: keyword,
    );
  }

  @override
  Future<ComicShelfWorkStats> getShelfWorkStats({required String comicId}) {
    return _snapshotStore.getShelfWorkStats(comicId: comicId);
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
  }) {
    return _episodeStore.updateEpisodeImageCacheMetadata(
      episodeId: episodeId,
      imageUrl: imageUrl,
      stableCacheKey: stableCacheKey,
      lastSourceUrl: lastSourceUrl,
      localPath: localPath,
      width: width,
      height: height,
      bytes: bytes,
      mimeType: mimeType,
      lastAccessedAt: lastAccessedAt,
      protected: protected,
    );
  }

  @override
  Future<List<ComicDuplicateGroup>> findDuplicateGroups({String? comicId}) {
    return _duplicateMergeStore.findDuplicateGroups(comicId: comicId);
  }

  @override
  Future<ComicDuplicateMergeResult> mergeDuplicateGroup({
    required Set<String> comicIds,
  }) {
    return _duplicateMergeStore.mergeDuplicateGroup(comicIds: comicIds);
  }
}
