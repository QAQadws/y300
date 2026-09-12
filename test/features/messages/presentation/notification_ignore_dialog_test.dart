import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/notification_ignore_dialog.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../support/message_test_repository.dart';

void main() {
  late MessageTestRepository repository;
  late ProviderContainer container;
  ForumNotificationIgnoreReceipt? receipt;
  setUp(() {
    repository = MessageTestRepository();
    receipt = null;
    container = ProviderContainer.test(
      overrides: [
        messageRepositoryProvider.overrideWithValue(repository),
        messageAccountIdProvider.overrideWithValue('10'),
      ],
    );
  });
  Future<void> pumpDialog(WidgetTester tester, {String author = '20'}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  receipt = await showDialog<ForumNotificationIgnoreReceipt>(
                    context: context,
                    builder: (_) => NotificationIgnoreDialog(
                      accountId: '10',
                      item: notificationTestItem('1', authorId: author),
                    ),
                  );
                },
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

  AppLocalizations l10n(WidgetTester tester) => AppLocalizations.of(
    tester.element(find.byType(NotificationIgnoreDialog)),
  );

  testWidgets(
    'author filtering is explicit and one command yields one matching receipt',
    (tester) async {
      await pumpDialog(tester);
      expect(repository.ignores, isEmpty);
      expect(find.text(l10n(tester).messageIgnoreExplanation), findsOneWidget);
      await tester.tap(find.byKey(const Key('notification-ignore-save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('notification-ignore-save')));
      expect(repository.ignores, hasLength(1));
      final command = repository.ignores.single;
      expect(command.submission.scope, ForumNotificationIgnoreScope.author);
      expect(command.submission.authorId, '20');
      expect(command.submission.type, 'post');
      command.succeed();
      await tester.pumpAndSettle();
      expect(receipt!.authorId, '20');
      expect(find.byType(NotificationIgnoreDialog), findsNothing);
    },
  );

  testWidgets('all-author filtering keeps its selected scope', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text(l10n(tester).messageIgnoreEveryone));
    await tester.pump();
    await tester.tap(find.byKey(const Key('notification-ignore-save')));
    await tester.pump();
    expect(
      repository.ignores.single.submission.scope,
      ForumNotificationIgnoreScope.allAuthors,
    );
    repository.ignores.single.succeed();
    await tester.pumpAndSettle();
    expect(receipt!.authorId, '0');
  });

  testWidgets('system notices never offer an invalid author-specific filter', (
    tester,
  ) async {
    await pumpDialog(tester, author: '0');
    expect(find.text(l10n(tester).messageIgnoreAuthor), findsNothing);
    await tester.tap(find.byKey(const Key('notification-ignore-save')));
    await tester.pump();
    expect(
      repository.ignores.single.submission.scope,
      ForumNotificationIgnoreScope.allAuthors,
    );
    repository.ignores.single.succeed();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'unknown outcomes remain open without automatic retry or raw errors',
    (tester) async {
      await pumpDialog(tester);
      final strings = l10n(tester);
      await tester.tap(find.byKey(const Key('notification-ignore-save')));
      await tester.pump();
      repository.ignores.single.result.completeError(
        StateError('PRIVATE RESPONSE'),
      );
      await tester.pumpAndSettle();
      expect(find.text(strings.messageIgnoreUnknown), findsOneWidget);
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(receipt, isNull);
      expect(repository.ignores, hasLength(1));
      await tester.pump(const Duration(seconds: 20));
      expect(repository.ignores, hasLength(1));
    },
  );

  testWidgets('closing cancels local waiting and ignores a late result', (
    tester,
  ) async {
    await pumpDialog(tester);
    final strings = l10n(tester);
    await tester.tap(find.byKey(const Key('notification-ignore-save')));
    await tester.pump();
    await tester.tap(find.text(strings.commonClose));
    await tester.pumpAndSettle();
    expect(
      repository.ignores.single.submission.cancellation!.isCancelled,
      isTrue,
    );
    repository.ignores.single.succeed();
    await tester.pumpAndSettle();
    expect(receipt, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account replacement prevents a late receipt from closing the new session UI',
    (tester) async {
      await pumpDialog(tester);
      await tester.tap(find.byKey(const Key('notification-ignore-save')));
      await tester.pump();
      container.updateOverrides([
        messageRepositoryProvider.overrideWithValue(repository),
        messageAccountIdProvider.overrideWithValue('11'),
      ]);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notification-ignore-save')), findsNothing);
      repository.ignores.single.succeed();
      await tester.pumpAndSettle();
      expect(receipt, isNull);
      expect(find.byType(NotificationIgnoreDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
