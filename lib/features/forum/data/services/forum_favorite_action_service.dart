import 'package:y300/core/network/api_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/favorites/data/repositories/favorite_directory_repositories.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';
import 'package:y300/features/favorites/domain/repositories/favorite_directory_repositories.dart';
import 'package:y300/features/forum/domain/models/forum_display_models.dart';
import 'package:y300/features/forum/data/repositories/forum_favorite_repository.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';

/// Applies the server-declared forum favorite action without duplicating the
/// Discuz favorite endpoints in presentation code.
class ForumFavoriteActionService {
  const ForumFavoriteActionService({
    required ForumFavoriteRepository mutationRepository,
    required FavoriteForumDirectoryRepository directoryRepository,
  }) : _mutationRepository = mutationRepository,
       _directoryRepository = directoryRepository;

  final ForumFavoriteRepository _mutationRepository;
  final FavoriteForumDirectoryRepository _directoryRepository;

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
        return _mutationRepository.favoriteForum(fid: normalizedFid);
      case ForumDisplayFavoriteAction.unfavorite:
        final favoriteResult = await _directoryRepository.load(
          const FavoriteForumDirectoryQuery(),
        );
        if (favoriteResult
            case final DataReadFailure<
                  FavoriteForumDirectoryData,
                  FavoriteForumDirectoryReadCapabilities
                >
                failure) {
          return ApiFailure<ForumFavoriteMutationResult>(
            ApiError(
              type: _apiErrorTypeFor(failure.kind),
              message: failure.diagnosticMessage,
              code: failure.code,
              statusCode: failure.statusCode,
            ),
          );
        }

        final success =
            favoriteResult
                as DataReadSuccess<
                  FavoriteForumDirectoryData,
                  FavoriteForumDirectoryReadCapabilities
                >;
        if (!success.capabilities.supports(
          FavoriteForumDirectoryCapability.stableRemoteFavoriteIdentity,
        )) {
          return const ApiFailure<ForumFavoriteMutationResult>(
            ApiError(type: ApiErrorType.business, message: '找不到当前版块的收藏标识'),
          );
        }
        FavoriteForumEntry? current;
        for (final forum in success.data.items) {
          if (forum.fid.trim() == normalizedFid) {
            current = forum;
            break;
          }
        }
        final remoteFavoriteId = current?.remoteFavoriteId?.trim();
        if (remoteFavoriteId == null || remoteFavoriteId.isEmpty) {
          return const ApiFailure<ForumFavoriteMutationResult>(
            ApiError(type: ApiErrorType.business, message: '找不到当前版块的收藏标识'),
          );
        }
        return _mutationRepository.unfavoriteForum(favid: remoteFavoriteId);
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
      mutationRepository: ref.watch(forumFavoriteRepositoryProvider),
      directoryRepository: ref.watch(favoriteForumDirectoryRepositoryProvider),
    );
  },
);

ApiErrorType _apiErrorTypeFor(DataReadFailureKind kind) {
  return switch (kind) {
    DataReadFailureKind.network ||
    DataReadFailureKind.cancelled => ApiErrorType.network,
    DataReadFailureKind.timeout => ApiErrorType.timeout,
    DataReadFailureKind.unauthorized => ApiErrorType.unauthorized,
    DataReadFailureKind.server => ApiErrorType.server,
    DataReadFailureKind.parse => ApiErrorType.parse,
    DataReadFailureKind.business ||
    DataReadFailureKind.unsupported => ApiErrorType.business,
    DataReadFailureKind.unknown => ApiErrorType.unknown,
  };
}
