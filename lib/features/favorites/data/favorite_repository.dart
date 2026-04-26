import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';

class FavoriteRepository {
  FavoriteRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<ApiResult<List<FavoriteForum>>> getFavoriteForums() {
    return _apiClient.getParsed<List<FavoriteForum>>(
      module: 'myfavforum',
      parser: (response) => ParseUtils.asList(
        response.variables['list'],
      ).map((item) => FavoriteForum.fromJson(ParseUtils.asMap(item))).toList(),
    );
  }

  Future<ApiResult<FavoriteThreadsPage>> getFavoriteThreads({
    required int page,
  }) {
    return _apiClient.getParsed<FavoriteThreadsPage>(
      module: 'myfavthread',
      queryParameters: {'page': page},
      parser: (response) =>
          FavoriteThreadsPage.fromVariables(response.variables, page: page),
    );
  }
}

final favoriteRepositoryProvider = Provider<FavoriteRepository>((ref) {
  return FavoriteRepository(ref.watch(apiClientProvider));
});
