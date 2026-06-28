import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/discuz_response.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_api_client.dart';
import 'package:y300/features/profile/data/models/my_message_models.dart';
import 'package:y300/features/profile/data/services/my_message_parser.dart';

abstract class MyMessageRepository {
  Future<ApiResult<MyMessageCenterData>> getMessageCenter();

  Future<ApiResult<MyNotificationPage>> getNotifications();

  Future<ApiResult<MyPrivateMessagePage>> getPrivateMessages();
}

class YamiboMyMessageRepository implements MyMessageRepository {
  const YamiboMyMessageRepository({
    required YamiboApiClient apiClient,
    MyNotificationParser notificationParser = const MyNotificationParser(),
    MyPrivateMessageParser privateMessageParser =
        const MyPrivateMessageParser(),
  }) : _apiClient = apiClient,
       _notificationParser = notificationParser,
       _privateMessageParser = privateMessageParser;

  final YamiboApiClient _apiClient;
  final MyNotificationParser _notificationParser;
  final MyPrivateMessageParser _privateMessageParser;

  @override
  Future<ApiResult<MyMessageCenterData>> getMessageCenter() async {
    final notificationsResult = await getNotifications();
    if (notificationsResult case ApiFailure<MyNotificationPage>(:final error)) {
      return ApiFailure<MyMessageCenterData>(error);
    }

    final messagesResult = await getPrivateMessages();
    if (messagesResult case ApiFailure<MyPrivateMessagePage>(:final error)) {
      return ApiFailure<MyMessageCenterData>(error);
    }

    return ApiSuccess(
      MyMessageCenterData(
        notifications:
            (notificationsResult as ApiSuccess<MyNotificationPage>).data,
        privateMessages:
            (messagesResult as ApiSuccess<MyPrivateMessagePage>).data,
      ),
    );
  }

  @override
  Future<ApiResult<MyNotificationPage>> getNotifications() async {
    final response = await _apiClient.getDiscuz(module: 'mynotelist');
    return response.when(
      success: (data) => _parseNotifications(data),
      failure: (error) =>
          ApiFailure<MyNotificationPage>(_wrapError('我的提醒加载失败', error)),
    );
  }

  @override
  Future<ApiResult<MyPrivateMessagePage>> getPrivateMessages() async {
    final response = await _apiClient.getDiscuz(module: 'mypm');
    return response.when(
      success: (data) => _parsePrivateMessages(data),
      failure: (error) =>
          ApiFailure<MyPrivateMessagePage>(_wrapError('我的消息加载失败', error)),
    );
  }

  ApiResult<MyNotificationPage> _parseNotifications(DiscuzResponse response) {
    try {
      return ApiSuccess(_notificationParser.parse(response.variables));
    } catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.parse,
          message: '我的提醒解析失败: $error',
          raw: error,
        ),
      );
    }
  }

  ApiResult<MyPrivateMessagePage> _parsePrivateMessages(
    DiscuzResponse response,
  ) {
    try {
      return ApiSuccess(_privateMessageParser.parse(response.variables));
    } catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.parse,
          message: '我的消息解析失败: $error',
          raw: error,
        ),
      );
    }
  }

  ApiError _wrapError(String prefix, ApiError error) {
    return ApiError(
      type: error.type,
      message: '$prefix: ${error.message}',
      code: error.code,
      statusCode: error.statusCode,
      raw: error.raw,
    );
  }
}

final myMessageRepositoryProvider = Provider<MyMessageRepository>((ref) {
  return YamiboMyMessageRepository(
    apiClient: ref.watch(yamiboApiClientProvider),
  );
});
