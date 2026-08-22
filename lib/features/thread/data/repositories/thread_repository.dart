import 'package:flutter/foundation.dart';
import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/cache/domain/services/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/thread/data/mappers/thread_detail_api_mapper.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';
import 'package:y300/features/thread/data/services/thread_detail_html_diagnostics.dart';
import 'package:y300/features/thread/data/services/thread_detail_html_parser.dart';
import 'package:y300/features/thread/data/services/thread_detail_snapshot_codec.dart';

class ApiThreadRepository implements ThreadRepository {
  ApiThreadRepository(
    this._apiClient, {
    this.apiVersion = '4',
    ThreadDetailApiMapper mapper = const ThreadDetailApiMapper(),
  }) : _mapper = mapper;

  final ApiClient _apiClient;
  final String apiVersion;
  final ThreadDetailApiMapper _mapper;

  @override
  ThreadDetailSourceCapabilities get capabilities => _apiCapabilities;

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    if (!query.isEmpty) {
      return unsupportedDataReadFailure(
        code: 'thread_detail_query_unsupported',
        diagnosticMessage:
            'The configured thread source cannot honor alternate-view parameters.',
      );
    }
    final result = await _apiClient.getParsed<ThreadDetailData>(
      module: 'viewthread',
      queryParameters: <String, dynamic>{
        'version': apiVersion,
        'tid': tid,
        'page': page,
      },
      parser: (response) =>
          _mapper.mapVariables(response.variables, page: page),
    );
    return switch (result) {
      ApiSuccess<ThreadDetailData>(:final data) => _validatedSuccess(
        data,
        requestedTid: tid,
        capabilities: capabilities.toReadCapabilities(),
      ),
      ApiFailure<ThreadDetailData>(:final error) => dataReadFailureFromApiError(
        error,
      ),
    };
  }
}

typedef ThreadDetailNativeDebugLog = void Function(String message);

class ThreadDetailHtmlRepository implements ThreadRepository {
  ThreadDetailHtmlRepository({
    required YamiboHtmlClient htmlClient,
    ThreadDetailHtmlParser parser = const ThreadDetailHtmlParser(),
    ThreadDetailHtmlDiagnostics htmlDiagnostics =
        const ThreadDetailHtmlDiagnostics(),
    DocumentCacheService? documentCacheService,
    ParsedSnapshotCacheService? snapshotCacheService,
    CacheKeyCanonicalizer cacheKeyCanonicalizer = const CacheKeyCanonicalizer(),
    ThreadDetailSnapshotCodec snapshotCodec = const ThreadDetailSnapshotCodec(),
    SnapshotCachePolicy snapshotPolicy = const SnapshotCachePolicy(
      freshFor: Duration(minutes: 5),
      keepStaleFor: Duration(days: 7),
    ),
    ThreadDetailNativeDebugLog? debugLog,
    DateTime Function()? now,
  }) : _htmlClient = htmlClient,
       _parser = parser,
       _htmlDiagnostics = htmlDiagnostics,
       _documentCacheService = documentCacheService,
       _snapshotCacheService = snapshotCacheService,
       _cacheKeyCanonicalizer = cacheKeyCanonicalizer,
       _snapshotCodec = snapshotCodec,
       _snapshotPolicy = snapshotPolicy,
       _debugLog = debugLog,
       _now = now ?? DateTime.now;

  final YamiboHtmlClient _htmlClient;
  final ThreadDetailHtmlParser _parser;
  final ThreadDetailHtmlDiagnostics _htmlDiagnostics;
  final DocumentCacheService? _documentCacheService;
  final ParsedSnapshotCacheService? _snapshotCacheService;
  final CacheKeyCanonicalizer _cacheKeyCanonicalizer;
  final ThreadDetailSnapshotCodec _snapshotCodec;
  final SnapshotCachePolicy _snapshotPolicy;
  final ThreadDetailNativeDebugLog? _debugLog;
  final DateTime Function() _now;

