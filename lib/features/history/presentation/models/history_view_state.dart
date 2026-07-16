import 'package:y300/features/history/domain/models/history_models.dart';

class HistoryViewState {
  const HistoryViewState({
    required this.isInitialLoading,
    required this.items,
    required this.searchText,
    required this.hasMore,
    required this.nextCursor,
    required this.isLoadingMore,
    required this.errorMessage,
    required this.loadMoreError,
  });

  factory HistoryViewState.initial() {
    return const HistoryViewState(
      isInitialLoading: false,
      items: <HistoryEntry>[],
      searchText: '',
      hasMore: false,
      nextCursor: null,
      isLoadingMore: false,
      errorMessage: null,
      loadMoreError: null,
    );
  }

  final bool isInitialLoading;
  final List<HistoryEntry> items;
  final String searchText;
  final bool hasMore;
  final HistoryCursor? nextCursor;
  final bool isLoadingMore;
  final String? errorMessage;
  final String? loadMoreError;

  bool get isSearching => searchText.trim().isNotEmpty;

  HistoryViewState copyWith({
    bool? isInitialLoading,
    List<HistoryEntry>? items,
    String? searchText,
    bool? hasMore,
    HistoryCursor? nextCursor,
    bool clearCursor = false,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearError = false,
    String? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return HistoryViewState(
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      items: items ?? this.items,
      searchText: searchText ?? this.searchText,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
    );
  }
}
