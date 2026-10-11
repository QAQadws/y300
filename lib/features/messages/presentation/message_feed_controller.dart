import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

enum MessageFeedOperation { idle, refresh, more }

/// Captured at an active read's start and invoked after its business success.
typedef MessageFeedReadCompletion<P> = void Function(P data);

@immutable
final class MessageFeedState<P> {
  const MessageFeedState({
    this.data,
    this.failure,
    this.operation = MessageFeedOperation.idle,
    this.failedOperation,
  });
  final P? data;
  final DataReadFailure<P, Object?>? failure;
  final MessageFeedOperation operation;
  final MessageFeedOperation? failedOperation;
  bool get isBusy => operation != MessageFeedOperation.idle;
  bool get isInitialLoading =>
      data == null && operation == MessageFeedOperation.refresh;
}

/// Pagination and refresh lifecycle shared by the three independent feeds.
/// Instances belong to one account and feed; disposal invalidates every task.
final class MessageFeedController<P>
    extends ValueNotifier<MessageFeedState<P>> {
  MessageFeedController({
    required this.initialPage,
    required this.load,
    required this.nextPage,
    required this.mergeMore,
    this.mergeRefresh,
    this.captureActiveRead,
  }) : super(MessageFeedState<P>());

  final int initialPage;
  final Future<DataReadResult<P, Object?>> Function(
    int page,
    ForumRequestCancellation cancellation,
  )
  load;
  final int? Function(P data) nextPage;
  final P Function(P current, P next) mergeMore;
  final P Function(P current, P next)? mergeRefresh;

  /// Captures immutable ownership for optional read-side effects. Hidden reads,
  /// cache playback and an activity lifetime that ended cannot complete it.
  final MessageFeedReadCompletion<P>? Function()? captureActiveRead;

  bool _disposed = false;
  final Set<Object> _activeOwners = {};
  final Object _defaultOwner = Object();
  bool get _active => _activeOwners.isNotEmpty;
  bool _dirty = false;
  int _generation = 0;
  int _activityGeneration = 0;
  ForumRequestCancellation? _cancellation;
  Future<void>? _pending;

  bool get hasMore => value.data != null && nextPage(value.data as P) != null;

  void setActive(bool active, {Object? owner}) {
    if (_disposed) return;
    final wasActive = _active;
    final identity = owner ?? _defaultOwner;
    if (active) {
      _activeOwners.add(identity);
    } else {
      _activeOwners.remove(identity);
    }
    if (wasActive == _active) return;
    ++_activityGeneration;
    if (active &&
        (_dirty || (value.data == null && value.failure == null)) &&
        !value.isBusy) {
      unawaited(refresh());
    }
  }

  /// Signals received during a read coalesce into one subsequent fresh read.
  /// Hidden feeds defer this work until actually visited, preserving read state.
  void invalidate() {
    if (_disposed) return;
    _dirty = true;
    if (_active && !value.isBusy) unawaited(refresh());
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (value.operation == MessageFeedOperation.refresh) {
      return _pending ?? Future.value();
    }
    _dirty = false;
    return _start(initialPage, MessageFeedOperation.refresh);
  }

  Future<void> loadMore() {
    if (_disposed || value.isBusy) return _pending ?? Future.value();
    final data = value.data;
    final page = data == null ? null : nextPage(data);
    if (page == null) return Future.value();
    return _start(page, MessageFeedOperation.more);
  }

  Future<void> _start(int page, MessageFeedOperation operation) {
    _cancellation?.cancel();
    final cancellation = _cancellation = ForumRequestCancellation();
    final generation = ++_generation;
    final activityGeneration = _activityGeneration;
    MessageFeedReadCompletion<P>? completionObserver;
    if (_active) {
      try {
        completionObserver = captureActiveRead?.call();
      } on Object {
        // Optional observation never prevents the underlying business read.
      }
    }
    // Install the shared future before notifying, so a reentrant refresh joins
    // this operation instead of starting another read.
    final completion = Completer<void>();
    _pending = completion.future;
    value = MessageFeedState(data: value.data, operation: operation);
    unawaited(
      _run(
        page,
        operation,
        generation,
        cancellation,
        activityGeneration,
        completionObserver,
      ).whenComplete(() => completion.complete()),
    );
    return completion.future;
  }

  Future<void> _run(
    int page,
    MessageFeedOperation operation,
    int generation,
    ForumRequestCancellation cancellation,
    int activityGeneration,
    MessageFeedReadCompletion<P>? completionObserver,
  ) async {
    try {
      final result = await load(page, cancellation);
      if (_disposed || generation != _generation) return;
      switch (result) {
        case DataReadSuccess<P, Object?>(:final data, :final metadata):
          final previous = value.data;
          final merged = previous == null
              ? data
              : operation == MessageFeedOperation.more
              ? mergeMore(previous, data)
              : mergeRefresh?.call(previous, data) ?? data;
          if (!cancellation.isCancelled &&
              _active &&
              activityGeneration == _activityGeneration &&
              metadata.origin == DataReadOrigin.network &&
              metadata.freshness == DataReadFreshness.current) {
            try {
              completionObserver?.call(data);
            } on Object {
              // A consumption/calibration observer cannot turn success into
              // a feed error or expose any response payload.
            }
          }
          if (_disposed || generation != _generation) return;
          value = MessageFeedState(data: merged);
        case DataReadFailure<P, Object?>():
          value = MessageFeedState(
            data: result.kind == DataReadFailureKind.unauthorized
                ? null
                : value.data,
            failure: result,
            failedOperation: operation,
          );
      }
    } on Object {
      if (_disposed || generation != _generation) return;
      value = MessageFeedState(
        data: value.data,
        failedOperation: operation,
        failure: DataReadFailure<P, Object?>(
          kind: DataReadFailureKind.unknown,
          code: 'message_read_failed',
          diagnosticMessage: 'message_read_failed',
        ),
      );
    } finally {
      if (!_disposed && generation == _generation) {
        _pending = null;
        if (_dirty && _active) unawaited(refresh());
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _cancellation?.cancel();
    super.dispose();
  }
}
