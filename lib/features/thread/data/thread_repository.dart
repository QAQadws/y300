import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_detail_html_parser.dart';

abstract class ThreadRepository {
  Future<ApiResult<ThreadDetailData>> getThreadDetail({
    required String tid,
    int page = 1,
  });
}

class ApiThreadRepository implements ThreadRepository {
  ApiThreadRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiResult<ThreadDetailData>> getThreadDetail({
    required String tid,
    int page = 1,
  }) {
    return _apiClient.getParsed<ThreadDetailData>(
      module: 'viewthread',
      queryParameters: {'tid': tid, 'page': page},
      parser: (response) =>
          ThreadDetailData.fromVariables(response.variables, page: page),
    );
  }
}

class ThreadDetailHtmlRepository implements ThreadRepository {
  ThreadDetailHtmlRepository({
    required YamiboHtmlClient htmlClient,
    ThreadDetailHtmlParser parser = const ThreadDetailHtmlParser(),
  }) : _htmlClient = htmlClient,
       _parser = parser;

  final YamiboHtmlClient _htmlClient;
  final ThreadDetailHtmlParser _parser;

  @override
  Future<ApiResult<ThreadDetailData>> getThreadDetail({
    required String tid,
    int page = 1,
  }) async {
    final htmlResult = await _htmlClient.getDesktopPage(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'viewthread',
        'tid': tid,
        'page': page.toString(),
      },
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.detail.html',
        pageKind: 'thread.detail',
      ),
    );

    if (htmlResult case ApiFailure<String>(:final error)) {
      return ApiFailure(
        ApiError(
          type: error.type,
          message: '帖子详情 HTML 加载失败: ${error.message}',
          code: error.code,
          statusCode: error.statusCode,
          raw: error.raw,
        ),
      );
    }

    try {
      return ApiSuccess(
        _parser.parse(
          htmlResult.dataOrNull ?? '',
          fallbackTid: tid,
          fallbackPage: page,
        ),
      );
    } catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.parse,
          message: '帖子详情 HTML 解析失败: $error',
          raw: error,
        ),
      );
    }
  }
}

final threadRepositoryProvider = Provider<ThreadRepository>((ref) {
  return ThreadDetailHtmlRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
  );
});
