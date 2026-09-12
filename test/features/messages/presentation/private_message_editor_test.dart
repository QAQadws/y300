import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/domain/message_refresh_bus.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/widgets/private_message_editor.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../support/message_test_repository.dart';

void main() {
  late MessageTestRepository repository;
  late ProviderContainer container;
  late List<ForumPrivateMessageReceipt> receipts;
  late List<MessageRefreshEvent> events;
  setUp(() {
    repository = MessageTestRepository();
    receipts = [];
    events = [];
    container = ProviderContainer.test(
      overrides: [
        messageRepositoryProvider.overrideWithValue(repository),
        messageAccountIdProvider.overrideWithValue('10'),
      ],
    );
    final subscription = container
        .read(messageRefreshBusProvider)
        .events
        .listen(events.add);
    addTearDown(subscription.cancel);
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    ForumPrivateMessageRecipient? recipient =
        const ForumPrivateMessageRecipient.user('20'),
    bool pushed = false,
  }) async {
    final editor = Consumer(
      builder: (context, ref, _) {
        final account = ref.watch(messageAccountIdProvider)!;
        return Scaffold(
          appBar: AppBar(),
          body: PrivateMessageEditor(
            key: ValueKey(account),
            accountId: account,
            recipient: recipient,
            onApplied: receipts.add,
          ),
        );
      },
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: pushed
              ? Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => editor)),
                      child: const Text('open'),
                    ),
                  ),
                )
              : editor,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (pushed) await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(PrivateMessageEditor)));
  Future<void> sendText(WidgetTester tester, [String text = 'draft']) async {
    await tester.enterText(find.byKey(const Key('message-input')), text);
    await tester.pump();
    await tester.tap(find.byKey(const Key('message-send')));
    await tester.pump();
  }

  testWidgets(
    'one explicit send preserves source text and clears only after proof',
    (tester) async {
      await pumpEditor(tester);
      await sendText(tester, '  原始繁體 <text>\n[文字]  ');
      await tester.tap(find.byKey(const Key('message-send')));
      expect(repository.sends, hasLength(1));
      expect(
        repository.sends.single.submission.message,
        '  原始繁體 <text>\n[文字]  ',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('message-input')))
            .controller!
            .text,
        isNotEmpty,
      );
      repository.sends.single.succeed();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('message-input')))
            .controller!
            .text,
        isEmpty,
      );
      expect(receipts, hasLength(1));
      expect(events.single.accountId, '10');
      expect(events.single.target, const ForumConversationTarget.direct('20'));
    },
  );

  testWidgets('group reply carries its actual conversation anchor', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      recipient: const ForumPrivateMessageRecipient.group(
        conversationId: '91',
        replyMessageId: '82',
      ),
    );
    await sendText(tester);
    expect(repository.sends.single.submission.recipient.replyMessageId, '82');
    repository.sends.single.succeed();
    await tester.pumpAndSettle();
    expect(events.single.target, const ForumConversationTarget.group('91'));
  });

  testWidgets(
    'unknown send keeps draft, hides raw error, and requires explicit resend confirmation',
    (tester) async {
      await pumpEditor(tester);
      await sendText(tester);
      repository.sends.single.result.completeError(
        StateError('SECRET RESPONSE HTML'),
      );
      await tester.pumpAndSettle();
      final strings = l10n(tester);
      expect(find.text(strings.messageUnknownOutcome), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(events, isEmpty);
      expect(receipts, isEmpty);
      await tester.tap(find.byKey(const Key('message-send')));
      await tester.pumpAndSettle();
      expect(find.text(strings.messageSendAgain), findsOneWidget);
      await tester.tap(find.text(strings.commonCancel));
      await tester.pumpAndSettle();
      expect(repository.sends, hasLength(1));
      await tester.tap(find.byKey(const Key('message-send')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(strings.messageSend),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.sends, hasLength(2));
      repository.sends.last.succeed();
      await tester.pumpAndSettle();
      expect(receipts, hasLength(1));
    },
  );

  testWidgets(
    'server rejection preserves input and explains a known restriction',
    (tester) async {
      await pumpEditor(tester);
      await sendText(tester);
      repository.sends.single.result.complete(
        const DataCommandRejected(
          DataCommandFailure(
            kind: DataCommandFailureKind.permissionDenied,
            retryPolicy: DataCommandRetryPolicy.afterInputChange,
            code: 'message_can_not_send_onlyfriend',
            diagnosticMessage: 'untrusted response',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n(tester).messageOnlyFriends), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('message-input')))
            .controller!
            .text,
        'draft',
      );
      expect(events, isEmpty);
      expect(receipts, isEmpty);
    },
  );

  testWidgets('new recipient rejects implicit multi-recipient syntax', (
    tester,
  ) async {
    await pumpEditor(tester, recipient: null);
    await tester.enterText(
      find.byKey(const Key('message-recipient')),
      'Alice,Bob',
    );
    await sendText(tester);
    expect(repository.sends, isEmpty);
    expect(find.text(l10n(tester).messageRecipientInvalid), findsOneWidget);
    await tester.enterText(find.byKey(const Key('message-recipient')), 'Alice');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message-send')));
    await tester.pump();
    expect(
      repository.sends.single.submission.recipient.kind,
      ForumPrivateMessageRecipientKind.username,
    );
    expect(repository.sends.single.submission.recipient.value, 'Alice');
    repository.sends.single.succeed();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'account replacement cancels old input owner and ignores its late receipt',
    (tester) async {
      await pumpEditor(tester);
      await sendText(tester);
      container.updateOverrides([
        messageRepositoryProvider.overrideWithValue(repository),
        messageAccountIdProvider.overrideWithValue('11'),
      ]);
      await tester.pumpAndSettle();
      expect(
        repository.sends.single.submission.cancellation!.isCancelled,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const Key('message-input')),
        'new account draft',
      );
      repository.sends.single.succeed();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('message-input')))
            .controller!
            .text,
        'new account draft',
      );
      expect(receipts, isEmpty);
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'back retains draft until confirmed and late completion after pop is harmless',
    (tester) async {
      await pumpEditor(tester, pushed: true);
      final strings = l10n(tester);
      await sendText(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(strings.messageLeavePending), findsOneWidget);
      await tester.tap(find.text(strings.commonCancel));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message-input')), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.messageLeave));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message-input')), findsNothing);
      expect(
        repository.sends.single.submission.cancellation!.isCancelled,
        isTrue,
      );
      repository.sends.single.succeed();
      await tester.pumpAndSettle();
      expect(receipts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
