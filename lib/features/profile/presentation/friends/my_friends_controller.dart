import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

typedef FriendFeedRead =
    DataReadResult<ForumFriendFeedPage, ForumFriendFeedReadCapabilities>;

@immutable
final class MyFriendsPageArgs {
  const MyFriendsPageArgs({
    this.initialScope = ForumFriendFeedScope.friends,
    this.initialPage = 1,
    this.routeOwner,
  });

  final ForumFriendFeedScope initialScope;
  final int initialPage;
  final Object? routeOwner;

  @override
  bool operator ==(Object other) =>
      other is MyFriendsPageArgs &&
      initialScope == other.initialScope &&
      initialPage == other.initialPage &&
      routeOwner == other.routeOwner;

  @override
  int get hashCode => Object.hash(initialScope, initialPage, routeOwner);
}

@immutable
final class MyFriendsPageState {
  const MyFriendsPageState({
    required this.query,
    this.data,
    this.failure,
    this.isLoading = false,
    this.removingUserId,
    this.unverifiedRemovalUserIds = const {},
  });

  final ForumFriendFeedQuery query;
  final ForumFriendFeedPage? data;
  final DataReadFailure<ForumFriendFeedPage, ForumFriendFeedReadCapabilities>?
  failure;
  final bool isLoading;
  final String? removingUserId;
  final Set<String> unverifiedRemovalUserIds;

  bool get isRemoving => removingUserId != null;
  int get currentPage => data?.page ?? query.page;
  int? get lastPage => data?.totalPages;
  bool get canLoadPrevious => data != null && currentPage > 1 && !isLoading;
  bool get canLoadNext =>
      data?.hasNext == true &&
      !isLoading &&
      (lastPage == null || currentPage < lastPage!);
}

/// Retained pages belong to one route and verified session revision. Reading
/// another tab cancels only reads; a sent deletion is never replayed.
final class MyFriendsController extends ValueNotifier<MyFriendsPageState> {
  MyFriendsController({
    required ForumFriendFeedRepository repository,
    required ForumFriendRemovalCommand removalCommand,
    required this.owner,
    required VerifiedProfileOwner? Function() currentOwner,
    required MyFriendsPageArgs args,
  }) : _repository = repository,
       _removalCommand = removalCommand,
       _currentOwner = currentOwner,
       super(
         MyFriendsPageState(
           query: ForumFriendFeedQuery(
             accountUserId: owner?.uid ?? '',
             scope: args.initialScope,
             page: args.initialPage,
           ),
         ),
       );

  final ForumFriendFeedRepository _repository;
  final ForumFriendRemovalCommand _removalCommand;
  final VerifiedProfileOwner? owner;
  final VerifiedProfileOwner? Function() _currentOwner;
  final _retained = <ForumFriendFeedScope, MyFriendsPageState>{};
  final _stale = <ForumFriendFeedScope>{};
  final _unverified = <String>{};
  ForumRequestCancellation? _cancellation;
  ForumRequestCancellation? _writeCancellation;
  Future<void>? _pending;
  Future<DataCommandResult<ForumFriendRemovalReceipt>>? _writePending;
  String? _removingUserId;
  bool _active = false;
  bool _disposed = false;
  int _generation = 0;

  bool get isCurrentOwner => owner != null && _matchesOwner;
  bool get _matchesOwner => !_disposed && _currentOwner() == owner;
  bool get active => _active && _matchesOwner;

  MyFriendsPageState stateForScope(ForumFriendFeedScope scope) {
    final state = scope == value.query.scope ? value : _retained[scope];
    return _state(
      query:
          state?.query ??
          ForumFriendFeedQuery(accountUserId: owner?.uid ?? '', scope: scope),
      data: state?.data,
      failure: state?.failure,
      isLoading: scope == value.query.scope && value.isLoading,
    );
  }

  Future<void> setActive(bool active) {
    if (_disposed) return Future.value();
    _active = active;
    if (!active) {
      _cancelRead();
      if (value.isLoading) value = _stateFrom(value);
      return Future.value();
    }
    if (!_matchesOwner) return Future.value();
    if (_pending != null) return _pending!;
    if (_stale.contains(value.query.scope)) {
      return _load(_page(value.query, 1));
    }
    return value.data == null && value.failure == null
        ? _load(value.query)
        : Future.value();
  }

