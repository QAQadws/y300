import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart' as forum;
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/profile/data/models/my_message_models.dart';

abstract class MyMessageRepository {
  Future<ApiResult<MyMessageCenterData>> getMessageCenter();
  Future<ApiResult<MyNotificationPage>> getNotifications();
  Future<ApiResult<MyPrivateMessagePage>> getPrivateMessages();
}

final class PackageMyMessageRepository implements MyMessageRepository {
  const PackageMyMessageRepository(this._client);
  final forum.YamiboForumClient _client;

  @override
  Future<ApiResult<MyMessageCenterData>> getMessageCenter() async {
    final notifications = await getNotifications();
    if (notifications case ApiFailure<MyNotificationPage>(:final error)) {
      return ApiFailure(error);
    }
    final messages = await getPrivateMessages();
    if (messages case ApiFailure<MyPrivateMessagePage>(:final error)) {
      return ApiFailure(error);
    }
    return ApiSuccess(
      MyMessageCenterData(
        notifications: notifications.dataOrNull!,
        privateMessages: messages.dataOrNull!,
      ),
    );
  }

  @override
  Future<ApiResult<MyNotificationPage>> getNotifications() async {
    final result = await _client.loadNotifications(
      const forum.ForumNotificationQuery(),
    );
    if (result
        case forum.DataReadFailure<
              forum.ForumNotificationPage,
              forum.ForumNotificationReadCapabilities
            >()) {
      return ApiFailure(_error(result));
    }
    final page =
        (result
                as forum.DataReadSuccess<
                  forum.ForumNotificationPage,
                  forum.ForumNotificationReadCapabilities
                >)
            .data;
    return ApiSuccess(
      MyNotificationPage(
        items: [
          for (final item in page.items)
            MyNotificationItem(
              id: item.id,
              type: item.type,
              isNew: item.isNew,
              authorId: item.authorId,
              author: item.authorName,
              noteHtml: item.noteMarkup,
              dateline: _notificationDateline(item),
            ),
        ],
        count: page.count,
        page: page.page,
        perPage: page.perPage,
      ),
    );
  }

  @override
  Future<ApiResult<MyPrivateMessagePage>> getPrivateMessages() async {
    final result = await _client.loadPrivateMessages(
      const forum.ForumPrivateMessageQuery(),
    );
    if (result
        case forum.DataReadFailure<
              forum.ForumPrivateMessagePage,
              forum.ForumPrivateMessageReadCapabilities
            >()) {
      return ApiFailure(_error(result));
    }
    final page =
        (result
                as forum.DataReadSuccess<
                  forum.ForumPrivateMessagePage,
                  forum.ForumPrivateMessageReadCapabilities
                >)
            .data;
    return ApiSuccess(
      MyPrivateMessagePage(
        items: [
          for (final item in page.items)
            MyPrivateMessageItem(
              plid: item.conversationId ?? '',
              pmid: item.messageId,
              isNew: item.isNew,
              subject: item.subject,
              fromUid: item.fromUserId,
              fromName: item.fromUserName,
              toUid: item.toUserId,
              toName: item.toUserName,
              message: item.message,
              dateline: _messageDateline(item),
            ),
        ],
        count: page.count,
        page: page.page,
        perPage: page.perPage,
      ),
    );
  }

  String _notificationDateline(forum.ForumNotificationItem item) {
    final dateTime = item.occurredAt?.toLocal();
    if (dateTime == null) return item.rawDateline;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}-${two(dateTime.month)}-${two(dateTime.day)} '
        '${two(dateTime.hour)}:${two(dateTime.minute)}';
  }

  String _messageDateline(forum.ForumPrivateMessageItem item) {
    final dateTime = item.sentAt?.toLocal();
    if (dateTime == null) return item.rawDateline;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}-${two(dateTime.month)}-${two(dateTime.day)} '
        '${two(dateTime.hour)}:${two(dateTime.minute)}';
  }

  ApiError _error<T, C>(forum.DataReadFailure<T, C> failure) => ApiError(
    type: switch (failure.kind) {
      forum.DataReadFailureKind.network ||
      forum.DataReadFailureKind.cancelled => ApiErrorType.network,
      forum.DataReadFailureKind.timeout => ApiErrorType.timeout,
      forum.DataReadFailureKind.unauthorized => ApiErrorType.unauthorized,
      forum.DataReadFailureKind.server => ApiErrorType.server,
      forum.DataReadFailureKind.parse => ApiErrorType.parse,
      forum.DataReadFailureKind.business ||
      forum.DataReadFailureKind.unsupported => ApiErrorType.business,
      forum.DataReadFailureKind.unknown => ApiErrorType.unknown,
    },
    message: failure.diagnosticMessage,
    code: failure.code,
    statusCode: failure.statusCode,
  );
}

final myMessageRepositoryProvider = Provider<MyMessageRepository>((ref) {
  return PackageMyMessageRepository(ref.watch(yamiboForumClientProvider));
});
