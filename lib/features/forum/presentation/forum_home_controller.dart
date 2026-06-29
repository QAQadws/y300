import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';

final forumHomeNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

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
    final now = ref.read(forumHomeNowProvider).call();
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
        lastUpdatedAt: now,
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
    if (payload.homeSections.isEmpty) {
      return _mapLegacySections(payload);
    }
    return [
      for (final section in payload.homeSections)
        ForumSection(
          title: section.title,
          type: section.kind == ForumHomeSectionKind.favorite
              ? ForumSectionType.favorite
              : ForumSectionType.regular,
          items: [
            for (final item in section.items)
              ForumHomeForumDisplayItem(
                fid: item.fid,
                title: item.title,
                description: item.description,
                todayPosts: item.todayPosts,
              ),
          ],
        ),
    ];
  }

  List<ForumSection> _mapLegacySections(ForumHomePayload payload) {
    final sections = <ForumSection>[];
    final favoriteItems = _mapLegacyFavoriteItems(payload);
    if (favoriteItems.isNotEmpty) {
      sections.add(
        ForumSection(
          title: '我收藏的版块',
          type: ForumSectionType.favorite,
          items: favoriteItems,
        ),
      );
    }
    sections.addAll(_mapLegacyRegularSections(payload.forumIndex));
    return sections;
  }

  List<ForumHomeForumDisplayItem> _mapLegacyFavoriteItems(
    ForumHomePayload payload,
  ) {
    final forumByFid = <String, ForumItem>{
      for (final forum in payload.forumIndex.forums) forum.fid: forum,
    };
    final chromeForumByFid = {
      for (final forum in payload.chromeData.favoriteForums) forum.fid: forum,
    };
    final seen = <String>{};
    final output = <ForumHomeForumDisplayItem>[];
    for (final forum in payload.favoriteForums) {
      if (!_shouldKeepFavoriteForum(forum, seen)) {
        continue;
      }
      final chromeForum = chromeForumByFid[forum.fid];
      final homeForum = forumByFid[forum.fid];
      output.add(
        ForumHomeForumDisplayItem(
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
              : chromeForum?.todayPosts ?? _legacyTodayPosts(homeForum),
        ),
      );
    }
    return output;
  }

  bool _shouldKeepFavoriteForum(FavoriteForum forum, Set<String> seen) {
    return forum.fid.trim().isNotEmpty && seen.add(forum.fid);
  }

  List<ForumSection> _mapLegacyRegularSections(ForumIndexData data) {
    final forumByFid = <String, ForumItem>{
      for (final item in data.forums) item.fid: item,
    };

    final sections = <ForumSection>[];
    for (final category in data.categories) {
      final items = <ForumHomeForumDisplayItem>[];
      for (final fid in category.forums) {
        final mapped = forumByFid[fid];
        if (mapped != null) {
          items.add(
            ForumHomeForumDisplayItem(
              fid: mapped.fid,
              title: mapped.name,
              description: mapped.description,
              todayPosts: _legacyTodayPosts(mapped),
            ),
          );
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
          items: [
            for (final forum in uncategorized)
              ForumHomeForumDisplayItem(
                fid: forum.fid,
                title: forum.name,
                description: forum.description,
                todayPosts: _legacyTodayPosts(forum),
              ),
          ],
          type: ForumSectionType.regular,
        ),
      );
    }

    return sections;
  }

  int? _legacyTodayPosts(ForumItem? forum) {
    final todayPosts = forum?.todayPosts ?? 0;
    return todayPosts > 0 ? todayPosts : null;
  }
}

class ForumHomeException implements Exception {
  ForumHomeException(this.message);

  final String message;

  @override
  String toString() => message;
}
