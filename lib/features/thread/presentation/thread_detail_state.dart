import 'package:y300/features/thread/data/models/thread_detail_models.dart';

class ThreadDetailPageState {
  const ThreadDetailPageState({
    required this.tid,
    required this.subject,
    required this.currentPage,
    required this.hasMore,
    required this.isLoadingInitial,
    required this.isLoadingMore,
    required this.posts,
    this.errorMessage,
  });

  final String tid;
  final String subject;
  final int currentPage;
  final bool hasMore;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final List<ThreadPost> posts;
  final String? errorMessage;

  factory ThreadDetailPageState.initial({
    required String tid,
    required String subject,
  }) {
    return ThreadDetailPageState(
      tid: tid,
      subject: subject,
      currentPage: 0,
      hasMore: true,
      isLoadingInitial: true,
      isLoadingMore: false,
      posts: const <ThreadPost>[],
      errorMessage: null,
    );
  }

  ThreadDetailPageState copyWith({
    String? tid,
    String? subject,
    int? currentPage,
    bool? hasMore,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    List<ThreadPost>? posts,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ThreadDetailPageState(
      tid: tid ?? this.tid,
      subject: subject ?? this.subject,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      posts: posts ?? this.posts,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
