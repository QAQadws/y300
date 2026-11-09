import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/domain/models/thread_post_rating_details.dart';
import 'package:y300/features/thread/domain/models/thread_ui_feedback.dart';
import 'package:y300/features/thread/presentation/models/thread_post_load_state.dart';
import 'package:y300/features/thread/presentation/models/thread_post_loading_content.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Owns per-post full-rating reads for one detail-controller lifetime.
final class ThreadPostRatingsLoader {
  ThreadPostRatingsLoader({
    required Future<ApiResult<ThreadPostRatingDetails>> Function(String)
    loadAll,
    required ThreadPostLoadingContent? Function() readContent,
    required void Function(Map<String, ThreadPostRatingsViewState>) onChanged,
  }) : _loadAll = loadAll,
       _readContent = readContent,
       _onChanged = onChanged;

  final Future<ApiResult<ThreadPostRatingDetails>> Function(String) _loadAll;
  final ThreadPostLoadingContent? Function() _readContent;
  final void Function(Map<String, ThreadPostRatingsViewState>) _onChanged;
  final _tokens = <String, Object>{};
  Map<String, ThreadPostRatingsViewState> _values = const {};
  Object _epoch = Object();
  bool _closed = false;

  Map<String, ThreadPostRatingsViewState> get values => _values;

  Future<void> load(ThreadPost post) async {
    if (_closed) return;
    final content = _readContent();
    final pid = post.pid.trim();
    final url = post.ratingSummary?.viewAllUrl?.trim();
    if (content == null ||
        !content.supportsRatings ||
        pid.isEmpty ||
        url == null ||
        url.isEmpty ||
        content.findPost(pid)?.ratingSummary?.viewAllUrl?.trim() != url) {
      return;
    }
    final status = _values[pid]?.status;
    if (status == ThreadPostRatingsLoadStatus.loading ||
        status == ThreadPostRatingsLoadStatus.loaded) {
      return;
    }

    final token = _tokens[pid] = Object();
    final epoch = _epoch;
    bool isCurrent() =>
        !_closed && identical(_epoch, epoch) && identical(_tokens[pid], token);
    _publish(pid, const ThreadPostRatingsViewState.loading());
    try {
      if (!isCurrent()) return;
      final result = await _loadAll(url);
      if (!isCurrent()) return;
      final latest = _readContent();
      if (latest?.tid != content.tid ||
          latest?.findPost(pid)?.ratingSummary?.viewAllUrl?.trim() != url ||
          _values[pid]?.status != ThreadPostRatingsLoadStatus.loading) {
        return;
      }
      _publish(pid, switch (result) {
        ApiSuccess<ThreadPostRatingDetails>(:final data) =>
          ThreadPostRatingsViewState.loaded(data),
        ApiFailure<ThreadPostRatingDetails>(:final error) =>
          ThreadPostRatingsViewState.failureWith(
            ThreadActionFailure(
              code: error.type == ApiErrorType.unauthorized
                  ? ThreadUiErrorCode.loginRequired
                  : ThreadUiErrorCode.unknown,
              action: ThreadActionKind.ratings,
              detail: error.message,
              message: error.message,
            ),
          ),
      });
    } catch (_) {
      if (isCurrent() &&
          _readContent()?.tid == content.tid &&
          _readContent()?.findPost(pid)?.ratingSummary?.viewAllUrl?.trim() ==
              url) {
        _publish(
          pid,
          const ThreadPostRatingsViewState.failureWith(
            ThreadActionFailure(
              code: ThreadUiErrorCode.unknown,
              action: ThreadActionKind.ratings,
            ),
          ),
        );
      }
    } finally {
      // A publication callback can already have started a newer retry.
      if (identical(_tokens[pid], token)) _tokens.remove(pid);
    }
  }

  void _publish(String pid, ThreadPostRatingsViewState value) {
    _values = Map.unmodifiable({..._values, pid: value});
    _onChanged(_values);
  }

  /// Clear only transient memory; the controller decides when to publish it.
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
