import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef UserThreadDirectoryRead =
    DataReadResult<
      UserThreadDirectoryData,
      UserThreadDirectoryReadCapabilities
    >;

enum UserThreadReadOperation { idle, refresh, more }

@immutable
final class UserThreadPageArgs {
  const UserThreadPageArgs({
    this.userId,
    this.initialType = UserThreadDirectoryType.threads,
    this.initialPage = 1,
    this.routeOwner,
  }) : assert(initialPage >= 1);

  final String? userId;
  final UserThreadDirectoryType initialType;
  final int initialPage;
  final Object? routeOwner;

  @override
  bool operator ==(Object other) =>
      other is UserThreadPageArgs &&
      userId == other.userId &&
      initialType == other.initialType &&
      initialPage == other.initialPage &&
      routeOwner == other.routeOwner;

  @override
  int get hashCode => Object.hash(userId, initialType, initialPage, routeOwner);
}

@immutable
final class UserThreadPageState {
  const UserThreadPageState({
    required this.query,
    this.data,
    this.capabilities,
    this.failure,
    this.operation = UserThreadReadOperation.idle,
    this.failedOperation,
  });

  final UserThreadDirectoryQuery query;
  final UserThreadDirectoryData? data;
  final UserThreadDirectoryReadCapabilities? capabilities;
  final DataReadFailure<
    UserThreadDirectoryData,
    UserThreadDirectoryReadCapabilities
  >?
  failure;
  final UserThreadReadOperation operation;
  final UserThreadReadOperation? failedOperation;

  bool get isBusy => operation != UserThreadReadOperation.idle;
  bool get hasMore => data?.pagination.hasNext == true;

  UserThreadPageState waiting(UserThreadReadOperation operation) =>
      UserThreadPageState(
        query: query,
        data: data,
        capabilities: capabilities,
        operation: operation,
      );
}

/// Owns one route and authenticated session. Only the selected, visible tab
/// reads; cancelled responses cannot update either retained tab.
final class UserThreadController extends ValueNotifier<UserThreadPageState> {
  UserThreadController({
    required UserThreadDirectoryRepository repository,
    required this.viewerUserId,
    required UserThreadPageArgs args,
  }) : _repository = repository,
       userId = args.userId ?? viewerUserId ?? '',
       super(
         UserThreadPageState(
           query: UserThreadDirectoryQuery(
             userId: args.userId ?? viewerUserId ?? '',
             viewerUserId: viewerUserId,
             type: args.initialType,
             page: args.initialPage,
           ),
         ),
       );

  final UserThreadDirectoryRepository _repository;
  final String? viewerUserId;
  final String userId;
  final _retained = <UserThreadDirectoryType, UserThreadPageState>{};
  ForumRequestCancellation? _cancellation;
  Future<void>? _pending;
  bool _active = false;
  bool _disposed = false;
  int _generation = 0;

  UserThreadPageState stateForType(UserThreadDirectoryType type) =>
      type == value.query.type
      ? value
      : _retained[type] ??
            UserThreadPageState(
              query: UserThreadDirectoryQuery(
                userId: userId,
                viewerUserId: viewerUserId,
                type: type,
              ),
            );

  Future<void> setActive(bool active) {
    if (_disposed) return Future.value();
    _active = active;
    if (!active) {
      _cancel();
      if (value.isBusy) value = value.waiting(UserThreadReadOperation.idle);
      return Future.value();
    }
    if (_pending != null) return _pending!;
    return value.data == null && value.failure == null
        ? _load(value.query, UserThreadReadOperation.refresh)
        : Future.value();
  }

  Future<void> selectType(UserThreadDirectoryType type) {
    if (_disposed || type == value.query.type) return Future.value();
    _cancel();
    // Returning to a failed tab must not silently resume automatic paging.
    _retained[value.query.type] = value.isBusy
        ? value.waiting(UserThreadReadOperation.idle)
        : value;
    value = stateForType(type);
    return setActive(_active);
  }

  Future<void> refresh() {
    if (_disposed || !_active) return Future.value();
    if (value.operation == UserThreadReadOperation.refresh) {
      return _pending ?? Future.value();
    }
    return _load(_page(value.query, 1), UserThreadReadOperation.refresh);
  }

  Future<void> loadMore() {
    if (_disposed || !_active || value.isBusy || !value.hasMore) {
      return _pending ?? Future.value();
    }
    return _load(
      _page(value.query, value.data!.pagination.currentPage + 1),
      UserThreadReadOperation.more,
    );
  }

  Future<void> retry() {
    if (value.failedOperation == UserThreadReadOperation.more &&
        value.data != null) {
      return loadMore();
    }
    if (_disposed || !_active || value.isBusy) {
      return _pending ?? Future.value();
    }
    // A failed URL page must retry that page; explicit refresh starts at one.
    return _load(
      _page(value.query, value.data == null ? value.query.page : 1),
      UserThreadReadOperation.refresh,
    );
  }

