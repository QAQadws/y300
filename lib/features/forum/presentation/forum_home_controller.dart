import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/services/forum_home_request_profile_resolver.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';

final forumHomeNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final forumHomeControllerProvider =
    AsyncNotifierProvider.autoDispose<ForumHomeController, ForumHomePageState>(
      ForumHomeController.new,
    );

/// 论坛首页状态控制器：负责拉取数据和映射为 UI 模型
class ForumHomeController extends AsyncNotifier<ForumHomePageState> {
  int _backgroundRefreshGeneration = 0;

  @override
  Future<ForumHomePageState> build() async {
    final requestProfile = await _resolveRequestProfile();
    final repository = ref.read(forumHomeRepositoryProvider);
    ForumHomeCacheEntry? cached;
    try {
      cached = await repository.readCachedPayload(
        requestProfile: requestProfile,
      );
    } catch (_) {
      // Cache corruption/unavailability is a miss, not a startup failure.
    }
    if (cached == null) {
      return _fetchForumHome(
        cachePolicy: CacheLoadPolicy.cacheFirst,
        requestProfile: requestProfile,
      );
    }

    final generation = ++_backgroundRefreshGeneration;
    unawaited(
      _refreshCachedHomeAfterPublish(
        requestProfile: requestProfile,
        generation: generation,
      ),
    );
    return _stateFromPayload(
      cached.payload,
      capabilities: cached.capabilities,
      metadata: cached.metadata,
      requestProfile: requestProfile,
      isRefreshing: true,
      lastUpdatedAt: cached.updatedAt,
    );
  }

  Future<void> refresh({bool forceNetwork = false}) async {
    final current = state.asData?.value;
    final cachePolicy = forceNetwork
        ? CacheLoadPolicy.networkFirst
        : CacheLoadPolicy.cacheFirst;
    if (current == null) {
      final generation = ++_backgroundRefreshGeneration;
      state = const AsyncLoading();
      final requestProfile = await _resolveRequestProfile();
      final next = await AsyncValue.guard(
        () => _fetchForumHome(
          cachePolicy: cachePolicy,
          requestProfile: requestProfile,
        ),
      );
      if (ref.mounted && generation == _backgroundRefreshGeneration) {
        state = next;
      }
      return;
    }

    if (current.isRefreshing) {
      return;
    }
    final generation = ++_backgroundRefreshGeneration;
    state = AsyncData(current.copyWith(isRefreshing: true, clearHint: true));
    try {
      final nextState = await _fetchForumHome(
        cachePolicy: cachePolicy,
        requestProfile: current.requestProfile,
      );
      if (!ref.mounted || generation != _backgroundRefreshGeneration) {
        return;
      }
      state = AsyncData(
        nextState.copyWith(isRefreshing: false, clearHint: true),
      );
    } catch (error) {
      if (!ref.mounted || generation != _backgroundRefreshGeneration) {
        return;
      }
      state = AsyncData(
        current.copyWith(
          isRefreshing: false,
          refreshNotice: ForumHomeNotice(
            code: ForumHomeNoticeCode.refreshFailed,
            detail: error.toString(),
          ),
        ),
      );
    }
  }

  Future<ForumHomePageState> _fetchForumHome({
    required CacheLoadPolicy cachePolicy,
    required DocumentRequestProfile requestProfile,
  }) async {
    final repository = ref.read(forumHomeRepositoryProvider);
    final now = ref.read(forumHomeNowProvider).call();
    final result = await repository.getForumHomePayload(
      cachePolicy: cachePolicy,
      requestProfileOverride: requestProfile,
    );

    return result.when(
      success: (payload, capabilities, metadata) => _stateFromPayload(
        payload,
        capabilities: capabilities,
        metadata: metadata,
        requestProfile: requestProfile,
        isRefreshing: false,
        lastUpdatedAt: now,
      ),
      failure: (error) => throw ForumHomeException(error.diagnosticMessage),
    );
  }

  ForumHomePageState _stateFromPayload(
    ForumHomePayload payload, {
    required ForumDirectoryReadCapabilities capabilities,
    required DataReadMetadata metadata,
    required DocumentRequestProfile requestProfile,
    required bool isRefreshing,
    required DateTime lastUpdatedAt,
  }) {
    return ForumHomePageState(
      viewData: ForumHomeViewData(
        sections: _mapSections(payload, capabilities),
        isLoggedIn: payload.isLoggedIn,
        carouselItems: payload.chromeData.carouselItems,
      ),
      requestProfile: requestProfile,
      isRefreshing: isRefreshing,
      lastUpdatedAt: lastUpdatedAt,
      capabilities: capabilities,
      readMetadata: metadata,
    );
  }

  Future<DocumentRequestProfile> _resolveRequestProfile() async {
    final authState = ref.read(authSessionControllerProvider).asData?.value;
    if (authState?.isLoggedIn == true) {
      return DocumentRequestProfile.loggedIn;
    }
    final localProfile = await ref
        .read(forumHomeRequestProfileResolverProvider)
        .resolve();
    if (!ref.mounted) {
      return localProfile;
    }
    final latestAuthState = ref
        .read(authSessionControllerProvider)
        .asData
        ?.value;
    return latestAuthState?.isLoggedIn == true
        ? DocumentRequestProfile.loggedIn
        : localProfile;
  }

