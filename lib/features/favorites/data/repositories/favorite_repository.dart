import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';

abstract class FavoriteRepository {
  Future<ApiResult<List<FavoriteForum>>> getFavoriteForums();

  Future<ApiResult<FavoriteThreadsPage>> getFavoriteThreads({
    required int page,
  });
}

class ApiFavoriteRepository implements FavoriteRepository {
  ApiFavoriteRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiResult<List<FavoriteForum>>> getFavoriteForums() {
    return _apiClient.getParsed<List<FavoriteForum>>(
      module: 'myfavforum',
      parser: (response) => ParseUtils.asList(
        response.variables['list'],
      ).map((item) => FavoriteForum.fromJson(ParseUtils.asMap(item))).toList(),
    );
  }

  @override
  Future<ApiResult<FavoriteThreadsPage>> getFavoriteThreads({
    required int page,
  }) {
    return _apiClient.getParsed<FavoriteThreadsPage>(
      module: 'myfavthread',
      // 收藏接口文档固定使用 version=4。这里显式声明，避免后续全局默认版本
      // 调整时影响收藏同步解析。
      queryParameters: {'version': '4', 'page': page},
      parser: (response) =>
          FavoriteThreadsPage.fromVariables(response.variables, page: page),
    );
  }
}

final favoriteRepositoryProvider = Provider<FavoriteRepository>((ref) {
  return ApiFavoriteRepository(ref.watch(apiClientProvider));
});
