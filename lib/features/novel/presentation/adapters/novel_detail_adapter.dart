import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_operation_failure.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_source_id_comparator.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_asset_factory.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_update_service.dart';

/// 小说详情适配器（Phase 6）。
class NovelDetailAdapter
    implements
        DetailModuleAdapter,
        DetailFullRefreshAdapter,
        DetailMetadataEditor,
        DetailCoverEditor {
  NovelDetailAdapter(
    this._repository, {
    LibraryCoverStore? coverStore,
    required LibraryStateRepository stateRepository,
    NovelSourceStateRepository? sourceStateRepository,
    NovelChapterUpdateService Function()? chapterUpdateServiceFactory,
  }) : _coverStore = coverStore,
       _stateRepository = stateRepository,
       _sourceStateRepository = sourceStateRepository,
       _chapterUpdateServiceFactory = chapterUpdateServiceFactory;

  final NovelRepository _repository;
  final LibraryCoverStore? _coverStore;
  final LibraryStateRepository _stateRepository;
  final NovelSourceStateRepository? _sourceStateRepository;
  final NovelChapterUpdateService Function()? _chapterUpdateServiceFactory;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.novel;

  @override
  DetailMetadataEditorConfig get metadataEditorConfig =>
      const DetailMetadataEditorConfig(
        fields: <LibraryMetadataField>{LibraryMetadataField.title},
        fallbackToDisplaySourceValues: false,
      );

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    final detail = await _repository.getDetail(novelId: workId);
    if (detail == null) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.workNotFound,
      );
    }
    final workState = await _stateRepository.getWorkState(
      moduleKey: LibraryModuleKey.novel,
      workId: workId,
    );
    final sourceState = await _sourceStateRepository?.getSourceState(
      novelId: workId,
    );
    final coverImageUrl = detail.coverHidden ? null : detail.coverImageUrl;
    final coverLocalPath = detail.coverHidden ? null : detail.coverLocalPath;
    return LibraryDetailHeader(
      workId: detail.novelId,
      title: detail.displayTitle,
      coverImageUrl: coverImageUrl,
      coverLocalPath: coverLocalPath,
      customCoverLocalPath: detail.coverHidden
          ? null
          : detail.customCoverLocalPath,
      customCoverFocusX: detail.coverHidden ? null : detail.customCoverFocusX,
      customCoverFocusY: detail.coverHidden ? null : detail.customCoverFocusY,
      coverAsset: detail.coverHidden
          ? null
          : LibraryCoverAssetFactory.preferred(
              ownerType: 'novel',
              ownerId: workId,
              sourceUrl: coverImageUrl,
              sourceLegacyPath: coverLocalPath,
              sourceRevision: detail.coverRevision,
              customLegacyPath: detail.customCoverLocalPath,
              customRevision: detail.customCoverRevision,
            ),
      sourceTitle: detail.sourceTitle,
      customTitle: detail.customTitle,
      publisherName: sourceState?.publisherName ?? detail.publisherName,
      sourceTid: detail.sourceTid,
      sourceTypeId: detail.sourceTypeId,
      sourceTagName: detail.sourceTagName,
      inShelf: true,
      intro: workState?.introText ?? sourceState?.sourceIntro,
    );
  }

  @override
  Future<List<LibraryChapterItem>> loadChapters({
    required String workId,
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  }) async {
    final episodes = await _repository.getEpisodes(
      novelId: workId,
      descending: false,
    );
    final progress = await _repository.getReadingProgress(novelId: workId);

    final mapped = <LibraryChapterItem>[];
    for (final item in episodes) {
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: item.episodeId,
      );
      mapped.add(
        LibraryChapterItem(
          episodeId: item.episodeId,
          workId: item.novelId,
          title: item.episodeTitle,
          orderIndex: item.orderIndex,
          sourceTid: item.sourceTid,
          sourcePid: item.sourcePid,
          publishTimeText: item.datelineText,
          isRead: false,
          isBookmarked: state?.isBookmarked ?? false,
          progressInfo: _progressInfoForEpisode(
            episodeId: item.episodeId,
            progress: progress,
          ),
        ),
      );
    }

    final filtered = _applyFilters(mapped, filters);
    return _sortChapters(filtered, sortOption);
  }

  LibraryChapterProgressInfo? _progressInfoForEpisode({
    required String episodeId,
    required NovelReadingProgress? progress,
  }) {
    if (progress == null || progress.episodeId != episodeId) {
      return null;
    }

    final fraction = progress.progressPercent.clamp(0.0, 1.0).toDouble();
    return LibraryChapterProgressInfo(
      kind: LibraryChapterProgressKind.lastRead,
      isCurrent: true,
      fraction: fraction,
    );
  }

  @override
  Future<ReaderRouteTarget?> getReaderRouteTarget({
    required String workId,
    required bool preferContinue,
  }) async {
    final progress = await _repository.getReadingProgress(novelId: workId);
    final episodes = await _repository.getEpisodes(
      novelId: workId,
      descending: false,
    );
    if (episodes.isEmpty) {
      return null;
    }
    if (preferContinue &&
        progress != null &&
        episodes.any((episode) => episode.episodeId == progress.episodeId)) {
      return ReaderRouteTarget(workId: workId, episodeId: progress.episodeId);
    }
    return ReaderRouteTarget(
      workId: workId,
      episodeId: episodes.first.episodeId,
    );
  }

  @override
  Future<ThreadRouteTarget?> getThreadRouteTarget({
    required String workId,
  }) async {
    final detail = await _repository.getDetail(novelId: workId);
    if (detail == null) {
      return null;
    }
    return ThreadRouteTarget(tid: detail.sourceTid, subject: detail.title);
  }

  @override
  Future<void> markChapterBookmarked({
    required String workId,
    required String episodeId,
    required bool isBookmarked,
  }) async {
    await _stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.novel,
      episodeId: episodeId,
      workId: workId,
      isBookmarked: isBookmarked,
    );
  }

  @override
  Future<DetailRefreshResult> refreshWork({required String workId}) async {
    final updateServiceFactory = _chapterUpdateServiceFactory;
    if (updateServiceFactory == null) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.unsupported,
      );
    }
    final result = await updateServiceFactory().update(workId);
    return DetailRefreshResult.chaptersChanged(
      insertedCount: result.insertedCount,
      updatedCount: result.updatedCount,
    );
  }

  @override
  Future<DetailRefreshResult> refreshWorkFully({required String workId}) async {
    final updateServiceFactory = _chapterUpdateServiceFactory;
    if (updateServiceFactory == null) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.unsupported,
      );
    }
    final result = await updateServiceFactory().update(
      workId,
      intent: NovelChapterUpdateIntent.full,
    );
    return DetailRefreshResult.chaptersChanged(
      insertedCount: result.insertedCount,
      updatedCount: result.updatedCount,
    );
  }

  @override
  Future<void> updateIntro({
    required String workId,
    required String intro,
  }) async {
    await _stateRepository.upsertWorkState(
      moduleKey: LibraryModuleKey.novel,
      workId: workId,
      introText: intro,
    );
  }

  @override
  Future<void> updateCustomMetadata({
    required String workId,
    String? customTitle,
    String? customAuthor,
    String? customTranslationGroup,
    String? customSearchTitle,
  }) {
    final repository = _repository;
    if (repository is NovelCustomMetadataWriter) {
      final writer = repository as NovelCustomMetadataWriter;
      return writer.updateCustomMetadata(
        novelId: workId,
        customTitle: customTitle,
      );
    }
    throw const LibraryOperationException(
      LibraryOperationFailureCode.unsupported,
    );
  }

  @override
  Future<void> setCustomCoverFromLocalFile({
    required String workId,
    required String sourceLocalPath,
    double? focusX,
    double? focusY,
  }) async {
    final repository = _repository;
    if (repository is! NovelCustomCoverWriter) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.unsupported,
      );
    }
    final store = _coverStore;
    if (store == null || repository is! NovelCustomCoverAssetWriter) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.unsupported,
      );
    }
    final assetWriter = repository as NovelCustomCoverAssetWriter;
    final detail = await repository.getDetail(novelId: workId);
    final revision = (detail?.customCoverRevision ?? 0) + 1;
    final asset = LibraryCoverAssetRef(
      assetId: LibraryCoverAssetIds.custom(
        ownerType: 'novel',
        ownerId: workId,
      ),
      revision: revision,
      kind: LibraryCoverAssetKind.custom,
    );
    await store.installLocalFile(asset: asset, sourcePath: sourceLocalPath);
    try {
      await assetWriter.activateCustomCoverAsset(
        novelId: workId,
        revision: revision,
        focusX: focusX,
        focusY: focusY,
      );
    } catch (_) {
      await store.invalidate(asset);
      rethrow;
    }
    await store.deleteOlderRevisions(asset);
  }

  @override
  bool canRemoveCover(LibraryDetailHeader header) {
    return _hasText(header.customCoverLocalPath) ||
        _hasText(header.coverLocalPath) ||
        _hasText(header.coverImageUrl);
  }

  @override
  Future<void> updateCustomCoverFocus({
    required String workId,
    required double? focusX,
    required double? focusY,
  }) {
    final repository = _repository;
    if (repository is NovelCustomCoverWriter) {
      final writer = repository as NovelCustomCoverWriter;
      return writer.updateCustomCoverFocus(
        novelId: workId,
        focusX: focusX,
        focusY: focusY,
      );
    }
    throw const LibraryOperationException(
      LibraryOperationFailureCode.unsupported,
    );
  }

  @override
  Future<void> removeCustomCover({required String workId}) async {
    final repository = _repository;
    if (repository is NovelCustomCoverWriter) {
      final writer = repository as NovelCustomCoverWriter;
      await writer.removeCustomCover(novelId: workId);
      await _coverStore?.deleteAsset(
        LibraryCoverAssetIds.custom(ownerType: 'novel', ownerId: workId),
      );
      return;
    }
    throw const LibraryOperationException(
      LibraryOperationFailureCode.unsupported,
    );
  }

  bool _hasText(String? value) => value?.trim().isNotEmpty ?? false;

  @override
  Future<void> moveWorkToCategory({
    required String workId,
    required String toCategoryId,
  }) async {
    final fromCategoryId = await _findCurrentCategoryId(workId);
    if (fromCategoryId == null || fromCategoryId == toCategoryId) {
      return;
    }
    await _repository.moveNovelToCategory(
      novelId: workId,
      fromCategoryId: fromCategoryId,
      toCategoryId: toCategoryId,
    );
  }

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    final categories = await _repository.getCategories();
    return categories
        .map(
          (item) => LibraryCategory(
            categoryId: item.categoryId,
            name: item.name,
            sortOrder: item.sortOrder,
            createdAt: item.createdAt,
          ),
        )
        .toList(growable: false);
  }

  Future<String?> _findCurrentCategoryId(String workId) async {
    final categories = await _repository.getCategories();
    for (final category in categories) {
      final works = await _repository.getShelfItems(
        categoryId: category.categoryId,
      );
      if (works.any((item) => item.novelId == workId)) {
        return category.categoryId;
      }
    }
    return null;
  }

  List<LibraryChapterItem> _applyFilters(
    List<LibraryChapterItem> source,
    LibraryFilterSet filters,
  ) {
    return source
        .where((chapter) {
          if (!_matchTriState(filters.bookmarked, chapter.isBookmarked)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  List<LibraryChapterItem> _sortChapters(
    List<LibraryChapterItem> source,
    LibraryChapterSortOption sortOption,
  ) {
    final list = [...source];
    int compare(LibraryChapterItem a, LibraryChapterItem b) {
      var result = compareLibrarySourceIds(a.sourcePid, b.sourcePid);
      if (result == 0) {
        result = a.orderIndex.compareTo(b.orderIndex);
      }
      if (result == 0) {
        result = a.episodeId.compareTo(b.episodeId);
      }
      return sortOption.direction == LibrarySortDirection.asc
          ? result
          : -result;
    }

    list.sort(compare);
    return list;
  }

  bool _matchTriState(TriStateFilterValue filterValue, bool flag) {
    return switch (filterValue) {
      TriStateFilterValue.ignore => true,
      TriStateFilterValue.include => flag,
      TriStateFilterValue.exclude => !flag,
    };
  }
}
