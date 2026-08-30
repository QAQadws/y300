import '../cache/forum_cache.dart';
import '../cache/forum_cache_key_canonicalizer.dart';
import '../client/forum_client_config.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/thread_detail_models.dart';
import '../contracts/thread_repository.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import 'discuz_api_client.dart';
import 'thread_detail_api_mapper.dart';
import 'thread_detail_html_parser.dart';
import 'thread_detail_snapshot_codec.dart';

final class ApiThreadRepository implements ThreadRepository {
  const ApiThreadRepository(
    this._api, {
    this.apiVersion = '4',
    this._mapper = const ThreadDetailApiMapper(),
  });

  final DiscuzApiClient _api;
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
      return const DataReadFailure(
        kind: DataReadFailureKind.unsupported,
        code: 'thread_detail_query_unsupported',
        diagnosticMessage: 'thread_detail_query_unsupported',
      );
    }
    final result = await _api.get(
      module: 'viewthread',
      queryParameters: <String, Object?>{
        'version': apiVersion,
        'tid': tid,
        'page': page,
      },
    );
    if (result case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return DataReadFailure(
        kind: toReadFailureKind(failure.kind),
        code: failure.code,
        statusCode: failure.statusCode,
        diagnosticMessage: failure.code,
      );
    }
    try {
      final data = _mapper.mapVariables(
        (result as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
            .response
            .body
            .variables,
        page: page,
      );
      return _validated(
        data,
        requestedTid: tid,
        capabilities: capabilities.toReadCapabilities(),
      );
    } on FormatException {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'thread_detail_api_parse_failed',
        diagnosticMessage: 'thread_detail_api_parse_failed',
      );
    }
  }
}

final class ThreadDetailHtmlRepository implements ThreadRepository {
  ThreadDetailHtmlRepository({
    required ForumClientConfig config,
    required this.network,
    required this.requestProfiles,
    this._documentStore,
    this._snapshotStore,
    ThreadDetailHtmlParser? parser,
    ForumCacheKeyCanonicalizer? cacheKeys,
    this._snapshotCodec = const ThreadDetailSnapshotCodec(),
    this._snapshotPolicy = const ForumSnapshotPolicy(
      freshFor: Duration(minutes: 5),
      keepStaleFor: Duration(days: 7),
    ),
    DateTime Function()? now,
  }) : _config = config,
       _parser =
           parser ?? ThreadDetailHtmlParser(siteOrigin: config.siteOrigin),
       _cacheKeys =
           cacheKeys ??
           ForumCacheKeyCanonicalizer(siteOrigin: config.siteOrigin),
       _now = now ?? DateTime.now;

