import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

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

final threadRepositoryProvider = Provider<ThreadRepository>((ref) {
  return ApiThreadRepository(ref.watch(apiClientProvider));
});
