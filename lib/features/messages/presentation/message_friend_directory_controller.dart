import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/domain/private_message_compose_repository.dart';

enum MessageFriendDirectoryOperation { idle, debouncing, firstPage, more }

@immutable
final class MessageFriendDirectoryState {
  const MessageFriendDirectoryState({
    this.query = '',
    this.items = const [],
    this.page = 0,
    this.perPage = 0,
    this.count = 0,
    this.operation = MessageFriendDirectoryOperation.idle,
    this.failure,
    this.failedOperation,
  });

  final String query;
  final List<ForumFriendDirectoryItem> items;
  final int page;
  final int perPage;
  final int count;
  final MessageFriendDirectoryOperation operation;
  final DataReadFailure<
    ForumFriendDirectoryPage,
    ForumFriendDirectoryReadCapabilities
  >?
  failure;
  final MessageFriendDirectoryOperation? failedOperation;

  bool get isBusy => operation != MessageFriendDirectoryOperation.idle;
  bool get hasMore => page > 0 && perPage > 0 && page * perPage < count;
}

/// One sheet's cancellable friend search. Recipient selection lives outside it
/// so filter changes never discard the compose route's selected people.
final class MessageFriendDirectoryController
    extends ValueNotifier<MessageFriendDirectoryState> {
  MessageFriendDirectoryController({
    required this.accountId,
    required this.currentAccountId,
    required this.repository,
    this.searchDebounce = const Duration(milliseconds: 300),
  }) : super(const MessageFriendDirectoryState());

  final String accountId;
  final String? Function() currentAccountId;
  final PrivateMessageComposeRepository repository;
  final Duration searchDebounce;

  Timer? _searchTimer;
  ForumRequestCancellation? _cancellation;
  Future<void>? _pending;
  int _generation = 0;
  bool _started = false;
  bool _disposed = false;

  bool get _ownsAccount => !_disposed && currentAccountId() == accountId;

  Future<void> initialize() {
    if (_started || !_ownsAccount) return Future.value();
    _started = true;
    return refresh();
  }

  void setSearchQuery(String rawQuery) {
    if (!_ownsAccount) return;
    final query = rawQuery.trim();
    if (query == value.query) return;
    _searchTimer?.cancel();
    _cancellation?.cancel();
    ++_generation;
    value = MessageFriendDirectoryState(
      query: query,
      operation: MessageFriendDirectoryOperation.debouncing,
    );
    _searchTimer = Timer(searchDebounce, () {
      if (_ownsAccount) unawaited(refresh());
    });
  }

  Future<void> refresh() {
    if (!_ownsAccount) return Future.value();
    if (value.operation == MessageFriendDirectoryOperation.firstPage) {
      return _pending ?? Future.value();
    }
    _searchTimer?.cancel();
    _started = true;
    return _start(
      page: 1,
      operation: MessageFriendDirectoryOperation.firstPage,
    );
  }

  Future<void> loadMore() {
    if (!_ownsAccount || value.isBusy || !value.hasMore) {
      return _pending ?? Future.value();
    }
    return _start(
      page: value.page + 1,
      operation: MessageFriendDirectoryOperation.more,
    );
  }

  Future<void> _start({
    required int page,
    required MessageFriendDirectoryOperation operation,
  }) {
    _cancellation?.cancel();
    final cancellation = _cancellation = ForumRequestCancellation();
    final generation = ++_generation;
    final query = value.query;
    final completion = Completer<void>();
    _pending = completion.future;
    value = MessageFriendDirectoryState(
      query: query,
      items: value.items,
      page: value.page,
      perPage: value.perPage,
      count: value.count,
      operation: operation,
    );
    unawaited(
      _run(
        page,
        query,
        operation,
        generation,
        cancellation,
      ).whenComplete(completion.complete),
    );
    return completion.future;
  }

  Future<void> _run(
    int page,
    String query,
    MessageFriendDirectoryOperation operation,
    int generation,
    ForumRequestCancellation cancellation,
  ) async {
    try {
      final result = await repository.loadFriends(
        ForumFriendDirectoryQuery(
          page: page,
          username: query,
          cancellation: cancellation,
        ),
      );
      if (!_isCurrent(generation, query)) return;
      switch (result) {
        case DataReadSuccess<
          ForumFriendDirectoryPage,
          ForumFriendDirectoryReadCapabilities
        >(
          :final data,
        ):
          final responseOwner = data.currentUserId;
          if (responseOwner != null &&
              responseOwner.isNotEmpty &&
              responseOwner != accountId) {
            value = MessageFriendDirectoryState(
              query: query,
              failure: const DataReadFailure(
                kind: DataReadFailureKind.unauthorized,
                code: 'message_friend_account_changed',
                diagnosticMessage: 'message_friend_account_changed',
              ),
              failedOperation: operation,
            );
            return;
          }
          value = MessageFriendDirectoryState(
            query: query,
            items: operation == MessageFriendDirectoryOperation.more
                ? _mergeByUserId(value.items, data.items)
                : List.unmodifiable(data.items),
            page: data.page,
            perPage: data.perPage,
            count: data.count,
          );
        case DataReadFailure<
          ForumFriendDirectoryPage,
          ForumFriendDirectoryReadCapabilities
        >():
          value = MessageFriendDirectoryState(
            query: query,
            items: operation == MessageFriendDirectoryOperation.more
                ? value.items
                : const [],
            page: operation == MessageFriendDirectoryOperation.more
                ? value.page
                : 0,
            perPage: operation == MessageFriendDirectoryOperation.more
                ? value.perPage
                : 0,
            count: operation == MessageFriendDirectoryOperation.more
                ? value.count
                : 0,
            failure: result,
            failedOperation: operation,
          );
      }
    } on Object {
      if (!_isCurrent(generation, query)) return;
      value = MessageFriendDirectoryState(
        query: query,
        items: operation == MessageFriendDirectoryOperation.more
            ? value.items
            : const [],
        page: operation == MessageFriendDirectoryOperation.more
            ? value.page
            : 0,
        perPage: operation == MessageFriendDirectoryOperation.more
            ? value.perPage
            : 0,
        count: operation == MessageFriendDirectoryOperation.more
            ? value.count
            : 0,
        failure: const DataReadFailure(
          kind: DataReadFailureKind.unknown,
          code: 'message_friend_read_failed',
          diagnosticMessage: 'message_friend_read_failed',
        ),
        failedOperation: operation,
      );
    } finally {
      if (_isCurrent(generation, query)) _pending = null;
    }
  }

  bool _isCurrent(int generation, String query) =>
      _ownsAccount && generation == _generation && value.query == query;

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _searchTimer?.cancel();
    _cancellation?.cancel();
    super.dispose();
  }
}

List<ForumFriendDirectoryItem> _mergeByUserId(
  List<ForumFriendDirectoryItem> current,
  List<ForumFriendDirectoryItem> next,
) {
  final seen = <String>{};
  return List.unmodifiable([
    for (final friend in [...current, ...next])
      if (seen.add(friend.userId)) friend,
  ]);
}
