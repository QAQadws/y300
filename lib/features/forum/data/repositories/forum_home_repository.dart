import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/services/cache_key_canonicalizer.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/forum/data/services/forum_home_carousel_image_probe.dart';
import 'package:y300/features/forum/data/services/forum_home_html_parser.dart';
import 'package:y300/features/forum/data/services/forum_home_snapshot_codec.dart';
import 'package:y300/features/forum/data/services/forum_directory_validator.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/data/models/forum_home_html_models.dart';

/// 论坛首页聚合结果：把论坛首页基础数据与登录态相关扩展信息统一返回。
class ForumHomePayload {
  ForumHomePayload({
    required this.directory,
    required this.isLoggedIn,
    required this.favoriteForums,
    this.chromeData = ForumHomeChromeData.empty,
  });

  final ForumDirectoryData directory;
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
  final ForumDirectoryReadCapabilities capabilities;
  final DataReadMetadata metadata;
  final DateTime updatedAt;
}

abstract class ForumHomeRepository {
  Future<ForumHomeCacheEntry?> readCachedPayload({
    required DocumentRequestProfile requestProfile,
  });

  Future<DataReadResult<ForumHomePayload, ForumDirectoryReadCapabilities>>
  getForumHomePayload({
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    DocumentRequestProfile? requestProfileOverride,
  });
}

