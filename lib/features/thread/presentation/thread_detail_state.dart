import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_post_ratings_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';
import 'package:y300/features/thread/domain/models/thread_ui_feedback.dart';

enum ThreadPostRatingsLoadStatus { idle, loading, loaded, failure }

final class ThreadPostRatingsViewState {
  const ThreadPostRatingsViewState({
    required this.status,
    this.details,
    this.errorMessage,
    this.failure,
  });

  const ThreadPostRatingsViewState.idle()
    : status = ThreadPostRatingsLoadStatus.idle,
      details = null,
      errorMessage = null,
      failure = null;

  const ThreadPostRatingsViewState.loading()
    : status = ThreadPostRatingsLoadStatus.loading,
      details = null,
      errorMessage = null,
      failure = null;

  const ThreadPostRatingsViewState.loaded(ThreadPostRatingDetails value)
    : status = ThreadPostRatingsLoadStatus.loaded,
      details = value,
      errorMessage = null,
      failure = null;

  const ThreadPostRatingsViewState.failure(String message)
    : status = ThreadPostRatingsLoadStatus.failure,
      details = null,
      errorMessage = message,
      failure = null;

  const ThreadPostRatingsViewState.failureWith(ThreadActionFailure value)
    : status = ThreadPostRatingsLoadStatus.failure,
      details = null,
      errorMessage = null,
      failure = value;

  final ThreadPostRatingsLoadStatus status;
  final ThreadPostRatingDetails? details;
  final String? errorMessage;
  final ThreadActionFailure? failure;
}

class ThreadDetailPageState {
  const ThreadDetailPageState({
    required this.tid,
    required this.fid,
    required this.typeid,
    required this.typeName,
    required this.forumName,
    required this.forumUrl,
    required this.sourceTagName,
    required this.contentKind,
    required this.subject,
    required this.views,
    required this.replies,
    required this.currentPage,
    required this.lastPage,
    required this.previousPageUrl,
    required this.nextPageUrl,
    required this.reverseOrderUrl,
    required this.onlyAuthorUrl,
    required this.favoriteUrl,
    required this.shareUrl,
    required this.homeUrl,
    required this.desktopUrl,
    required this.hasMore,
    required this.queryParameters,
    required this.isLoadingInitial,
    required this.isLoadingMore,
    required this.posts,
    required this.isThreadFavorited,
    required this.isThreadFavoriteActionLoading,
    required this.threadFavoriteHint,
    required this.selectedPollOptionIds,
    required this.isPollVoteSubmitting,
    required this.pollVoteHint,
    this.ratingsByPostId = const <String, ThreadPostRatingsViewState>{},
    required this.replyText,
    required this.isReplySubmitting,
    required this.replyHint,
    this.capabilities,
    this.readMetadata,
    this.errorMessage,
    this.loadFailure,
    this.threadFavoriteNotice,
    this.pollVoteNotice,
    this.replyNotice,
  });

  final String tid;
  final String fid;
  final String typeid;
  final String? typeName;
  final String? forumName;
  final String? forumUrl;
  final String? sourceTagName;
  final ThreadContentKind contentKind;
  final String subject;
  final int views;
  final int replies;
  final int currentPage;
  final int? lastPage;
  final String? previousPageUrl;
  final String? nextPageUrl;
  final String? reverseOrderUrl;
  final String? onlyAuthorUrl;
  final String? favoriteUrl;
  final String? shareUrl;
  final String? homeUrl;
  final String? desktopUrl;
  final bool hasMore;
  final Map<String, String> queryParameters;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final List<ThreadPost> posts;
  final bool isThreadFavorited;
  final bool isThreadFavoriteActionLoading;
  final String? threadFavoriteHint;
  final Set<String> selectedPollOptionIds;
  final bool isPollVoteSubmitting;
  final String? pollVoteHint;
  final Map<String, ThreadPostRatingsViewState> ratingsByPostId;
  final String replyText;
  final bool isReplySubmitting;
  final String? replyHint;
  final ThreadDetailReadCapabilities? capabilities;
  final DataReadMetadata? readMetadata;
  final String? errorMessage;
  final ThreadActionFailure? loadFailure;
  final ThreadActionNotice? threadFavoriteNotice;
  final ThreadActionNotice? pollVoteNotice;
  final ThreadActionNotice? replyNotice;

  bool get isOnlyAuthorView =>
      (queryParameters['authorid']?.trim().isNotEmpty ?? false);

  bool get isReverseOrderView => queryParameters['ordertype']?.trim() == '1';

  bool supports(ThreadDetailCapability capability) {
    return capabilities?.supports(capability) ?? false;
  }

  factory ThreadDetailPageState.initial({
    required String tid,
    required String subject,
  }) {
    return ThreadDetailPageState(
      tid: tid,
      fid: '',
      typeid: '',
      typeName: null,
      forumName: null,
      forumUrl: null,
      sourceTagName: null,
      contentKind: ThreadContentKind.forum,
      subject: subject,
      views: 0,
      replies: 0,
      currentPage: 0,
      lastPage: null,
      previousPageUrl: null,
      nextPageUrl: null,
      reverseOrderUrl: null,
      onlyAuthorUrl: null,
      favoriteUrl: null,
      shareUrl: null,
      homeUrl: null,
      desktopUrl: null,
      hasMore: true,
      queryParameters: const <String, String>{},
      isLoadingInitial: true,
      isLoadingMore: false,
      posts: const <ThreadPost>[],
      isThreadFavorited: false,
      isThreadFavoriteActionLoading: false,
      threadFavoriteHint: null,
      selectedPollOptionIds: const <String>{},
      isPollVoteSubmitting: false,
      pollVoteHint: null,
      replyText: '',
      isReplySubmitting: false,
      replyHint: null,
      capabilities: null,
      readMetadata: null,
      errorMessage: null,
      loadFailure: null,
      threadFavoriteNotice: null,
      pollVoteNotice: null,
      replyNotice: null,
    );
  }

