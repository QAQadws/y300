import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/presentation/models/thread_post_load_state.dart';
import 'package:y300/features/thread/presentation/models/thread_post_loading_content.dart';

typedef ThreadPostCommentsRead =
    DataReadResult<ThreadPostCommentsPage, ThreadPostCommentsReadCapabilities>;

/// Owns confirmed continuation pages, independently of the full-rating cache.
final class ThreadPostCommentsLoader {
  ThreadPostCommentsLoader({
    required Future<ThreadPostCommentsRead> Function(ThreadPostCommentsQuery)
    loadPage,
    required ThreadPostLoadingContent? Function() readContent,
    required void Function(Map<String, ThreadPostCommentsViewState>) onChanged,
  }) : _loadPage = loadPage,
       _readContent = readContent,
       _onChanged = onChanged;

  final Future<ThreadPostCommentsRead> Function(ThreadPostCommentsQuery)
  _loadPage;
  final ThreadPostLoadingContent? Function() _readContent;
  final void Function(Map<String, ThreadPostCommentsViewState>) _onChanged;
  final _tokens = <String, Object>{};
  Map<String, ThreadPostCommentsViewState> _values = const {};
  Object _epoch = Object();
  bool _closed = false;

  Map<String, ThreadPostCommentsViewState> get values => _values;

  Future<void> loadMore(ThreadPost post) async {
    if (_closed) return;
    final content = _readContent();
    final pid = post.pid.trim();
    final currentPost = content?.findPost(pid);
    if (content == null || pid.isEmpty || currentPost == null) return;
    final previous =
        _values[pid] ??
        ThreadPostCommentsViewState(
          comments: const [],
          nextPage: currentPost.commentNextPage,
        );
    final page = previous.nextPage;
    if (page == null || previous.isLoading) return;
    final token = _tokens[pid] = Object();
    final epoch = _epoch;
    bool isCurrent() =>
        !_closed && identical(_epoch, epoch) && identical(_tokens[pid], token);
    _publish(pid, previous.copyWith(isLoading: true, clearFailure: true));
    try {
      if (!isCurrent()) return;
      final result = await _loadPage(
        ThreadPostCommentsQuery(tid: content.tid, pid: pid, page: page),
      );
      if (!isCurrent()) return;
      final latest = _readContent();
      final activePost = latest?.findPost(pid);
      final active = _values[pid];
      if (latest?.tid != content.tid ||
          activePost == null ||
          active == null ||
          active.nextPage != page ||
          !active.isLoading) {
        return;
      }
      result.when(
        success: (data, capabilities, metadata) {
          if (data.tid != content.tid || data.pid != pid || data.page != page) {
            _publish(
              pid,
              active.copyWith(
                isLoading: false,
                failure: ThreadPostCommentsFailure.other,
              ),
            );
            return;
          }
          final ids = <String>{
            for (final comment in activePost.comments)
              if (comment.commentId != null) comment.commentId!,
            for (final comment in active.comments)
              if (comment.commentId != null) comment.commentId!,
          };
          final appended = <ThreadPostCommentEntry>[];
          for (final comment in data.comments) {
            final id = comment.commentId;
            if (id == null || ids.add(id)) appended.add(comment);
          }
          _publish(
            pid,
            active.copyWith(
              comments: List.unmodifiable([...active.comments, ...appended]),
              nextPage: data.nextPage,
              clearNextPage: data.nextPage == null,
              isLoading: false,
              clearFailure: true,
            ),
          );
        },
        failure: (failure) => _publish(
          pid,
          active.copyWith(
            isLoading: false,
            failure: failure.kind == DataReadFailureKind.unauthorized
                ? ThreadPostCommentsFailure.loginRequired
                : failure.code == 'thread_post_comments_permission_denied'
                ? ThreadPostCommentsFailure.permissionDenied
                : ThreadPostCommentsFailure.other,
          ),
        ),
      );
    } catch (_) {
      final active = _values[pid];
      if (isCurrent() &&
          _readContent()?.tid == content.tid &&
          _readContent()?.findPost(pid) != null &&
          active != null &&
          active.nextPage == page) {
        _publish(
          pid,
          active.copyWith(
            isLoading: false,
            failure: ThreadPostCommentsFailure.other,
          ),
        );
      }
    } finally {
      if (identical(_tokens[pid], token)) _tokens.remove(pid);
    }
  }

  void _publish(String pid, ThreadPostCommentsViewState value) {
    _values = Map.unmodifiable({..._values, pid: value});
    _onChanged(_values);
  }

  /// Identity changes reset comments; ratings deliberately have their own owner.
  void reset() {
    _epoch = Object();
    _tokens.clear();
    _values = const {};
  }

  void close() {
    _closed = true;
    reset();
  }
}
