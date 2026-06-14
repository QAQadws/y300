import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

class ApiNovelThreadGateway implements NovelThreadGateway {
  const ApiNovelThreadGateway(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ThreadDetailData> getThreadDetail({
    required String tid,
    required int page,
  }) async {
    final result = await _apiClient.getParsed<ThreadDetailData>(
      module: 'viewthread',
      queryParameters: <String, dynamic>{
        'tid': tid,
        'page': page,
        'version': 1,
      },
      parser: (response) =>
          ThreadDetailData.fromVariables(response.variables, page: page),
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
