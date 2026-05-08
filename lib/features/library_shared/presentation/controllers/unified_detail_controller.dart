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
  });

  final bool isLoading;
  final LibraryDetailHeader? header;
  final List<LibraryChapterItem> chapters;
  final LibraryChapterSortOption chapterSortOption;
  final LibraryFilterSet filters;
  final String? errorMessage;
  final bool isRefreshing;

  factory UnifiedDetailState.initial() {
    return const UnifiedDetailState(
      isLoading: false,
      header: null,
      chapters: <LibraryChapterItem>[],
      chapterSortOption: LibraryChapterSortOption.defaults,
      filters: LibraryFilterSet.defaults,
      errorMessage: null,
      isRefreshing: false,
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
  }) {
    return UnifiedDetailState(
      isLoading: isLoading ?? this.isLoading,
      header: header ?? this.header,
      chapters: chapters ?? this.chapters,
      chapterSortOption: chapterSortOption ?? this.chapterSortOption,
      filters: filters ?? this.filters,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

/// 统一详情页控制器（Phase 4）。
class UnifiedDetailController {
  UnifiedDetailController({
    required DetailModuleAdapter adapter,
    required String workId,
  })  : _adapter = adapter,
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

  Future<void> refresh() async {
    _state = _state.copyWith(isRefreshing: true, clearError: true);
    try {
      await _adapter.refreshWork(workId: _workId);
      await _load();
    } finally {
      _state = _state.copyWith(isRefreshing: false);
    }
  }

  Future<void> toggleSortDirection() async {
    final nextDirection = _state.chapterSortOption.direction == LibrarySortDirection.asc
        ? LibrarySortDirection.desc
        : LibrarySortDirection.asc;
    _state = _state.copyWith(
      chapterSortOption: LibraryChapterSortOption(
        field: _state.chapterSortOption.field,
        direction: nextDirection,
      ),
    );
    await _loadChaptersOnly();
  }

  Future<void> updateChapterSortField(LibraryChapterSortField field) async {
    _state = _state.copyWith(
      chapterSortOption: LibraryChapterSortOption(
        field: field,
        direction: _state.chapterSortOption.direction,
      ),
    );
    await _loadChaptersOnly();
  }

  Future<void> updateFilters(LibraryFilterSet filters) async {
    _state = _state.copyWith(filters: filters);
    await _loadChaptersOnly();
  }

  Future<void> markChapterRead({
    required String episodeId,
    required bool isRead,
  }) async {
    await _adapter.markChapterRead(
      workId: _workId,
      episodeId: episodeId,
      isRead: isRead,
    );
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
    await _adapter.markChapterDownloaded(
      workId: _workId,
      episodeId: episodeId,
      isDownloaded: isDownloaded,
    );
    await _loadChaptersOnly();
  }

  Future<void> clearAllReadState() async {
    await _adapter.clearAllReadState(workId: _workId);
    await _loadChaptersOnly();
  }

  Future<void> deleteChapterDownload({required String episodeId}) async {
    await _adapter.deleteChapterDownload(
      workId: _workId,
      episodeId: episodeId,
    );
    await _loadChaptersOnly();
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
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: '$error',
      );
    }
  }

  Future<void> _loadChaptersOnly() async {
    try {
      final chapters = await _adapter.loadChapters(
        workId: _workId,
        filters: _state.filters,
        sortOption: _state.chapterSortOption,
      );
      _state = _state.copyWith(
        chapters: chapters,
        clearError: true,
      );
    } catch (error) {
      _state = _state.copyWith(errorMessage: '$error');
    }
  }
}
