import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';

abstract class ForumRepository {
  Future<ApiResult<ForumIndexData>> getForumIndex();
}

/// Discuz 论坛数据仓库实现
class DiscuzForumRepository implements ForumRepository {
  DiscuzForumRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiResult<ForumIndexData>> getForumIndex() {
    return _apiClient.getParsed<ForumIndexData>(
      module: 'forumindex',
      parser: (response) => ForumIndexData.fromVariables(response.variables),
    );
  }
}

final forumRepositoryProvider = Provider<ForumRepository>((ref) {
  return DiscuzForumRepository(ref.watch(apiClientProvider));
});