  Future<void> selectScope(ForumFriendFeedScope scope) {
    if (!_matchesOwner || scope == value.query.scope) return Future.value();
    _cancelRead();
    _retained[value.query.scope] = _stateFrom(value);
    value = stateForScope(scope);
    return setActive(_active);
  }

  Future<void> refresh() {
    if (!active) return Future.value();
    if (value.isLoading) return _pending ?? Future.value();
    return _load(value.query);
  }

  Future<void> loadPreviousPage() => loadPageNumber(value.currentPage - 1);
  Future<void> loadNextPage() => value.canLoadNext
      ? loadPageNumber(value.currentPage + 1)
      : Future.value();

  Future<void> loadPageNumber(int page) {
    if (!active ||
        value.isLoading ||
        page < 1 ||
        page == value.currentPage ||
        (value.lastPage != null && page > value.lastPage!)) {
      return _pending ?? Future.value();
    }
    return _load(_page(value.query, page));
  }

  Future<void> _load(ForumFriendFeedQuery query) {
    _cancelRead();
    final generation = _generation;
    final cancellation = _cancellation = ForumRequestCancellation();
    final previous = value;
    final completion = Completer<void>();
    _pending = completion.future;
    value = _state(query: query, data: previous.data, isLoading: true);
    unawaited(
      _runRead(
        query,
        previous,
        generation,
        cancellation,
      ).whenComplete(completion.complete),
    );
    return completion.future;
  }

  Future<void> _runRead(
    ForumFriendFeedQuery query,
    MyFriendsPageState previous,
    int generation,
    ForumRequestCancellation cancellation,
  ) async {
    final result = await _performRead(query, cancellation);
    if (!_matchesOwner ||
        generation != _generation ||
        cancellation.isCancelled) {
      return;
    }
    _pending = null;
    _cancellation = null;
    switch (result) {
      case DataReadSuccess(:final data):
        final fresh = result.metadata.freshness == DataReadFreshness.current;
        if (fresh) _stale.remove(query.scope);
        if (fresh && query.scope == ForumFriendFeedScope.friends) {
          // Only a fresh row proves the relationship still exists. Old retained
          // pages cannot unlock another delete after an uncertain submission.
          _unverified.removeAll(data.items.map((item) => item.userId));
        }
        value = _state(query: _page(query, data.page), data: data);
      case DataReadFailure():
        final retain = !{
          DataReadFailureKind.unauthorized,
          DataReadFailureKind.business,
        }.contains(result.kind);
        if (!retain) _retained.clear();
        value = _state(
          query: retain && previous.data != null ? previous.query : query,
          data: retain ? previous.data : null,
          failure: result,
        );
    }
  }

