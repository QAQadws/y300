import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/document_cache_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_detail_html_parser.dart';
import 'package:y300/features/thread/data/thread_post_locator.dart';

abstract class ThreadRepository {
  Future<ApiResult<ThreadDetailData>> getThreadDetail({
    required String tid,
    int page = 1,
    Map<String, String> queryParameters = const <String, String>{},
  });
}

class ApiThreadRepository implements ThreadRepository {
  ApiThreadRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiResult<ThreadDetailData>> getThreadDetail({
    required String tid,
    int page = 1,
    Map<String, String> queryParameters = const <String, String>{},
  }) {
    return _apiClient.getParsed<ThreadDetailData>(
      module: 'viewthread',
      queryParameters: {...queryParameters, 'tid': tid, 'page': page},
      parser: (response) =>
          ThreadDetailData.fromVariables(response.variables, page: page),
    );
  }
}

class ThreadDetailHtmlRepository implements ThreadRepository {
  ThreadDetailHtmlRepository({
    required YamiboHtmlClient htmlClient,
    ThreadDetailHtmlParser parser = const ThreadDetailHtmlParser(),
    DocumentCacheService? documentCacheService,
    CacheKeyCanonicalizer cacheKeyCanonicalizer = const CacheKeyCanonicalizer(),
    DateTime Function()? now,
  }) : _htmlClient = htmlClient,
       _parser = parser,
       _documentCacheService = documentCacheService,
       _cacheKeyCanonicalizer = cacheKeyCanonicalizer,
       _now = now ?? DateTime.now;

  final YamiboHtmlClient _htmlClient;
  final ThreadDetailHtmlParser _parser;
  final DocumentCacheService? _documentCacheService;
  final CacheKeyCanonicalizer _cacheKeyCanonicalizer;
  final DateTime Function() _now;

  @override
  Future<ApiResult<ThreadDetailData>> getThreadDetail({
    required String tid,
    int page = 1,
    Map<String, String> queryParameters = const <String, String>{},
  }) async {
    final documentDescriptor = _cacheKeyCanonicalizer.threadDetail(
      tid: tid,
      page: page,
      queryParameters: queryParameters,
    );
    final htmlResult = await _htmlClient.getDesktopPage(
      path: '/forum.php',
      queryParameters: <String, String>{
        ...queryParameters,
        'mod': 'viewthread',
        'tid': tid,
        'page': page.toString(),
      },
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.detail.html',
        pageKind: 'thread.detail',
      ),
    );

    if (htmlResult case ApiFailure<String>(:final error)) {
      final cached = await _parseCachedDocument(
        descriptor: documentDescriptor,
        tid: tid,
        page: page,
      );
      if (cached != null) {
        return ApiSuccess(cached);
      }
      return ApiFailure(
        ApiError(
          type: error.type,
          message: '帖子详情 HTML 加载失败: ${error.message}',
          code: error.code,
          statusCode: error.statusCode,
          raw: error.raw,
        ),
      );
    }

    try {
      final html = htmlResult.dataOrNull ?? '';
      final data = _parser.parse(html, fallbackTid: tid, fallbackPage: page);
      await _putDocument(descriptor: documentDescriptor, html: html);
      return ApiSuccess(data);
    } catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.parse,
          message: '帖子详情 HTML 解析失败: $error',
          raw: error,
        ),
      );
    }
  }

  Future<ThreadDetailData?> _parseCachedDocument({
    required DocumentCacheDescriptor descriptor,
    required String tid,
    required int page,
  }) async {
    final cache = _documentCacheService;
    if (cache == null) {
      return null;
    }
    final document = await _safeGetCachedDocument(cache, descriptor.cacheKey);
    if (document == null) {
      return null;
    }
    try {
      final data = _parser.parse(
        document.body,
        fallbackTid: tid,
        fallbackPage: page,
      );
      await _safeTouchCachedDocument(cache, descriptor.cacheKey, _now());
      return data;
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
      // 页面网络加载成功时，缓存写入失败不应阻断阅读。
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

final threadRepositoryProvider = Provider<ThreadRepository>((ref) {
  return ThreadDetailHtmlRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
    documentCacheService: ref.watch(documentCacheServiceProvider),
  );
});

final threadPostLocatorProvider = Provider<ThreadPostLocator>((ref) {
  return HtmlThreadPostLocator(gateway: ref.watch(yamiboHttpGatewayProvider));
});
