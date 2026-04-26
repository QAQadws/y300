import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';

class ForumRepository {
  ForumRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<ApiResult<ForumIndexData>> getForumIndex() {
    return _apiClient.getParsed<ForumIndexData>(
      module: 'forumindex',
      parser: (response) => ForumIndexData.fromVariables(response.variables),
    );
  }
}

final forumRepositoryProvider = Provider<ForumRepository>((ref) {
  return ForumRepository(ref.watch(apiClientProvider));
});
