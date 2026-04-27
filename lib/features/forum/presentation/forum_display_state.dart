import 'package:y300/features/forum/data/models/forum_display_models.dart';

class ForumDisplayPageState {
  const ForumDisplayPageState({
    required this.fid,
    required this.title,
    required this.currentPage,
    required this.hasMore,
    required this.isLoadingInitial,
    required this.isLoadingMore,
    required this.threads,
    this.errorMessage,
  });

  final String fid;
  final String title;
  final int currentPage;
  final bool hasMore;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final List<ForumThreadSummary> threads;
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
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
