import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/private_conversation_page.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../support/message_test_repository.dart';

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
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: PrivateConversationPage(
            target: destination,
            title: 'Alice',
            onOpenLink: (_, url) => links.add(url),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(PrivateConversationPage)));

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

  testWidgets(
    'group send uses response anchor and refreshes only after applied',
    (tester) async {
      await pumpPage(
        tester,
        destination: const ForumConversationTarget.group('91'),
      );
      repository.reads.single.result.complete(
        messageTestPage([messageTestItem('1')], anchor: '77'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('message-input')), 'reply');
      await tester.pump();
      await tester.tap(find.byKey(const Key('message-send')));
      await tester.pump();
      expect(repository.sends.single.submission.recipient.replyMessageId, '77');
      expect(repository.reads, hasLength(1));
      repository.sends.single.succeed();
      await tester.pump();
      expect(repository.reads, hasLength(2));
      repository.reads.last.result.complete(
        messageTestPage([
          messageTestItem('1'),
          messageTestItem('100', sender: '10'),
        ], anchor: '100'),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('message-input')))
            .controller!
            .text,
        isEmpty,
      );
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
        await tester.enterText(
          find.byKey(const Key('message-input')),
          'multiple\nlines\nof\ninput',
        );
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
}