  final ForumClientConfig _config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
  final ForumDocumentStore? _documentStore;
  final ForumSnapshotStore? _snapshotStore;
  final ThreadDetailHtmlParser _parser;
  final ForumCacheKeyCanonicalizer _cacheKeys;
  final ThreadDetailSnapshotCodec _snapshotCodec;
  final ForumSnapshotPolicy _snapshotPolicy;
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
    final documentDescriptor = _cacheKeys.threadDetail(
      tid: tid,
      page: page,
      queryParameters: queryParameters,
    );
    final snapshotDescriptor = _cacheKeys.threadDetailSnapshot(
      tid: tid,
      page: page,
      queryParameters: queryParameters,
    );
    final snapshot = await _freshSnapshot(snapshotDescriptor);
    if (snapshot != null) {
      return _validated(
        snapshot,
        requestedTid: tid,
        capabilities: _htmlReadCapabilities(snapshot),
        metadata: const DataReadMetadata(
          origin: DataReadOrigin.freshSnapshot,
          freshness: DataReadFreshness.freshCache,
        ),
      );
    }
    final parameters = <String, String>{
      ...queryParameters,
      'mod': 'viewthread',
      'tid': tid,
      'page': '$page',
      'mobile': '2',
    };
    final uri = _config.siteOrigin.replace(
      path: '/forum.php',
      queryParameters: parameters,
    );
    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'thread.detail.html',
          pageKind: 'thread.detail',
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.mobileHtml)
            .headers,
      ),
    );
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      final cached = await _cachedDocument(
        descriptor: documentDescriptor,
        snapshotDescriptor: snapshotDescriptor,
        tid: tid,
        page: page,
      );
      if (cached != null) {
        return _validated(
          cached,
          requestedTid: tid,
          capabilities: _htmlReadCapabilities(cached),
          metadata: const DataReadMetadata(
            origin: DataReadOrigin.cachedDocumentFallback,
            freshness: DataReadFreshness.staleOrUnknown,
          ),
        );
      }
      return DataReadFailure(
        kind: toReadFailureKind(failure.kind),
        code: failure.code,
        statusCode: failure.statusCode,
        diagnosticMessage: failure.code,
      );
    }
    final body =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response.body;
    if (body is! String) return _parseFailure('thread_detail_text_expected');
    try {
      final data = _parser.parse(body, fallbackTid: tid, fallbackPage: page);
      if (data.posts.isEmpty) {
        return _parseFailure('thread_detail_posts_missing');
      }
      await _putDocument(documentDescriptor, body);
      await _putSnapshot(snapshotDescriptor, data);
      return _validated(
        data,
        requestedTid: tid,
        capabilities: _htmlReadCapabilities(data),
      );
    } on FormatException {
      return _parseFailure('thread_detail_parse_failed');
    }
  }

  Future<ThreadDetailData?> _cachedDocument({
    required ForumDocumentDescriptor descriptor,
    required ForumSnapshotDescriptor snapshotDescriptor,
    required String tid,
    required int page,
  }) async {
    final store = _documentStore;
    if (store == null) return null;
    ForumCachedDocument? document;
    try {
      document = await store.get(descriptor);
    } catch (_) {
      return null;
    }
    if (document == null) return null;
    try {
      final data = _parser.parse(
        document.body,
        fallbackTid: tid,
        fallbackPage: page,
      );
      if (data.posts.isEmpty) return null;
      await _safeTouch(descriptor);
      await _putSnapshot(snapshotDescriptor, data);
      return data;
    } on FormatException {
      return null;
    }
  }

  Future<ThreadDetailData?> _freshSnapshot(
    ForumSnapshotDescriptor descriptor,
  ) async {
    final store = _snapshotStore;
    if (store == null) return null;
    try {
      final value = await store.get(descriptor, _snapshotCodec);
      return value != null &&
              value.isFresh(_now()) &&
              value.value.posts.isNotEmpty
          ? value.value
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _putDocument(
    ForumDocumentDescriptor descriptor,
    String body,
  ) async {
    final store = _documentStore;
    if (store == null) return;
    final now = _now();
    try {
      await store.put(
        ForumCachedDocument(
          descriptor: descriptor,
          body: body,
          contentType: 'text/html',
          statusCode: 200,
          fetchedAt: now,
          updatedAt: now,
          lastAccessedAt: now,
        ),
      );
    } catch (_) {
      // A successful page remains usable when cache persistence fails.
    }
  }

  Future<void> _putSnapshot(
    ForumSnapshotDescriptor descriptor,
    ThreadDetailData data,
  ) async {
    if (data.posts.isEmpty) return;
    try {
      await _snapshotStore?.put(
        descriptor,
        data,
        _snapshotCodec,
        policy: _snapshotPolicy,
      );
    } catch (_) {
      // Snapshot persistence is best effort.
    }
  }

  Future<void> _safeTouch(ForumDocumentDescriptor descriptor) async {
    try {
      await _documentStore?.touch(descriptor, _now());
    } catch (_) {
      return;
    }
  }

  DataReadFailure<ThreadDetailData, ThreadDetailReadCapabilities> _parseFailure(
    String code,
  ) => DataReadFailure(
    kind: DataReadFailureKind.parse,
    code: code,
    diagnosticMessage: code,
  );
}

ThreadDetailReadCapabilities _htmlReadCapabilities(ThreadDetailData data) {
  final exact = data.lastPage != null && data.lastPage! > 0;
  return ThreadDetailReadCapabilities(
    values: _htmlCapabilities.values.withSupport(
      ThreadDetailCapability.exactPagination,
      exact
          ? DataCapabilitySupport.supported
          : DataCapabilitySupport.unsupported,
    ),
    paginationPrecision: exact
        ? PaginationPrecision.exact
        : data.previousPageUrl != null || data.nextPageUrl != null
        ? PaginationPrecision.directional
        : PaginationPrecision.heuristic,
  );
}

DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities> _validated(
  ThreadDetailData data, {
  required String requestedTid,
  required ThreadDetailReadCapabilities capabilities,
  DataReadMetadata metadata = const DataReadMetadata.network(),
}) {
  final ids = <String>{};
  final valid =
      requestedTid.trim().isNotEmpty &&
      data.tid.trim() == requestedTid.trim() &&
      data.posts.isNotEmpty &&
      data.posts.every((post) {
        final id = post.pid.trim();
        return id.isNotEmpty && ids.add(id);
      });
  if (!valid) {
    return const DataReadFailure(
      kind: DataReadFailureKind.parse,
      code: 'thread_detail_identity_invalid',
      diagnosticMessage: 'thread_detail_identity_invalid',
    );
  }
  return DataReadSuccess(
    data: data,
    capabilities: capabilities,
    metadata: metadata,
  );
}

final _htmlCapabilities = ThreadDetailSourceCapabilities(
  values: DataCapabilitySet.from(
    supported: ThreadDetailCapability.values
        .where(
          (value) =>
              value != ThreadDetailCapability.attachmentMetadata &&
              value != ThreadDetailCapability.pollVoteAction,
        )
        .toList(growable: false),
    unsupported: const [
      ThreadDetailCapability.attachmentMetadata,
      ThreadDetailCapability.pollVoteAction,
    ],
  ),
  paginationPrecision: PaginationPrecision.exact,
);

final _apiCapabilities = ThreadDetailSourceCapabilities(
  values: DataCapabilitySet.from(
    supported: const [
      ThreadDetailCapability.threadIdentity,
      ThreadDetailCapability.forumIdentity,
      ThreadDetailCapability.orderedPosts,
      ThreadDetailCapability.firstPostIdentity,
      ThreadDetailCapability.renderableBody,
      ThreadDetailCapability.avatars,
      ThreadDetailCapability.attachmentMetadata,
      ThreadDetailCapability.directionalPagination,
    ],
    unsupported: const [
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
