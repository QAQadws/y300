import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';

enum ForumDisplayFailureCode { loadFailed }

class ForumDisplayFailure {
  const ForumDisplayFailure({required this.code, this.detail});

  final ForumDisplayFailureCode code;
  final String? detail;
}

class ForumDisplayPageState {
  const ForumDisplayPageState({
    required this.fid,
    required this.title,
    required this.currentPage,
    required this.hasMore,
    required this.isLoadingInitial,
    required this.isLoadingMore,
    required this.threads,
    required this.query,
    this.headImageUrl,
    this.headImageDimensions,
    this.forumIconUrl,
    this.todayPosts = 0,
    this.totalThreads = 0,
    this.rank = 0,
    this.primaryFilters = const <ForumDisplayFilterItem>[],
    this.typeFilters = const <ForumDisplayFilterItem>[],
    this.subForums = const <ForumDisplaySubForum>[],
    this.topEntries = const <ForumDisplayTopEntry>[],
    this.previousPageUrl,
    this.nextPageUrl,
    this.lastPage,
    this.favoriteAction = ForumDisplayFavoriteAction.unknown,
    this.failure,
    @Deprecated('Use failure and presentation localization instead.')
    this.errorMessage,
  });

  final String fid;
  final String title;
  final int currentPage;
  final bool hasMore;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final List<ForumThreadSummary> threads;
  final ForumDisplayQuery query;
  final String? headImageUrl;
  final ForumImageDimensions? headImageDimensions;
  final String? forumIconUrl;
  final int todayPosts;
  final int totalThreads;
  final int rank;
  final List<ForumDisplayFilterItem> primaryFilters;
  final List<ForumDisplayFilterItem> typeFilters;
  final List<ForumDisplaySubForum> subForums;
  final List<ForumDisplayTopEntry> topEntries;
  final String? previousPageUrl;
  final String? nextPageUrl;
  final int? lastPage;
  final ForumDisplayFavoriteAction favoriteAction;

  final ForumDisplayFailure? failure;

  @Deprecated('Use failure and presentation localization instead.')
  final String? errorMessage;

  factory ForumDisplayPageState.initial({
    required String fid,
    required String title,
  }) {
    return ForumDisplayPageState(
      fid: fid,
      title: title,
      currentPage: 0,
      hasMore: true,
      isLoadingInitial: true,
      isLoadingMore: false,
      threads: const <ForumThreadSummary>[],
      query: ForumDisplayQuery.initial(fid: fid),
      headImageUrl: null,
      headImageDimensions: null,
      forumIconUrl: null,
      todayPosts: 0,
      totalThreads: 0,
      rank: 0,
      primaryFilters: const <ForumDisplayFilterItem>[],
      typeFilters: const <ForumDisplayFilterItem>[],
      subForums: const <ForumDisplaySubForum>[],
      topEntries: const <ForumDisplayTopEntry>[],
      previousPageUrl: null,
      nextPageUrl: null,
      lastPage: null,
      favoriteAction: ForumDisplayFavoriteAction.unknown,
      failure: null,
      errorMessage: null,
    );
  }

  ForumDisplayPageState copyWith({
    String? fid,
    String? title,
    int? currentPage,
    bool? hasMore,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    List<ForumThreadSummary>? threads,
    ForumDisplayQuery? query,
    String? headImageUrl,
    ForumImageDimensions? headImageDimensions,
    String? forumIconUrl,
    int? todayPosts,
    int? totalThreads,
    int? rank,
    List<ForumDisplayFilterItem>? primaryFilters,
    List<ForumDisplayFilterItem>? typeFilters,
    List<ForumDisplaySubForum>? subForums,
    List<ForumDisplayTopEntry>? topEntries,
    String? previousPageUrl,
    String? nextPageUrl,
    int? lastPage,
    ForumDisplayFavoriteAction? favoriteAction,
    ForumDisplayFailure? failure,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ForumDisplayPageState(
      fid: fid ?? this.fid,
      title: title ?? this.title,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      threads: threads ?? this.threads,
      query: query ?? this.query,
      headImageUrl: headImageUrl ?? this.headImageUrl,
      headImageDimensions: headImageDimensions ?? this.headImageDimensions,
      forumIconUrl: forumIconUrl ?? this.forumIconUrl,
      todayPosts: todayPosts ?? this.todayPosts,
      totalThreads: totalThreads ?? this.totalThreads,
      rank: rank ?? this.rank,
      primaryFilters: primaryFilters ?? this.primaryFilters,
      typeFilters: typeFilters ?? this.typeFilters,
      subForums: subForums ?? this.subForums,
      topEntries: topEntries ?? this.topEntries,
      previousPageUrl: previousPageUrl ?? this.previousPageUrl,
      nextPageUrl: nextPageUrl ?? this.nextPageUrl,
      lastPage: lastPage ?? this.lastPage,
      favoriteAction: favoriteAction ?? this.favoriteAction,
      failure: clearError ? null : (failure ?? this.failure),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
