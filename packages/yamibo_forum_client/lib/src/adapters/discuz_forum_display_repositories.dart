// ignore_for_file: public_member_api_docs

import '../cache/forum_cache.dart';
import '../cache/forum_cache_key_canonicalizer.dart';
import '../client/forum_client_config.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/forum_display_models.dart';
import '../contracts/forum_display_repository.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_session_store.dart';
import 'discuz_api_client.dart';
import 'forum_display_api_mapper.dart';
import 'forum_display_html_parser.dart';
import 'forum_display_snapshot_codec.dart';

final class ForumDisplayHtmlRepository implements ForumDisplayRepository {
  ForumDisplayHtmlRepository({
    required ForumClientConfig config,
    required this.network,
    required this.requestProfiles,
    this._sessionStore,
    this._documentStore,
    this._snapshotStore,
    ForumDisplayHtmlParser? parser,
    ForumCacheKeyCanonicalizer? cacheKeys,
    this._snapshotCodec = const ForumDisplaySnapshotCodec(),
    this._snapshotPolicy = const ForumSnapshotPolicy(
      freshFor: Duration(minutes: 3),
      keepStaleFor: Duration(hours: 12),
    ),
    DateTime Function()? now,
  }) : _config = config,
       _parser =
           parser ?? ForumDisplayHtmlParser(siteOrigin: config.siteOrigin),
       _cacheKeys =
           cacheKeys ??
           ForumCacheKeyCanonicalizer(siteOrigin: config.siteOrigin),
       _now = now ?? DateTime.now;

  final ForumClientConfig _config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
  final ForumSessionStore? _sessionStore;
  final ForumDocumentStore? _documentStore;
  final ForumSnapshotStore? _snapshotStore;
  final ForumDisplayHtmlParser _parser;
  final ForumCacheKeyCanonicalizer _cacheKeys;
  final ForumDisplaySnapshotCodec _snapshotCodec;
  final ForumSnapshotPolicy _snapshotPolicy;
  final DateTime Function() _now;

  @override
  ForumDisplaySourceCapabilities get capabilities => _htmlCapabilities;

