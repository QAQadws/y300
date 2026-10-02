import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/domain/message_refresh_bus.dart';
import 'package:y300/features/messages/domain/private_message_compose_repository.dart';
import 'package:y300/features/messages/domain/private_message_recipient_selection.dart';

enum PrivateMessageBatchSendAttempt {
  completed,
  confirmationRequired,
  invalid,
  busy,
  inactive,
}

@immutable
final class PrivateMessageBatchSnapshot {
  PrivateMessageBatchSnapshot({
    required List<String> usernames,
    required this.message,
  }) : usernames = List.unmodifiable(usernames);

  final List<String> usernames;
  final String message;
}

@immutable
final class PrivateMessageBatchSendState {
  const PrivateMessageBatchSendState({
    this.isSending = false,
    this.snapshot,
    this.result,
  });

  final bool isSending;
  final PrivateMessageBatchSnapshot? snapshot;
  final DataCommandResult<ForumPrivateMessageBatchReceipt>? result;

  bool get repeatRequiresConfirmation =>
      result is DataCommandOutcomeUnknown<ForumPrivateMessageBatchReceipt> ||
      result is DataCommandApplied<ForumPrivateMessageBatchReceipt>;
}

/// One compose route's write coordinator. Each invocation sends at most one
/// server command; an inconclusive write always requires a separate user act.
final class PrivateMessageBatchSendController
    extends ValueNotifier<PrivateMessageBatchSendState> {
  PrivateMessageBatchSendController({
    required this.accountId,
    required this.currentAccountId,
    required this.repository,
    required this.refreshBus,
  }) : super(const PrivateMessageBatchSendState());

  final String accountId;
  final String? Function() currentAccountId;
  final PrivateMessageComposeRepository repository;
  final MessageRefreshBus refreshBus;

  ForumRequestCancellation? _cancellation;
  List<String>? _lastAppliedUsernames;
  bool _hasUnresolvedUnknown = false;
  bool _disposed = false;
  int _generation = 0;

  bool get _ownsAccount => !_disposed && currentAccountId() == accountId;

  Future<PrivateMessageBatchSendAttempt> send({
    required List<String> usernames,
    required String message,
    bool confirmedRepeat = false,
  }) async {
    if (!_ownsAccount) return PrivateMessageBatchSendAttempt.inactive;
    if (value.isSending) return PrivateMessageBatchSendAttempt.busy;
    final selection = PrivateMessageRecipientSelection();
    for (final username in usernames) {
      if (selection.addUsername(username) !=
          AddPrivateMessageRecipientResult.added) {
        return PrivateMessageBatchSendAttempt.invalid;
      }
    }
    if (selection.isEmpty || message.trim().isEmpty) {
      return PrivateMessageBatchSendAttempt.invalid;
    }
    final nextUsernames = selection.usernameSnapshot();
    final lastApplied = _lastAppliedUsernames;
    final repeatApplied =
        lastApplied != null &&
        lastApplied.length == nextUsernames.length &&
        nextUsernames.every(lastApplied.contains);
    if (!confirmedRepeat && (_hasUnresolvedUnknown || repeatApplied)) {
      return PrivateMessageBatchSendAttempt.confirmationRequired;
    }

    final snapshot = PrivateMessageBatchSnapshot(
      usernames: nextUsernames,
      message: message,
    );
    final generation = ++_generation;
    final cancellation = _cancellation = ForumRequestCancellation();
    value = PrivateMessageBatchSendState(isSending: true, snapshot: snapshot);
    DataCommandResult<ForumPrivateMessageBatchReceipt> result;
    try {
      result = await repository.sendBatch(
        ForumPrivateMessageBatchSubmission(
          usernames: snapshot.usernames,
          message: snapshot.message,
          cancellation: cancellation,
        ),
      );
    } on Object {
      // A thrown write cannot prove that the forum did not receive the POST.
      result = const DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.unknown,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'message_batch_send_failed',
          diagnosticMessage: 'message_batch_send_failed',
        ),
      );
    }
    if (!_ownsAccount || generation != _generation) {
      return PrivateMessageBatchSendAttempt.inactive;
    }
    value = PrivateMessageBatchSendState(snapshot: snapshot, result: result);
    if (result is DataCommandApplied<ForumPrivateMessageBatchReceipt>) {
      _lastAppliedUsernames = snapshot.usernames;
      // The aggregate receipt cannot identify which conversations received a
      // multi-recipient send. Only re-read the directory; insert no fake rows.
      refreshBus.publish(
        MessageRefreshEvent(
          accountId: accountId,
          kind: MessageRefreshKind.messages,
          directoryOnly: true,
        ),
      );
    } else if (result
        is DataCommandOutcomeUnknown<ForumPrivateMessageBatchReceipt>) {
      _hasUnresolvedUnknown = true;
    }
    return PrivateMessageBatchSendAttempt.completed;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _cancellation?.cancel();
    super.dispose();
  }
}
