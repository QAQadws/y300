import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/thread_post_rating_details.dart';
import 'package:y300/features/thread/domain/models/thread_ui_feedback.dart';

enum ThreadPostRatingsLoadStatus { idle, loading, loaded, failure }

enum ThreadPostCommentsFailure { loginRequired, permissionDenied, other }

/// Transient continuation state for a single post's comments.
final class ThreadPostCommentsViewState {
  const ThreadPostCommentsViewState({
    required this.comments,
    required this.nextPage,
    this.isLoading = false,
    this.failure,
  });

  final List<ThreadPostCommentEntry> comments;
  final int? nextPage;
  final bool isLoading;
  final ThreadPostCommentsFailure? failure;
  bool get hasFailure => failure != null;

  ThreadPostCommentsViewState copyWith({
    List<ThreadPostCommentEntry>? comments,
    int? nextPage,
    bool clearNextPage = false,
    bool? isLoading,
    ThreadPostCommentsFailure? failure,
    bool clearFailure = false,
  }) => ThreadPostCommentsViewState(
    comments: comments ?? this.comments,
    nextPage: clearNextPage ? null : (nextPage ?? this.nextPage),
    isLoading: isLoading ?? this.isLoading,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

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
