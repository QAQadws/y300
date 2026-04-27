import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';

abstract class ForumDisplayRepository {
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page,
  });
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
}

final forumDisplayRepositoryProvider = Provider<ForumDisplayRepository>((ref) {
  return DiscuzForumDisplayRepository(ref.watch(apiClientProvider));
});