  @override
  Future<DataReadResult<ForumDisplayData, ForumDisplayReadCapabilities>>
  getForumDisplayByQuery(
    ForumDisplayQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final parameters = query.toRequestParameters();
    final profile = _profile();
    final documentDescriptor = _cacheKeys.forumDisplay(
      fid: query.fid,
      page: query.page,
      queryParameters: parameters,
      requestProfile: profile,
    );
    final snapshotDescriptor = _cacheKeys.forumDisplaySnapshot(
      fid: query.fid,
      page: query.page,
      queryParameters: parameters,
      requestProfile: profile,
    );
    if (cachePolicy == CacheLoadPolicy.cacheFirst) {
      final snapshot = await _freshSnapshot(snapshotDescriptor);
      if (snapshot != null) {
        return _validated(
          requestedFid: query.fid,
          data: snapshot,
          capabilities: _htmlReadCapabilities(snapshot),
          metadata: const DataReadMetadata(
            origin: DataReadOrigin.freshSnapshot,
            freshness: DataReadFreshness.freshCache,
          ),
        );
      }
    }
    final uri = _config.siteOrigin.replace(
      path: '/forum.php',
      queryParameters: parameters,
    );
    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'forum.display.html',
          pageKind: 'forum.display',
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
        documentDescriptor: documentDescriptor,
        snapshotDescriptor: snapshotDescriptor,
        query: query,
      );
      if (cached != null) {
        return _validated(
          requestedFid: query.fid,
          data: cached,
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
    if (body is! String) return _parseFailure('forum_display_text_expected');
    try {
      final data = _parser.parse(
        body,
        fallbackFid: query.fid,
        fallbackPage: query.page,
      );
      await _putDocument(documentDescriptor, body);
      await _putSnapshot(snapshotDescriptor, data);
      return _validated(
        requestedFid: query.fid,
        data: data,
        capabilities: _htmlReadCapabilities(data),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return _parseFailure('forum_display_parse_failed');
    }
  }

  ForumDocumentRequestProfile _profile() =>
      _sessionStore?.readCurrent()?.isLoggedIn == true
      ? ForumDocumentRequestProfile.loggedIn
      : ForumDocumentRequestProfile.anonymous;

  Future<ForumDisplayData?> _cachedDocument({
    required ForumDocumentDescriptor documentDescriptor,
    required ForumSnapshotDescriptor snapshotDescriptor,
    required ForumDisplayQuery query,
  }) async {
    final store = _documentStore;
    if (store == null) return null;
    ForumCachedDocument? document;
    try {
      document = await store.get(documentDescriptor);
    } catch (_) {
      return null;
    }
    if (document == null) return null;
    try {
      final data = _parser.parse(
        document.body,
        fallbackFid: query.fid,
        fallbackPage: query.page,
      );
      await _safeTouchDocument(documentDescriptor);
      await _putSnapshot(snapshotDescriptor, data);
      return data;
    } on FormatException {
      return null;
    }
  }

  Future<ForumDisplayData?> _freshSnapshot(
    ForumSnapshotDescriptor descriptor,
  ) async {
    final store = _snapshotStore;
    if (store == null) return null;
    try {
      final value = await store.get(descriptor, _snapshotCodec);
      return value != null && value.isFresh(_now()) ? value.value : null;
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
      // Cache writes are best effort and must not hide valid network data.
    }
  }

  Future<void> _putSnapshot(
    ForumSnapshotDescriptor descriptor,
    ForumDisplayData data,
  ) async {
    try {
      await _snapshotStore?.put(
        descriptor,
        data,
        _snapshotCodec,
        policy: _snapshotPolicy,
      );
    } catch (_) {
      // Snapshot writes are best effort.
    }
  }

  Future<void> _safeTouchDocument(ForumDocumentDescriptor descriptor) async {
    try {
      await _documentStore?.touch(descriptor, _now());
    } catch (_) {
      return;
    }
  }

  DataReadFailure<ForumDisplayData, ForumDisplayReadCapabilities> _parseFailure(
    String code,
  ) => DataReadFailure(
    kind: DataReadFailureKind.parse,
    code: code,
    diagnosticMessage: code,
  );
}

final class DiscuzForumDisplayRepository implements ForumDisplayRepository {
  const DiscuzForumDisplayRepository(
    this._api, {
    this._mapper = const ForumDisplayApiMapper(),
  });

  final DiscuzApiClient _api;
  final ForumDisplayApiMapper _mapper;

  @override
  ForumDisplaySourceCapabilities get capabilities => _apiCapabilities;

  @override
  Future<DataReadResult<ForumDisplayData, ForumDisplayReadCapabilities>>
  getForumDisplayByQuery(
    ForumDisplayQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    if (query.parameters.keys.any((key) => key != 'fid' && key != 'page')) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unsupported,
        code: 'forum_display_query_unsupported',
        diagnosticMessage: 'forum_display_query_unsupported',
      );
    }
    final result = await _api.get(
      module: 'forumdisplay',
      queryParameters: <String, Object?>{'fid': query.fid, 'page': query.page},
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
        page: query.page,
      );
      return _validated(
        requestedFid: query.fid,
        data: data,
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_display_api_parse_failed',
        diagnosticMessage: 'forum_display_api_parse_failed',
      );
    }
  }
}

ForumDisplayReadCapabilities _htmlReadCapabilities(ForumDisplayData data) {
  final exact = data.lastPage != null && data.lastPage! > 0;
  return ForumDisplayReadCapabilities(
    values: _htmlCapabilities.values.withSupport(
      ForumDisplayCapability.exactPagination,
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

DataReadResult<ForumDisplayData, ForumDisplayReadCapabilities> _validated({
  required String requestedFid,
  required ForumDisplayData data,
  required ForumDisplayReadCapabilities capabilities,
  required DataReadMetadata metadata,
}) {
  final fid = requestedFid.trim();
  if (fid.isEmpty || data.fid.trim() != fid) {
    return const DataReadFailure(
      kind: DataReadFailureKind.parse,
      code: 'forum_display_identity_mismatch',
      diagnosticMessage: 'forum_display_identity_mismatch',
    );
  }
  final ids = <String>{};
  for (final thread in data.threads) {
    if (thread.tid.trim().isEmpty || !ids.add(thread.tid.trim())) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_display_thread_identity_invalid',
        diagnosticMessage: 'forum_display_thread_identity_invalid',
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
  values: DataCapabilitySet.supported(ForumDisplayCapability.values),
  paginationPrecision: PaginationPrecision.exact,
);

final _apiCapabilities = ForumDisplaySourceCapabilities(
  values: DataCapabilitySet.from(
    supported: const [
      ForumDisplayCapability.forumIdentity,
      ForumDisplayCapability.orderedThreadSummaries,
      ForumDisplayCapability.directionalPagination,
    ],
    unsupported: const [
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
