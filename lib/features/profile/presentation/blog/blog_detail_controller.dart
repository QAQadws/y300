import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef BlogDetailRead =
    DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>;

@immutable
final class UserBlogDetailPageState {
  const UserBlogDetailPageState({
    required this.query,
    this.data,
    this.capabilities,
    this.failure,
    this.isLoading = false,
    this.firstCommentPage = 1,
  });

  final UserBlogDetailQuery query;
  final UserBlogDetailData? data;
  final UserBlogDetailReadCapabilities? capabilities;
  final DataReadFailure<UserBlogDetailData, UserBlogDetailReadCapabilities>?
  failure;
  final bool isLoading;
  final int firstCommentPage;

  bool get canLoadNext =>
      !isLoading &&
      query.commentId == null &&
      data?.commentPagination.hasNext == true;
}

/// One route owns one read session. Comment paging keeps the displayed article
/// and its image widgets in place until the new response is available.
final class ProfileBlogDetailController
    extends ValueNotifier<UserBlogDetailPageState> {
  ProfileBlogDetailController({
    required UserBlogDetailRepository repository,
    required UserBlogDetailQuery query,
  }) : _repository = repository,
       _initialQuery = query,
       super(UserBlogDetailPageState(query: query));

  final UserBlogDetailRepository _repository;
  final UserBlogDetailQuery _initialQuery;
  ForumRequestCancellation? _cancellation;
  Future<void>? _pending;
  bool _disposed = false;
  bool _active = false;
  bool _refreshing = false;
  bool _deleted = false;
  UserBlogDetailQuery? _refreshQuery;
  int _generation = 0;

  Future<void> setActive(bool active) {
    if (_disposed) return Future.value();
    _active = active;
    if (!active) {
      _cancel();
      if (value.isLoading) {
        value = UserBlogDetailPageState(
          query: value.query,
          data: value.data,
          capabilities: value.capabilities,
          firstCommentPage: value.firstCommentPage,
        );
      }
      return Future.value();
    }
    if (_pending != null) return _pending!;
    if (_refreshQuery != null && !_deleted) {
      return _load(_refreshQuery!, refresh: true);
    }
    return value.data == null && value.failure == null
        ? _load(value.query)
        : Future.value();
  }

  Future<void> refresh() {
    if (!_active || _disposed || _deleted) return Future.value();
    if (_pending != null) {
      if (_refreshing || value.data == null) return _pending!;
      _cancel();
    }
    return _load(_initialQuery, refresh: true);
  }

  Future<void> loadNextComments() => !_active || _disposed || !value.canLoadNext
      ? Future.value()
      : _load(
          _query(page: value.data!.commentPagination.currentPage + 1),
          append: true,
        );

  Future<void> selectCommentPage(int page, {bool refresh = false}) {
    if (!_active || _disposed || _deleted || page < 1) return Future.value();
    _cancel();
    return _load(_query(page: page), refresh: refresh);
  }

  Future<void> loadLastComments() {
    if (!_active || _disposed || _deleted) return Future.value();
    _cancel();
    return _load(_query(last: true), refresh: true);
  }

  Future<void> invalidate({bool deleted = false}) {
    if (_disposed || _deleted) return Future.value();
    _cancel();
    _deleted = deleted;
    if (deleted) {
      _refreshQuery = null;
      value = UserBlogDetailPageState(
        query: value.query,
        failure: const DataReadFailure(
          kind: DataReadFailureKind.business,
          code: 'user_blog_unavailable',
          diagnosticMessage: 'user_blog_unavailable',
        ),
      );
      return Future.value();
    }
    _refreshQuery = _initialQuery;
    return setActive(_active);
  }

  /// The editor can return before this route becomes current again. Defer its
  /// precise comment destination until activation instead of dropping refresh.
  Future<void> refreshAfterComment(UserBlogCommentAction action) {
    if (_disposed || _deleted) return Future.value();
    _cancel();
    _refreshQuery =
        action == UserBlogCommentAction.add ||
            action == UserBlogCommentAction.reply
        ? _query(last: true)
        : _query(page: value.firstCommentPage);
    return setActive(_active);
  }

  Future<void> _load(
    UserBlogDetailQuery query, {
    bool refresh = false,
    bool append = false,
  }) {
    final previous = value;
    final generation = ++_generation;
    final cancellation = ForumRequestCancellation();
    _cancellation = cancellation;
    _refreshing = refresh;
    value = UserBlogDetailPageState(
      query: previous.query,
      data: previous.data,
      capabilities: previous.capabilities,
      firstCommentPage: previous.firstCommentPage,
      isLoading: true,
    );
    return _pending = _perform(query, cancellation, refresh: refresh).then((
      result,
    ) {
      if (_disposed || generation != _generation || cancellation.isCancelled) {
        return;
      }
      _pending = null;
      _cancellation = null;
      if (result case DataReadSuccess(:final data, :final capabilities)) {
        _refreshQuery = null;
        value = UserBlogDetailPageState(
          query: query,
          data: append && previous.data != null
              ? _append(previous.data!, data)
              : data,
          capabilities: capabilities,
          firstCommentPage: append
              ? previous.firstCommentPage
              : data.commentPagination.currentPage,
        );
      } else {
        final failure = result.failureOrNull!;
        final retain = !{
          DataReadFailureKind.unauthorized,
          DataReadFailureKind.business,
        }.contains(failure.kind);
        value = UserBlogDetailPageState(
          query: previous.query,
          data: retain ? previous.data : null,
          capabilities: retain ? previous.capabilities : null,
          failure: failure,
          firstCommentPage: previous.firstCommentPage,
        );
      }
    });
  }

  Future<BlogDetailRead> _perform(
    UserBlogDetailQuery query,
    ForumRequestCancellation cancellation, {
    required bool refresh,
  }) async {
    try {
      return await _repository.load(
        query,
        cancellation: cancellation,
        cachePolicy: refresh
            ? CacheLoadPolicy.networkFirst
            : CacheLoadPolicy.cacheFirst,
      );
    } catch (_) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unknown,
        code: 'blog_read_failed',
        diagnosticMessage: 'blog_read_failed',
      );
    }
  }

  UserBlogDetailQuery _query({int page = 1, bool last = false}) =>
      UserBlogDetailQuery(
        ownerUserId: _initialQuery.ownerUserId,
        blogId: _initialQuery.blogId,
        page: page,
        lastCommentPage: last,
      );

  void _cancel() {
    ++_generation;
    _cancellation?.cancel();
    _cancellation = null;
    _pending = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    super.dispose();
  }
}

UserBlogDetailData _append(
  UserBlogDetailData previous,
  UserBlogDetailData next,
) => UserBlogDetailData(
  blogId: previous.blogId,
  ownerUserId: previous.ownerUserId,
  title: previous.title,
  bodyHtml: previous.bodyHtml,
  authorName: previous.authorName,
  avatarUrl: previous.avatarUrl,
  publishedAtText: previous.publishedAtText,
  viewCount: next.viewCount,
  commentCount: next.commentCount,
  commentsOpen: next.commentsOpen,
  actions: next.actions,
  commentPagination: next.commentPagination,
  comments: List.unmodifiable(
    {
      for (final item in [...previous.comments, ...next.comments])
        item.commentId: item,
    }.values,
  ),
);
