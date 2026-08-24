import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    as forum;
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/data/services/forum_home_carousel_image_probe.dart';

class ForumHomePayload {
  ForumHomePayload({
    required this.directory,
    required this.isLoggedIn,
    required this.favoriteForums,
    this.chromeData = ForumHomeChromeData.empty,
  });
  final forum.ForumDirectoryData directory;
  final bool isLoggedIn;
  final List<ForumHomeFavoriteForum> favoriteForums;
  final ForumHomeChromeData chromeData;
}

class ForumHomeFavoriteForum {
  const ForumHomeFavoriteForum({
    required this.fid,
    required this.title,
    required this.description,
    required this.todayPosts,
  });
  final String fid;
  final String title;
  final String description;
  final int? todayPosts;
}

class ForumHomeCacheEntry {
  const ForumHomeCacheEntry({
    required this.payload,
    required this.capabilities,
    required this.metadata,
    required this.updatedAt,
  });
  final ForumHomePayload payload;
  final forum.ForumDirectoryReadCapabilities capabilities;
  final forum.DataReadMetadata metadata;
  final DateTime updatedAt;
}

abstract class ForumHomeRepository {
  Future<ForumHomeCacheEntry?> readCachedPayload({
    required DocumentRequestProfile requestProfile,
  });

  Future<
    forum.DataReadResult<ForumHomePayload, forum.ForumDirectoryReadCapabilities>
  >
  getForumHomePayload({
    forum.CacheLoadPolicy cachePolicy = forum.CacheLoadPolicy.cacheFirst,
    DocumentRequestProfile? requestProfileOverride,
  });
}

