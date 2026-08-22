import 'package:y300/core/network/api_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/domain/models/forum_display_models.dart';
import 'package:y300/features/forum/data/repositories/forum_favorite_repository.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';

/// Applies the server-declared forum favorite action without duplicating the
/// Discuz favorite endpoints in presentation code.
class ForumFavoriteActionService {
  const ForumFavoriteActionService(this._repository);

  final ForumFavoriteRepository _repository;

  Future<ApiResult<ForumFavoriteMutationResult>> apply({
    required String fid,
    required ForumDisplayFavoriteAction action,
  }) async {
    final normalizedFid = fid.trim();
    if (normalizedFid.isEmpty || action == ForumDisplayFavoriteAction.unknown) {
      return const ApiFailure<ForumFavoriteMutationResult>(
        ApiError(type: ApiErrorType.business, message: '论坛收藏操作缺少有效目标'),
      );
    }

    switch (action) {
      case ForumDisplayFavoriteAction.favorite:
        return _repository.favoriteForum(fid: normalizedFid);
      case ForumDisplayFavoriteAction.unfavorite:
        final favoriteResult = await _repository.loadFavoriteForums();
        if (favoriteResult case ApiFailure<List<FavoriteForum>>(:final error)) {
          return ApiFailure<ForumFavoriteMutationResult>(error);
        }

        final favorites =
            (favoriteResult as ApiSuccess<List<FavoriteForum>>).data;
        FavoriteForum? current;
        for (final forum in favorites) {
          if (forum.fid.trim() == normalizedFid) {
            current = forum;
            break;
          }
        }
        if (current == null || current.favid.trim().isEmpty) {
          return const ApiFailure<ForumFavoriteMutationResult>(
            ApiError(type: ApiErrorType.business, message: '找不到当前版块的收藏标识'),
          );
        }
        return _repository.unfavoriteForum(favid: current.favid);
      case ForumDisplayFavoriteAction.unknown:
        return const ApiFailure<ForumFavoriteMutationResult>(
          ApiError(type: ApiErrorType.business, message: '论坛收藏状态未知'),
        );
    }
  }
}

final forumFavoriteActionServiceProvider = Provider<ForumFavoriteActionService>(
  (ref) {
    return ForumFavoriteActionService(
      ref.watch(forumFavoriteRepositoryProvider),
    );
  },
);
