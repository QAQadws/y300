import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';

abstract class ThreadFavoriteRepository {
  Future<ApiResult<ThreadFavoriteResult>> favoriteThread({
    required ThreadFavoriteRequest request,
  });
}