/// Projects the package's source-neutral home document into Y300 UI data.
final class ForumHomeHtmlRepository
    implements ForumHomeRepository, forum.ForumDirectoryRepository {
  const ForumHomeHtmlRepository({
    required forum.ForumHomeRepository repository,
    required forum.ForumDirectoryRepository directoryRepository,
    required ForumHomeCarouselImageProbe imageProbe,
    YamiboSessionStore? sessionStore,
  }) : _repository = repository,
       _directoryRepository = directoryRepository,
       _imageProbe = imageProbe,
       _sessionStore = sessionStore;

  final forum.ForumHomeRepository _repository;
  final forum.ForumDirectoryRepository _directoryRepository;
  final ForumHomeCarouselImageProbe _imageProbe;
  final YamiboSessionStore? _sessionStore;

  @override
  forum.ForumDirectorySourceCapabilities get capabilities =>
      _directoryRepository.capabilities;

  @override
  Future<
    forum.DataReadResult<
      forum.ForumDirectoryData,
      forum.ForumDirectoryReadCapabilities
    >
  >
  load(
    forum.ForumDirectoryQuery query, {
    forum.CacheLoadPolicy cachePolicy = forum.CacheLoadPolicy.cacheFirst,
  }) => _directoryRepository.load(query, cachePolicy: cachePolicy);

  @override
  Future<ForumHomeCacheEntry?> readCachedPayload({
    required DocumentRequestProfile requestProfile,
  }) async {
    final value = await _repository.readCached(
      forum.ForumHomeQuery(audience: _audience(requestProfile)),
    );
    if (value == null) return null;
    return ForumHomeCacheEntry(
      payload: _project(value.data, requestProfile: requestProfile),
      capabilities: _directoryCapabilities,
      metadata: value.metadata,
      updatedAt: value.updatedAt,
    );
  }

  @override
  Future<
    forum.DataReadResult<ForumHomePayload, forum.ForumDirectoryReadCapabilities>
  >
  getForumHomePayload({
    forum.CacheLoadPolicy cachePolicy = forum.CacheLoadPolicy.cacheFirst,
    DocumentRequestProfile? requestProfileOverride,
  }) async {
    final profile =
        requestProfileOverride ??
        (_sessionStore?.readCurrent()?.isLoggedIn == true
            ? DocumentRequestProfile.loggedIn
            : DocumentRequestProfile.anonymous);
    final result = await _repository.loadHome(
      forum.ForumHomeQuery(audience: _audience(profile)),
      cachePolicy: cachePolicy,
    );
    if (result case forum.DataReadFailure<
      forum.ForumHomeDocument,
      forum.ForumHomeReadCapabilities
    >(
      :final kind,
      :final code,
      :final statusCode,
      :final diagnosticMessage,
    )) {
      return forum.DataReadFailure(
        kind: kind,
        code: code,
        statusCode: statusCode,
        diagnosticMessage: diagnosticMessage,
      );
    }
    final success =
        result
            as forum.DataReadSuccess<
              forum.ForumHomeDocument,
              forum.ForumHomeReadCapabilities
            >;
    var payload = _project(success.data, requestProfile: profile);
    if (success.metadata.origin == forum.DataReadOrigin.network) {
      payload = await _resolveCarousel(payload);
    }
    return forum.DataReadSuccess(
      data: payload,
      capabilities: _directoryCapabilities,
      metadata: success.metadata,
    );
  }

  forum.ForumHomeAudience _audience(DocumentRequestProfile profile) =>
      switch (profile) {
        DocumentRequestProfile.anonymous => forum.ForumHomeAudience.anonymous,
        DocumentRequestProfile.loggedIn =>
          forum.ForumHomeAudience.authenticated,
      };

  ForumHomePayload _project(
    forum.ForumHomeDocument value, {
    required DocumentRequestProfile requestProfile,
  }) {
    final favorites = [
      for (final item in value.favoriteForums)
        ForumHomeFavoriteForum(
          fid: item.fid,
          title: item.title,
          description: item.description,
          todayPosts: item.todayPosts,
        ),
    ];
    return ForumHomePayload(
      directory: value.directory,
      isLoggedIn: requestProfile == DocumentRequestProfile.loggedIn,
      favoriteForums: List.unmodifiable(favorites),
      chromeData: ForumHomeChromeData(
        carouselItems: [
          for (final item in value.carousel)
            ForumHomeCarouselItem(
              imageUrl: item.imageUri.toString(),
              targetUrl: item.targetUri.toString(),
            ),
        ],
        favoriteForums: [
          for (final item in favorites)
            ForumHomeChromeForumItem(
              fid: item.fid,
              title: item.title,
              description: item.description,
              todayPosts: item.todayPosts,
            ),
        ],
      ),
    );
  }

  Future<ForumHomePayload> _resolveCarousel(ForumHomePayload payload) async {
    if (payload.chromeData.carouselItems.isEmpty) return payload;
    final first = payload.chromeData.carouselItems.first;
    final ratio = await _imageProbe.resolveAspectRatio(first.imageUrl);
    if (ratio == null) return payload;
    return ForumHomePayload(
      directory: payload.directory,
      isLoggedIn: payload.isLoggedIn,
      favoriteForums: payload.favoriteForums,
      chromeData: payload.chromeData.copyWith(
        carouselItems: [
          first.copyWith(aspectRatio: ratio),
          ...payload.chromeData.carouselItems.skip(1),
        ],
      ),
    );
  }
}

final forumHomeRepositoryProvider = Provider<ForumHomeRepository>((ref) {
  final client = ref.watch(yamiboForumClientProvider);
  return ForumHomeHtmlRepository(
    repository: client.forumHome!,
    directoryRepository: client.forumDirectory!,
    sessionStore: ref.watch(yamiboSessionStoreProvider),
    imageProbe: ForumHomeCarouselImageProbe(
      resourceClient: ref.watch(yamiboForumResourceClientProvider),
      referenceResolver: ref.watch(
        yamiboForumResourceReferenceResolverProvider,
      ),
      referer: ref.watch(forumImageRefererProvider),
    ),
  );
});

final forumDirectoryRepositoryProvider =
    Provider<forum.ForumDirectoryRepository>(
      (ref) => ref.watch(yamiboForumClientProvider).forumDirectory!,
    );

final _directoryCapabilities = forum.ForumDirectoryReadCapabilities(
  values: forum.DataCapabilitySet<forum.ForumDirectoryCapability>.from(
    supported: const [
      forum.ForumDirectoryCapability.stableSectionIdentity,
      forum.ForumDirectoryCapability.orderedSections,
      forum.ForumDirectoryCapability.stableForumIdentity,
      forum.ForumDirectoryCapability.orderedForums,
      forum.ForumDirectoryCapability.forumDescription,
      forum.ForumDirectoryCapability.todayPostCount,
    ],
    unsupported: const [forum.ForumDirectoryCapability.nestedForums],
  ),
);
