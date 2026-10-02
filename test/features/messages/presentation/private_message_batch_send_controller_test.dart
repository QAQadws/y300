import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/domain/message_refresh_bus.dart';
import 'package:y300/features/messages/domain/private_message_compose_repository.dart';
import 'package:y300/features/messages/presentation/private_message_batch_send_controller.dart';

void main() {
  late _ComposeRepository repository;
  late MessageRefreshBus bus;
  late PrivateMessageBatchSendController controller;
  late List<MessageRefreshEvent> events;
  late String account;
  late bool disposed;

  setUp(() {
    repository = _ComposeRepository();
    bus = MessageRefreshBus();
    events = [];
    account = '10';
    disposed = false;
    controller = PrivateMessageBatchSendController(
      accountId: '10',
      currentAccountId: () => account,
      repository: repository,
      refreshBus: bus,
    );
    final subscription = bus.events.listen(events.add);
    addTearDown(() async {
      if (!disposed) controller.dispose();
      await subscription.cancel();
      bus.dispose();
    });
  });

  test(
    'captures immutable recipients and refreshes only after applied',
    () async {
      final usernames = ['Alice', 'Bob'];
      final pending = controller.send(
        usernames: usernames,
        message: 'Hi <b>all</b>',
      );
      expect(controller.value.isSending, isTrue);
      expect(repository.sends, hasLength(1));
      expect(events, isEmpty);
      expect(
        await controller.send(usernames: usernames, message: 'duplicate'),
        PrivateMessageBatchSendAttempt.busy,
      );
      usernames.add('Charlie');
      expect(repository.sends.single.submission.usernames, ['Alice', 'Bob']);
      expect(controller.value.snapshot!.usernames, ['Alice', 'Bob']);
      expect(
        () => controller.value.snapshot!.usernames.add('D'),
        throwsUnsupportedError,
      );

      repository.sends.single.result.complete(
        DataCommandApplied(
          ForumPrivateMessageBatchReceipt(
            usernames: ['Alice', 'Bob'],
            serverReportedAcceptedCount: 2,
            excludedUsernames: [],
          ),
        ),
      );
      expect(await pending, PrivateMessageBatchSendAttempt.completed);
      expect(controller.value.snapshot!.message, 'Hi <b>all</b>');
      expect(events, hasLength(1));
      expect(events.single.accountId, '10');
      expect(events.single.directoryOnly, isTrue);
      expect(events.single.target, isNull);
      expect(
        await controller.send(usernames: ['Alice', 'Bob'], message: 'Hi again'),
        PrivateMessageBatchSendAttempt.confirmationRequired,
      );
      expect(repository.sends, hasLength(1));
      final repeat = controller.send(
        usernames: ['Alice', 'Bob'],
        message: 'Hi again',
        confirmedRepeat: true,
      );
      expect(repository.sends, hasLength(2));
      repository.sends.last.result.complete(
        const DataCommandNotSent(
          DataCommandFailure(
            kind: DataCommandFailureKind.validation,
            retryPolicy: DataCommandRetryPolicy.afterInputChange,
            code: 'not_sent',
            diagnosticMessage: 'not_sent',
          ),
        ),
      );
      await repeat;
      expect(events, hasLength(1));
      expect(
        await controller.send(
          usernames: ['Bob', 'Alice'],
          message: 'third try',
        ),
        PrivateMessageBatchSendAttempt.confirmationRequired,
      );
      expect(repository.sends, hasLength(2));
    },
  );

  test(
    'unknown keeps snapshot and a repeat needs explicit confirmation',
    () async {
      final first = controller.send(usernames: ['Alice'], message: 'draft');
      repository.sends.single.result.complete(
        const DataCommandOutcomeUnknown(
          DataCommandFailure(
            kind: DataCommandFailureKind.timeout,
            retryPolicy: DataCommandRetryPolicy.explicitOnly,
            code: 'timeout',
            diagnosticMessage: 'timeout',
          ),
        ),
      );
      await first;
      expect(controller.value.repeatRequiresConfirmation, isTrue);
      expect(controller.value.snapshot!.message, 'draft');
      expect(events, isEmpty);
      expect(
        await controller.send(usernames: ['Alice'], message: 'draft'),
        PrivateMessageBatchSendAttempt.confirmationRequired,
      );
      expect(repository.sends, hasLength(1));

      final second = controller.send(
        usernames: ['Alice'],
        message: 'draft',
        confirmedRepeat: true,
      );
      expect(repository.sends, hasLength(2));
      repository.sends.last.result.complete(
        DataCommandApplied(
          ForumPrivateMessageBatchReceipt(
            usernames: ['Alice'],
            serverReportedAcceptedCount: 1,
            excludedUsernames: [],
          ),
        ),
      );
      await second;
      expect(
        controller.value.result!.receiptOrNull!.confirmsSingleRecipient,
        isTrue,
      );
      expect(events, hasLength(1));
    },
  );

  test(
    'not-sent leaves draft without publishing and can retry normally',
    () async {
      final first = controller.send(usernames: ['Alice'], message: 'draft');
      repository.sends.single.result.complete(
        const DataCommandNotSent(
          DataCommandFailure(
            kind: DataCommandFailureKind.validation,
            retryPolicy: DataCommandRetryPolicy.afterInputChange,
            code: 'invalid',
            diagnosticMessage: 'invalid',
          ),
        ),
      );
      await first;
      expect(controller.value.snapshot!.message, 'draft');
      expect(events, isEmpty);
      final second = controller.send(usernames: ['Alice'], message: 'revised');
      expect(repository.sends, hasLength(2));
      repository.sends.last.result.complete(const DataCommandUnsupported());
      await second;
      expect(events, isEmpty);
    },
  );

  test(
    'invalid input and a late old-account receipt cannot write UI state',
    () async {
      expect(
        await controller.send(usernames: ['Alice,Bob'], message: 'draft'),
        PrivateMessageBatchSendAttempt.invalid,
      );
      expect(repository.sends, isEmpty);
      final pending = controller.send(usernames: ['Alice'], message: 'draft');
      account = '11';
      controller.dispose();
      disposed = true;
      expect(
        repository.sends.single.submission.cancellation!.isCancelled,
        isTrue,
      );
      repository.sends.single.result.complete(
        DataCommandApplied(
          ForumPrivateMessageBatchReceipt(
            usernames: ['Alice'],
            serverReportedAcceptedCount: 1,
            excludedUsernames: [],
          ),
        ),
      );
      expect(await pending, PrivateMessageBatchSendAttempt.inactive);
      expect(events, isEmpty);
    },
  );
}

class _ComposeRepository implements PrivateMessageComposeRepository {
  final sends = <_BatchSend>[];

  @override
  Future<DataCommandResult<ForumPrivateMessageBatchReceipt>> sendBatch(
    ForumPrivateMessageBatchSubmission submission,
  ) {
    final send = _BatchSend(submission);
    sends.add(send);
    return send.result.future;
  }

  @override
  Future<FriendDirectoryRead> loadFriends(ForumFriendDirectoryQuery query) =>
      throw UnimplementedError();
}

class _BatchSend {
  _BatchSend(this.submission);

  final ForumPrivateMessageBatchSubmission submission;
  final result =
      Completer<DataCommandResult<ForumPrivateMessageBatchReceipt>>();
}
