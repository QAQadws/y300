import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/services/unified_detail_operation_coordinator.dart';

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

/// Owns result acceptance and operation admission for one detail surface.
class UnifiedDetailController {
  UnifiedDetailController({
    required DetailModuleAdapter adapter,
    required String workId,
  }) : _adapter = adapter,
       _workId = workId,
       _state = UnifiedDetailState.initial();

  final DetailModuleAdapter _adapter;
  final String _workId;
  final _operations = UnifiedDetailOperationCoordinator();
  _DetailLoadRequest? _headerRequest;
  _DetailLoadRequest? _chapterRequest;
  Future<DetailRefreshResult>? _refreshInFlight;
  String? _headerError;
  String? _chapterError;
  bool _closed = false;

  UnifiedDetailState _state;
  UnifiedDetailState get state => _state;

  bool get isResettingWorkReading => _operations.isResettingReading;

  bool isChapterDownloadPending(String episodeId) =>
      _operations.isPending(UnifiedDetailOperationKind.download, episodeId);

  bool isChapterReadingStateLocked(String episodeId) =>
      isResettingWorkReading ||
      _operations.isPending(UnifiedDetailOperationKind.readingState, episodeId);

  void close() {
    if (_closed) return;
    _closed = true;
    _headerRequest = null;
    _chapterRequest = null;
    _refreshInFlight = null;
    _operations.close();
    _state = _state.copyWith(isLoading: false, isRefreshing: false);
  }

  Future<void> initialize() async {
    await _load();
  }

  /// 仅重新读取本地详情与章节状态，不触发模块侧“更新章节”动作。
  Future<void> reload() async {
    await _load();
  }

  Future<DetailRefreshResult> refresh() {
    return _runRefresh(() => _adapter.refreshWork(workId: _workId));
  }

  Future<DetailRefreshResult> refreshFully() {
    return _runRefresh(() {
      final adapter = _fullRefreshAdapter;
      if (adapter == null) throw UnsupportedError('fullRefresh');
      return adapter.refreshWorkFully(workId: _workId);
    });
  }

  Future<DetailRefreshResult> _runRefresh(
    Future<DetailRefreshResult> Function() action,
  ) {
    if (_closed) return Future.value(DetailRefreshResult.skipped);
    final active = _refreshInFlight;
    if (active != null) return active;
    late final Future<DetailRefreshResult> request;
    request = _performRefresh(action).whenComplete(() {
      if (identical(_refreshInFlight, request)) _refreshInFlight = null;
    });
    _refreshInFlight = request;
    return request;
  }

  Future<DetailRefreshResult> _performRefresh(
    Future<DetailRefreshResult> Function() action,
  ) async {
    _headerError = null;
    _chapterError = null;
    _state = _state.copyWith(
      isRefreshing: true,
      clearError: true,
      clearRefreshResult: true,
    );
    late final DetailRefreshResult result;
    try {
      result = await action();
      if (_closed) return result;
      if (result.shouldReload) {
        await _load();
      }
      if (!_closed) _state = _state.copyWith(lastRefreshResult: result);
      return result;
    } finally {
      if (!_closed) _state = _state.copyWith(isRefreshing: false);
    }
  }

  Future<void> updateChapterQuery({
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  }) async {
    if (_closed) return;
    _state = _state.copyWith(filters: filters, chapterSortOption: sortOption);
    await _loadChaptersOnly();
  }

  Future<void> updateFilters(LibraryFilterSet filters) async {
    if (_closed) return;
    _state = _state.copyWith(filters: filters);
    await _loadChaptersOnly();
  }

  Future<void> toggleChapterReadingState({
    required String episodeId,
    required bool isCurrentlyRead,
  }) async {
    if (_closed) return;
    final readStateAdapter = _readStateAdapter;
    if (readStateAdapter == null) {
      throw UnsupportedError('chapterReadState');
    }
    await _runChapterOperation(
      UnifiedDetailOperationKind.readingState,
      episodeId,
      () => isCurrentlyRead
          ? readStateAdapter.resetChapterReadingState(
              workId: _workId,
              episodeId: episodeId,
            )
          : readStateAdapter.markChapterRead(
              workId: _workId,
              episodeId: episodeId,
              isRead: true,
            ),
    );
  }

  Future<void> markChapterBookmarked({
    required String episodeId,
    required bool isBookmarked,
  }) async {
    await _runChapterOperation(
      UnifiedDetailOperationKind.bookmark,
      episodeId,
      () => _adapter.markChapterBookmarked(
        workId: _workId,
        episodeId: episodeId,
        isBookmarked: isBookmarked,
      ),
    );
  }