  Future<void> _refreshCachedHomeAfterPublish({
    required DocumentRequestProfile requestProfile,
    required int generation,
  }) async {
    // Let AsyncNotifier publish the cached build result before starting work
    // that may complete synchronously in tests or on a very fast connection.
    await Future<void>.delayed(Duration.zero);
    if (!ref.mounted || generation != _backgroundRefreshGeneration) {
      return;
    }
    final current = state.asData?.value;
    if (current == null || current.requestProfile != requestProfile) {
      return;
    }
    try {
      final next = await _fetchForumHome(
        cachePolicy: CacheLoadPolicy.networkFirst,
        requestProfile: requestProfile,
      );
      if (!ref.mounted || generation != _backgroundRefreshGeneration) {
        return;
      }
      state = AsyncData(next.copyWith(isRefreshing: false, clearHint: true));
    } catch (error) {
      if (!ref.mounted || generation != _backgroundRefreshGeneration) {
        return;
      }
      final latest = state.asData?.value;
      if (latest == null || latest.requestProfile != requestProfile) {
        return;
      }
      state = AsyncData(
        latest.copyWith(
          isRefreshing: false,
          refreshNotice: ForumHomeNotice(
            code: ForumHomeNoticeCode.refreshFailed,
            detail: error.toString(),
          ),
        ),
      );
    }
  }

  List<ForumSection> _mapSections(
    ForumHomePayload payload,
    ForumDirectoryReadCapabilities capabilities,
  ) {
    final identities = <String>{};
    final sections = <ForumSection>[];
    final chromeForumByFid = {
      for (final forum in payload.chromeData.favoriteForums) forum.fid: forum,
    };
    final directoryForumByFid = <String, ForumDirectoryForum>{};
    void indexDirectoryForum(ForumDirectoryForum forum) {
      directoryForumByFid[forum.fid] = forum;
      forum.children.forEach(indexDirectoryForum);
    }

    for (final section in payload.directory.sections) {
      section.forums.forEach(indexDirectoryForum);
    }
    final favoriteItems = <ForumHomeForumDisplayItem>[];
    final favoriteFids = <String>{};
    for (final forum
        in payload.isLoggedIn
            ? payload.favoriteForums
            : const <ForumHomeFavoriteForum>[]) {
      if (forum.fid.trim().isEmpty || !favoriteFids.add(forum.fid)) {
        continue;
      }
      final chromeForum = chromeForumByFid[forum.fid];
      final directoryForum = directoryForumByFid[forum.fid];
      favoriteItems.add(
        ForumHomeForumDisplayItem(
          fid: forum.fid,
          title: forum.title.trim().isNotEmpty
              ? forum.title
              : chromeForum?.title.trim().isNotEmpty == true
              ? chromeForum!.title
              : directoryForum?.title ?? '',
          description: forum.description.trim().isNotEmpty
              ? forum.description
              : chromeForum?.description.trim().isNotEmpty == true
              ? chromeForum!.description
              : directoryForum?.description ?? '',
          todayPosts:
              forum.todayPosts ??
              chromeForum?.todayPosts ??
              directoryForum?.todayPosts,
        ),
      );
    }
    if (favoriteItems.isNotEmpty) {
      sections.add(
        ForumSection(
          sourceIdentity: _uniqueSectionIdentity(
            type: ForumSectionType.favorite,
            items: favoriteItems,
            used: identities,
          ),
          title: '',
          type: ForumSectionType.favorite,
          items: favoriteItems,
        ),
      );
    }
    for (final section in payload.directory.sections) {
      final type = section.kind == ForumDirectorySectionKind.uncategorized
          ? ForumSectionType.uncategorized
          : ForumSectionType.regular;
      final items = <ForumHomeForumDisplayItem>[];
      for (final forum in section.forums) {
        items.add(
          ForumHomeForumDisplayItem(
            fid: forum.fid,
            title: forum.title,
            description:
                capabilities.supports(ForumDirectoryCapability.forumDescription)
                ? forum.description
                : '',
            todayPosts:
                capabilities.supports(ForumDirectoryCapability.todayPostCount)
                ? forum.todayPosts
                : null,
          ),
        );
      }

      if (items.isNotEmpty) {
        sections.add(
          ForumSection(
            sourceIdentity: _uniqueSectionIdentityFromSource(
              section.identity,
              type: type,
              used: identities,
            ),
            title: section.title,
            items: items,
            type: type,
          ),
        );
      }
    }
    return sections;
  }

  String _uniqueSectionIdentityFromSource(
    String sourceIdentity, {
    required ForumSectionType type,
    required Set<String> used,
  }) {
    final base = '${type.name}:${sourceIdentity.trim()}';
    var identity = base;
    var occurrence = 2;
    while (!used.add(identity)) {
      identity = '$base:$occurrence';
      occurrence += 1;
    }
    return identity;
  }

  String _uniqueSectionIdentity({
    required ForumSectionType type,
    required Iterable<ForumHomeForumDisplayItem> items,
    required Set<String> used,
  }) {
    final base = '${type.name}:${items.map((item) => item.fid).join(',')}';
    var identity = base;
    var occurrence = 2;
    while (!used.add(identity)) {
      identity = '$base:$occurrence';
      occurrence += 1;
    }
    return identity;
  }
}

class ForumHomeException implements Exception {
  ForumHomeException(this.message);

  final String message;

  @override
  String toString() => message;
}