  Future<FriendFeedRead> _performRead(
    ForumFriendFeedQuery query,
    ForumRequestCancellation cancellation,
  ) async {
    if (owner == null) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'friends_login_required',
        diagnosticMessage: 'friends_login_required',
      );
    }
    try {
      final result = await _repository.load(
        ForumFriendFeedQuery(
          accountUserId: query.accountUserId,
          scope: query.scope,
          page: query.page,
          cancellation: cancellation,
        ),
        cachePolicy: CacheLoadPolicy.networkFirst,
      );
      final data = result.dataOrNull;
      if (data != null &&
          (data.currentUserId != owner!.uid ||
              data.scope != query.scope ||
              data.page != query.page)) {
        return const DataReadFailure(
          kind: DataReadFailureKind.unauthorized,
          code: 'friends_context_changed',
          diagnosticMessage: 'friends_context_changed',
        );
      }
      return result;
    } on Object {
      return const DataReadFailure(
        kind: DataReadFailureKind.unknown,
        code: 'friends_read_failed',
        diagnosticMessage: 'friends_read_failed',
      );
    }
  }

  Future<DataCommandResult<ForumFriendRemovalReceipt>> removeFriend(
    String userId,
  ) {
    if (_writePending != null && _removingUserId == userId) {
      return _writePending!;
    }
    final allowed =
        value.query.scope == ForumFriendFeedScope.friends &&
        (value.data?.items.any(
              (item) => item.userId == userId && item.canRemove,
            ) ??
            false);
    if (!active ||
        !isCurrentOwner ||
        !allowed ||
        value.isLoading ||
        _stale.contains(ForumFriendFeedScope.friends) ||
        _unverified.contains(userId) ||
        _writePending != null) {
      return Future.value(_notSent());
    }
    _cancelRead();
    _removingUserId = userId;
    final cancellation = _writeCancellation = ForumRequestCancellation();
    final completion =
        Completer<DataCommandResult<ForumFriendRemovalReceipt>>();
    _writePending = completion.future;
    value = _stateFrom(value);
    unawaited(_runRemoval(userId, cancellation).then(completion.complete));
    return completion.future;
  }

  Future<DataCommandResult<ForumFriendRemovalReceipt>> _runRemoval(
    String userId,
    ForumRequestCancellation cancellation,
  ) async {
    DataCommandResult<ForumFriendRemovalReceipt> result;
    try {
      result = await _removalCommand.execute(
        ForumFriendRemovalSubmission(
          actorUserId: owner!.uid,
          userId: userId,
          cancellation: cancellation,
        ),
      );
    } on Object {
      result = const DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.unknown,
          retryPolicy: DataCommandRetryPolicy.never,
          code: 'friends_removal_unknown',
          diagnosticMessage: 'friends_removal_unknown',
        ),
      );
    }
    if (!isCurrentOwner) return result;
    final receipt = result.receiptOrNull;
    if (receipt != null &&
        (receipt.actorUserId != owner!.uid || receipt.userId != userId)) {
      result = const DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.parse,
          retryPolicy: DataCommandRetryPolicy.never,
          code: 'friends_removal_context_changed',
          diagnosticMessage: 'friends_removal_context_changed',
        ),
      );
    }
    _writePending = null;
    _writeCancellation = null;
    _removingUserId = null;
    if (result is DataCommandOutcomeUnknown<ForumFriendRemovalReceipt>) {
      _unverified.add(userId);
    }
    if (result is DataCommandApplied<ForumFriendRemovalReceipt>) {
      _stale.add(ForumFriendFeedScope.friends);
      _retained.remove(ForumFriendFeedScope.friends);
    }
    value = _stateFrom(value);
    if (result is DataCommandApplied<ForumFriendRemovalReceipt> &&
        active &&
        value.query.scope == ForumFriendFeedScope.friends) {
      // A deletion can remove the last row of the last page. Restarting at one
      // avoids showing an invalid page cursor after the confirmed write.
      await _load(_page(value.query, 1));
    }
    return result;
  }

  MyFriendsPageState _state({
    required ForumFriendFeedQuery query,
    ForumFriendFeedPage? data,
    DataReadFailure<ForumFriendFeedPage, ForumFriendFeedReadCapabilities>?
    failure,
    bool isLoading = false,
  }) => MyFriendsPageState(
    query: query,
    data: data,
    failure: failure,
    isLoading: isLoading,
    removingUserId: _removingUserId,
    unverifiedRemovalUserIds: Set.unmodifiable(_unverified),
  );

  MyFriendsPageState _stateFrom(MyFriendsPageState state) => _state(
    // Cancelling a pending page keeps the page actually on screen. Its
    // requested cursor must not silently become the next refresh target.
    query: _page(state.query, state.currentPage),
    data: state.data,
    failure: state.failure,
  );

  void _cancelRead() {
    ++_generation;
    _cancellation?.cancel();
    _cancellation = null;
    _pending = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _cancelRead();
    _writeCancellation?.cancel();
    _retained.clear();
    _unverified.clear();
    super.dispose();
  }
}

ForumFriendFeedQuery _page(ForumFriendFeedQuery query, int page) =>
    ForumFriendFeedQuery(
      accountUserId: query.accountUserId,
      scope: query.scope,
      page: page,
    );

DataCommandNotSent<ForumFriendRemovalReceipt> _notSent() =>
    const DataCommandNotSent(
      DataCommandFailure(
        kind: DataCommandFailureKind.validation,
        retryPolicy: DataCommandRetryPolicy.never,
        code: 'friends_removal_unavailable',
        diagnosticMessage: 'friends_removal_unavailable',
      ),
    );
