import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/navigation/message_routes.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/presentation/message_center_page.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/new_private_message_page.dart';
import 'package:y300/features/messages/presentation/private_conversation_page.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../support/message_test_repository.dart';

void main() {
  late MessageTestRepository repository;
  late ProviderContainer container;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = MessageTestRepository();
    container = ProviderContainer.test(
      overrides: [
        messageAccountIdProvider.overrideWithValue('10'),
        messageRepositoryProvider.overrideWithValue(repository),
      ],
    );
  });
  Future<void> pumpCenter(
    WidgetTester tester, {
    MessageCenterTab tab = MessageCenterTab.messages,
    bool active = true,
    Locale locale = const Locale('zh'),
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          locale: locale,
          theme: ThemeData(brightness: brightness),
          home: MessageCenterDestination(initialTab: tab, isActive: active),
        ),
      ),
    );
    await tester.pump();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(MessageCenterPage).first));
  Future<void> selectTab(WidgetTester tester, MessageCenterTab tab) async {
    await tester.tap(
      find.text(
        tab == MessageCenterTab.messages
            ? l10n(tester).messageMessagesTab
            : l10n(tester).messageNotificationsTab,
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'tabs load independently and an unfinished hidden tab does not animate',
    (tester) async {
      await pumpCenter(tester);
      expect(repository.reads, hasLength(1));
      expect(repository.notificationReads, isEmpty);
      await selectTab(tester, MessageCenterTab.notifications);
      repository.notificationReads.single.result.complete(
        notificationTestPage([notificationTestItem('1')]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ForumHtmlContentView), findsOneWidget);
      repository.reads.single.result.complete(
        const DataReadFailure(
          kind: DataReadFailureKind.timeout,
          code: 'fixture',
          diagnosticMessage: 'SECRET ERROR',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('SECRET'), findsNothing);
      await selectTab(tester, MessageCenterTab.messages);
      await tester.pumpAndSettle();
      expect(find.text(l10n(tester).commonTimeoutError), findsOneWidget);
      expect(repository.reads, hasLength(1));
    },
  );

  testWidgets(
    'inactive shell never reads until selected and notifications-only entry stays lazy',
    (tester) async {
      await pumpCenter(
        tester,
        tab: MessageCenterTab.notifications,
        active: false,
      );
      expect(repository.reads, isEmpty);
      expect(repository.notificationReads, isEmpty);
      await pumpCenter(tester, tab: MessageCenterTab.notifications);
      expect(repository.reads, isEmpty);
      expect(repository.notificationReads, hasLength(1));
      repository.notificationReads.single.result.complete(
        notificationTestPage([]),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n(tester).profileNoNotifications), findsOneWidget);
    },
  );

  testWidgets(
    'directory opens the real UID, returns, and refreshes unread state once',
    (tester) async {
      await pumpCenter(tester);
      repository.reads.single.result.complete(
        messageTestPage([messageTestItem('1', sender: '10')]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice'));
      await tester.pump();
      expect(
        repository.reads.last.query.target,
        const ForumConversationTarget.direct('20'),
      );
      repository.reads.last.result.complete(
        messageTestPage([messageTestItem('1')]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PrivateConversationPage), findsOneWidget);
      expect(repository.reads, hasLength(2));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(repository.reads, hasLength(3));
      expect(repository.reads.last.query.target, isNull);
      repository.reads.last.result.complete(
        messageTestPage([messageTestItem('1', sender: '10')]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
    },
  );

  testWidgets(
    'page failure retains items and retry requests the failed next page',
    (tester) async {
      await pumpCenter(tester);
      repository.reads.single.result.complete(
        messageTestPage(
          [messageTestItem('1', sender: '10')],
          count: 2,
          perPage: 1,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n(tester).messageLoadMore));
      await tester.pump();
      expect(repository.reads.last.query.page, 2);
      repository.reads.last.result.complete(
        const DataReadFailure(
          kind: DataReadFailureKind.network,
          code: 'fixture',
          diagnosticMessage: 'fixture',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      await tester.tap(find.text(l10n(tester).commonRetry));
      await tester.pump();
      expect(repository.reads.last.query.page, 2);
      repository.reads.last.result.complete(
        messageTestPage([], page: 2, count: 1, perPage: 1),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'compose action returns after a proven send and refreshes the directory',
    (tester) async {
      await pumpCenter(tester);
      repository.reads.single.result.complete(messageTestPage([]));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n(tester).messageNew));
      await tester.pumpAndSettle();
      expect(find.byType(NewPrivateMessagePage), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('message-recipient')),
        'Alice',
      );
      await tester.enterText(find.byKey(const Key('message-input')), 'hello');
      await tester.pump();
      await tester.tap(find.byKey(const Key('message-send')));
      await tester.pump();
      repository.sends.single.succeed();
      await tester.pumpAndSettle();
      expect(find.byType(NewPrivateMessagePage), findsNothing);
      expect(repository.reads, hasLength(2));
      repository.reads.last.result.complete(
        messageTestPage([messageTestItem('100', sender: '10')]),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('scroll position survives a tab round trip', (tester) async {
    await pumpCenter(tester);
    repository.reads.single.result.complete(
      messageTestPage([
        for (var i = 0; i < 20; i++)
          messageTestItem('$i', sender: '10', recipient: '${i + 20}'),
      ]),
    );
    await tester.pumpAndSettle();
    final list = find.byKey(const PageStorageKey('private-message-list:10'));
    await tester.drag(list, const Offset(0, -650));
    await tester.pumpAndSettle();
    final state = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    final before = state.position.pixels;
    await selectTab(tester, MessageCenterTab.notifications);
    repository.notificationReads.single.result.complete(
      notificationTestPage([]),
    );
    await tester.pumpAndSettle();
    await selectTab(tester, MessageCenterTab.messages);
    await tester.pumpAndSettle();
    expect(state.position.pixels, before);
  });

  testWidgets('narrow traditional dark mailbox supports larger system text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpCenter(
      tester,
      tab: MessageCenterTab.notifications,
      locale: const Locale('zh', 'TW'),
      brightness: Brightness.dark,
    );
    repository.notificationReads.single.result.complete(
      notificationTestPage([notificationTestItem('1')]),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip(l10n(tester).messageIgnore));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'notification links and author are forwarded and ignoring preserves existing notices',
    (tester) async {
      final users = <String>[];
      final links = <String>[];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LocalizedTestApp(
            home: MessageCenterPage(
              initialTab: MessageCenterTab.notifications,
              onOpenConversation: (_, _, _) {},
              onOpenUser: (_, id) => users.add(id),
              onOpenLink: (_, url) => links.add(url),
            ),
          ),
        ),
      );
      await tester.pump();
      repository.notificationReads.single.result.complete(
        notificationTestPage([notificationTestItem('1')]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice'));
      expect(users, ['20']);
      final body = tester.widget<ForumHtmlContentView>(
        find.byType(ForumHtmlContentView),
      );
      body.onOpenLink?.call('forum.php?mod=viewthread&tid=42');
      expect(links, ['forum.php?mod=viewthread&tid=42']);
      await tester.tap(find.byTooltip(l10n(tester).messageIgnore));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-ignore-save')));
      await tester.pump();
      repository.ignores.single.succeed();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(l10n(tester).messageIgnoreApplied), findsOneWidget);
      expect(find.byType(ForumHtmlContentView), findsOneWidget);
      expect(repository.notificationReads, hasLength(1));
    },
  );
}