  Future<void> _load(
    UserThreadDirectoryQuery query,
    UserThreadReadOperation operation,
  ) {
    _cancel();
    final previous = value;
    final generation = _generation;
    final cancellation = _cancellation = ForumRequestCancellation();
    final completion = Completer<void>();
    // Install the future before notifying listeners so refresh remains
    // single-flight even when a listener synchronously requests it again.
    _pending = completion.future;
    value = UserThreadPageState(
      query: previous.data == null ? query : previous.query,
      data: previous.data,
      capabilities: previous.capabilities,
      operation: operation,
    );
    unawaited(
      _run(
        query,
        operation,
        previous,
        generation,
        cancellation,
      ).whenComplete(completion.complete),
    );
    return completion.future;
  }

  Future<void> _run(
    UserThreadDirectoryQuery query,
    UserThreadReadOperation operation,
    UserThreadPageState previous,
    int generation,
    ForumRequestCancellation cancellation,
  ) async {
    final result = await _perform(query, cancellation);
    if (_disposed || generation != _generation || cancellation.isCancelled) {
      return;
    }
    _pending = null;
    _cancellation = null;
    if (result case DataReadSuccess(:final data, :final capabilities)) {
      value = UserThreadPageState(
        query: _page(query, data.pagination.currentPage),
        data: operation == UserThreadReadOperation.more && previous.data != null
            ? _mergeMore(previous.data!, data)
            : data,
        capabilities: operation == UserThreadReadOperation.more
            ? previous.capabilities?.intersect(capabilities) ?? capabilities
            : capabilities,
      );
    } else {
      final failure = result.failureOrNull!;
      final retain = !{
        DataReadFailureKind.unauthorized,
        DataReadFailureKind.business,
      }.contains(failure.kind);
      // Access rejection invalidates both tabs, including retained content.
      if (!retain) _retained.clear();
      value = UserThreadPageState(
        query: retain && previous.data != null ? previous.query : query,
        data: retain ? previous.data : null,
        capabilities: retain ? previous.capabilities : null,
        failure: failure,
        failedOperation: operation,
      );
    }
  }

  Future<UserThreadDirectoryRead> _perform(
    UserThreadDirectoryQuery query,
    ForumRequestCancellation cancellation,
  ) async {
    if (viewerUserId == null) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'user_thread_login_required',
        diagnosticMessage: 'user_thread_login_required',
      );
    }
    if (!RegExp(r'^[1-9]\d*$').hasMatch(query.userId)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'user_thread_invalid_user',
        diagnosticMessage: 'user_thread_invalid_user',
      );
    }
    try {
      return await _repository.load(
        query,
        cachePolicy: CacheLoadPolicy.networkFirst,
        cancellation: cancellation,
      );
    } catch (_) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unknown,
        code: 'user_thread_read_failed',
        diagnosticMessage: 'user_thread_read_failed',
      );
    }
  }

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
    _retained.clear();
    super.dispose();
  }
}

UserThreadDirectoryQuery _page(UserThreadDirectoryQuery query, int page) =>
    UserThreadDirectoryQuery(
      userId: query.userId,
      viewerUserId: query.viewerUserId,
      type: query.type,
      page: page,
    );

UserThreadDirectoryData _mergeMore(
  UserThreadDirectoryData current,
  UserThreadDirectoryData next,
) {
  final items = <String, UserThreadSummary>{
    for (final item in current.items) item.threadId: item,
  };
  for (final item in next.items) {
    final previous = items[item.threadId];
    if (previous == null) {
      items[item.threadId] = item;
      continue;
    }
    // Replies to one thread can straddle directory pages. Merge by PID rather
    // than discarding the repeated TID or collapsing separate replies.
    final previews = <String, UserThreadReplyPreview>{
      for (final preview in previous.replyPreviews) preview.postId: preview,
      for (final preview in item.replyPreviews) preview.postId: preview,
    };
    items[item.threadId] = UserThreadSummary(
      threadId: item.threadId,
      title: item.title,
      uri: item.uri,
      authorName: item.authorName,
      authorUserId: item.authorUserId,
      avatarUrl: item.avatarUrl,
      publishedAtText: item.publishedAtText,
      excerpt: item.excerpt,
      forumId: item.forumId,
      forumName: item.forumName,
      views: item.views,
      replies: item.replies,
      images: item.images,
      replyPreviews: previews.values.toList(growable: false),
    );
  }
  return UserThreadDirectoryData(
    items: items.values.toList(growable: false),
    pagination: next.pagination,
  );
}