  ThreadDetailPageState copyWith({
    String? tid,
    String? fid,
    String? typeid,
    String? typeName,
    String? forumName,
    String? forumUrl,
    String? sourceTagName,
    ThreadContentKind? contentKind,
    String? subject,
    int? views,
    int? replies,
    int? currentPage,
    int? lastPage,
    String? previousPageUrl,
    String? nextPageUrl,
    String? reverseOrderUrl,
    String? onlyAuthorUrl,
    String? favoriteUrl,
    String? shareUrl,
    String? homeUrl,
    String? desktopUrl,
    bool? hasMore,
    Map<String, String>? queryParameters,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    List<ThreadPost>? posts,
    bool? isThreadFavorited,
    bool? isThreadFavoriteActionLoading,
    String? threadFavoriteHint,
    Set<String>? selectedPollOptionIds,
    bool? isPollVoteSubmitting,
    String? pollVoteHint,
    Map<String, ThreadPostRatingsViewState>? ratingsByPostId,
    String? replyText,
    bool? isReplySubmitting,
    String? replyHint,
    ThreadDetailReadCapabilities? capabilities,
    DataReadMetadata? readMetadata,
    String? errorMessage,
    ThreadActionFailure? loadFailure,
    ThreadActionNotice? threadFavoriteNotice,
    ThreadActionNotice? pollVoteNotice,
    ThreadActionNotice? replyNotice,
    bool clearReplyHint = false,
    bool clearThreadFavoriteHint = false,
    bool clearPollVoteHint = false,
    bool clearError = false,
    bool clearLoadFailure = false,
    bool clearThreadFavoriteNotice = false,
    bool clearPollVoteNotice = false,
    bool clearReplyNotice = false,
    bool clearSourceTagName = false,
    bool clearTypeName = false,
    bool clearLastPage = false,
    bool clearPreviousPageUrl = false,
    bool clearNextPageUrl = false,
    bool clearReverseOrderUrl = false,
    bool clearOnlyAuthorUrl = false,
    bool clearForumName = false,
    bool clearForumUrl = false,
    bool clearFavoriteUrl = false,
    bool clearShareUrl = false,
    bool clearHomeUrl = false,
    bool clearDesktopUrl = false,
  }) {
    return ThreadDetailPageState(
      tid: tid ?? this.tid,
      fid: fid ?? this.fid,
      typeid: typeid ?? this.typeid,
      typeName: clearTypeName ? null : (typeName ?? this.typeName),
      forumName: clearForumName ? null : (forumName ?? this.forumName),
      forumUrl: clearForumUrl ? null : (forumUrl ?? this.forumUrl),
      sourceTagName: clearSourceTagName
          ? null
          : (sourceTagName ?? this.sourceTagName),
      contentKind: contentKind ?? this.contentKind,
      subject: subject ?? this.subject,
      views: views ?? this.views,
      replies: replies ?? this.replies,
      currentPage: currentPage ?? this.currentPage,
      lastPage: clearLastPage ? null : (lastPage ?? this.lastPage),
      previousPageUrl: clearPreviousPageUrl
          ? null
          : (previousPageUrl ?? this.previousPageUrl),
      nextPageUrl: clearNextPageUrl ? null : (nextPageUrl ?? this.nextPageUrl),
      reverseOrderUrl: clearReverseOrderUrl
          ? null
          : (reverseOrderUrl ?? this.reverseOrderUrl),
      onlyAuthorUrl: clearOnlyAuthorUrl
          ? null
          : (onlyAuthorUrl ?? this.onlyAuthorUrl),
      favoriteUrl: clearFavoriteUrl ? null : (favoriteUrl ?? this.favoriteUrl),
      shareUrl: clearShareUrl ? null : (shareUrl ?? this.shareUrl),
      homeUrl: clearHomeUrl ? null : (homeUrl ?? this.homeUrl),
      desktopUrl: clearDesktopUrl ? null : (desktopUrl ?? this.desktopUrl),
      hasMore: hasMore ?? this.hasMore,
      queryParameters: queryParameters ?? this.queryParameters,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      posts: posts ?? this.posts,
      isThreadFavorited: isThreadFavorited ?? this.isThreadFavorited,
      isThreadFavoriteActionLoading:
          isThreadFavoriteActionLoading ?? this.isThreadFavoriteActionLoading,
      threadFavoriteHint: clearThreadFavoriteHint
          ? null
          : (threadFavoriteHint ?? this.threadFavoriteHint),
      selectedPollOptionIds:
          selectedPollOptionIds ?? this.selectedPollOptionIds,
      isPollVoteSubmitting: isPollVoteSubmitting ?? this.isPollVoteSubmitting,
      pollVoteHint: clearPollVoteHint
          ? null
          : (pollVoteHint ?? this.pollVoteHint),
      ratingsByPostId: ratingsByPostId ?? this.ratingsByPostId,
      replyText: replyText ?? this.replyText,
      isReplySubmitting: isReplySubmitting ?? this.isReplySubmitting,
      replyHint: clearReplyHint ? null : (replyHint ?? this.replyHint),
      capabilities: capabilities ?? this.capabilities,
      readMetadata: readMetadata ?? this.readMetadata,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
      threadFavoriteNotice: clearThreadFavoriteNotice
          ? null
          : (threadFavoriteNotice ?? this.threadFavoriteNotice),
      pollVoteNotice: clearPollVoteNotice
          ? null
          : (pollVoteNotice ?? this.pollVoteNotice),
      replyNotice: clearReplyNotice ? null : (replyNotice ?? this.replyNotice),
    );
  }
}
