import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef UserThreadDirectoryRead =
    DataReadResult<
      UserThreadDirectoryData,
      UserThreadDirectoryReadCapabilities
    >;

enum MyThreadReadOperation { idle, refresh, more }

@immutable
final class MyThreadPageArgs {
  const MyThreadPageArgs({
    this.initialType = UserThreadDirectoryType.threads,
    this.routeOwner,
  });

  final UserThreadDirectoryType initialType;
  final Object? routeOwner;

  @override
  bool operator ==(Object other) =>
      other is MyThreadPageArgs &&
      initialType == other.initialType &&
      routeOwner == other.routeOwner;

  @override
  int get hashCode => Object.hash(initialType, routeOwner);
}

@immutable
final class MyThreadPageState {
  const MyThreadPageState({
    required this.query,
    this.data,
    this.capabilities,
    this.failure,
    this.operation = MyThreadReadOperation.idle,
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
  final MyThreadReadOperation operation;
  final MyThreadReadOperation? failedOperation;

  bool get isBusy => operation != MyThreadReadOperation.idle;
  bool get hasMore => data?.pagination.hasNext == true;

  MyThreadPageState waiting(MyThreadReadOperation operation) =>
      MyThreadPageState(
        query: query,
        data: data,
        capabilities: capabilities,
        operation: operation,
      );
}

/// Owns one route and authenticated session. Only the selected, visible tab
/// reads; cancelled responses cannot update either retained tab.
final class MyThreadController extends ValueNotifier<MyThreadPageState> {
  MyThreadController({
    required UserThreadDirectoryRepository repository,
    required this.accountId,
    required MyThreadPageArgs args,
  }) : _repository = repository,
       super(
         MyThreadPageState(
           query: UserThreadDirectoryQuery(
             userId: accountId ?? '',
             type: args.initialType,
           ),
         ),
       );

  final UserThreadDirectoryRepository _repository;
  final String? accountId;
  final _retained = <UserThreadDirectoryType, MyThreadPageState>{};
  ForumRequestCancellation? _cancellation;
  Future<void>? _pending;
  bool _active = false;
  bool _disposed = false;
  int _generation = 0;

  MyThreadPageState stateForType(UserThreadDirectoryType type) =>
      type == value.query.type
      ? value
      : _retained[type] ??
            MyThreadPageState(
              query: UserThreadDirectoryQuery(
                userId: accountId ?? '',
                type: type,
              ),
            );

  Future<void> setActive(bool active) {
    if (_disposed) return Future.value();
    _active = active;
    if (!active) {
      _cancel();
      if (value.isBusy) value = value.waiting(MyThreadReadOperation.idle);
      return Future.value();
    }
    if (_pending != null) return _pending!;
    return value.data == null && value.failure == null
        ? _load(_page(value.query, 1), MyThreadReadOperation.refresh)
        : Future.value();
  }

  Future<void> selectType(UserThreadDirectoryType type) {
    if (_disposed || type == value.query.type) return Future.value();
    _cancel();
    _retained[value.query.type] = value.waiting(MyThreadReadOperation.idle);
    value = stateForType(type);
    return setActive(_active);
  }

  Future<void> refresh() {
    if (_disposed || !_active) return Future.value();
    if (value.operation == MyThreadReadOperation.refresh) {
      return _pending ?? Future.value();
    }
    return _load(_page(value.query, 1), MyThreadReadOperation.refresh);
  }

  Future<void> loadMore() {
    if (_disposed || !_active || value.isBusy || !value.hasMore) {
      return _pending ?? Future.value();
    }
    return _load(
      _page(value.query, value.data!.pagination.currentPage + 1),
      MyThreadReadOperation.more,
    );
  }

  Future<void> retry() => value.failedOperation == MyThreadReadOperation.more
      ? loadMore()
      : refresh();

  Future<void> _load(
    UserThreadDirectoryQuery query,
    MyThreadReadOperation operation,
  ) {
    _cancel();
    final previous = value;
    final generation = _generation;
    final cancellation = _cancellation = ForumRequestCancellation();
    final completion = Completer<void>();
    // Install the future before notifying listeners so refresh remains
    // single-flight even when a listener synchronously requests it again.
    _pending = completion.future;
    value = previous.waiting(operation);
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
    MyThreadReadOperation operation,
    MyThreadPageState previous,
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
      value = MyThreadPageState(
        query: _page(query, data.pagination.currentPage),
        data: operation == MyThreadReadOperation.more && previous.data != null
            ? _mergeMore(previous.data!, data)
            : data,
        capabilities: operation == MyThreadReadOperation.more
            ? previous.capabilities?.intersect(capabilities) ?? capabilities
            : capabilities,
      );
    } else {
      final failure = result.failureOrNull!;
      if (failure.kind == DataReadFailureKind.unauthorized) _retained.clear();
      final retain = !{
        DataReadFailureKind.unauthorized,
        DataReadFailureKind.business,
      }.contains(failure.kind);
      value = MyThreadPageState(
        query: previous.query,
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
    if (accountId == null) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'user_thread_login_required',
        diagnosticMessage: 'user_thread_login_required',
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
