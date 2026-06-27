import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/cache_diagnostic_models.dart';
import 'package:y300/features/cache/domain/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/cache_load_policy.dart';
import 'package:y300/features/cache/domain/document_cache_models.dart';
import 'package:y300/features/cache/domain/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';
import 'package:y300/features/forum/data/forum_display_html_parser.dart';
import 'package:y300/features/forum/data/forum_display_snapshot_codec.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';

abstract class ForumDisplayRepository {
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page,
    CacheLoadPolicy cachePolicy,
  });

  Future<ApiResult<ForumDisplayData>> getForumDisplayByQuery(
    ForumDisplayQuery query, {
    CacheLoadPolicy cachePolicy,
  });
}

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
    CacheDiagnosticRecorder diagnosticRecorder =
        const NoopCacheDiagnosticRecorder(),
    DateTime Function()? now,
  }) : _htmlClient = htmlClient,
       _sessionStore = sessionStore,
       _parser = parser,
       _documentCacheService = documentCacheService,
       _snapshotCacheService = snapshotCacheService,
       _cacheKeyCanonicalizer = cacheKeyCanonicalizer,
       _snapshotCodec = snapshotCodec,
       _snapshotPolicy = snapshotPolicy,
       _diagnosticRecorder = diagnosticRecorder,
       _now = now ?? DateTime.now;

  final YamiboHtmlClient _htmlClient;
  final YamiboSessionStore? _sessionStore;
  final ForumDisplayHtmlParser _parser;
  final DocumentCacheService? _documentCacheService;
  final ParsedSnapshotCacheService? _snapshotCacheService;
  final CacheKeyCanonicalizer _cacheKeyCanonicalizer;
  final ForumDisplaySnapshotCodec _snapshotCodec;
  final SnapshotCachePolicy _snapshotPolicy;
  final CacheDiagnosticRecorder _diagnosticRecorder;
  final DateTime Function() _now;

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page = 1,
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    return getForumDisplayByQuery(
      ForumDisplayQuery.initial(fid: fid).copyWithPage(page),
      cachePolicy: cachePolicy,
    );
  }

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplayByQuery(
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
        return ApiSuccess(snapshot);
      }
    }

    _recordPageCacheEvent(
      event: 'refresh',
      descriptor: documentDescriptor,
      reason: cachePolicy == CacheLoadPolicy.networkFirst
          ? 'network_first'
          : 'snapshot_not_fresh',
    );
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
      _recordPageCacheEvent(
        event: 'refresh_failed',
        descriptor: documentDescriptor,
        reason: error.type.name,
        fields: <String, Object?>{
          'message': error.message,
          if (error.statusCode != null) 'statusCode': error.statusCode,
        },
      );
      final cached = await _parseCachedDocument(
        documentDescriptor: documentDescriptor,
        snapshotDescriptor: snapshotDescriptor,
        query: query,
      );
      if (cached != null) {
        _recordPageCacheEvent(
          event: 'stale',
          descriptor: documentDescriptor,
          reason: 'network_failed_document_fallback',
          hit: true,
        );
        return ApiSuccess(cached);
      }
      return ApiFailure(
        ApiError(
          type: error.type,
          message: '帖子列表 HTML 加载失败: ${error.message}',
          code: error.code,
          statusCode: error.statusCode,
          raw: error.raw,
        ),
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
      _recordPageCacheEvent(
        event: 'refresh_succeeded',
        descriptor: documentDescriptor,
        fields: <String, Object?>{'bodyBytes': html.length},
      );
      return ApiSuccess(data);
    } catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.parse,
          message: '帖子列表 HTML 解析失败: $error',
          raw: error,
        ),
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

  void _recordPageCacheEvent({
    required String event,
    required DocumentCacheDescriptor descriptor,
    String? reason,
    bool? hit,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    _diagnosticRecorder.record(
      CacheDiagnosticEvent(
        event: event,
        namespace: CacheNamespace.document,
        bucket: StorageBucket.pageCache,
        cacheKey: descriptor.cacheKey,
        ownerType: descriptor.ownerType,
        ownerId: descriptor.ownerId,
        hit: hit,
        reason: reason,
        fields: fields,
      ),
    );
  }
}

/// Discuz forumdisplay 实现，负责帖子列表分页拉取。
class DiscuzForumDisplayRepository implements ForumDisplayRepository {
  DiscuzForumDisplayRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page = 1,
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    return _apiClient.getParsed<ForumDisplayData>(
      module: 'forumdisplay',
      queryParameters: {'fid': fid, 'page': page},
      parser: (response) =>
          ForumDisplayData.fromVariables(response.variables, page: page),
    );
  }

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplayByQuery(
    ForumDisplayQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    return getForumDisplay(fid: query.fid, page: query.page);
  }
}

final forumDisplayRepositoryProvider = Provider<ForumDisplayRepository>((ref) {
  return ForumDisplayHtmlRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
    sessionStore: ref.watch(yamiboSessionStoreProvider),
    documentCacheService: ref.watch(documentCacheServiceProvider),
    snapshotCacheService: ref.watch(parsedSnapshotCacheServiceProvider),
    diagnosticRecorder: ref.watch(cacheDiagnosticRecorderProvider),
  );
});