/// HTML-first 论坛首页仓库。
///
/// 原生首页初始渲染只依赖移动端首页 HTML；版块目录 contract 复用同一读取链路。
class ForumHomeHtmlRepository
    implements ForumHomeRepository, ForumDirectoryRepository {
  ForumHomeHtmlRepository({
    required YamiboHtmlClient htmlClient,
    required ForumHomeCarouselImageProbe imageProbe,
    YamiboSessionStore? sessionStore,
    ForumHomeHtmlParser parser = const ForumHomeHtmlParser(),
    DocumentCacheService? documentCacheService,
    ParsedSnapshotCacheService? snapshotCacheService,
    CacheKeyCanonicalizer cacheKeyCanonicalizer = const CacheKeyCanonicalizer(),
    ForumHomeSnapshotCodec snapshotCodec = const ForumHomeSnapshotCodec(),
    SnapshotCachePolicy snapshotPolicy = const SnapshotCachePolicy(
      freshFor: Duration(minutes: 5),
      keepStaleFor: Duration(days: 1),
    ),
    DateTime Function()? now,
  }) : _htmlClient = htmlClient,
       _imageProbe = imageProbe,
       _sessionStore = sessionStore,
       _parser = parser,
       _documentCacheService = documentCacheService,
       _snapshotCacheService = snapshotCacheService,
       _cacheKeyCanonicalizer = cacheKeyCanonicalizer,
       _snapshotCodec = snapshotCodec,
       _snapshotPolicy = snapshotPolicy,
       _now = now ?? DateTime.now;

  final YamiboHtmlClient _htmlClient;
  final ForumHomeCarouselImageProbe _imageProbe;
  final YamiboSessionStore? _sessionStore;
  final ForumHomeHtmlParser _parser;
  final DocumentCacheService? _documentCacheService;
  final ParsedSnapshotCacheService? _snapshotCacheService;
  final CacheKeyCanonicalizer _cacheKeyCanonicalizer;
  final ForumHomeSnapshotCodec _snapshotCodec;
  final SnapshotCachePolicy _snapshotPolicy;
  final DateTime Function() _now;

  @override
  ForumDirectorySourceCapabilities get capabilities =>
      _htmlDirectoryCapabilities;

  @override
  Future<DataReadResult<ForumDirectoryData, ForumDirectoryReadCapabilities>>
  load(
    ForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final result = await _readHomePayload(
      cachePolicy: cachePolicy,
      resolveCarouselAspectRatio: false,
      persistSnapshot: false,
    );
    return result.when(
      success: (payload, capabilities, metadata) => DataReadSuccess(
        data: payload.directory,
        capabilities: capabilities,
        metadata: metadata,
      ),
      failure: (failure) => failure.retype(),
    );
  }

  @override
  Future<ForumHomeCacheEntry?> readCachedPayload({
    required DocumentRequestProfile requestProfile,
  }) async {
    final documentDescriptor = _cacheKeyCanonicalizer.forumHome(
      requestProfile: requestProfile,
    );
    final snapshotDescriptor = _cacheKeyCanonicalizer.forumHomeSnapshot(
      requestProfile: requestProfile,
    );
    final snapshot = await _getCachedSnapshot(snapshotDescriptor);
    if (snapshot != null) {
      final payload = _withRequestProfile(
        snapshot.value,
        requestProfile: requestProfile,
      );
      if (validateForumDirectory(payload.directory) != null) {
        return null;
      }
      return ForumHomeCacheEntry(
        payload: payload,
        capabilities: _htmlReadCapabilitiesFor(),
        metadata: DataReadMetadata(
          origin: DataReadOrigin.freshSnapshot,
          freshness: snapshot.isFresh(_now())
              ? DataReadFreshness.freshCache
              : DataReadFreshness.staleOrUnknown,
        ),
        updatedAt: snapshot.updatedAt,
      );
    }

    final documentCache = _documentCacheService;
    if (documentCache == null) {
      return null;
    }
    final cachedDocument = await _safeGetCachedDocument(
      documentCache,
      documentDescriptor.cacheKey,
    );
    if (cachedDocument == null) {
      return null;
    }
    try {
      // Rehydrating the last successful page must stay disk/CPU-only. In
      // particular, do not probe the carousel image before cached content can
      // be shown; the background network refresh will resolve a fresh ratio.
      final payload = await _parsePayload(
        cachedDocument.body,
        requestProfile: requestProfile,
        resolveCarouselAspectRatio: false,
      );
      final validation = validateForumDirectory(payload.directory);
      if (validation != null) {
        return null;
      }
      return ForumHomeCacheEntry(
        payload: payload,
        capabilities: _htmlReadCapabilitiesFor(),
        metadata: const DataReadMetadata(
          origin: DataReadOrigin.cachedDocumentFallback,
          freshness: DataReadFreshness.staleOrUnknown,
        ),
        updatedAt: cachedDocument.updatedAt,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DataReadResult<ForumHomePayload, ForumDirectoryReadCapabilities>>
  getForumHomePayload({
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    DocumentRequestProfile? requestProfileOverride,
  }) async {
    return _readHomePayload(
      cachePolicy: cachePolicy,
      requestProfileOverride: requestProfileOverride,
      resolveCarouselAspectRatio: true,
      persistSnapshot: true,
    );
  }

  Future<DataReadResult<ForumHomePayload, ForumDirectoryReadCapabilities>>
  _readHomePayload({
    required CacheLoadPolicy cachePolicy,
    DocumentRequestProfile? requestProfileOverride,
    required bool resolveCarouselAspectRatio,
    required bool persistSnapshot,
  }) async {
    final requestProfile = _resolveRequestProfile(
      requestProfileOverride: requestProfileOverride,
    );
    final documentDescriptor = _cacheKeyCanonicalizer.forumHome(
      requestProfile: requestProfile,
    );
    final snapshotDescriptor = _cacheKeyCanonicalizer.forumHomeSnapshot(
      requestProfile: requestProfile,
    );
    if (cachePolicy == CacheLoadPolicy.cacheFirst) {
      final snapshot = await _getCachedSnapshot(snapshotDescriptor);
      if (snapshot != null && snapshot.isFresh(_now())) {
        final payload = _withRequestProfile(
          snapshot.value,
          requestProfile: requestProfile,
        );
        final validation = validateForumDirectory(payload.directory);
        if (validation == null) {
          return DataReadSuccess(
            data: payload,
            capabilities: _htmlReadCapabilitiesFor(),
            metadata: const DataReadMetadata(
              origin: DataReadOrigin.freshSnapshot,
              freshness: DataReadFreshness.freshCache,
            ),
          );
        }
      }
    }

    final htmlResult = await _htmlClient.getMobilePage(
      path: '/index.php',
      queryParameters: const <String, String>{'mobile': '2'},
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'forum.home.html',
        pageKind: 'forum.home',
      ),
    );
    if (htmlResult case ApiFailure<String>(:final error)) {
      final cached = await _parseCachedDocument(
        documentDescriptor: documentDescriptor,
        snapshotDescriptor: snapshotDescriptor,
        requestProfile: requestProfile,
        persistSnapshot: persistSnapshot,
      );
      if (cached != null) {
        return DataReadSuccess(
          data: cached,
          capabilities: _htmlReadCapabilitiesFor(),
          metadata: const DataReadMetadata(
            origin: DataReadOrigin.cachedDocumentFallback,
            freshness: DataReadFreshness.staleOrUnknown,
          ),
        );
      }
      return DataReadFailure(
        kind: _failureKindFor(error),
        code: error.code,
        statusCode: error.statusCode,
        diagnosticMessage: '论坛首页 HTML 加载失败: ${error.message}',
      );
    }

    try {
      final html = htmlResult.dataOrNull ?? '';
      final payload = await _parsePayload(
        html,
        requestProfile: requestProfile,
        resolveCarouselAspectRatio: resolveCarouselAspectRatio,
      );
      final validation = validateForumDirectory(payload.directory);
      if (validation != null) {
        throw FormatException(validation);
      }
      await _putDocument(descriptor: documentDescriptor, html: html);
      if (persistSnapshot) {
        await _putSnapshot(descriptor: snapshotDescriptor, payload: payload);
      }
      final capabilities = _htmlReadCapabilitiesFor();
      return DataReadSuccess(
        data: payload,
        capabilities: capabilities,
        metadata: const DataReadMetadata.network(),
      );
    } catch (error) {
      return DataReadFailure(
        kind: DataReadFailureKind.parse,
        diagnosticMessage: '论坛首页 HTML 解析失败: $error',
      );
    }
  }

  DocumentRequestProfile _resolveRequestProfile({
    DocumentRequestProfile? requestProfileOverride,
  }) {
    if (requestProfileOverride != null) {
      return requestProfileOverride;
    }
    final session = _sessionStore?.readCurrent();
    return session?.isLoggedIn == true
        ? DocumentRequestProfile.loggedIn
        : DocumentRequestProfile.anonymous;
  }

  Future<ForumHomePayload> _parsePayload(
    String html, {
    required DocumentRequestProfile requestProfile,
    bool resolveCarouselAspectRatio = true,
  }) async {
    final htmlData = _parser.parse(html);
    if (!htmlData.hasForumList) {
      throw const FormatException('论坛首页缺少版块目录根节点');
    }
    final resolved = resolveCarouselAspectRatio
        ? await _withResolvedCarouselAspectRatio(htmlData)
        : htmlData;
    return _toPayload(resolved, requestProfile: requestProfile);
  }

  Future<ForumHomePayload?> _parseCachedDocument({
    required DocumentCacheDescriptor documentDescriptor,
    required SnapshotCacheDescriptor snapshotDescriptor,
    required DocumentRequestProfile requestProfile,
    required bool persistSnapshot,
  }) async {
    final cache = _documentCacheService;
    if (cache == null) {
      return null;
    }
    final document = await _safeGetCachedDocument(
      cache,
      documentDescriptor.cacheKey,
    );
    if (document == null) {
      return null;
    }
    try {
      final payload = await _parsePayload(
        document.body,
        requestProfile: requestProfile,
        resolveCarouselAspectRatio: false,
      );
      await _safeTouchCachedDocument(cache, document.cacheKey, _now());
      if (persistSnapshot) {
        await _putSnapshot(descriptor: snapshotDescriptor, payload: payload);
      }
      return payload;
    } catch (_) {
      return null;
    }
  }

  Future<CachedSnapshot<ForumHomePayload>?> _getCachedSnapshot(
    SnapshotCacheDescriptor descriptor,
  ) async {
    final cache = _snapshotCacheService;
    if (cache == null) {
      return null;
    }
    try {
      return await cache.get(descriptor, _snapshotCodec);
    } catch (_) {
      return null;
    }
  }

  Future<void> _putDocument({
    required DocumentCacheDescriptor descriptor,
    required String html,
  }) async {
    final cache = _documentCacheService;
    if (cache == null) {
      return;
    }
    final now = _now();
    try {
      await cache.put(
        CachedDocument(
          cacheKey: descriptor.cacheKey,
          ownerType: descriptor.ownerType,
          ownerId: descriptor.ownerId,
          sourceUrl: descriptor.sourceUrl,
          requestProfile: descriptor.requestProfile,
          body: html,
          contentType: 'text/html',
          statusCode: 200,
          fetchedAt: now,
          updatedAt: now,
          lastAccessedAt: now,
        ),
      );
    } catch (_) {
      // 首页网络加载成功时，缓存写入失败不应阻断渲染。
    }
  }

  Future<void> _putSnapshot({
    required SnapshotCacheDescriptor descriptor,
    required ForumHomePayload payload,
  }) async {
    final cache = _snapshotCacheService;
    if (cache == null) {
      return;
    }
    try {
      await cache.put(
        descriptor,
        payload,
        _snapshotCodec,
        policy: _snapshotPolicy,
      );
    } catch (_) {
      // Snapshot 写入失败不应阻断首页展示。
    }
  }

  Future<CachedDocument?> _safeGetCachedDocument(
    DocumentCacheService cache,
    String cacheKey,
  ) async {
    try {
      return await cache.getByKey(cacheKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _safeTouchCachedDocument(
    DocumentCacheService cache,
    String cacheKey,
    DateTime accessedAt,
  ) async {
    try {
      await cache.touch(cacheKey, accessedAt);
    } catch (_) {
      return;
    }
  }

  Future<ForumHomeHtmlData> _withResolvedCarouselAspectRatio(
    ForumHomeHtmlData data,
  ) async {
    if (data.carouselItems.isEmpty) {
      return data;
    }
    final firstItem = data.carouselItems.first;
    final aspectRatio = await _imageProbe.resolveAspectRatio(
      firstItem.imageUrl,
    );
    if (aspectRatio == null) {
      return data;
    }
    return ForumHomeHtmlData(
      carouselItems: [
        firstItem.copyWith(aspectRatio: aspectRatio),
        ...data.carouselItems.skip(1),
      ],
      sections: data.sections,
      hasForumList: data.hasForumList,
    );
  }

  ForumHomePayload _toPayload(
    ForumHomeHtmlData data, {
    required DocumentRequestProfile requestProfile,
  }) {
    final regularSections = data.sections
        .where((section) => !section.isFavoriteSection)
        .toList(growable: false);

    final favoriteItems = [
      for (final section in data.sections)
        if (section.isFavoriteSection)
          for (final item in section.items) item,
    ];

    return ForumHomePayload(
      directory: ForumDirectoryData(
        sections: [
          for (final section in regularSections)
            ForumDirectorySection(
              identity: section.identity,
              title: section.title,
              forums: [
                for (final item in section.items)
                  ForumDirectoryForum(
                    fid: item.fid,
                    title: item.title,
                    description: item.description,
                    todayPosts: item.todayPosts,
                  ),
              ],
            ),
        ],
      ),
      isLoggedIn: requestProfile == DocumentRequestProfile.loggedIn,
      favoriteForums: [
        for (final item in favoriteItems) _toFavoriteForum(item),
      ],
      chromeData: ForumHomeChromeData(
        carouselItems: data.carouselItems,
        favoriteForums: [
          for (final item in favoriteItems) _toChromeForumItem(item),
        ],
      ),
    );
  }

  ForumHomePayload _withRequestProfile(
    ForumHomePayload payload, {
    required DocumentRequestProfile requestProfile,
  }) {
    final isLoggedIn = requestProfile == DocumentRequestProfile.loggedIn;
    if (payload.isLoggedIn == isLoggedIn) {
      return payload;
    }
    return ForumHomePayload(
      directory: payload.directory,
      isLoggedIn: isLoggedIn,
      favoriteForums: payload.favoriteForums,
      chromeData: payload.chromeData,
    );
  }

  ForumHomeFavoriteForum _toFavoriteForum(ForumHomeHtmlForumItem item) {
    return ForumHomeFavoriteForum(
      fid: item.fid,
      title: item.title,
      description: item.description,
      todayPosts: item.todayPosts,
    );
  }

  ForumHomeChromeForumItem _toChromeForumItem(ForumHomeHtmlForumItem item) {
    return ForumHomeChromeForumItem(
      fid: item.fid,
      title: item.title,
      description: item.description,
      todayPosts: item.todayPosts,
    );
  }
}

final forumHomeHtmlRepositoryProvider = Provider<ForumHomeHtmlRepository>((
  ref,
) {
  return ForumHomeHtmlRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
    imageProbe: ForumHomeCarouselImageProbe(
      resourceClient: ref.watch(yamiboResourceClientProvider),
      headerBuilder: ref.watch(imageRequestHeaderBuilderProvider),
    ),
    sessionStore: ref.watch(yamiboSessionStoreProvider),
    documentCacheService: ref.watch(documentCacheServiceProvider),
    snapshotCacheService: ref.watch(parsedSnapshotCacheServiceProvider),
  );
});

final forumHomeRepositoryProvider = Provider<ForumHomeRepository>((ref) {
  return ref.watch(forumHomeHtmlRepositoryProvider);
});

final forumDirectoryRepositoryProvider = Provider<ForumDirectoryRepository>((
  ref,
) {
  return ref.watch(yamiboForumClientProvider).forumDirectory!;
});

DataReadFailureKind _failureKindFor(ApiError error) {
  if (error.code == 'request_cancelled') {
    return DataReadFailureKind.cancelled;
  }
  return switch (error.type) {
    ApiErrorType.network => DataReadFailureKind.network,
    ApiErrorType.timeout => DataReadFailureKind.timeout,
    ApiErrorType.unauthorized => DataReadFailureKind.unauthorized,
    ApiErrorType.server => DataReadFailureKind.server,
    ApiErrorType.parse => DataReadFailureKind.parse,
    ApiErrorType.business => DataReadFailureKind.business,
    ApiErrorType.unknown => DataReadFailureKind.unknown,
  };
}

final _htmlDirectoryCapabilities = ForumDirectorySourceCapabilities(
  values: DataCapabilitySet<ForumDirectoryCapability>.from(
    supported: const <ForumDirectoryCapability>[
      ForumDirectoryCapability.stableSectionIdentity,
      ForumDirectoryCapability.orderedSections,
      ForumDirectoryCapability.stableForumIdentity,
      ForumDirectoryCapability.orderedForums,
      ForumDirectoryCapability.forumDescription,
      ForumDirectoryCapability.todayPostCount,
    ],
    unsupported: const <ForumDirectoryCapability>[
      ForumDirectoryCapability.nestedForums,
    ],
  ),
);

ForumDirectoryReadCapabilities _htmlReadCapabilitiesFor() {
  return _htmlDirectoryCapabilities.toReadCapabilities();
}
