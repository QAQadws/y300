import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/forum/data/forum_display_html_parser.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';

abstract class ForumDisplayRepository {
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page,
  });

  Future<ApiResult<ForumDisplayData>> getForumDisplayByQuery(
    ForumDisplayQuery query,
  );
}

class ForumDisplayHtmlRepository implements ForumDisplayRepository {
  ForumDisplayHtmlRepository({
    required YamiboHtmlClient htmlClient,
    ForumDisplayHtmlParser parser = const ForumDisplayHtmlParser(),
  }) : _htmlClient = htmlClient,
       _parser = parser;

  final YamiboHtmlClient _htmlClient;
  final ForumDisplayHtmlParser _parser;

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page = 1,
  }) {
    return getForumDisplayByQuery(
      ForumDisplayQuery.initial(fid: fid).copyWithPage(page),
    );
  }

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplayByQuery(
    ForumDisplayQuery query,
  ) async {
    final htmlResult = await _htmlClient.getMobilePage(
      path: '/forum.php',
      queryParameters: query.toRequestParameters(),
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'forum.display.html',
        pageKind: 'forum.display',
      ),
    );

    if (htmlResult case ApiFailure<String>(:final error)) {
      return ApiFailure(
        ApiError(
          type: error.type,
          message: '帖子列表 HTML 加载失败: ${error.message}',
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
          fallbackFid: query.fid,
          fallbackPage: query.page,
        ),
      );
    } catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.parse,
          message: '帖子列表 HTML 解析失败: $error',
          raw: error,
        ),
      );
    }
  }
}

/// Discuz forumdisplay 实现，负责帖子列表分页拉取。
class DiscuzForumDisplayRepository implements ForumDisplayRepository {
  DiscuzForumDisplayRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page = 1,
  }) {
    return _apiClient.getParsed<ForumDisplayData>(
      module: 'forumdisplay',
      queryParameters: {'fid': fid, 'page': page},
      parser: (response) => ForumDisplayData.fromVariables(response.variables, page: page),
    );
  }

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplayByQuery(
    ForumDisplayQuery query,
  ) {
    return getForumDisplay(fid: query.fid, page: query.page);
  }
}

final forumDisplayRepositoryProvider = Provider<ForumDisplayRepository>((ref) {
  return ForumDisplayHtmlRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
  );
});
