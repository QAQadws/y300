import 'package:flutter/widgets.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:y300/features/thread/domain/models/thread_ui_feedback.dart';
import 'package:y300/features/thread/presentation/services/thread_image_viewport_coordinator.dart';
import 'package:y300/features/thread/presentation/services/thread_post_body_presentation.dart';
import 'package:y300/features/thread/presentation/thread_detail_content_projector.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/data/repositories/thread_post_ratings_repository.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    show ThreadPost;

/// Owned by one chapter/account generation. Recycling a row releases widgets,
/// image decoders and subscriptions, while retaining only presentation values.
class ComicCommentPresentationStore {
  ComicCommentPresentationStore({ScrollController? scrollController})
    : scrollController =
          scrollController ?? ScrollController(keepScrollOffset: false);

  final ScrollController scrollController;
  final _entries = <String, ComicCommentPostPresentation>{};
  ComicCommentContentProjection? _projection;
  final imageViewport = ThreadImageViewportCoordinator();
  bool _disposed = false;

  ComicCommentPostPresentation? operator [](String pid) => _entries[pid];

  ComicCommentPostPresentation? forRenderedPost(ThreadPost post) {
    final entry = _entries[post.pid];
    return entry?.renderRevision == _revision(post) ? entry : null;
  }

  static int _revision(ThreadPost post) =>
      Object.hashAll(ThreadDetailContentProjector.postRevisionParts(post));

  void synchronize(ComicCommentContentProjection projection) {
    if (_disposed || identical(_projection, projection)) return;
    _projection = projection;
    final ids = <String>{};
    for (final item in projection.items) {
      final pid = item.sourceItem.pid;
      ids.add(pid);
      final revision = _revision(item.sourceItem.post);
      if (_entries[pid]?.sourceRevision != revision) {
        _entries.remove(pid)?.dispose();
        _entries[pid] = ComicCommentPostPresentation(sourceRevision: revision);
      }
      _entries[pid]!.renderRevision = _revision(item.renderPost);
    }
    for (final pid in _entries.keys.toList()) {
      if (!ids.contains(pid)) _entries.remove(pid)?.dispose();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    scrollController.dispose();
    imageViewport.dispose();
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
    _projection = null;
  }
}

class ComicCommentPostPresentation extends ChangeNotifier {
  ComicCommentPostPresentation({this.sourceRevision = 0});

  final int sourceRevision;
  int? renderRevision;
  bool ratingsExpanded = true;
  bool commentsExpanded = true;
  final body = ThreadPostBodyPresentation();
  final _imageSizes = <String, Size>{};
  ThreadPostRatingsViewState ratings = const ThreadPostRatingsViewState.idle();
  ThreadPostRatingsViewState displayRatings =
      const ThreadPostRatingsViewState.idle();
  int _conversionGeneration = 0;
  Object? _conversionIdentity;
  bool _disposed = false;

  double? imageAspectRatio(String cacheKey) =>
      _imageSizes[cacheKey]?.aspectRatio;

  void recordImageSize(String cacheKey, Size size) {
    if (!_disposed &&
        size.width > 0 &&
        size.height > 0 &&
        size.width.isFinite &&
        size.height.isFinite) {
      _imageSizes[cacheKey] = size;
    }
  }

  Future<void> loadRatings(
    Future<ApiResult<ThreadPostRatingDetails>> Function() load,
  ) async {
    if (_disposed ||
        ratings.status == ThreadPostRatingsLoadStatus.loading ||
        ratings.status == ThreadPostRatingsLoadStatus.loaded) {
      return;
    }
    ratings = displayRatings = const ThreadPostRatingsViewState.loading();
    notifyListeners();
    try {
      final result = await load();
      if (_disposed) return;
      ratings = displayRatings = switch (result) {
        ApiSuccess<ThreadPostRatingDetails>(:final data) =>
          ThreadPostRatingsViewState.loaded(data),
        _ => _ratingsFailure,
      };
    } catch (_) {
      if (_disposed) return;
      ratings = displayRatings = _ratingsFailure;
    }
    notifyListeners();
  }

  Future<void> convertRatings({
    required Object identity,
    required Future<ThreadPostRatingDetails> Function(ThreadPostRatingDetails)
    convert,
  }) async {
    final details = ratings.details;
    if (_disposed || details == null || _conversionIdentity == identity) return;
    _conversionIdentity = identity;
    final generation = ++_conversionGeneration;
    try {
      final result = await convert(details);
      if (_disposed || generation != _conversionGeneration) return;
      displayRatings = ThreadPostRatingsViewState.loaded(result);
    } catch (_) {
      if (_disposed || generation != _conversionGeneration) return;
      displayRatings = ratings;
    }
    notifyListeners();
  }

  static const _ratingsFailure = ThreadPostRatingsViewState.failureWith(
    ThreadActionFailure(
      code: ThreadUiErrorCode.unknown,
      action: ThreadActionKind.ratings,
    ),
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    body.dispose();
    _imageSizes.clear();
    super.dispose();
  }
}
