import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/data/private_message_compose_repository_provider.dart';
import 'package:y300/features/messages/domain/message_refresh_bus.dart';
import 'package:y300/features/messages/domain/private_message_compose_repository.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/new_private_message_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../support/message_input_test_helper.dart';

void main() {
  late _ComposeRepository repository;
  late ProviderContainer container;
  late List<MessageRefreshEvent> events;

  setUp(() {
    repository = _ComposeRepository();
    events = [];
    container = ProviderContainer.test(
      overrides: [
        messageAccountIdProvider.overrideWithValue('10'),
        privateMessageComposeRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final subscription = container
        .read(messageRefreshBusProvider)
        .events
        .listen(events.add);
    addTearDown(subscription.cancel);
  });

  Future<void> openPage(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NewPrivateMessagePage(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(NewPrivateMessagePage)));

  Future<void> addUsername(WidgetTester tester, String username) async {
    await tester.enterText(
      find.byKey(const Key('message-recipient')),
      username,
    );
    final add = find.byKey(const Key('message-recipient-add'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester, String message) async {
    await enterMessageText(tester, message);
    final send = find.byKey(const Key('message-send'));
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pump();
  }

  testWidgets(
    'one exact username uses batch command and only proven success exits',
    (tester) async {
      await openPage(tester);
      await tester.enterText(
        find.byKey(const Key('message-recipient')),
        ' Alice ',
      );
      await submit(tester, '原样 <text> [smile]');
      expect(repository.sends, hasLength(1));
      expect(repository.sends.single.submission.usernames, ['Alice']);
      expect(repository.sends.single.submission.message, '原样 <text> [smile]');
      expect(find.byType(NewPrivateMessagePage), findsOneWidget);
      expect(events, isEmpty);

      repository.sends.single.succeed(accepted: 1);
      await tester.pumpAndSettle();
      expect(events, hasLength(1));
      expect(events.single.accountId, '10');
      expect(events.single.directoryOnly, isTrue);
      expect(find.byType(NewPrivateMessagePage), findsNothing);
    },
  );

  testWidgets(
    'multi-recipient result preserves the send snapshot and uncertainty',
    (tester) async {
      await openPage(tester);
      await addUsername(tester, 'Alice');
      await addUsername(tester, 'Bob');
      expect(
        find.byKey(const Key('message-recipient-chip-Alice')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('message-recipient-chip-Bob')),
        findsOneWidget,
      );
      await submit(tester, 'hello group');
      expect(repository.sends.single.submission.usernames, ['Alice', 'Bob']);
      repository.sends.single.succeed(accepted: 1, excluded: ['Bob']);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('message-batch-result')), findsOneWidget);
      expect(
        find.text(l10n(tester).messageBatchReportedAccepted(1)),
        findsOneWidget,
      );
      expect(find.text(l10n(tester).messageBatchResultCaution), findsOneWidget);
      expect(find.text(l10n(tester).messageBatchExcluded), findsOneWidget);
      expect(find.text(l10n(tester).messageBatchUnproven), findsOneWidget);
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Bob'), findsWidgets);
      expect(find.text('hello group'), findsOneWidget);
      expect(events, hasLength(1));
      expect(events.single.directoryOnly, isTrue);

      await tester.tap(find.byKey(const Key('message-batch-send-again')));
      await tester.pumpAndSettle();
      expect(repository.sends, hasLength(1));
      expect(find.text(l10n(tester).messageBatchRepeatTitle), findsOneWidget);
      await tester.tap(find.text(l10n(tester).commonCancel));
      await tester.pumpAndSettle();
      expect(repository.sends, hasLength(1));

      await tester.tap(find.byKey(const Key('message-batch-done')));
      await tester.pumpAndSettle();
      expect(find.byType(NewPrivateMessagePage), findsNothing);
    },
  );

  testWidgets(
    'unknown outcome requires confirmation and a rejected repeat keeps draft',
    (tester) async {
      await openPage(tester);
      await addUsername(tester, 'Alice');
      await submit(tester, 'uncertain draft');
      repository.sends.single.result.complete(
        const DataCommandOutcomeUnknown(
          DataCommandFailure(
            kind: DataCommandFailureKind.timeout,
            retryPolicy: DataCommandRetryPolicy.explicitOnly,
            code: 'timeout',
            diagnosticMessage: 'SECRET SERVER RESPONSE',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(messageInputValue(tester), 'uncertain draft');
      expect(
        find.byKey(const Key('message-recipient-chip-Alice')),
        findsOneWidget,
      );
      expect(find.text(l10n(tester).messageUnknownOutcome), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(events, isEmpty);

      await tester.tap(find.byKey(const Key('message-send')));
      await tester.pumpAndSettle();
      expect(repository.sends, hasLength(1));
      expect(find.text(l10n(tester).messageSendAgain), findsOneWidget);
      await tester.tap(find.text(l10n(tester).commonCancel));
      await tester.pumpAndSettle();
      expect(repository.sends, hasLength(1));

      await tester.tap(find.byKey(const Key('message-send')));
      await tester.pumpAndSettle();
      expect(find.text(l10n(tester).messageSendAgain), findsOneWidget);
      await tester.tap(find.text(l10n(tester).messageSend));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.sends, hasLength(2));
      expect(repository.sends.last.submission.usernames, ['Alice']);
      expect(repository.sends.last.submission.message, 'uncertain draft');
      await tester.tap(find.byKey(const Key('message-send')));
      await tester.pump();
      expect(repository.sends, hasLength(2));

      repository.sends.last.result.complete(
        const DataCommandRejected(
          DataCommandFailure(
            kind: DataCommandFailureKind.validation,
            retryPolicy: DataCommandRetryPolicy.afterInputChange,
            code: 'message_can_not_send_3',
            diagnosticMessage: 'SECRET REJECTION',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(messageInputValue(tester), 'uncertain draft');
      expect(
        find.byKey(const Key('message-recipient-chip-Alice')),
        findsOneWidget,
      );
      expect(find.text(l10n(tester).messageBatchOnlyFriends), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(events, isEmpty);
    },
  );

  testWidgets(
    'switching accounts cancels a pending batch and erases old draft',
    (tester) async {
      await openPage(tester);
      await addUsername(tester, 'Alice');
      await submit(tester, 'old account draft');
      final old = repository.sends.single;
      container.updateOverrides([
        messageAccountIdProvider.overrideWithValue('11'),
        privateMessageComposeRepositoryProvider.overrideWithValue(repository),
      ]);
      await tester.pump();
      expect(old.submission.cancellation!.isCancelled, isTrue);
      expect(
        find.byKey(const Key('message-recipient-chip-Alice')),
        findsNothing,
      );
      expect(messageInputValue(tester), isEmpty);
      old.succeed(accepted: 1);
      await tester.pump();
      expect(find.byKey(const Key('message-batch-result')), findsNothing);
      expect(events, isEmpty);
    },
  );

  testWidgets(
    'leaving during a pending send cancels it without assuming rollback',
    (tester) async {
      await openPage(tester);
      await addUsername(tester, 'Alice');
      await submit(tester, 'pending draft');
      final send = repository.sends.single;
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(l10n(tester).messageLeavePending), findsOneWidget);
      await tester.tap(find.text(l10n(tester).commonCancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(NewPrivateMessagePage), findsOneWidget);
      expect(send.submission.cancellation!.isCancelled, isFalse);

      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(l10n(tester).messageLeave));
      await tester.pumpAndSettle();
      expect(find.byType(NewPrivateMessagePage), findsNothing);
      expect(send.submission.cancellation!.isCancelled, isTrue);
      send.succeed(accepted: 1);
      await tester.pump();
      expect(events, isEmpty);
    },
  );

  testWidgets('a proven send while leave confirmation is open exits once', (
    tester,
  ) async {
    await openPage(tester);
    for (final confirmLeave in [false, true]) {
      if (confirmLeave) {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }
      await addUsername(tester, 'Alice');
      await submit(tester, 'pending success');
      final send = repository.sends.last;
      final previousEvents = events.length;

      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(l10n(tester).messageLeavePending), findsOneWidget);
      send.succeed(accepted: 1);
      await tester.pump();
      expect(events, hasLength(previousEvents + 1));
      expect(events.last.directoryOnly, isTrue);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(
        find.text(
          confirmLeave ? l10n(tester).messageLeave : l10n(tester).commonCancel,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NewPrivateMessagePage), findsNothing);
      expect(find.text('open').hitTestable(), findsOneWidget);
      expect(Navigator.of(tester.element(find.text('open'))).canPop(), isFalse);
      expect(events, hasLength(previousEvents + 1));
    }
  });
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

  void succeed({required int accepted, List<String> excluded = const []}) =>
      result.complete(
        DataCommandApplied(
          ForumPrivateMessageBatchReceipt(
            usernames: submission.usernames,
            serverReportedAcceptedCount: accepted,
            excludedUsernames: excluded,
          ),
        ),
      );
}