  @override
  ThreadDetailSourceCapabilities get capabilities => _htmlCapabilities;

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    final queryParameters = query.toRequestParameters();
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
      _logNative(
        'snapshot_hit',
        'tid=$tid page=$page query=${_formatQuery(queryParameters)} '
            '${_formatThreadData(snapshot)}',
      );
      return _validatedSuccess(
        snapshot,
        requestedTid: tid,
        capabilities: _htmlReadCapabilitiesFor(snapshot),
        metadata: const DataReadMetadata(
          origin: DataReadOrigin.freshSnapshot,
          freshness: DataReadFreshness.freshCache,
        ),
      );
    }
    _logNative(
      'load_start',
      'tid=$tid page=$page query=${_formatQuery(queryParameters)} '
          'snapshot=fresh-miss',
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
      _logNative(
        'html_failure',
        'tid=$tid page=$page type=${error.type.name} '
            'status=${error.statusCode ?? '-'} message=${_oneLine(error.message)}',
      );
      final cached = await _parseCachedDocument(
        descriptor: documentDescriptor,
        snapshotDescriptor: snapshotDescriptor,
        tid: tid,
        page: page,
      );
      if (cached != null) {
        _logNative(
          'cached_document_fallback_success',
          'tid=$tid page=$page ${_formatThreadData(cached)}',
        );
        return _validatedSuccess(
          cached,
          requestedTid: tid,
          capabilities: _htmlReadCapabilitiesFor(cached),
          metadata: const DataReadMetadata(
            origin: DataReadOrigin.cachedDocumentFallback,
            freshness: DataReadFreshness.staleOrUnknown,
          ),
        );
      }
      final failure =
          dataReadFailureFromApiError<
            ThreadDetailData,
            ThreadDetailReadCapabilities
          >(error);
      return DataReadFailure(
        kind: failure.kind,
        code: failure.code,
        statusCode: failure.statusCode,
        diagnosticMessage: '帖子详情 HTML 加载失败: ${error.message}',
      );
    }

    ThreadDetailHtmlDiagnosticSnapshot? htmlDiagnostic;
    try {
      final html = htmlResult.dataOrNull ?? '';
      htmlDiagnostic = _htmlDiagnostics.inspect(html);
      _logNative(
        'html_received',
        'tid=$tid page=$page query=${_formatQuery(queryParameters)} '
            '${htmlDiagnostic.toLogFields()}',
      );
      final data = _parser.parse(html, fallbackTid: tid, fallbackPage: page);
      _ensureRenderablePosts(data);
      _logNative(
        'parse_success',
        'tid=$tid page=$page ${_formatThreadData(data)}',
      );
      await _putDocument(descriptor: documentDescriptor, html: html);
      await _putSnapshot(descriptor: snapshotDescriptor, data: data);
      return _validatedSuccess(
        data,
        requestedTid: tid,
        capabilities: _htmlReadCapabilitiesFor(data),
      );
    } catch (error, stackTrace) {
      final diagnosticFields = htmlDiagnostic?.toLogFields() ?? 'no-html-probe';
      _logNative(
        'parse_failure',
        'tid=$tid page=$page error=${_oneLine(error.toString())} '
            '$diagnosticFields stack=${_stackHead(stackTrace)}',
      );
      return DataReadFailure(
        kind: DataReadFailureKind.parse,
        diagnosticMessage: '帖子详情 HTML 解析失败: $error；诊断: $diagnosticFields',
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
      _logNative(
        'cached_document_miss',
        'tid=$tid page=$page cacheKey=${descriptor.cacheKey}',
      );
      return null;
    }
    try {
      final diagnostic = _htmlDiagnostics.inspect(document.body);
      _logNative(
        'cached_document_hit',
        'tid=$tid page=$page cacheKey=${descriptor.cacheKey} '
            '${diagnostic.toLogFields()}',
      );
      final data = _parser.parse(
        document.body,
        fallbackTid: tid,
        fallbackPage: page,
      );
      if (!_hasRenderablePosts(data)) {
        _logNative(
          'cached_document_rejected',
          'tid=$tid page=$page reason=no-posts ${_formatThreadData(data)}',
        );
        return null;
      }
      await _safeTouchCachedDocument(cache, descriptor.cacheKey, _now());
      await _putSnapshot(descriptor: snapshotDescriptor, data: data);
      _logNative(
        'cached_document_parse_success',
        'tid=$tid page=$page ${_formatThreadData(data)}',
      );
      return data;
    } catch (error, stackTrace) {
      _logNative(
        'cached_document_parse_failure',
        'tid=$tid page=$page error=${_oneLine(error.toString())} '
            'stack=${_stackHead(stackTrace)}',
      );
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
      if (!_hasRenderablePosts(snapshot.value)) {
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
    if (!_hasRenderablePosts(data)) {
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

  bool _hasRenderablePosts(ThreadDetailData data) {
    return data.posts.isNotEmpty;
  }

  void _ensureRenderablePosts(ThreadDetailData data) {
    if (_hasRenderablePosts(data)) {
      return;
    }
    throw StateError('帖子详情 HTML 未解析到任何楼层');
  }

  void _logNative(String stage, String message) {
    final line = '[ThreadDetail][native][$stage] $message';
    final debugLog = _debugLog;
    if (debugLog != null) {
      debugLog(line);
      return;
    }
    if (kDebugMode) {
      debugPrint(line);
    }
  }

  String _formatThreadData(ThreadDetailData data) {
    final firstPost = data.posts.isEmpty ? null : data.posts.first;
    final emptyMessages = data.posts
        .where((post) => post.message.trim().isEmpty)
        .length;
    final attachmentImages = data.posts.fold<int>(
      0,
      (total, post) => total + post.attachmentImages.length,
    );
    return [
      'parsedTid=${data.tid}',
      'fid=${data.fid}',
      'typeid=${data.typeid}',
      'page=${data.currentPage}',
      'lastPage=${data.lastPage ?? '-'}',
      'subjectLength=${data.subject.length}',
      'posts=${data.posts.length}',
      'emptyMessages=$emptyMessages',
      'attachmentImages=$attachmentImages',
      if (firstPost != null) 'firstPid=${firstPost.pid}',
      if (firstPost != null) 'firstNo=${firstPost.number}',
      if (firstPost != null) 'firstMessageLength=${firstPost.message.length}',
      if (firstPost != null) 'firstAuthorId=${firstPost.authorId}',
    ].join(' ');
  }

  String _formatQuery(Map<String, String> queryParameters) {
    if (queryParameters.isEmpty) {
      return '-';
    }
    return queryParameters.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
  }

  String _oneLine(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _stackHead(StackTrace stackTrace) {
    final text = stackTrace.toString().trim();
    if (text.isEmpty) {
      return '-';
    }
    return _oneLine(text.split('\n').first);
  }
}

ThreadDetailReadCapabilities _htmlReadCapabilitiesFor(ThreadDetailData data) {
  final hasExactPagination = data.lastPage != null && data.lastPage! > 0;
  return ThreadDetailReadCapabilities(
    values: _htmlCapabilities.values.withSupport(
      ThreadDetailCapability.exactPagination,
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

DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>
_validatedSuccess(
  ThreadDetailData data, {
  required String requestedTid,
  required ThreadDetailReadCapabilities capabilities,
  DataReadMetadata metadata = const DataReadMetadata.network(),
}) {
  final normalizedRequestedTid = requestedTid.trim();
  final normalizedTid = data.tid.trim();
  final postIds = <String>{};
  final valid =
      normalizedTid.isNotEmpty &&
      normalizedRequestedTid.isNotEmpty &&
      normalizedTid == normalizedRequestedTid &&
      data.posts.isNotEmpty &&
      data.posts.every((post) {
        final pid = post.pid.trim();
        return pid.isNotEmpty && postIds.add(pid);
      });
  if (!valid) {
    return const DataReadFailure(
      kind: DataReadFailureKind.parse,
      code: 'thread_detail_identity_invalid',
      diagnosticMessage:
          'Thread data did not provide stable identity and unique renderable posts.',
    );
  }
  return DataReadSuccess(
    data: data,
    capabilities: capabilities,
    metadata: metadata,
  );
}

final _htmlCapabilities = ThreadDetailSourceCapabilities(
  values: DataCapabilitySet<ThreadDetailCapability>.from(
    supported: ThreadDetailCapability.values
        .where(
          (capability) =>
              capability != ThreadDetailCapability.attachmentMetadata,
        )
        .toList(growable: false),
    unsupported: const <ThreadDetailCapability>[
      ThreadDetailCapability.attachmentMetadata,
    ],
  ),
  paginationPrecision: PaginationPrecision.exact,
);

final _apiCapabilities = ThreadDetailSourceCapabilities(
  values: DataCapabilitySet<ThreadDetailCapability>.from(
    supported: const <ThreadDetailCapability>[
      ThreadDetailCapability.threadIdentity,
      ThreadDetailCapability.forumIdentity,
      ThreadDetailCapability.orderedPosts,
      ThreadDetailCapability.firstPostIdentity,
      ThreadDetailCapability.renderableBody,
      ThreadDetailCapability.avatars,
      ThreadDetailCapability.attachmentMetadata,
      ThreadDetailCapability.directionalPagination,
    ],
    unsupported: const <ThreadDetailCapability>[
      ThreadDetailCapability.forumPresentation,
      ThreadDetailCapability.losslessBody,
      ThreadDetailCapability.exactPagination,
      ThreadDetailCapability.alternateViews,
      ThreadDetailCapability.threadNavigation,
      ThreadDetailCapability.replyAction,
      ThreadDetailCapability.editAction,
      ThreadDetailCapability.ratingSummary,
      ThreadDetailCapability.ratingAction,
      ThreadDetailCapability.comments,
      ThreadDetailCapability.commentAction,
      ThreadDetailCapability.pollContent,
      ThreadDetailCapability.pollVoteAction,
      ThreadDetailCapability.tagLinks,
      ThreadDetailCapability.favoriteEntry,
    ],
  ),
  paginationPrecision: PaginationPrecision.directional,
);
