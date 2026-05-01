import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';

class ThreadDetailPageState {
  const ThreadDetailPageState({
    required this.tid,
    required this.subject,
    required this.currentPage,
    required this.hasMore,
    required this.isLoadingInitial,
    required this.isLoadingMore,
    required this.posts,
    required this.comicCandidateInfo,
    required this.parsedComicPost,
    required this.isInShelf,
    required this.isComicActionLoading,
    this.errorMessage,
  });

  final String tid;
  final String subject;
  final int currentPage;
  final bool hasMore;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final List<ThreadPost> posts;
  final ComicCandidateInfo comicCandidateInfo;
  final ParsedComicPost parsedComicPost;
  final bool isInShelf;
  final bool isComicActionLoading;
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
      comicCandidateInfo: ComicCandidateInfo.notCandidate,
      parsedComicPost: ParsedComicPost.empty,
      isInShelf: false,
      isComicActionLoading: false,
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
    ComicCandidateInfo? comicCandidateInfo,
    ParsedComicPost? parsedComicPost,
    bool? isInShelf,
    bool? isComicActionLoading,
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
      comicCandidateInfo: comicCandidateInfo ?? this.comicCandidateInfo,
      parsedComicPost: parsedComicPost ?? this.parsedComicPost,
      isInShelf: isInShelf ?? this.isInShelf,
      isComicActionLoading: isComicActionLoading ?? this.isComicActionLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
