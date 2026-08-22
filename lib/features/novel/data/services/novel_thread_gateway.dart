import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/thread/data/mappers/thread_detail_api_mapper.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';

class ApiNovelThreadGateway implements NovelThreadGateway {
  const ApiNovelThreadGateway(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ThreadDetailData> loadAuthorPostsPage({
    required String tid,
    required String authorId,
    required int page,
    int postsPerPage = 200,
  }) async {
    final normalizedTid = tid.trim();
    final normalizedAuthorId = authorId.trim();
    if (normalizedTid.isEmpty) {
      throw ArgumentError.value(tid, 'tid', 'must not be empty');
    }
    if (normalizedAuthorId.isEmpty) {
      throw ArgumentError.value(authorId, 'authorId', 'must not be empty');
    }
    if (page < 1) {
      throw RangeError.range(page, 1, null, 'page');
    }
    if (postsPerPage < 1) {
      throw RangeError.range(postsPerPage, 1, null, 'postsPerPage');
    }
    final result = await _apiClient.getParsed<ThreadDetailData>(
      module: 'viewthread',
      queryParameters: <String, dynamic>{
        'tid': normalizedTid,
        'page': page,
        'version': 1,
        'ppp': postsPerPage,
        'authorid': normalizedAuthorId,
      },
      parser: (response) => const ThreadDetailApiMapper().mapVariables(
        response.variables,
        page: page,
      ),
    );
    final data = result.dataOrNull;
    if (!result.isSuccess || data == null) {
      final message = result.errorOrNull?.message ?? '加载帖子详情失败';
      throw StateError(message);
    }
    return data;
  }
}

final novelThreadGatewayProvider = Provider<NovelThreadGateway>((ref) {
  return ApiNovelThreadGateway(ref.watch(apiClientProvider));
});
