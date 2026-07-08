import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/cache_diagnostic_models.dart';
import 'package:y300/features/cache/domain/services/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/services/thread_detail_html_parser.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';
import 'package:y300/features/thread/data/services/thread_detail_snapshot_codec.dart';

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
    ParsedSnapshotCacheService? snapshotCacheService,
    CacheKeyCanonicalizer cacheKeyCanonicalizer = const CacheKeyCanonicalizer(),
    ThreadDetailSnapshotCodec snapshotCodec = const ThreadDetailSnapshotCodec(),
    SnapshotCachePolicy snapshotPolicy = const SnapshotCachePolicy(
      freshFor: Duration(minutes: 5),
      keepStaleFor: Duration(days: 7),
    ),
    CacheDiagnosticRecorder diagnosticRecorder =
        const NoopCacheDiagnosticRecorder(),
    DateTime Function()? now,
  }) : _htmlClient = htmlClient,
       _parser = parser,
       _documentCacheService = documentCacheService,
       _snapshotCacheService = snapshotCacheService,
       _cacheKeyCanonicalizer = cacheKeyCanonicalizer,
       _snapshotCodec = snapshotCodec,
       _snapshotPolicy = snapshotPolicy,
       _diagnosticRecorder = diagnosticRecorder,
       _now = now ?? DateTime.now;

  final YamiboHtmlClient _htmlClient;
  final ThreadDetailHtmlParser _parser;
  final DocumentCacheService? _documentCacheService;
  final ParsedSnapshotCacheService? _snapshotCacheService;
  final CacheKeyCanonicalizer _cacheKeyCanonicalizer;
  final ThreadDetailSnapshotCodec _snapshotCodec;
  final SnapshotCachePolicy _snapshotPolicy;
  final CacheDiagnosticRecorder _diagnosticRecorder;
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
    final snapshotDescriptor = _cacheKeyCanonicalizer.threadDetailSnapshot(
      tid: tid,
      page: page,
      queryParameters: queryParameters,
    );
    final snapshot = await _getFreshSnapshot(snapshotDescriptor);
    if (snapshot != null) {
      return ApiSuccess(snapshot);
    }
    _recordPageCacheEvent(
      event: 'refresh',
      descriptor: documentDescriptor,
      reason: 'snapshot_not_fresh',
    );
    final htmlResult = await _htmlClient.getMobilePage(
      path: '/forum.php',
      queryParameters: <String, String>{
        ...queryParameters,
        'mod': 'viewthread',
        'tid': tid,
        'page': page.toString(),
        'mobile': '2',
      },
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.detail.html',
        pageKind: 'thread.detail',
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
        descriptor: documentDescriptor,
        snapshotDescriptor: snapshotDescriptor,
        tid: tid,
        page: page,
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
          message: '帖子详情 HTML 解析失败: $error',
          raw: error,
        ),
      );
    }
  }

  Future<ThreadDetailData?> _parseCachedDocument({
    required DocumentCacheDescriptor descriptor,
    required SnapshotCacheDescriptor snapshotDescriptor,
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
      await _putSnapshot(descriptor: snapshotDescriptor, data: data);
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

  Future<ThreadDetailData?> _getFreshSnapshot(
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

  Future<void> _putSnapshot({
    required SnapshotCacheDescriptor descriptor,
    required ThreadDetailData data,
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
      // Snapshot 写入失败不应影响已经解析成功的页面数据。
    }
  }
}

/// 阅读页专用：HTML-first 渲染需要完整 DOM，走移动端 HTML 数据源。
final threadRepositoryProvider = Provider<ThreadRepository>((ref) {
  return ThreadDetailHtmlRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
    documentCacheService: ref.watch(documentCacheServiceProvider),
    snapshotCacheService: ref.watch(parsedSnapshotCacheServiceProvider),
    diagnosticRecorder: ref.watch(cacheDiagnosticRecorderProvider),
  );
});

/// 收藏同步 / 漫画发现专用：走 JSON viewthread，带 typeid 等结构化字段。
/// HTML 正文 == JSON message，但 JSON 更轻且无需复杂 DOM 解析。
/// 阅读页仍用 [threadRepositoryProvider]（HTML-first）。
final threadJsonRepositoryProvider = Provider<ThreadRepository>((ref) {
  return ApiThreadRepository(ref.watch(apiClientProvider));
});

final threadPostLocatorProvider = Provider<ThreadPostLocator>((ref) {
  return HtmlThreadPostLocator(gateway: ref.watch(yamiboHttpGatewayProvider));
});
