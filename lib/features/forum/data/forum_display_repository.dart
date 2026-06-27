import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/document_cache_models.dart';
import 'package:y300/features/cache/domain/parsed_snapshot_cache_models.dart';
import 'package:y300/features/forum/data/forum_display_html_parser.dart';
import 'package:y300/features/forum/data/forum_display_snapshot_codec.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';

abstract class ForumDisplayRepository {
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page,
  });

  Future<ApiResult<ForumDisplayData>> getForumDisplayByQuery(
    ForumDisplayQuery query,
  );
}

class ForumDisplayHtmlRepository implements ForumDisplayRepository {
  ForumDisplayHtmlRepository({
    required YamiboHtmlClient htmlClient,
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
       _parser = parser,
       _documentCacheService = documentCacheService,
       _snapshotCacheService = snapshotCacheService,
       _cacheKeyCanonicalizer = cacheKeyCanonicalizer,
       _snapshotCodec = snapshotCodec,
       _snapshotPolicy = snapshotPolicy,
       _now = now ?? DateTime.now;

  final YamiboHtmlClient _htmlClient;
  final ForumDisplayHtmlParser _parser;
  final DocumentCacheService? _documentCacheService;
  final ParsedSnapshotCacheService? _snapshotCacheService;
  final CacheKeyCanonicalizer _cacheKeyCanonicalizer;
  final ForumDisplaySnapshotCodec _snapshotCodec;
  final SnapshotCachePolicy _snapshotPolicy;
  final DateTime Function() _now;

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page = 1,
  }) {
    return getForumDisplayByQuery(
      ForumDisplayQuery.initial(fid: fid).copyWithPage(page),
    );
  }

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplayByQuery(
    ForumDisplayQuery query,
  ) async {
    final requestParameters = query.toRequestParameters();
    final documentDescriptor = _cacheKeyCanonicalizer.forumDisplay(
      fid: query.fid,
      page: query.page,
      queryParameters: requestParameters,
    );
    final snapshotDescriptor = _cacheKeyCanonicalizer.forumDisplaySnapshot(
      fid: query.fid,
      page: query.page,
      queryParameters: requestParameters,
    );
    final snapshot = await _getFreshSnapshot(snapshotDescriptor);
    if (snapshot != null) {
      return ApiSuccess(snapshot);
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

/// Discuz forumdisplay 实现，负责帖子列表分页拉取。
class DiscuzForumDisplayRepository implements ForumDisplayRepository {
  DiscuzForumDisplayRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page = 1,
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
    ForumDisplayQuery query,
  ) {
    return getForumDisplay(fid: query.fid, page: query.page);
  }
}

final forumDisplayRepositoryProvider = Provider<ForumDisplayRepository>((ref) {
  return ForumDisplayHtmlRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
    documentCacheService: ref.watch(documentCacheServiceProvider),
    snapshotCacheService: ref.watch(parsedSnapshotCacheServiceProvider),
  );
});
