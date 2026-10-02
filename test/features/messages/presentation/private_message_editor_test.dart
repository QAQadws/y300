import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_input.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/domain/message_refresh_bus.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/widgets/private_message_editor.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../support/message_test_repository.dart';
import '../support/message_input_test_helper.dart';

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
    PrivateMessageEditorLayout layout = PrivateMessageEditorLayout.form,
    double textScale = 1,
  }) async {
    final editor = Consumer(
      builder: (context, ref, _) {
        final account = ref.watch(messageAccountIdProvider)!;
        final input = PrivateMessageEditor(
          key: ValueKey(account),
          accountId: account,
          recipient: recipient,
          layout: layout,
          onApplied: receipts.add,
        );
        return Scaffold(
          appBar: AppBar(),
          body: layout == PrivateMessageEditorLayout.conversation
              ? LayoutBuilder(
                  builder: (_, constraints) => Column(
                    children: [
                      const Expanded(child: SizedBox.shrink()),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * 0.55,
                        ),
                        child: input,
                      ),
                    ],
                  ),
                )
              : input,
        );
      },
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
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
    await enterMessageText(tester, text);
    await tester.pump();
    await tester.tap(find.byKey(const Key('message-send')));
    await tester.pump();
  }

  testWidgets('default layout retains the separate recipient form', (
    tester,
  ) async {
    await pumpEditor(tester, recipient: null);
    final input = tester.widget<ComposerStickerInput>(messageInputSurface);
    expect(input.minLines, 1);
    expect(input.hintText, l10n(tester).messageInput);
    expect(find.byKey(const Key('message-recipient')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('message-send'))).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('message-input'))).dy,
      ),
    );
  });

  testWidgets('conversation keeps input and its busy send action on one row', (
    tester,
  ) async {
    await pumpEditor(tester, layout: PrivateMessageEditorLayout.conversation);
    final inputFinder = find.byKey(const Key('message-input'));
    final sendFinder = find.byKey(const Key('message-send'));
    final input = tester.widget<ComposerStickerInput>(messageInputSurface);
    expect(input.minLines, 1);
    expect(input.maxLines, 5);
    expect(input.hintText, l10n(tester).messageInput);
    expect(tester.widget<IconButton>(sendFinder).onPressed, isNull);
    expect(find.byKey(const Key('message-recipient')), findsNothing);
    await enterMessageText(tester, 'first line\nsecond line');
    await tester.pumpAndSettle();
    final sendRect = tester.getRect(sendFinder);
    final inputRect = tester.getRect(messageInputSurface);
    expect(sendRect.size, const Size.square(48));
    expect(sendRect.left, greaterThan(inputRect.right));
    expect(sendRect.bottom, closeTo(inputRect.bottom, 0.1));

    await tester.tap(sendFinder);
    await tester.pump();
    expect(tester.widget<QuillEditor>(inputFinder).controller.readOnly, isTrue);
    expect(tester.widget<IconButton>(sendFinder).onPressed, isNull);
    expect(tester.getRect(sendFinder), sendRect);
    expect(find.byTooltip(l10n(tester).messageSending), findsOneWidget);
    expect(
      find.descendant(
        of: sendFinder,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(sendFinder);
    expect(repository.sends, hasLength(1));
    expect(messageInputValue(tester), 'first line\nsecond line');
    repository.sends.single.succeed();
    await tester.pumpAndSettle();
    expect(messageInputValue(tester), isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip(l10n(tester).messageSend), findsOneWidget);
    expect(events, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'conversation keeps send reachable with keyboard, long input, large text, and errors',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpEditor(
        tester,
        layout: PrivateMessageEditorLayout.conversation,
        textScale: 1.8,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      final inputFinder = find.byKey(const Key('message-input'));
      final sendFinder = find.byKey(const Key('message-send'));
      const draft = 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight';
      await enterMessageText(tester, draft);
      await tester.pumpAndSettle();
      final inputScroll = tester.state<ScrollableState>(
        find.descendant(of: inputFinder, matching: find.byType(Scrollable)),
      );
      expect(inputScroll.position.maxScrollExtent, greaterThan(0));
      expect(sendFinder.hitTestable(), findsOneWidget);
      expect(tester.getSize(sendFinder), const Size.square(48));
      expect(
        tester.getBottomLeft(sendFinder).dy,
        closeTo(tester.getBottomLeft(messageInputSurface).dy, 0.1),
      );
      await tester.tap(sendFinder);
      await tester.pump();
      repository.sends.single.result.completeError(StateError('SECRET'));
      await tester.pumpAndSettle();
      expect(find.text(l10n(tester).messageUnknownOutcome), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(sendFinder.hitTestable(), findsOneWidget);
      expect(tester.getSize(sendFinder), const Size.square(48));
      expect(messageInputValue(tester), draft);
      await tester.tap(sendFinder);
      await tester.pumpAndSettle();
      expect(find.text(l10n(tester).messageSendAgain), findsOneWidget);
      await tester.tap(find.text(l10n(tester).commonCancel));
      await tester.pumpAndSettle();
      expect(repository.sends, hasLength(1));
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

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
      expect(messageInputValue(tester), isNotEmpty);
      repository.sends.single.succeed();
      await tester.pumpAndSettle();
      expect(messageInputValue(tester), isEmpty);
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
    'a sticker-only message submits its forum code and clears on proof',
    (tester) async {
      await pumpEditor(tester, layout: PrivateMessageEditorLayout.conversation);
      const code = '{:3_41:}';
      final controller = tester
          .widget<QuillEditor>(find.byKey(const Key('message-input')))
          .controller;
      controller.replaceText(
        0,
        0,
        composerQuillStickerEmbed(code),
        const TextSelection.collapsed(offset: 1),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('message-send')));
      await tester.pump();
      expect(repository.sends.single.submission.message, code);
      expect(messageInputValue(tester), code);
      repository.sends.single.succeed();
      await tester.pumpAndSettle();
      expect(messageInputValue(tester), isEmpty);
      expect(receipts, hasLength(1));
    },
  );

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
      expect(messageInputValue(tester), 'draft');
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
      await enterMessageText(tester, 'new account draft');
      repository.sends.single.succeed();
      await tester.pumpAndSettle();
      expect(messageInputValue(tester), 'new account draft');
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
