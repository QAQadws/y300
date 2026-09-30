import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/data/models/my_message_models.dart';
import 'package:y300/features/profile/data/repositories/my_message_repository.dart';
import 'package:y300/features/profile/presentation/my_message_center_page.dart';

void main() {
  testWidgets('MyMessageCenterPage shows notifications and private messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myMessageRepositoryProvider.overrideWithValue(
            const _FakeMyMessageRepository(),
          ),
          forumImageRefererProvider.overrideWithValue(
            'https://bbs.yamibo.com/',
          ),
        ],
        child: const LocalizedTestApp(home: MyMessageCenterPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('消息提醒'), findsOneWidget);
    expect(find.byKey(const Key('my-message-center-tabs')), findsOneWidget);
    expect(find.text('提醒 1'), findsOneWidget);
    expect(find.byKey(const Key('my-notification-list')), findsOneWidget);
    expect(find.text('示例用户'), findsOneWidget);
    expect(_richTextContaining('点评了您'), findsOneWidget);

    await tester.tap(find.text('消息 1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('my-private-message-list')), findsOneWidget);
    expect(find.text('测试消息'), findsOneWidget);
    expect(find.text('收到，这是一条测试消息'), findsOneWidget);
  });

  testWidgets('localizes Traditional Chinese chrome and preserves messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myMessageRepositoryProvider.overrideWithValue(
            const _FakeMyMessageRepository(),
          ),
          forumImageRefererProvider.overrideWithValue(
            'https://bbs.yamibo.com/',
          ),
        ],
        child: const LocalizedTestApp(
          locale: Locale('zh', 'TW'),
          home: MyMessageCenterPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('訊息提醒'), findsOneWidget);
    expect(find.text('提醒 1'), findsOneWidget);
    expect(find.text('示例用户'), findsOneWidget);
  });

  testWidgets('localizes Traditional Chinese chrome and preserves messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myMessageRepositoryProvider.overrideWithValue(
            const _FakeMyMessageRepository(),
          ),
          forumImageRefererProvider.overrideWithValue(
            'https://bbs.yamibo.com/',
          ),
        ],
        child: const LocalizedTestApp(
          locale: Locale('zh', 'TW'),
          home: MyMessageCenterPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('訊息提醒'), findsOneWidget);
    expect(find.text('提醒 1'), findsOneWidget);
    expect(find.text('示例用户'), findsOneWidget);
  });
}

class _FakeMyMessageRepository implements MyMessageRepository {
  const _FakeMyMessageRepository();

  @override
  Future<ApiResult<MyMessageCenterData>> getMessageCenter() async {
    return const ApiSuccess<MyMessageCenterData>(
      MyMessageCenterData(
        notifications: MyNotificationPage(
          count: 1,
          page: 1,
          perPage: 30,
          items: [
            MyNotificationItem(
              id: '42',
              type: 'pcomment',
              isNew: false,
              authorId: '12',
              author: '示例用户',
              noteHtml: '<a href="home.php?mod=space&uid=12">示例用户</a> 点评了您',
              dateline: '2025-01-02 12:00',
            ),
          ],
        ),
        privateMessages: MyPrivateMessagePage(
          count: 1,
          page: 1,
          perPage: 15,
          items: [
            MyPrivateMessageItem(
              plid: '77',
              pmid: '77',
              isNew: false,
              subject: '测试消息',
              fromUid: '42',
              fromName: '示例发件人',
              toUid: '12',
              toName: '示例用户',
              message: '收到，这是一条测试消息',
              dateline: '2025-01-02 12:30',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Future<ApiResult<MyNotificationPage>> getNotifications() async {
    return ApiSuccess((await getMessageCenter()).dataOrNull!.notifications);
  }

  @override
  Future<ApiResult<MyPrivateMessagePage>> getPrivateMessages() async {
    return ApiSuccess((await getMessageCenter()).dataOrNull!.privateMessages);
  }
}

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate((widget) {
    if (widget is! RichText) {
      return false;
    }
    return widget.text.toPlainText().contains(text);
  });
}
