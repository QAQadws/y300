import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/services/posting_form_metadata_parser.dart';

abstract class PostingFormMetadataRepository {
  /// 调用 `module=forumdisplay` 拉 formhash + threadtypes / threadsorts。
  ///
  /// 数据层只关心怎么拿到 metadata；版块名 / 必选分类 / 选项都已经在
  /// [NewThreadFormMetadata] 里。
  Future<ApiResult<NewThreadFormMetadata>> getFormMetadata({
    required String fid,
  });
}

/// Discuz 站点上的实现。
///
/// 不复用 `forumDisplayRepositoryProvider`（它返回 `ForumDisplayData`，扩展
/// 进 metadata 字段会污染列表回调路径）。两边各自调 forumdisplay，
/// 在 [ApiClient] 层共享 cookie / 限流 / 超时即可。
class DiscuzPostingFormMetadataRepository
    implements PostingFormMetadataRepository {
  DiscuzPostingFormMetadataRepository(
    this._apiClient, {
    PostingFormMetadataParser parser = const PostingFormMetadataParser(),
  }) : _parser = parser;

  final ApiClient _apiClient;
  final PostingFormMetadataParser _parser;

  @override
  Future<ApiResult<NewThreadFormMetadata>> getFormMetadata({
    required String fid,
  }) {
    return _apiClient.getParsed<NewThreadFormMetadata>(
      module: 'forumdisplay',
      queryParameters: {'fid': fid, 'page': 1},
      parser: (response) =>
          _parser.parse(fid: fid, variables: response.variables),
    );
  }
}
