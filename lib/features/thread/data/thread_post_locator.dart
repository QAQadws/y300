import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/thread/data/thread_detail_html_parser.dart';

class ThreadPostLocation {
  const ThreadPostLocation({
    required this.tid,
    required this.pid,
    required this.page,
    required this.url,
  });

  final String tid;
  final String pid;
  final int page;
  final String url;
}

abstract class ThreadPostLocator {
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  });
}

class HtmlThreadPostLocator implements ThreadPostLocator {
  const HtmlThreadPostLocator({
    required YamiboHttpGateway gateway,
    ThreadDetailHtmlParser parser = const ThreadDetailHtmlParser(),
  }) : _gateway = gateway,
       _parser = parser;

  final YamiboHttpGateway _gateway;
  final ThreadDetailHtmlParser _parser;

  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) async {
    final result = await _gateway.getText(
      sourceUri,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post.locate',
        pageKind: 'thread.detail',
      ),
      followRedirects: true,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    );
    if (result case ApiFailure(:final error)) {
      return ApiFailure<ThreadPostLocation>(
        ApiError(
          type: error.type,
          message: '楼层定位失败: ${error.message}',
          code: error.code,
          statusCode: error.statusCode,
          raw: error.raw,
        ),
      );
    }
    try {
      final response = result.dataOrNull;
      if (response == null) {
        return const ApiFailure<ThreadPostLocation>(
          ApiError(type: ApiErrorType.unknown, message: '楼层定位结果为空'),
        );
      }
      final detail = _parser.parse(
        response.body,
        fallbackTid: tid,
        fallbackPage: 1,
      );
      final hasTargetPost = detail.posts.any((post) => post.pid == pid);
      if (!hasTargetPost) {
        return const ApiFailure<ThreadPostLocation>(
          ApiError(type: ApiErrorType.parse, message: '目标楼层未出现在定位结果中'),
        );
      }
      final page = detail.currentPage <= 0 ? 1 : detail.currentPage;
      return ApiSuccess<ThreadPostLocation>(
        ThreadPostLocation(
          tid: detail.tid.isEmpty ? tid : detail.tid,
          pid: pid,
          page: page,
          url: response.uri.toString(),
        ),
      );
    } catch (error) {
      return ApiFailure<ThreadPostLocation>(
        ApiError(
          type: ApiErrorType.parse,
          message: '楼层定位结果解析失败: $error',
          raw: error,
        ),
      );
    }
  }
}
