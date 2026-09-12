import 'dart:async';

import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

enum MessageRefreshKind { messages, notifications }

/// Only invalidation identities cross this boundary, never private payloads.
final class MessageRefreshEvent {
  const MessageRefreshEvent({
    required this.accountId,
    required this.kind,
    this.target,
    this.directoryOnly = false,
  });
  final String accountId;
  final MessageRefreshKind kind;
  final ForumConversationTarget? target;

  /// Reading a conversation updates unread markers without reloading itself.
  final bool directoryOnly;
}

/// Local writes and future push adapters share the same account-scoped signal.
final class MessageRefreshBus {
  final _events = StreamController<MessageRefreshEvent>.broadcast(sync: true);
  Stream<MessageRefreshEvent> get events => _events.stream;

  void publish(MessageRefreshEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void dispose() {
    unawaited(_events.close());
  }
}
