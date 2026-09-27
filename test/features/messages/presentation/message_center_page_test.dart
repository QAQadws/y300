import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/navigation/message_routes.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
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
          theme: AppTheme.build(
            family: AppThemeFamily.warmPaper,
            brightness: brightness,
          ),
          home: MessageCenterDestination(initialTab: tab, isActive: active),
        ),
      ),
    );
    await tester.pump();
  }

  Finder feedList(MessageCenterTab tab, {String account = '10'}) => find.byKey(
    PageStorageKey(
      tab == MessageCenterTab.messages
          ? 'private-message-list:$account'
          : 'notification-list:$account',
    ),
  );

  ScrollPosition feedPosition(
    WidgetTester tester,
    MessageCenterTab tab, {
    String account = '10',
  }) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: feedList(tab, account: account),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  Future<void> finishSwipe(WidgetTester tester) async {
    await tester.pump();
    // The destination may still be loading, so settle only the page motion.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  Future<void> swipeToTab(WidgetTester tester, MessageCenterTab tab) async {
    final pages = find.byType(TabBarView);
    final distance = tester.getSize(pages).width * 0.8;
    await tester.drag(
      pages,
      Offset(tab == MessageCenterTab.notifications ? -distance : distance, 0),
    );
    await finishSwipe(tester);
    final controller = tester.widget<TabBar>(find.byType(TabBar)).controller!;
    expect(controller.index, tab.index);
    expect(controller.animation!.value, closeTo(tab.index.toDouble(), 0.001));
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
    // The page animation starts from the tab controller's first animation tick.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(kTabScrollDuration);
    await tester.pump();
  }

  testWidgets(
    'swipes and tab taps agree across loading, empty, and error pages',
    (tester) async {
      await pumpCenter(tester);
      await swipeToTab(tester, MessageCenterTab.notifications);
      expect(repository.reads, hasLength(1));
      expect(repository.notificationReads, hasLength(1));
      repository.notificationReads.single.result.complete(
        notificationTestPage([]),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n(tester).profileNoNotifications), findsOneWidget);

      await swipeToTab(tester, MessageCenterTab.messages);
      expect(
        find
            .descendant(
              of: feedList(MessageCenterTab.messages),
              matching: find.byType(CircularProgressIndicator),
            )
            .hitTestable(),
        findsOneWidget,
      );
      await selectTab(tester, MessageCenterTab.notifications);
      expect(
        find.text(l10n(tester).profileNoNotifications).hitTestable(),
        findsOneWidget,
      );
      repository.reads.single.result.complete(
        const DataReadFailure(
          kind: DataReadFailureKind.timeout,
          code: 'fixture',
          diagnosticMessage: 'fixture',
        ),
      );
      await tester.pumpAndSettle();
      await selectTab(tester, MessageCenterTab.messages);
      expect(
        find.text(l10n(tester).commonTimeoutError).hitTestable(),
        findsOneWidget,
      );
      await swipeToTab(tester, MessageCenterTab.notifications);
      expect(
        find.text(l10n(tester).profileNoNotifications).hitTestable(),
        findsOneWidget,
      );
      expect(repository.reads, hasLength(1));
      expect(repository.notificationReads, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a short cancelled horizontal swipe does not visit the other feed',
    (tester) async {
      await pumpCenter(tester);
      repository.reads.single.result.complete(messageTestPage([]));
      await tester.pumpAndSettle();
      final pages = find.byType(TabBarView);
      final gesture = await tester.startGesture(tester.getCenter(pages));
      await gesture.moveBy(Offset(-tester.getSize(pages).width * 0.15, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.notificationReads, isEmpty);
      await gesture.up();
      await finishSwipe(tester);
      final controller = tester.widget<TabBar>(find.byType(TabBar)).controller!;
      expect(controller.index, MessageCenterTab.messages.index);
      expect(controller.animation!.value, closeTo(0, 0.001));
      expect(repository.reads, hasLength(1));
      expect(repository.notificationReads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'horizontal navigation never refreshes and pulls target only the current feed',
    (tester) async {
      await pumpCenter(tester);
      repository.reads.single.result.complete(messageTestPage([]));
      await tester.pumpAndSettle();
      await swipeToTab(tester, MessageCenterTab.notifications);
      repository.notificationReads.single.result.complete(
        notificationTestPage([]),
      );
      await tester.pumpAndSettle();
      expect(repository.reads, hasLength(1));
      expect(repository.notificationReads, hasLength(1));

      await tester.drag(
        feedList(MessageCenterTab.notifications),
        const Offset(0, 360),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.notificationReads, hasLength(2));
      expect(repository.reads, hasLength(1));
      await swipeToTab(tester, MessageCenterTab.messages);
      repository.notificationReads.last.result.complete(
        notificationTestPage([
          notificationTestItem('2', markup: '<p>Hidden refresh result</p>'),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        feedList(MessageCenterTab.messages),
        const Offset(0, 360),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.reads, hasLength(2));
      expect(repository.notificationReads, hasLength(2));
      repository.reads.last.result.complete(messageTestPage([]));
      await tester.pumpAndSettle();
      await swipeToTab(tester, MessageCenterTab.notifications);
      await tester.pumpAndSettle();
      expect(
        find.text('Hidden refresh result', findRichText: true).hitTestable(),
        findsOneWidget,
      );
      expect(repository.reads, hasLength(2));
      expect(repository.notificationReads, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  for (final tab in MessageCenterTab.values) {
    for (final empty in [true, false]) {
      testWidgets(
        '${tab.name} ${empty ? 'empty' : 'short'} list supports pull refresh without shifting content',
        (tester) async {
          await pumpCenter(tester, tab: tab);
          void completeRead() {
            if (tab == MessageCenterTab.messages) {
              repository.reads.last.result.complete(
                messageTestPage([
                  if (!empty) messageTestItem('1', sender: '10'),
                ]),
              );
            } else {
              repository.notificationReads.last.result.complete(
                notificationTestPage([if (!empty) notificationTestItem('1')]),
              );
            }
          }

          int readCount() => tab == MessageCenterTab.messages
              ? repository.reads.length
              : repository.notificationReads.length;
          completeRead();
          await tester.pumpAndSettle();
          final list = find.byKey(
            PageStorageKey(
              tab == MessageCenterTab.messages
                  ? 'private-message-list:10'
                  : 'notification-list:10',
            ),
          );
          expect(find.byTooltip(l10n(tester).messageRefresh), findsNothing);
          await tester.drag(list, const Offset(0, 360));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(readCount(), 2);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          if (tab == MessageCenterTab.messages) {
            expect(repository.reads.last.query.page, 1);
            expect(repository.notificationReads, isEmpty);
          } else {
            expect(repository.notificationReads.last.query.page, 1);
            expect(repository.reads, isEmpty);
          }
          completeRead();
          await tester.pumpAndSettle();

          if (!empty) {
            final viewportBefore = tester.getRect(list);
            final messageBefore = tester.getRect(find.text('Alice'));
            final refresh = tab == MessageCenterTab.messages
                ? container.read(privateMessageFeedProvider(null)).refresh()
                : container.read(notificationFeedProvider).refresh();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
            expect(readCount(), 3);
            expect(find.byType(LinearProgressIndicator), findsNothing);
            expect(tester.getRect(list), viewportBefore);
            expect(tester.getRect(find.text('Alice')), messageBefore);
            completeRead();
            await refresh;
            await tester.pumpAndSettle();
            expect(tester.getRect(list), viewportBefore);
            expect(tester.getRect(find.text('Alice')), messageBefore);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'tabs load independently and an unfinished hidden tab does not animate',
    (tester) async {
      await pumpCenter(tester);
      expect(repository.reads, hasLength(1));
      expect(repository.notificationReads, isEmpty);
      await selectTab(tester, MessageCenterTab.notifications);
      repository.notificationReads.single.result.complete(
        notificationTestPage([notificationTestItem('1', duplicateCount: 3)]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ForumHtmlContentView), findsOneWidget);
      expect(
        find.text(l10n(tester).messageRepeatedNotifications(3)),
        findsOneWidget,
      );
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
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
      await tester.pump();
      // Sending schedules the pop after the editor rebuilds its PopScope.
      // Start that reverse route animation before advancing its duration.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.reads, hasLength(2));
      repository.reads.last.result.complete(
        messageTestPage([messageTestItem('100', sender: '10')]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NewPrivateMessagePage), findsNothing);
    },
  );

  testWidgets(
    'group directory item opens its conversation ID rather than its author',
    (tester) async {
      await pumpCenter(tester);
      repository.reads.single.result.complete(
        messageTestPage([
          const ForumPrivateMessageItem(
            messageId: '80',
            conversationId: '91',
            isNew: true,
            subject: 'Reading group',
            fromUserId: '20',
            fromUserName: 'Alice',
            toUserId: '0',
            toUserName: '',
            message: 'Latest discussion',
            sentAt: null,
            rawDateline: '',
            isGroupConversation: true,
            participantCount: 3,
          ),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reading group'));
      await tester.pump();
      expect(
        repository.reads.last.query.target,
        const ForumConversationTarget.group('91'),
      );
      repository.reads.last.result.complete(
        messageTestPage([messageTestItem('80')], anchor: '80'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PrivateConversationPage), findsOneWidget);
      expect(find.text('Reading group'), findsOneWidget);
    },
  );

  testWidgets('both feed scroll positions survive swipes and tab taps', (
    tester,
  ) async {
    await pumpCenter(tester);
    repository.reads.single.result.complete(
      messageTestPage([
        for (var i = 0; i < 20; i++)
          messageTestItem('$i', sender: '10', recipient: '${i + 20}'),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      feedList(MessageCenterTab.messages),
      const Offset(0, -650),
    );
    await tester.pumpAndSettle();
    final messageOffset = feedPosition(
      tester,
      MessageCenterTab.messages,
    ).pixels;
    expect(messageOffset, greaterThan(0));
    await selectTab(tester, MessageCenterTab.notifications);
    repository.notificationReads.single.result.complete(
      notificationTestPage([
        for (var i = 0; i < 20; i++) notificationTestItem('$i'),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      feedList(MessageCenterTab.notifications),
      const Offset(0, -430),
    );
    await tester.pumpAndSettle();
    final notificationOffset = feedPosition(
      tester,
      MessageCenterTab.notifications,
    ).pixels;
    expect(notificationOffset, greaterThan(0));

    await swipeToTab(tester, MessageCenterTab.messages);
    expect(
      feedPosition(tester, MessageCenterTab.messages).pixels,
      closeTo(messageOffset, 0.1),
    );
    await selectTab(tester, MessageCenterTab.notifications);
    expect(
      feedPosition(tester, MessageCenterTab.notifications).pixels,
      closeTo(notificationOffset, 0.1),
    );
    await swipeToTab(tester, MessageCenterTab.messages);
    expect(
      feedPosition(tester, MessageCenterTab.messages).pixels,
      closeTo(messageOffset, 0.1),
    );
    expect(repository.reads, hasLength(1));
    expect(repository.notificationReads, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account replacement removes both retained feeds and their scroll positions',
    (tester) async {
      await pumpCenter(tester);
      repository.reads.single.result.complete(
        messageTestPage([
          for (var i = 0; i < 20; i++)
            messageTestItem(
              '$i',
              sender: '10',
              recipient: '${i + 20}',
              html: '<p>Old private $i</p>',
            ),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        feedList(MessageCenterTab.messages),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(
        feedPosition(tester, MessageCenterTab.messages).pixels,
        greaterThan(0),
      );
      await swipeToTab(tester, MessageCenterTab.notifications);
      repository.notificationReads.single.result.complete(
        notificationTestPage([
          for (var i = 0; i < 20; i++)
            notificationTestItem('$i', markup: '<p>Old reminder $i</p>'),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        feedList(MessageCenterTab.notifications),
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      expect(
        feedPosition(tester, MessageCenterTab.notifications).pixels,
        greaterThan(0),
      );

      container.updateOverrides([
        messageAccountIdProvider.overrideWithValue('11'),
        messageRepositoryProvider.overrideWithValue(repository),
      ]);
      await tester.pump();
      await tester.pump();
      expect(repository.reads, hasLength(2));
      expect(repository.notificationReads, hasLength(1));
      repository.reads.last.result.complete(
        messageTestPage([
          messageTestItem(
            '201',
            sender: '10',
            html: '<p>New private message</p>',
          ),
        ], owner: '11'),
      );
      await tester.pumpAndSettle();
      expect(
        feedPosition(tester, MessageCenterTab.messages, account: '11').pixels,
        0,
      );
      expect(
        find.byKey(
          const PageStorageKey('private-message-list:10'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const PageStorageKey('notification-list:10'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        find.textContaining(
          'Old private',
          findRichText: true,
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        find.textContaining(
          'Old reminder',
          findRichText: true,
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(find.text('New private message').hitTestable(), findsOneWidget);

      await swipeToTab(tester, MessageCenterTab.notifications);
      expect(repository.notificationReads, hasLength(2));
      repository.notificationReads.last.result.complete(
        notificationTestPage([
          notificationTestItem('201', markup: '<p>New reminder</p>'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(
        feedPosition(
          tester,
          MessageCenterTab.notifications,
          account: '11',
        ).pixels,
        0,
      );
      expect(
        find.text('New reminder', findRichText: true).hitTestable(),
        findsOneWidget,
      );
      expect(repository.reads, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

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
