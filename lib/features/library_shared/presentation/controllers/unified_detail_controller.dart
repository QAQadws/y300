import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

/// 统一详情页状态。
class UnifiedDetailState {
  const UnifiedDetailState({
    required this.isLoading,
    required this.header,
    required this.chapters,
    required this.chapterSortOption,
    required this.filters,
    required this.errorMessage,
    required this.isRefreshing,
    this.lastRefreshResult,
  });

  final bool isLoading;
  final LibraryDetailHeader? header;
  final List<LibraryChapterItem> chapters;
  final LibraryChapterSortOption chapterSortOption;
  final LibraryFilterSet filters;
  final String? errorMessage;
  final bool isRefreshing;
  final DetailRefreshResult? lastRefreshResult;

  factory UnifiedDetailState.initial() {
    return const UnifiedDetailState(
      isLoading: false,
      header: null,
      chapters: <LibraryChapterItem>[],
      chapterSortOption: LibraryChapterSortOption.defaults,
      filters: LibraryFilterSet.defaults,
      errorMessage: null,
      isRefreshing: false,
      lastRefreshResult: null,
    );
  }

  UnifiedDetailState copyWith({
    bool? isLoading,
    LibraryDetailHeader? header,
    List<LibraryChapterItem>? chapters,
    LibraryChapterSortOption? chapterSortOption,
    LibraryFilterSet? filters,
    String? errorMessage,
    bool clearError = false,
    bool? isRefreshing,
    DetailRefreshResult? lastRefreshResult,
    bool clearRefreshResult = false,
  }) {
    return UnifiedDetailState(
      isLoading: isLoading ?? this.isLoading,
      header: header ?? this.header,
      chapters: chapters ?? this.chapters,
      chapterSortOption: chapterSortOption ?? this.chapterSortOption,
      filters: filters ?? this.filters,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastRefreshResult: clearRefreshResult
          ? null
          : (lastRefreshResult ?? this.lastRefreshResult),
    );
  }
}

/// 统一详情页控制器（Phase 4）。
class UnifiedDetailController {
  UnifiedDetailController({
    required DetailModuleAdapter adapter,
    required String workId,
  }) : _adapter = adapter,
       _workId = workId,
       _state = UnifiedDetailState.initial();

  final DetailModuleAdapter _adapter;
  final String _workId;

  UnifiedDetailState _state;
  UnifiedDetailState get state => _state;

  Future<void> initialize() async {
    await _load();
  }

  /// 仅重新读取本地详情与章节状态，不触发模块侧“更新章节”动作。
  Future<void> reload() async {
    await _load();
  }

  Future<DetailRefreshResult> refresh() async {
    _state = _state.copyWith(
      isRefreshing: true,
      clearError: true,
      clearRefreshResult: true,
    );
    late final DetailRefreshResult result;
    try {
      result = await _adapter.refreshWork(workId: _workId);
      if (result.shouldReload) {
        await _load();
      }
      _state = _state.copyWith(lastRefreshResult: result);
      return result;
    } finally {
      _state = _state.copyWith(isRefreshing: false);
    }
  }

  Future<void> updateChapterQuery({
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  }) async {
    _state = _state.copyWith(filters: filters, chapterSortOption: sortOption);
    await _loadChaptersOnly();
  }

  Future<void> updateFilters(LibraryFilterSet filters) async {
    _state = _state.copyWith(filters: filters);
    await _loadChaptersOnly();
  }

  Future<void> toggleChapterReadingState({
    required String episodeId,
    required bool isCurrentlyRead,
  }) async {
    final readStateAdapter = _readStateAdapter;
    if (readStateAdapter == null) {
      throw UnsupportedError('chapterReadState');
    }
    if (isCurrentlyRead) {
      await readStateAdapter.resetChapterReadingState(
        workId: _workId,
        episodeId: episodeId,
      );
    } else {
      await readStateAdapter.markChapterRead(
        workId: _workId,
        episodeId: episodeId,
        isRead: true,
      );
    }
    await _loadChaptersOnly();
  }

  Future<void> markChapterBookmarked({
    required String episodeId,
    required bool isBookmarked,
  }) async {
    await _adapter.markChapterBookmarked(
      workId: _workId,
      episodeId: episodeId,
      isBookmarked: isBookmarked,
    );
    await _loadChaptersOnly();
  }

  Future<void> markChapterDownloaded({
    required String episodeId,
    required bool isDownloaded,
  }) async {
    final downloadAdapter = _downloadAdapter;
    if (downloadAdapter == null) {
      throw UnsupportedError('chapterDownload');
    }
    await downloadAdapter.markChapterDownloaded(
      workId: _workId,
      episodeId: episodeId,
      isDownloaded: isDownloaded,
    );
    await _loadChaptersOnly();
  }

  Future<void> resetWorkReadingState() async {
    final resetAdapter = _workReadingResetAdapter;
    if (resetAdapter == null) {
      throw UnsupportedError('workReadingReset');
    }
    await resetAdapter.resetWorkReadingState(workId: _workId);
    await _loadChaptersOnly();
  }

  Future<void> deleteChapterDownload({required String episodeId}) async {
    final downloadAdapter = _downloadAdapter;
    if (downloadAdapter == null) {
      throw UnsupportedError('chapterDownload');
    }
    await downloadAdapter.deleteChapterDownload(
      workId: _workId,
      episodeId: episodeId,
    );
    await _loadChaptersOnly();
  }

  DetailChapterDownloadAdapter? get _downloadAdapter {
    final adapter = _adapter;
    return adapter is DetailChapterDownloadAdapter
        ? adapter as DetailChapterDownloadAdapter
        : null;
  }

  DetailChapterReadStateAdapter? get _readStateAdapter {
    final adapter = _adapter;
    return adapter is DetailChapterReadStateAdapter
        ? adapter as DetailChapterReadStateAdapter
        : null;
  }

  DetailWorkReadingResetAdapter? get _workReadingResetAdapter {
    final adapter = _adapter;
    return adapter is DetailWorkReadingResetAdapter
        ? adapter as DetailWorkReadingResetAdapter
        : null;
  }

  Future<void> _load() async {
    _state = _state.copyWith(isLoading: true, clearError: true);
    try {
      final header = await _adapter.loadHeader(workId: _workId);
      final chapters = await _adapter.loadChapters(
        workId: _workId,
        filters: _state.filters,
        sortOption: _state.chapterSortOption,
      );
      _state = _state.copyWith(
        isLoading: false,
        header: header,
        chapters: chapters,
        clearError: true,
      );
    } catch (error) {
      _state = _state.copyWith(isLoading: false, errorMessage: '$error');
    }
  }

  Future<void> _loadChaptersOnly() async {
    try {
      final chapters = await _adapter.loadChapters(
        workId: _workId,
        filters: _state.filters,
        sortOption: _state.chapterSortOption,
      );
      _state = _state.copyWith(chapters: chapters, clearError: true);
    } catch (error) {
      _state = _state.copyWith(errorMessage: '$error');
    }
  }
}