  Future<void> markChapterDownloaded({
    required String episodeId,
    required bool isDownloaded,
  }) async {
    if (_closed) return;
    final downloadAdapter = _downloadAdapter;
    if (downloadAdapter == null) {
      throw UnsupportedError('chapterDownload');
    }
    await _runChapterOperation(
      UnifiedDetailOperationKind.download,
      episodeId,
      () => downloadAdapter.markChapterDownloaded(
        workId: _workId,
        episodeId: episodeId,
        isDownloaded: isDownloaded,
      ),
    );
  }

  Future<void> resetWorkReadingState() async {
    if (_closed) return;
    final resetAdapter = _workReadingResetAdapter;
    if (resetAdapter == null) {
      throw UnsupportedError('workReadingReset');
    }
    final request = _operations.beginReadingReset();
    if (request == null) return;
    try {
      await request.predecessorsSettled;
      if (!_operations.owns(request)) return;
      await resetAdapter.resetWorkReadingState(workId: _workId);
      if (_operations.owns(request)) await _loadChaptersOnly();
    } finally {
      _operations.finish(request);
    }
  }

  Future<void> deleteChapterDownload({required String episodeId}) async {
    if (_closed) return;
    final downloadAdapter = _downloadAdapter;
    if (downloadAdapter == null) {
      throw UnsupportedError('chapterDownload');
    }
    await _runChapterOperation(
      UnifiedDetailOperationKind.download,
      episodeId,
      () => downloadAdapter.deleteChapterDownload(
        workId: _workId,
        episodeId: episodeId,
      ),
    );
  }

  Future<void> _runChapterOperation(
    UnifiedDetailOperationKind kind,
    String episodeId,
    Future<void> Function() action,
  ) async {
    final request = _operations.beginChapter(kind, episodeId);
    if (request == null) return;
    try {
      await action();
      if (_operations.owns(request)) await _loadChaptersOnly();
    } finally {
      _operations.finish(request);
    }
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

  DetailFullRefreshAdapter? get _fullRefreshAdapter {
    final adapter = _adapter;
    return adapter is DetailFullRefreshAdapter
        ? adapter as DetailFullRefreshAdapter
        : null;
  }

  Future<void> _load() async {
    if (_closed) return;
    final request = _newLoadRequest(includesHeader: true);
    _headerError = null;
    _chapterError = null;
    _headerRequest = request;
    _chapterRequest = request;
    _state = _state.copyWith(isLoading: true, clearError: true);
    try {
      final header = await _adapter.loadHeader(workId: _workId);
      if (_closed || !identical(_headerRequest, request)) return;
      _headerRequest = null;
      _headerError = null;
      // Header and chapter ownership are independent: a newer filter may have
      // already supplied chapters while this header was still being read.
      _state = _state.copyWith(
        header: header,
        isLoading: _isLoading,
        errorMessage: _chapterError,
        clearError: _chapterError == null,
      );
      if (identical(_chapterRequest, request)) await _readChapters(request);
    } catch (error) {
      if (_closed || !identical(_headerRequest, request)) return;
      _headerRequest = null;
      if (identical(_chapterRequest, request)) _chapterRequest = null;
      _headerError = '$error';
      _state = _state.copyWith(
        isLoading: _isLoading,
        errorMessage: _headerError,
      );
    }
  }

  Future<void> _loadChaptersOnly() async {
    if (_closed) return;
    final request = _newLoadRequest(includesHeader: false);
    _chapterRequest = request;
    _chapterError = null;
    _state = _state.copyWith(
      isLoading: _isLoading,
      errorMessage: _headerError,
      clearError: _headerError == null,
    );
    await _readChapters(request);
  }

  bool get _isLoading =>
      _headerRequest != null || _chapterRequest?.includesHeader == true;

  _DetailLoadRequest _newLoadRequest({required bool includesHeader}) =>
      _DetailLoadRequest(
        includesHeader: includesHeader,
        filters: _state.filters,
        sortOption: _state.chapterSortOption,
      );

  Future<void> _readChapters(_DetailLoadRequest request) async {
    try {
      final chapters = await _adapter.loadChapters(
        workId: _workId,
        filters: request.filters,
        sortOption: request.sortOption,
      );
      if (_closed || !identical(_chapterRequest, request)) return;
      _chapterRequest = null;
      _chapterError = null;
      _state = _state.copyWith(
        chapters: chapters,
        isLoading: _isLoading,
        errorMessage: _headerError,
        clearError: _headerError == null,
      );
    } catch (error) {
      if (_closed || !identical(_chapterRequest, request)) return;
      _chapterRequest = null;
      _chapterError = '$error';
      _state = _state.copyWith(
        isLoading: _isLoading,
        errorMessage: _headerError ?? _chapterError,
      );
    }
  }
}

final class _DetailLoadRequest {
  _DetailLoadRequest({
    required this.includesHeader,
    required this.filters,
    required this.sortOption,
  });

  final bool includesHeader;
  final LibraryFilterSet filters;
  final LibraryChapterSortOption sortOption;
}
