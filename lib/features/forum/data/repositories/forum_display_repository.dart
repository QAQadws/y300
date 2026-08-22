import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/cache/domain/services/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/forum/data/services/forum_display_html_parser.dart';
import 'package:y300/features/forum/data/services/forum_display_snapshot_codec.dart';
import 'package:y300/features/forum/data/mappers/forum_display_api_mapper.dart';
import 'package:y300/features/forum/domain/models/forum_display_models.dart';
import 'package:y300/features/forum/domain/repositories/forum_display_repository.dart';

class ForumDisplayHtmlRepository implements ForumDisplayRepository {
  ForumDisplayHtmlRepository({
    required YamiboHtmlClient htmlClient,
    YamiboSessionStore? sessionStore,
    ForumDisplayHtmlParser parser = const ForumDisplayHtmlParser(),
    DocumentCacheService? documentCacheService,
    ParsedSnapshotCacheService? snapshotCacheService,
    CacheKeyCanonicalizer cacheKeyCanonicalizer = const CacheKeyCanonicalizer(),
    ForumDisplaySnapshotCodec snapshotCodec = const ForumDisplaySnapshotCodec(),
    SnapshotCachePolicy snapshotPolicy = const SnapshotCachePolicy(
      freshFor: Duration(minutes: 3),
      keepStaleFor: Duration(hours: 12),
    ),
    DateTime Function()? now,
  }) : _htmlClient = htmlClient,
       _sessionStore = sessionStore,
       _parser = parser,
       _documentCacheService = documentCacheService,
       _snapshotCacheService = snapshotCacheService,
       _cacheKeyCanonicalizer = cacheKeyCanonicalizer,
       _snapshotCodec = snapshotCodec,
       _snapshotPolicy = snapshotPolicy,
       _now = now ?? DateTime.now;

  final YamiboHtmlClient _htmlClient;
  final YamiboSessionStore? _sessionStore;
  final ForumDisplayHtmlParser _parser;
  final DocumentCacheService? _documentCacheService;
  final ParsedSnapshotCacheService? _snapshotCacheService;
  final CacheKeyCanonicalizer _cacheKeyCanonicalizer;
  final ForumDisplaySnapshotCodec _snapshotCodec;
  final SnapshotCachePolicy _snapshotPolicy;
  final DateTime Function() _now;

  @override
  ForumDisplaySourceCapabilities get capabilities => _htmlCapabilities;

  @override
  Future<DataReadResult<ForumDisplayData, ForumDisplayReadCapabilities>>
  getForumDisplayByQuery(
    ForumDisplayQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final requestParameters = query.toRequestParameters();
    final requestProfile = _resolveRequestProfile();
    final documentDescriptor = _cacheKeyCanonicalizer.forumDisplay(
      fid: query.fid,
      page: query.page,
      queryParameters: requestParameters,
      requestProfile: requestProfile,
    );
    final snapshotDescriptor = _cacheKeyCanonicalizer.forumDisplaySnapshot(
      fid: query.fid,
      page: query.page,
      queryParameters: requestParameters,
      requestProfile: requestProfile,
    );
    if (cachePolicy == CacheLoadPolicy.cacheFirst) {
      final snapshot = await _getFreshSnapshot(snapshotDescriptor);
      if (snapshot != null) {
        return _validatedForumDisplayResult(
          requestedFid: query.fid,
          data: snapshot,
          capabilities: _htmlReadCapabilitiesFor(snapshot),
          metadata: const DataReadMetadata(
            origin: DataReadOrigin.freshSnapshot,
            freshness: DataReadFreshness.freshCache,
          ),
        );
      }
    }

    final htmlResult = await _htmlClient.getMobilePage(
      path: '/forum.php',
      queryParameters: requestParameters,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'forum.display.html',
        pageKind: 'forum.display',
      ),
    );

