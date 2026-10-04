import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/messages/presentation/conversation_message_presentation.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/widgets/conversation_message_tile.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  late ProviderContainer container;
  late String currentAccount;
  final links = <String>[];
  const direct = ForumConversationTarget.direct('20');
  const group = ForumConversationTarget.group('91');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    currentAccount = '10';
    links.clear();
    container = ProviderContainer.test(
      overrides: [
        messageAccountIdProvider.overrideWith((ref) => currentAccount),
        forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
      ],
    );
  });

  Future<void> pumpTiles(
    WidgetTester tester,
    List<ForumPrivateMessageItem> items, {
    ForumConversationTarget target = direct,
    bool use24HourFormat = true,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(alwaysUse24HourFormat: use24HourFormat),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final row in deriveConversationMessagePresentations(
                    items,
                  ))
                    ConversationMessageTile(
                      key: ValueKey(row.item.messageId),
                      presentation: row,
                      accountId: '10',
                      target: target,
                      imageReferer: 'https://bbs.yamibo.com/',
                      onOpenLink: (_, url) => links.add(url),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) => AppLocalizations.of(
    tester.element(find.byType(ConversationMessageTile).first),
  );

  Finder bubble(String id) => find.byKey(ValueKey('conversation-bubble-$id'));

  testWidgets(
    'direct chats hide author labels and missing time adds no top gap',
    (tester) async {
      await pumpTiles(tester, [_item('1')]);

      expect(find.text('Alice'), findsNothing);
      expect(find.byKey(const ValueKey('message-time:1')), findsNothing);
      expect(
        tester.getTopLeft(bubble('1')).dy,
        tester.getTopLeft(find.byKey(const ValueKey('1'))).dy,
      );
      final content = tester.widget<ForumHtmlContentView>(
        find.byType(ForumHtmlContentView),
      );
      expect(content.contentLayout, ForumHtmlContentLayout.compact);
      expect(content.imageCacheOwnerId, 'private:10:direct:20:1');

      await tester.tap(find.byKey(const ValueKey('message-avatar:1')));
      expect(links, ['home.php?mod=space&uid=20']);
      expect(
        tester.getSize(find.byKey(const ValueKey('message-avatar:1'))),
        const Size(48, 48),
      );
    },
  );

  testWidgets(
    'incoming group names occur only before the first bubble in each group',
    (tester) async {
      final time = DateTime(2026, 9, 12, 10, 30);
      await pumpTiles(tester, [
        _item('1', time: time),
        _item('2', time: time),
        _item('3', time: time, sender: '10', name: 'Me'),
      ], target: group);

      expect(find.byKey(const ValueKey('message-author:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-author:2')), findsNothing);
      expect(find.text('Me'), findsNothing);
      expect(find.byKey(const ValueKey('message-avatar:2')), findsNothing);
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('message-author:1'))).dy,
        lessThan(tester.getTopLeft(bubble('1')).dy),
      );
      expect(
        find.descendant(of: bubble('1'), matching: find.text('Alice')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: bubble('1'),
          matching: find.byKey(const ValueKey('message-time:1')),
        ),
        findsNothing,
      );
      final firstBottomGap =
          tester.getBottomLeft(find.byKey(const ValueKey('1'))).dy -
          tester.getBottomLeft(bubble('1')).dy;
      final groupedBottomGap =
          tester.getBottomLeft(find.byKey(const ValueKey('2'))).dy -
          tester.getBottomLeft(bubble('2')).dy;
      expect(firstBottomGap, closeTo(groupedBottomGap, 0.01));
    },
  );

  testWidgets(
    'details preserve original selectable HTML, image owner and local full time',
    (tester) async {
      final time = DateTime(2026, 9, 12, 18, 30, 42);
      const html =
          '<p>Original <strong>message</strong></p><p>Second paragraph</p>';
      await pumpTiles(tester, [_item('1', time: time, html: html)]);
      final semanticAction = tester.widget<Semantics>(
        find
            .ancestor(
              of: bubble('1'),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.onLongPress != null,
              ),
            )
            .first,
      );
      expect(
        semanticAction.properties.hintOverrides?.onLongPressHint,
        l10n(tester).messageDetails,
      );

      await tester.longPress(bubble('1'));
      await tester.pumpAndSettle();

      expect(find.text(l10n(tester).messageDetails), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(
        find.text(
          DateFormat.yMd(l10n(tester).localeName).add_Hms().format(time),
        ),
        findsOneWidget,
      );
      final detailsFinder = find.byWidgetPredicate(
        (widget) =>
            widget is ForumHtmlContentView &&
            widget.sourceId.endsWith(':details'),
      );
      final details = tester.widget<ForumHtmlContentView>(detailsFinder);
      expect(details.html, html);
      expect(details.contentLayout, ForumHtmlContentLayout.document);
      expect(details.imageCacheOwnerId, 'private:10:direct:20:1');
      expect(details.imageReferer, 'https://bbs.yamibo.com/');
      expect(
        find.ancestor(of: detailsFinder, matching: find.byType(SelectionArea)),
        findsOneWidget,
      );

      currentAccount = '30';
      container.invalidate(messageAccountIdProvider);
      await tester.pumpAndSettle();
      expect(detailsFinder, findsNothing);
      expect(find.text(l10n(tester).messageDetails), findsNothing);
    },
  );

  testWidgets(
    'unknown time remains in details and supplied raw time is preserved',
    (tester) async {
      await pumpTiles(tester, [_item('1')]);
      expect(find.text(l10n(tester).messageTimeUnknown), findsNothing);
      await tester.longPress(bubble('1'));
      await tester.pumpAndSettle();
      expect(find.text(l10n(tester).messageTimeUnknown), findsOneWidget);
      await tester.tap(find.byTooltip(l10n(tester).commonClose));
      await tester.pumpAndSettle();

      await pumpTiles(tester, [
        _item('1', rawDateline: 'Original server date'),
      ]);
      expect(find.text('Original server date'), findsOneWidget);
    },
  );

  testWidgets('details use the locale clock when system does not force 24h', (
    tester,
  ) async {
    final time = DateTime(2026, 9, 12, 18, 30, 42);
    await pumpTiles(tester, [_item('1', time: time)], use24HourFormat: false);
    await tester.longPress(bubble('1'));
    await tester.pumpAndSettle();
    expect(
      find.text(DateFormat.yMd(l10n(tester).localeName).add_jms().format(time)),
      findsOneWidget,
    );
  });
}

ForumPrivateMessageItem _item(
  String id, {
  DateTime? time,
  String rawDateline = '',
  String sender = '20',
  String name = 'Alice',
  String html = '<p>Hello</p>',
}) => ForumPrivateMessageItem(
  messageId: id,
  conversationId: '91',
  isNew: false,
  subject: '',
  fromUserId: sender,
  fromUserName: name,
  toUserId: sender == '10' ? '20' : '10',
  toUserName: sender == '10' ? 'Alice' : 'Me',
  message: html,
  sentAt: time,
  rawDateline: rawDateline,
);
