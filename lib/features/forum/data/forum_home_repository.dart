import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/auth_repository.dart';
import 'package:y300/features/favorites/data/favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/forum_home_chrome_repository.dart';
import 'package:y300/features/forum/data/forum_repository.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';

/// 论坛首页聚合结果：把论坛首页基础数据与登录态相关扩展信息统一返回。
class ForumHomePayload {
  ForumHomePayload({
    required this.forumIndex,
    required this.isLoggedIn,
    required this.favoriteForums,
    this.chromeData = ForumHomeChromeData.empty,
  });

  final ForumIndexData forumIndex;
  final bool isLoggedIn;
  final List<FavoriteForum> favoriteForums;
  final ForumHomeChromeData chromeData;
}

abstract class ForumHomeRepository {
  Future<ApiResult<ForumHomePayload>> getForumHomePayload();
}

/// Discuz 论坛首页聚合仓库。
///
/// 约定：
/// 1) forumindex 是首页主数据，失败则整体失败。
/// 2) profile 仅用于判断登录态。
/// 3) 版块收藏只是论坛首页的快捷入口，线程收藏仍统一走收藏 Tab。
class DiscuzForumHomeRepository implements ForumHomeRepository {
  DiscuzForumHomeRepository({
    required Future<ApiResult<ForumIndexData>> Function() loadForumIndex,
    required Future<ApiResult<SessionInfo>> Function() refreshSession,
    Future<ApiResult<List<FavoriteForum>>> Function()? loadFavoriteForums,
    Future<ApiResult<ForumHomeChromeData>> Function()? loadChrome,
  }) : _loadForumIndex = loadForumIndex,
       _refreshSession = refreshSession,
       _loadFavoriteForums = loadFavoriteForums,
       _loadChrome = loadChrome;

  final Future<ApiResult<ForumIndexData>> Function() _loadForumIndex;
  final Future<ApiResult<SessionInfo>> Function() _refreshSession;
  final Future<ApiResult<List<FavoriteForum>>> Function()? _loadFavoriteForums;
  final Future<ApiResult<ForumHomeChromeData>> Function()? _loadChrome;

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
    final favoriteForums = isLoggedIn ? await _safeLoadFavoriteForums() : const <FavoriteForum>[];
    final chromeData = await _safeLoadChrome();

    return ApiSuccess(
      ForumHomePayload(
        forumIndex: forumIndex,
        isLoggedIn: isLoggedIn,
        favoriteForums: favoriteForums,
        chromeData: chromeData,
      ),
    );
  }

  Future<List<FavoriteForum>> _safeLoadFavoriteForums() async {
    final loader = _loadFavoriteForums;
    if (loader == null) {
      return const <FavoriteForum>[];
    }
    final result = await loader();
    return result.when(
      success: (forums) => forums,
      failure: (_) => const <FavoriteForum>[],
    );
  }

  Future<ForumHomeChromeData> _safeLoadChrome() async {
    final loader = _loadChrome;
    if (loader == null) {
      return ForumHomeChromeData.empty;
    }
    final result = await loader();
    return result.when(
      success: (chrome) => chrome,
      failure: (_) => ForumHomeChromeData.empty,
    );
  }
}

final forumHomeRepositoryProvider = Provider<ForumHomeRepository>((ref) {
  final forumRepository = ref.watch(forumRepositoryProvider);
  final authRepository = ref.watch(authRepositoryProvider);

  return DiscuzForumHomeRepository(
    loadForumIndex: forumRepository.getForumIndex,
    refreshSession: authRepository.refreshSession,
    loadFavoriteForums: ref.watch(favoriteRepositoryProvider).getFavoriteForums,
    loadChrome: ref.watch(forumHomeChromeRepositoryProvider).loadChrome,
  );
});
