import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
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
          imageRequestHeaderBuilderProvider.overrideWithValue(
            const _StaticImageHeaderBuilder(),
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
    expect(find.text('筱林透'), findsOneWidget);
    expect(_richTextContaining('点评了您'), findsOneWidget);

    await tester.tap(find.text('消息 1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('my-private-message-list')), findsOneWidget);
    expect(find.text('嗨！28君好'), findsOneWidget);
    expect(find.text('好的，我QQ就是2834758851'), findsOneWidget);
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
              id: '4117644',
              type: 'pcomment',
              isNew: false,
              authorId: '8',
              author: '筱林透',
              noteHtml: '<a href="home.php?mod=space&uid=8">筱林透</a> 点评了您',
              dateline: '2026-06-21 12:00',
            ),
          ],
        ),
        privateMessages: MyPrivateMessagePage(
          count: 1,
          page: 1,
          perPage: 15,
          items: [
            MyPrivateMessageItem(
              plid: '133466',
              pmid: '133466',
              isNew: false,
              subject: '嗨！28君好',
              fromUid: '597454',
              fromName: '2834758851',
              toUid: '8',
              toName: '筱林透',
              message: '好的，我QQ就是2834758851',
              dateline: '2026-5-11 19:50',
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

class _StaticImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageHeaderBuilder();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{};
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
