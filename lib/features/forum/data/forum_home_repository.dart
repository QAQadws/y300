import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/auth_repository.dart';
import 'package:y300/features/favorites/data/favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/forum_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';

/// 论坛首页聚合结果：把论坛首页基础数据与登录态相关扩展信息统一返回。
class ForumHomePayload {
  ForumHomePayload({
    required this.forumIndex,
    required this.isLoggedIn,
    required this.favoriteForums,
  });

  final ForumIndexData forumIndex;
  final bool isLoggedIn;
  final List<FavoriteForum> favoriteForums;
}

abstract class ForumHomeRepository {
  Future<ApiResult<ForumHomePayload>> getForumHomePayload();
}

/// Discuz 论坛首页聚合仓库。
///
/// 约定：
/// 1) forumindex 是首页主数据，失败则整体失败。
/// 2) profile / myfavforum 属于增强信息，失败时降级为空，不影响首页主流程。
class DiscuzForumHomeRepository implements ForumHomeRepository {
  DiscuzForumHomeRepository({
    required Future<ApiResult<ForumIndexData>> Function() loadForumIndex,
    required Future<ApiResult<SessionInfo>> Function() refreshSession,
    required Future<ApiResult<List<FavoriteForum>>> Function()
    loadFavoriteForums,
  }) : _loadForumIndex = loadForumIndex,
       _refreshSession = refreshSession,
       _loadFavoriteForums = loadFavoriteForums;

  final Future<ApiResult<ForumIndexData>> Function() _loadForumIndex;
  final Future<ApiResult<SessionInfo>> Function() _refreshSession;
  final Future<ApiResult<List<FavoriteForum>>> Function() _loadFavoriteForums;

  @override
  Future<ApiResult<ForumHomePayload>> getForumHomePayload() async {
    final forumResult = await _loadForumIndex();
    if (forumResult.isFailure) {
      return ApiFailure<ForumHomePayload>(forumResult.errorOrNull!);
    }

    final forumIndex = forumResult.dataOrNull!;
    final sessionResult = await _refreshSession();

    final isLoggedIn = sessionResult.when(
      success: (session) => session.isLoggedIn,
      failure: (_) => false,
    );

    if (!isLoggedIn) {
      return ApiSuccess(
        ForumHomePayload(
          forumIndex: forumIndex,
          isLoggedIn: false,
          favoriteForums: const [],
        ),
      );
    }

    final favoriteResult = await _loadFavoriteForums();
    final favoriteForums = favoriteResult.when(
      success: (items) => items,
      failure: (_) => <FavoriteForum>[],
    );

    return ApiSuccess(
      ForumHomePayload(
        forumIndex: forumIndex,
        isLoggedIn: true,
        favoriteForums: favoriteForums,
      ),
    );
  }
}

final forumHomeRepositoryProvider = Provider<ForumHomeRepository>((ref) {
  final forumRepository = ref.watch(forumRepositoryProvider);
  final authRepository = ref.watch(authRepositoryProvider);
  final favoriteRepository = ref.watch(favoriteRepositoryProvider);

  return DiscuzForumHomeRepository(
    loadForumIndex: forumRepository.getForumIndex,
    refreshSession: authRepository.refreshSession,
    loadFavoriteForums: favoriteRepository.getFavoriteForums,
  );
});