    if (htmlResult case ApiFailure<String>(:final error)) {
      final cached = await _parseCachedDocument(
        documentDescriptor: documentDescriptor,
        snapshotDescriptor: snapshotDescriptor,
        query: query,
      );
      if (cached != null) {
        return _validatedForumDisplayResult(
          requestedFid: query.fid,
          data: cached,
          capabilities: _htmlReadCapabilitiesFor(cached),
          metadata: const DataReadMetadata(
            origin: DataReadOrigin.cachedDocumentFallback,
            freshness: DataReadFreshness.staleOrUnknown,
          ),
        );
      }
      final failure =
          dataReadFailureFromApiError<
            ForumDisplayData,
            ForumDisplayReadCapabilities
          >(error);
      return DataReadFailure(
        kind: failure.kind,
        code: failure.code,
        statusCode: failure.statusCode,
        diagnosticMessage: '帖子列表 HTML 加载失败: ${error.message}',
      );
    }

    try {
      final html = htmlResult.dataOrNull ?? '';
      final data = _parser.parse(
        html,
        fallbackFid: query.fid,
        fallbackPage: query.page,
      );
      await _putDocument(descriptor: documentDescriptor, html: html);
      await _putSnapshot(descriptor: snapshotDescriptor, data: data);
      return _validatedForumDisplayResult(
        requestedFid: query.fid,
        data: data,
        capabilities: _htmlReadCapabilitiesFor(data),
        metadata: const DataReadMetadata.network(),
      );
    } catch (error) {
      return DataReadFailure(
        kind: DataReadFailureKind.parse,
        diagnosticMessage: '帖子列表 HTML 解析失败: $error',
      );
    }
  }

  DocumentRequestProfile _resolveRequestProfile() {
    final session = _sessionStore?.readCurrent();
    return session?.isLoggedIn == true
        ? DocumentRequestProfile.loggedIn
        : DocumentRequestProfile.anonymous;
  }

  Future<ForumDisplayData?> _parseCachedDocument({
    required DocumentCacheDescriptor documentDescriptor,
    required SnapshotCacheDescriptor snapshotDescriptor,
    required ForumDisplayQuery query,
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
      final data = _parser.parse(
        document.body,
        fallbackFid: query.fid,
        fallbackPage: query.page,
      );
      await _safeTouchCachedDocument(cache, document.cacheKey, _now());
      await _putSnapshot(descriptor: snapshotDescriptor, data: data);
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<ForumDisplayData?> _getFreshSnapshot(
    SnapshotCacheDescriptor descriptor,
  ) async {
    final cache = _snapshotCacheService;
    if (cache == null) {
      return null;
    }
    try {
      final snapshot = await cache.get(descriptor, _snapshotCodec);
      if (snapshot == null || !snapshot.isFresh(_now())) {
        return null;
      }
      return snapshot.value;
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
      // HTML 文档写入失败不应阻断帖子列表展示。
    }
  }

  Future<void> _putSnapshot({
    required SnapshotCacheDescriptor descriptor,
    required ForumDisplayData data,
  }) async {
    final cache = _snapshotCacheService;
    if (cache == null) {
      return;
    }
    try {
      await cache.put(
        descriptor,
        data,
        _snapshotCodec,
        policy: _snapshotPolicy,
      );
    } catch (_) {
      // Snapshot 写入失败不应阻断帖子列表展示。
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
}

ForumDisplayReadCapabilities _htmlReadCapabilitiesFor(ForumDisplayData data) {
  final hasExactPagination = data.lastPage != null && data.lastPage! > 0;
  return ForumDisplayReadCapabilities(
    values: _htmlCapabilities.values.withSupport(
      ForumDisplayCapability.exactPagination,
      hasExactPagination
          ? DataCapabilitySupport.supported
          : DataCapabilitySupport.unsupported,
    ),
    paginationPrecision: hasExactPagination
        ? PaginationPrecision.exact
        : (data.previousPageUrl != null || data.nextPageUrl != null)
        ? PaginationPrecision.directional
        : PaginationPrecision.heuristic,
  );
}

/// Discuz forumdisplay 实现，负责帖子列表分页拉取。
class DiscuzForumDisplayRepository implements ForumDisplayRepository {
  DiscuzForumDisplayRepository(
    this._apiClient, {
    ForumDisplayApiMapper mapper = const ForumDisplayApiMapper(),
  }) : _mapper = mapper;

  final ApiClient _apiClient;
  final ForumDisplayApiMapper _mapper;

  @override
  ForumDisplaySourceCapabilities get capabilities => _apiCapabilities;

  @override
  Future<DataReadResult<ForumDisplayData, ForumDisplayReadCapabilities>>
  getForumDisplayByQuery(
    ForumDisplayQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    if (_hasUnsupportedQuery(query)) {
      return unsupportedDataReadFailure(
        code: 'forum_display_query_unsupported',
        diagnosticMessage:
            'The configured forum source cannot honor this filter or ordering query.',
      );
    }
    final result = await _apiClient.getParsed<ForumDisplayData>(
      module: 'forumdisplay',
      queryParameters: {'fid': query.fid, 'page': query.page},
      parser: (response) =>
          _mapper.mapVariables(response.variables, page: query.page),
    );
    return switch (result) {
      ApiSuccess<ForumDisplayData>(:final data) => _validatedForumDisplayResult(
        requestedFid: query.fid,
        data: data,
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      ),
      ApiFailure<ForumDisplayData>(:final error) => dataReadFailureFromApiError(
        error,
      ),
    };
  }

  bool _hasUnsupportedQuery(ForumDisplayQuery query) {
    final parameters = query.parameters;
    return parameters.entries.any((entry) {
      return entry.key != 'fid' && entry.key != 'page';
    });
  }
}

DataReadResult<ForumDisplayData, ForumDisplayReadCapabilities>
_validatedForumDisplayResult({
  required String requestedFid,
  required ForumDisplayData data,
  required ForumDisplayReadCapabilities capabilities,
  required DataReadMetadata metadata,
}) {
  final normalizedFid = requestedFid.trim();
  if (normalizedFid.isEmpty || data.fid.trim() != normalizedFid) {
    return const DataReadFailure(
      kind: DataReadFailureKind.parse,
      code: 'forum_display_identity_mismatch',
      diagnosticMessage: 'Forum display identity does not match the request.',
    );
  }
  final tids = <String>{};
  for (final thread in data.threads) {
    final tid = thread.tid.trim();
    if (tid.isEmpty || !tids.add(tid)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_display_thread_identity_invalid',
        diagnosticMessage:
            'Forum display contains an invalid or duplicate thread identity.',
      );
    }
  }
  return DataReadSuccess(
    data: data,
    capabilities: capabilities,
    metadata: metadata,
  );
}

final _htmlCapabilities = ForumDisplaySourceCapabilities(
  values: DataCapabilitySet<ForumDisplayCapability>.supported(
    ForumDisplayCapability.values,
  ),
  paginationPrecision: PaginationPrecision.exact,
);

final _apiCapabilities = ForumDisplaySourceCapabilities(
  values: DataCapabilitySet<ForumDisplayCapability>.from(
    supported: const <ForumDisplayCapability>[
      ForumDisplayCapability.forumIdentity,
      ForumDisplayCapability.orderedThreadSummaries,
      ForumDisplayCapability.directionalPagination,
    ],
    unsupported: const <ForumDisplayCapability>[
      ForumDisplayCapability.richThreadSummaries,
      ForumDisplayCapability.threadTypeQuery,
      ForumDisplayCapability.lastPostOrdering,
      ForumDisplayCapability.opaqueQueryParameters,
      ForumDisplayCapability.forumChrome,
      ForumDisplayCapability.filters,
      ForumDisplayCapability.subForums,
      ForumDisplayCapability.topEntries,
      ForumDisplayCapability.postingEntry,
      ForumDisplayCapability.searchEntry,
      ForumDisplayCapability.favoriteState,
      ForumDisplayCapability.exactPagination,
    ],
  ),
  paginationPrecision: PaginationPrecision.totalBased,
);
