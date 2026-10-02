import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/domain/private_message_compose_repository.dart';
import 'package:y300/features/messages/domain/private_message_recipient_selection.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/message_friend_directory_controller.dart';
import 'package:y300/features/messages/presentation/widgets/message_friend_picker_sheet.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('empty and failed reads stay inside the sheet and retry', (
    tester,
  ) async {
    final harness = await _Harness.open(tester);
    harness.repository.reads.single.result.complete(
      const DataReadFailure(
        kind: DataReadFailureKind.network,
        code: 'offline',
        diagnosticMessage: 'untrusted-server-payload',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(harness.strings.messageFriendLoadFailed), findsOneWidget);
    expect(find.text('untrusted-server-payload'), findsNothing);
    await tester.tap(find.text(harness.strings.commonRetry));
    await tester.pump();
    expect(harness.repository.reads, hasLength(2));
    harness.repository.reads.last.result.complete(_page([]));
    await tester.pumpAndSettle();
    expect(find.text(harness.strings.messageFriendEmpty), findsOneWidget);
    expect(
      find.byKey(const Key('message-friends-done')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('failed pagination retains friends and retries the same page', (
    tester,
  ) async {
    final harness = await _Harness.open(tester);
    harness.repository.reads.single.result.complete(_page([1], count: 21));
    await tester.pumpAndSettle();
    await tester.tap(find.text(harness.strings.messageLoadMore));
    await tester.pump();
    expect(harness.repository.reads.last.query.page, 2);
    harness.repository.reads.last.result.complete(
      const DataReadFailure(
        kind: DataReadFailureKind.timeout,
        code: 'timeout',
        diagnosticMessage: 'timeout',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-friend-1')), findsOneWidget);
    await tester.tap(find.text(harness.strings.commonRetry));
    await tester.pump();
    expect(harness.repository.reads.last.query.page, 2);
    harness.repository.reads.last.result.complete(
      _page([1, 2], page: 2, count: 21),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-friend-1')), findsOneWidget);
    expect(find.byKey(const Key('message-friend-2')), findsOneWidget);
  });

  testWidgets(
    'the cap disables new choices while selected friends remain removable',
    (tester) async {
      final selection = PrivateMessageRecipientSelection();
      for (var id = 1; id <= 20; id++) {
        selection.addFriend(userId: '$id', username: 'friend$id');
      }
      final harness = await _Harness.open(tester, selection: selection);
      harness.repository.reads.single.result.complete(_page([1, 21]));
      await tester.pumpAndSettle();
      final extra = find.byKey(const Key('message-friend-21'));
      expect(tester.widget<CheckboxListTile>(extra).onChanged, isNull);
      expect(
        find.text(harness.strings.messageRecipientLimitReached),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('message-friend-1')));
      await tester.pumpAndSettle();
      expect(selection.length, 19);
      expect(tester.widget<CheckboxListTile>(extra).onChanged, isNotNull);
      await tester.tap(extra);
      await tester.pumpAndSettle();
      expect(selection.length, 20);
      expect(selection.containsFriend('21', 'friend21'), isTrue);
      expect(harness.selectionChanges, 2);
    },
  );

  testWidgets(
    'closing during debounce cancels the pending search and keeps selection',
    (tester) async {
      final harness = await _Harness.open(tester);
      harness.repository.reads.single.result.complete(_page([1]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-friend-1')));
      await tester.enterText(
        find.byKey(const Key('message-friends-search')),
        'friend',
      );
      await tester.tap(find.byKey(const Key('message-friends-done')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      expect(harness.repository.reads, hasLength(1));
      expect(harness.disposed, isTrue);
      expect(harness.selection.usernameSnapshot(), ['friend1']);
    },
  );

  testWidgets(
    'switching account hides the old list and ignores a late pending read',
    (tester) async {
      final harness = await _Harness.open(tester);
      final pending = harness.repository.reads.single;
      harness.container.updateOverrides([
        messageAccountIdProvider.overrideWithValue('11'),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(MessageFriendPickerSheet), findsNothing);
      expect(pending.query.cancellation!.isCancelled, isTrue);
      expect(harness.disposed, isTrue);
      pending.result.complete(_page([1]));
      await tester.pumpAndSettle();
      expect(find.text('friend1'), findsNothing);
      expect(harness.selection.isEmpty, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Harness {
  _Harness(this.tester, this.selection) {
    container = ProviderContainer(
      overrides: [messageAccountIdProvider.overrideWithValue('10')],
    );
    controller = MessageFriendDirectoryController(
      accountId: '10',
      currentAccountId: () => container.read(messageAccountIdProvider),
      repository: repository,
    );
  }

  final WidgetTester tester;
  final PrivateMessageRecipientSelection selection;
  final repository = _Repository();
  late final ProviderContainer container;
  late final MessageFriendDirectoryController controller;
  late AppLocalizations strings;
  bool disposed = false;
  int selectionChanges = 0;

  static Future<_Harness> open(
    WidgetTester tester, {
    PrivateMessageRecipientSelection? selection,
  }) async {
    final harness = _Harness(
      tester,
      selection ?? PrivateMessageRecipientSelection(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      if (!harness.disposed) harness.controller.dispose();
      harness.container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: LocalizedTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                harness.strings = AppLocalizations.of(context);
                return FilledButton(
                  onPressed: () => unawaited(
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => MessageFriendPickerSheet(
                        accountId: '10',
                        controller: harness.controller,
                        selection: harness.selection,
                        onSelectionChanged: () => harness.selectionChanges++,
                      ),
                    ).whenComplete(() {
                      harness.controller.dispose();
                      harness.disposed = true;
                    }),
                  ),
                  child: const Text('open-fixture'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    return harness;
  }
}

FriendDirectoryRead _page(List<int> ids, {int page = 1, int? count}) =>
    DataReadSuccess(
      data: ForumFriendDirectoryPage(
        items: [
          for (final id in ids)
            ForumFriendDirectoryItem(userId: '$id', username: 'friend$id'),
        ],
        page: page,
        perPage: 20,
        count: count ?? ids.length,
        currentUserId: '10',
      ),
      capabilities: ForumFriendDirectoryReadCapabilities(
        values: DataCapabilitySet.supported(
          ForumFriendDirectoryCapability.values,
        ),
      ),
      metadata: const DataReadMetadata.network(),
    );

class _Repository implements PrivateMessageComposeRepository {
  final reads = <_Read>[];

  @override
  Future<FriendDirectoryRead> loadFriends(ForumFriendDirectoryQuery query) {
    final read = _Read(query);
    reads.add(read);
    return read.result.future;
  }

  @override
  Future<DataCommandResult<ForumPrivateMessageBatchReceipt>> sendBatch(
    ForumPrivateMessageBatchSubmission submission,
  ) => throw UnimplementedError();
}

class _Read {
  _Read(this.query);
  final ForumFriendDirectoryQuery query;
  final result = Completer<FriendDirectoryRead>();
}
