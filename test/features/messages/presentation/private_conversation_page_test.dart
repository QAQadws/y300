import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/private_conversation_page.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../support/message_test_repository.dart';
import '../support/message_input_test_helper.dart';

void main() {
  late MessageTestRepository repository;
  late ProviderContainer container;
  final links = <String>[];
  const target = ForumConversationTarget.direct('20');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    links.clear();
    repository = MessageTestRepository();
    container = ProviderContainer.test(
      overrides: [
        messageAccountIdProvider.overrideWithValue('10'),
        messageRepositoryProvider.overrideWithValue(repository),
        forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
      ],
    );
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    ForumConversationTarget destination = target,
    Brightness brightness = Brightness.light,
    double textScale = 1,
    String title = 'Alice',
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          theme: AppTheme.build(
            family: AppThemeFamily.warmPaper,
            brightness: brightness,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: PrivateConversationPage(
            target: destination,
            title: title,
            onOpenLink: (_, url) => links.add(url),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(PrivateConversationPage)));

  Finder timeline() => find.byKey(const Key('private-conversation-list'));

  ScrollController scrollController(WidgetTester tester) =>
      tester.widget<CustomScrollView>(timeline()).controller!;

  void expectLatest(WidgetTester tester, String messageId) {
    final scroll = scrollController(tester);
    expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 0.1));
    expect(
      tester.getBottomLeft(find.byKey(ValueKey(messageId))).dy,
      closeTo(tester.getBottomLeft(timeline()).dy, 0.1),
    );
    expect(find.text(l10n(tester).messageLatest), findsNothing);
  }

  Future<void> refreshMessages(
    WidgetTester tester,
    List<ForumPrivateMessageItem> items, {
    ForumConversationTarget destination = target,
  }) async {
    final refresh = container
        .read(privateMessageFeedProvider(destination))
        .refresh();
    repository.reads.last.result.complete(messageTestPage(items));
    await refresh;
    await tester.pumpAndSettle();
  }

  for (final entry in {0: 'empty', 2: 'short', 30: 'long'}.entries) {
    testWidgets(
      '${entry.value} conversation refreshes only when pulling down at the physical top',
      (tester) async {
        await pumpPage(tester);
        final items = [
          for (var id = 1; id <= entry.key; id++) messageTestItem('$id'),
        ];
        repository.reads.single.result.complete(messageTestPage(items));
        await tester.pumpAndSettle();
        expect(find.byTooltip(l10n(tester).messageRefresh), findsNothing);

        // The reversed timeline initially shows its newest/bottom edge. An
        // upward pull there must not become a bottom-positioned refresh action.
        await tester.drag(timeline(), const Offset(0, -300));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(repository.reads, hasLength(1));

        final scroll = scrollController(tester);
        for (var attempt = 0; attempt < 3; attempt++) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
          await tester.pumpAndSettle();
        }
        await tester.drag(timeline(), const Offset(0, 360));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(repository.reads, hasLength(2));
        expect(repository.reads.last.query.page, 0);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        repository.reads.last.result.complete(messageTestPage(items));
        await tester.pumpAndSettle();
        expect(repository.reads, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('refresh pending does not move the viewport or reading anchor', (
    tester,
  ) async {
    await pumpPage(tester);
    final items = [for (var id = 1; id <= 30; id++) messageTestItem('$id')];
    repository.reads.single.result.complete(messageTestPage(items));
    await tester.pumpAndSettle();
    scrollController(tester).jumpTo(350);
    await tester.pumpAndSettle();
    final viewportBefore = tester.getRect(timeline());
    final visible = tester
        .widgetList<ForumHtmlContentView>(find.byType(ForumHtmlContentView))
        .firstWhere((widget) {
          final rect = tester.getRect(find.byWidget(widget));
          return rect.top > viewportBefore.top &&
              rect.bottom < viewportBefore.bottom;
        });
    Finder anchor() => find.byWidgetPredicate(
      (widget) =>
          widget is ForumHtmlContentView && widget.sourceId == visible.sourceId,
    );
    final messageBefore = tester.getRect(anchor());
    final refresh = container
        .read(privateMessageFeedProvider(target))
        .refresh();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.reads, hasLength(2));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.getRect(timeline()), viewportBefore);
    expect(tester.getRect(anchor()), messageBefore);
    repository.reads.last.result.complete(messageTestPage(items));
    await refresh;
    await tester.pumpAndSettle();
    expect(tester.getRect(timeline()), viewportBefore);
    expect(tester.getRect(anchor()), messageBefore);
    expect(tester.takeException(), isNull);
  });

  for (final destination in [
    target,
    const ForumConversationTarget.group('91'),
  ]) {
    testWidgets(
      '${destination.kind.name} short conversation starts at top and grows downward',
      (tester) async {
        await pumpPage(tester, destination: destination);
        repository.reads.single.result.complete(
          messageTestPage([messageTestItem('1')], anchor: '1'),
        );
        await tester.pumpAndSettle();
        final top = tester.getTopLeft(timeline()).dy;
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('1'))).dy,
          closeTo(top, 0.1),
        );

        await refreshMessages(tester, [
          messageTestItem('1'),
          messageTestItem('2', sender: '10'),
        ], destination: destination);
        final first = tester.getRect(find.byKey(const ValueKey('1')));
        final second = tester.getRect(find.byKey(const ValueKey('2')));
        expect(first.top, closeTo(top, 0.1));
        expect(second.top, closeTo(first.bottom, 0.1));
        expect(second.bottom, lessThan(tester.getBottomLeft(timeline()).dy));
        expect(find.text(l10n(tester).messageOlder), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('appending messages crosses a screen without losing latest', (
    tester,
  ) async {
    await pumpPage(tester);
    repository.reads.single.result.complete(
      messageTestPage([messageTestItem('1')]),
    );
    await tester.pumpAndSettle();
    var becameScrollable = false;
    for (var count = 2; count <= 18; count++) {
      await refreshMessages(tester, [
        for (var id = 1; id <= count; id++) messageTestItem('$id'),
      ]);
      final bounds = tester.getRect(timeline());
      final scroll = scrollController(tester);
      final last = tester.getRect(find.byKey(ValueKey('$count')));
      expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 0.1));
      expect(last.bottom, lessThanOrEqualTo(bounds.bottom + 0.1));
      if (scroll.position.maxScrollExtent - scroll.position.minScrollExtent >
          0.1) {
        becameScrollable = true;
        expectLatest(tester, '$count');
      } else {
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('1'))).dy,
          closeTo(bounds.top, 0.1),
        );
      }
      await tester.pump();
      expect(
        tester.getBottomLeft(find.byKey(ValueKey('$count'))).dy,
        closeTo(last.bottom, 0.1),
      );
    }
    expect(becameScrollable, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long conversation follows latest through keyboard, input, font, and HTML changes',
    (tester) async {
      await pumpPage(tester);
      repository.reads.single.result.complete(
        messageTestPage([
          for (var id = 1; id <= 20; id++) messageTestItem('$id'),
        ]),
      );
      await tester.pumpAndSettle();
      expectLatest(tester, '20');

      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(tester.view.resetViewInsets);
      await enterMessageText(tester, 'multiple\nlines\nof\ninput');
      await tester.pumpAndSettle();
      expectLatest(tester, '20');

      await container
          .read(forumHtmlReaderPreferencesControllerProvider.notifier)
          .setFontScale(1.6);
      await tester.pumpAndSettle();
      expectLatest(tester, '20');
      await refreshMessages(tester, [
        for (var id = 1; id < 20; id++) messageTestItem('$id'),
        messageTestItem(
          '20',
          html: '<p>Expanded body</p><p>Another paragraph</p>',
        ),
      ]);
      expectLatest(tester, '20');

      tester.view.resetViewInsets();
      await enterMessageText(tester, '');
      await tester.pumpAndSettle();
      expectLatest(tester, '20');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opens latest page, shares thread typography, and dispatches links',
    (tester) async {
      await pumpPage(tester);
      expect(repository.reads.single.query.target, target);
      expect(repository.reads.single.query.page, 0);
      repository.reads.single.result.complete(
        messageTestPage([
          messageTestItem(
            '1',
            html:
                '<p><a href="forum.php?mod=viewthread&amp;tid=42">Thread link</a></p>',
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message-input')), findsOneWidget);
      final view = tester.widget<ForumHtmlContentView>(
        find.byType(ForumHtmlContentView),
      );
      expect(view.imageCacheOwnerId, 'private:10:direct:20:1');
      view.onOpenLink!('forum.php?mod=viewthread&tid=42');
      expect(links.single, contains('tid=42'));
      await container
          .read(forumHtmlReaderPreferencesControllerProvider.notifier)
          .setFontScale(1.6);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ForumHtmlWidgetPostRenderer>(
              find.byType(ForumHtmlWidgetPostRenderer),
            )
            .preferences!
            .typography
            .fontScale,
        1.6,
      );
      expect(repository.reads, hasLength(1));
    },
  );

  testWidgets(
    'dragging into history suspends latest following until explicitly resumed',
    (tester) async {
      await pumpPage(tester);
      repository.reads.single.result.complete(
        messageTestPage([
          for (var id = 1; id <= 20; id++) messageTestItem('$id'),
        ]),
      );
      await tester.pumpAndSettle();
      expectLatest(tester, '20');

      await tester.drag(timeline(), const Offset(0, 300));
      await tester.pumpAndSettle();
      final scroll = scrollController(tester);
      expect(scroll.offset - scroll.position.minScrollExtent, greaterThan(80));
      expect(find.text(l10n(tester).messageLatest), findsOneWidget);
      final bounds = tester.getRect(timeline());
      final visible = tester
          .widgetList<ForumHtmlContentView>(find.byType(ForumHtmlContentView))
          .firstWhere((widget) {
            final rect = tester.getRect(find.byWidget(widget));
            return rect.top > bounds.top && rect.bottom < bounds.bottom;
          });
      Finder anchor() => find.byWidgetPredicate(
        (widget) =>
            widget is ForumHtmlContentView &&
            widget.sourceId == visible.sourceId,
      );
      final before = tester.getTopLeft(anchor()).dy;

      final refresh = container
          .read(privateMessageFeedProvider(target))
          .refresh();
      repository.reads.last.result.complete(
        messageTestPage([
          for (var id = 1; id <= 21; id++) messageTestItem('$id'),
        ], page: 2),
      );
      await refresh;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor()).dy, closeTo(before, 0.1));
      expect(find.text(l10n(tester).messageLatest), findsOneWidget);

      await tester.tap(find.text(l10n(tester).messageLatest));
      await tester.pumpAndSettle();
      expectLatest(tester, '21');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'growing both history and recent messages preserves the visible reading anchor',
    (tester) async {
      await pumpPage(tester);
      repository.reads.single.result.complete(
        messageTestPage(
          [for (var id = 21; id <= 40; id++) messageTestItem('$id')],
          page: 2,
          count: 40,
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(
            find.byKey(const Key('private-conversation-list')),
          )
          .controller!;
      scroll.jumpTo(350);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(
        find.byKey(const Key('private-conversation-list')),
      );
      final visible =
          find
                  .byType(ForumHtmlContentView)
                  .evaluate()
                  .where((element) {
                    final rect = tester.getRect(find.byWidget(element.widget));
                    return rect.top > bounds.top && rect.bottom < bounds.bottom;
                  })
                  .first
                  .widget
              as ForumHtmlContentView;
      final source = visible.sourceId;
      Finder anchor() => find.byWidgetPredicate(
        (widget) => widget is ForumHtmlContentView && widget.sourceId == source,
      );
      final before = tester.getTopLeft(anchor());
      final controller = container.read(privateMessageFeedProvider(target));
      final older = controller.loadMore();
      expect(repository.reads.last.query.page, 1);
      repository.reads.last.result.complete(
        messageTestPage(
          [for (var id = 1; id <= 20; id++) messageTestItem('$id')],
          page: 1,
          count: 40,
        ),
      );
      await older;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor()).dy, closeTo(before.dy, 0.1));
      final latest = controller.refresh();
      repository.reads.last.result.complete(
        messageTestPage(
          [for (var id = 39; id <= 42; id++) messageTestItem('$id')],
          page: 3,
          count: 42,
        ),
      );
      await latest;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor()).dy, closeTo(before.dy, 0.1));
      await tester.tap(find.text(l10n(tester).messageLatest));
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 0.1));
      expect(find.byKey(const ValueKey('42')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('group send returns from history to latest only after applied', (
    tester,
  ) async {
    await pumpPage(
      tester,
      destination: const ForumConversationTarget.group('91'),
    );
    repository.reads.single.result.complete(
      messageTestPage([
        for (var id = 1; id <= 20; id++) messageTestItem('$id'),
      ], anchor: '77'),
    );
    await tester.pumpAndSettle();
    final scroll = scrollController(tester);
    scroll.jumpTo(350);
    await tester.pumpAndSettle();
    await enterMessageText(tester, 'reply');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message-send')));
    await tester.pump();
    expect(repository.sends.single.submission.recipient.replyMessageId, '77');
    expect(repository.reads, hasLength(1));
    expect(scroll.offset - scroll.position.minScrollExtent, greaterThan(80));
    repository.sends.single.succeed();
    await tester.pump();
    expect(repository.reads, hasLength(2));
    repository.reads.last.result.complete(
      messageTestPage(
        [
          for (var id = 1; id <= 20; id++) messageTestItem('$id'),
          messageTestItem('100', sender: '10'),
        ],
        page: 2,
        anchor: '100',
      ),
    );
    await tester.pumpAndSettle();
    expect(messageInputValue(tester), isEmpty);
    expectLatest(tester, '100');
    expect(tester.takeException(), isNull);
  });

  const sendFailure = DataCommandFailure(
    kind: DataCommandFailureKind.network,
    retryPolicy: DataCommandRetryPolicy.explicitOnly,
    diagnosticMessage: 'message_send_failed',
  );
  for (final result in <DataCommandResult<ForumPrivateMessageReceipt>>[
    const DataCommandNotSent(sendFailure),
    const DataCommandOutcomeUnknown(sendFailure),
  ]) {
    testWidgets('${result.runtimeType} keeps the reader in history', (
      tester,
    ) async {
      await pumpPage(tester);
      repository.reads.single.result.complete(
        messageTestPage([
          for (var id = 1; id <= 20; id++) messageTestItem('$id'),
        ]),
      );
      await tester.pumpAndSettle();
      final scroll = scrollController(tester);
      scroll.jumpTo(350);
      await tester.pumpAndSettle();
      await enterMessageText(tester, 'reply');
      await tester.pump();
      await tester.tap(find.byKey(const Key('message-send')));
      await tester.pump();
      repository.sends.single.result.complete(result);
      await tester.pumpAndSettle();
      expect(repository.reads, hasLength(1));
      expect(scroll.offset - scroll.position.minScrollExtent, greaterThan(80));
      expect(find.text(l10n(tester).messageLatest), findsOneWidget);
      expect(messageInputValue(tester), 'reply');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'account switch resets history position and ignores late refresh',
    (tester) async {
      await pumpPage(tester);
      repository.reads.single.result.complete(
        messageTestPage([
          for (var id = 1; id <= 20; id++) messageTestItem('$id'),
        ]),
      );
      await tester.pumpAndSettle();
      scrollController(tester).jumpTo(350);
      await enterMessageText(tester, 'old draft');
      final oldRefresh = container
          .read(privateMessageFeedProvider(target))
          .refresh();
      final oldRead = repository.reads.last;
      container.updateOverrides([
        messageAccountIdProvider.overrideWithValue('11'),
        messageRepositoryProvider.overrideWithValue(repository),
        forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(oldRead.query.cancellation?.isCancelled, isTrue);
      repository.reads.last.result.complete(
        messageTestPage([messageTestItem('200')], owner: '11'),
      );
      oldRead.result.complete(messageTestPage([messageTestItem('100')]));
      await oldRefresh;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('100')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('200'))).dy,
        closeTo(tester.getTopLeft(timeline()).dy, 0.1),
      );
      expect(find.text(l10n(tester).messageLatest), findsNothing);
      expect(messageInputValue(tester), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'narrow large text conversation fits ${brightness.name} theme and keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpPage(tester, brightness: brightness, textScale: 1.8);
        repository.reads.single.result.complete(
          messageTestPage([messageTestItem('1', html: '<p>长消息与共享主题</p>')]),
        );
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.resetViewInsets);
        await enterMessageText(tester, 'multiple\nlines\nof\ninput');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('signed-out conversation offers login without private reads', (
    tester,
  ) async {
    container.updateOverrides([
      messageAccountIdProvider.overrideWithValue(null),
      messageRepositoryProvider.overrideWithValue(repository),
      forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
    ]);
    await pumpPage(tester);
    await tester.pumpAndSettle();
    expect(find.text(l10n(tester).messageLoginRequired), findsOneWidget);
    expect(repository.reads, isEmpty);
  });

  testWidgets('title resolves the peer and details expose selectable HTML', (
    tester,
  ) async {
    await pumpPage(tester, title: '');
    repository.reads.single.result.complete(
      messageTestPage([messageTestItem('1', html: '<p>可复制的正文</p>')]),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Alice')),
      findsOneWidget,
    );
    await tester.longPress(find.byType(ForumHtmlContentView));
    await tester.pumpAndSettle();
    expect(find.text(l10n(tester).messageDetails), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'history loads once per user scroll and failures require manual retry',
    (tester) async {
      await pumpPage(tester);
      repository.reads.single.result.complete(
        messageTestPage(
          [for (var id = 41; id <= 60; id++) messageTestItem('$id')],
          page: 3,
          count: 60,
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.reads, hasLength(1));
      final scroll = scrollController(tester);
      scroll.jumpTo(scroll.position.maxScrollExtent - 210);
      await tester.pumpAndSettle();
      expect(repository.reads, hasLength(1));
      await tester.drag(timeline(), const Offset(0, 120));
      await tester.pump();
      expect(repository.reads, hasLength(2));
      expect(repository.reads.last.query.page, 2);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      repository.reads.last.result.complete(
        const DataReadFailure(
          kind: DataReadFailureKind.network,
          code: 'message_read_failed',
          diagnosticMessage: 'message_read_failed',
        ),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(scroll.position.maxScrollExtent - 100);
      await tester.pumpAndSettle();
      await tester.drag(timeline(), const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(repository.reads, hasLength(2));
      await tester.ensureVisible(find.text(l10n(tester).commonRetry));
      await tester.tap(find.text(l10n(tester).commonRetry));
      await tester.pump();
      expect(repository.reads, hasLength(3));
      expect(repository.reads.last.query.page, 2);
      repository.reads.last.result.complete(
        messageTestPage(
          [for (var id = 21; id <= 40; id++) messageTestItem('$id')],
          page: 2,
          count: 60,
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.reads, hasLength(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short history and layout changes never trigger automatic pagination',
    (tester) async {
      await pumpPage(tester);
      repository.reads.single.result.complete(
        messageTestPage([messageTestItem('21')], page: 2, count: 21),
      );
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(tester.view.resetViewInsets);
      await enterMessageText(tester, '两行\n输入');
      await tester.pumpAndSettle();
      await container
          .read(forumHtmlReaderPreferencesControllerProvider.notifier)
          .setFontScale(1.4);
      await tester.pumpAndSettle();
      expect(repository.reads, hasLength(1));
      expect(find.text(l10n(tester).messageOlder), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'prepending a group removes repeated headers without moving its visible body',
    (tester) async {
      const group = ForumConversationTarget.group('91');
      await pumpPage(tester, destination: group);
      repository.reads.single.result.complete(
        messageTestPage(
          [for (var id = 21; id <= 40; id++) messageTestItem('$id')],
          page: 2,
          count: 40,
        ),
      );
      await tester.pumpAndSettle();
      final scroll = scrollController(tester);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      Finder body() => find.byWidgetPredicate(
        (widget) =>
            widget is ForumHtmlContentView &&
            widget.sourceId == 'private:10:group:91:21',
      );
      final before = tester.getRect(body());
      expect(find.byKey(const ValueKey('message-author:21')), findsOneWidget);
      final older = container
          .read(privateMessageFeedProvider(group))
          .loadMore();
      repository.reads.last.result.complete(
        messageTestPage(
          [for (var id = 1; id <= 20; id++) messageTestItem('$id')],
          page: 1,
          count: 40,
        ),
      );
      await older;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message-author:21')), findsNothing);
      expect(tester.getRect(body()).top, closeTo(before.top, 0.1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account switch closes details and removes the old message', (
    tester,
  ) async {
    await pumpPage(tester);
    repository.reads.single.result.complete(
      messageTestPage([messageTestItem('1', html: '<p>旧账号私信</p>')]),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(ForumHtmlContentView));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionArea), findsOneWidget);
    container.updateOverrides([
      messageAccountIdProvider.overrideWithValue('11'),
      messageRepositoryProvider.overrideWithValue(repository),
      forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
    ]);
    await tester.pump();
    await tester.pump();
    repository.reads.last.result.complete(messageTestPage([], owner: '11'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionArea), findsNothing);
    expect(find.text('旧账号私信', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
