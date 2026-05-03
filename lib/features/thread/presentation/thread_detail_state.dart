import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';

class ThreadDetailPageState {
  const ThreadDetailPageState({
    required this.tid,
    required this.fid,
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
    required this.isNovelCandidate,
    required this.isNovelInShelf,
    required this.isNovelActionLoading,
    required this.replyText,
    required this.isReplySubmitting,
    required this.replyHint,
    this.errorMessage,
  });

  final String tid;
  final String fid;
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
  final bool isNovelCandidate;
  final bool isNovelInShelf;
  final bool isNovelActionLoading;
  final String replyText;
  final bool isReplySubmitting;
  final String? replyHint;
  final String? errorMessage;

  factory ThreadDetailPageState.initial({
    required String tid,
    required String subject,
  }) {
    return ThreadDetailPageState(
      tid: tid,
      fid: '',
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
      isNovelCandidate: false,
      isNovelInShelf: false,
      isNovelActionLoading: false,
      replyText: '',
      isReplySubmitting: false,
      replyHint: null,
      errorMessage: null,
    );
  }

  ThreadDetailPageState copyWith({
    String? tid,
    String? fid,
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
    bool? isNovelCandidate,
    bool? isNovelInShelf,
    bool? isNovelActionLoading,
    String? replyText,
    bool? isReplySubmitting,
    String? replyHint,
    String? errorMessage,
    bool clearReplyHint = false,
    bool clearError = false,
  }) {
    return ThreadDetailPageState(
      tid: tid ?? this.tid,
      fid: fid ?? this.fid,
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
      isNovelCandidate: isNovelCandidate ?? this.isNovelCandidate,
      isNovelInShelf: isNovelInShelf ?? this.isNovelInShelf,
      isNovelActionLoading: isNovelActionLoading ?? this.isNovelActionLoading,
      replyText: replyText ?? this.replyText,
      isReplySubmitting: isReplySubmitting ?? this.isReplySubmitting,
      replyHint: clearReplyHint ? null : (replyHint ?? this.replyHint),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
