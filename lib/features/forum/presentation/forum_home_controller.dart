import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';

final forumHomeControllerProvider =
    AsyncNotifierProvider.autoDispose<ForumHomeController, ForumHomePageState>(
      ForumHomeController.new,
    );

/// 论坛首页状态控制器：负责拉取数据和映射为 UI 模型
class ForumHomeController extends AsyncNotifier<ForumHomePageState> {
  @override
  Future<ForumHomePageState> build() async {
    return _fetchForumHome();
  }

  Future<void> refresh({bool forceNetwork = false}) async {
    final current = state.asData?.value;
    final cachePolicy = forceNetwork
        ? CacheLoadPolicy.networkFirst
        : CacheLoadPolicy.cacheFirst;
    if (current == null) {
      state = const AsyncLoading();
      state = await AsyncValue.guard(
        () => _fetchForumHome(cachePolicy: cachePolicy),
      );
      return;
    }

    if (current.isRefreshing) {
      return;
    }
    state = AsyncData(current.copyWith(isRefreshing: true, clearHint: true));
    try {
      final nextState = await _fetchForumHome(cachePolicy: cachePolicy);
      state = AsyncData(
        nextState.copyWith(
          isRefreshing: false,
          clearHint: true,
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          isRefreshing: false,
          refreshHint: '刷新失败：$error',
        ),
      );
    }
  }

  Future<ForumHomePageState> _fetchForumHome({
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final repository = ref.read(forumHomeRepositoryProvider);
    final requestProfile = _resolveRequestProfile();
    final result = await repository.getForumHomePayload(
      cachePolicy: cachePolicy,
      requestProfileOverride: requestProfile,
    );

    return result.when(
      success: (payload) => ForumHomePageState(
        viewData: ForumHomeViewData(
          sections: _mapSections(payload),
          isLoggedIn: payload.isLoggedIn,
          carouselItems: payload.chromeData.carouselItems,
        ),
        requestProfile: requestProfile,
        isRefreshing: false,
      ),
      failure: (error) => throw ForumHomeException(error.message),
    );
  }

  DocumentRequestProfile _resolveRequestProfile() {
    final authState = ref.read(authSessionControllerProvider).asData?.value;
    return authState?.isLoggedIn == true
        ? DocumentRequestProfile.loggedIn
        : DocumentRequestProfile.anonymous;
  }

  List<ForumSection> _mapSections(ForumHomePayload payload) {
    final sections = <ForumSection>[];
    final favoriteForums = _mapFavoriteForums(payload);
    if (favoriteForums.isNotEmpty) {
      sections.add(
        ForumSection(
          title: '我收藏的版块',
          favoriteItems: favoriteForums,
          type: ForumSectionType.favorite,
        ),
      );
    }
    sections.addAll(_mapRegularSections(payload.forumIndex));
    return sections;
  }

  List<FavoriteForumDisplayItem> _mapFavoriteForums(ForumHomePayload payload) {
    final forumByFid = <String, ForumItem>{
      for (final forum in payload.forumIndex.forums) forum.fid: forum,
    };
    final chromeForumByFid = {
      for (final forum in payload.chromeData.favoriteForums) forum.fid: forum,
    };
    final seen = <String>{};
    final output = <FavoriteForumDisplayItem>[];
    for (final forum in payload.favoriteForums) {
      if (forum.fid.trim().isEmpty || !seen.add(forum.fid)) {
        continue;
      }
      final chromeForum = chromeForumByFid[forum.fid];
      final homeForum = forumByFid[forum.fid];
      output.add(
        FavoriteForumDisplayItem(
          fid: forum.fid,
          title: forum.title.trim().isNotEmpty
              ? forum.title
              : chromeForum?.title.trim().isNotEmpty == true
              ? chromeForum!.title
              : homeForum?.name ?? forum.title,
          description: forum.description.trim().isNotEmpty
              ? forum.description
              : chromeForum?.description.trim().isNotEmpty == true
              ? chromeForum!.description
              : homeForum?.description ?? '',
          todayPosts: forum.todayPosts > 0
              ? forum.todayPosts
              : chromeForum?.todayPosts != null && chromeForum!.todayPosts > 0
              ? chromeForum.todayPosts
              : homeForum?.todayPosts ?? 0,
        ),
      );
    }
    return output;
  }

  List<ForumSection> _mapRegularSections(ForumIndexData data) {
    final forumByFid = <String, ForumItem>{
      for (final item in data.forums) item.fid: item,
    };

    final sections = <ForumSection>[];

    // Discuz 的 catlist 中 forums 字段是 fid 列表，这里做一次稳定映射
    for (final category in data.categories) {
      final items = <ForumItem>[];
      for (final fid in category.forums) {
        final mapped = forumByFid[fid];
        if (mapped != null) {
          items.add(mapped);
        }
      }

      if (items.isNotEmpty) {
        sections.add(
          ForumSection(
            title: category.name,
            items: items,
            type: ForumSectionType.regular,
          ),
        );
      }
    }

    // 后端若给出未分组 forum，这里归并到“未分类”防止数据丢失
    final categorizedFids = sections
        .expand((section) => section.items)
        .map((item) => item.fid)
        .toSet();

    final uncategorized = data.forums
        .where((forum) => !categorizedFids.contains(forum.fid))
        .toList();

    if (uncategorized.isNotEmpty) {
      sections.add(
        ForumSection(
          title: '未分类',
          items: uncategorized,
          type: ForumSectionType.regular,
        ),
      );
    }

    return sections;
  }
}

class ForumHomeException implements Exception {
  ForumHomeException(this.message);

  final String message;

  @override
  String toString() => message;
}
