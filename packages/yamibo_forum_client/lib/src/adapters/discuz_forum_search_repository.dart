import '../client/forum_client_config.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/forum_search.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_formhash_provider.dart';
import '../url/forum_uri_resolver.dart';
import 'discuz_search_html_parser.dart';

final class DiscuzForumSearchRepository implements ForumSearchRepository {
  DiscuzForumSearchRepository({
    required ForumClientConfig config,
    required this.network,
    required this.requestProfiles,
    required this.formhashProvider,
    DiscuzSearchHtmlParser? parser,
  }) : _config = config,
       _resolver = ForumUriResolver(siteOrigin: config.siteOrigin),
       _parser =
           parser ?? DiscuzSearchHtmlParser(siteOrigin: config.siteOrigin);

  final ForumClientConfig _config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
  final ForumFormhashProvider formhashProvider;
  final ForumUriResolver _resolver;
  final DiscuzSearchHtmlParser _parser;
  final Map<String, _Continuation> _continuations = <String, _Continuation>{};
  String? _cachedFormhash;
  int _nextToken = 0;

  ForumSearchSourceCapabilities get capabilities => _searchCapabilities;

  @override
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>> load(
    ForumSearchQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final normalized = _normalize(query);
    if (normalized == null) return _invalidQuery();
    final formhash = await _loadFormhash();
    if (formhash case DataReadFailure<String, Object?> failure) {
      return failure.retype();
    }
    final entryUri = _entryUri(normalized);
    final submit = await network.send(
      ForumRequest(
        method: ForumRequestMethod.post,
        uri: _submitUri(normalized),
        context: const ForumRequestContext(
          operation: 'search.forum.submit',
          pageKind: 'search',
        ),
        headers: <String, String>{
          ...requestProfiles
              .resolve(ForumRequestProfileKind.mobileHtml)
              .headers,
          'referer': entryUri.toString(),
        },
        body: <String, String>{
          'srchtxt': normalized.normalizedKeyword,
          'formhash': (formhash as DataReadSuccess<String, Object?>).data,
          if (normalized.normalizedForumId case final String fid) 'srhfid': fid,
        },
        followRedirects: false,
      ),
    );
    if (submit case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _failure(failure, 'forum_search_submit_failed');
    }
    final response =
        (submit as ForumTransportSuccess<ForumResponse<Object?>>).response;
    final body = response.body;
    if (body is! String) return _parseFailure('forum_search_submit_invalid');
    final location = _firstHeader(response.headers, 'location');
    if (_loginLocation(location) || _loginHtml(body)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'forum_search_unauthorized',
        diagnosticMessage: 'forum_search_unauthorized',
      );
    }
    final resultUri = _resolveSearchUri(location);
    if (resultUri == null) {
      return _parseFailure('forum_search_context_missing');
    }
    final searchIds = resultUri.queryParametersAll['searchid'] ?? const [];
    final searchId = searchIds.length == 1 ? searchIds.single.trim() : '';
    final pages = resultUri.queryParametersAll['page'] ?? const [];
    final page = pages.isEmpty
        ? 1
        : pages.length == 1
        ? int.tryParse(pages.single.trim())
        : null;
    if (searchId.isEmpty ||
        page != 1 ||
        !_matchesScope(resultUri, normalized)) {
      return _parseFailure('forum_search_context_invalid');
    }
    return _loadPage(
      uri: resultUri,
      query: normalized,
      page: 1,
      searchId: searchId,
      referer: entryUri,
      operation: 'search.forum.result',
    );
  }

  @override
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>>
  loadNextPage(
    ForumSearchQuery query,
    ForumSearchPageIdentity page, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final normalized = _normalize(query);
    final continuation = _continuations[page.token];
    if (normalized == null ||
        page.token.trim().isEmpty ||
        page.page < 2 ||
        continuation == null ||
        continuation.page != page.page ||
        continuation.queryFingerprint != _fingerprint(normalized)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'forum_search_continuation_expired',
        diagnosticMessage: 'forum_search_continuation_expired',
      );
    }
    return _loadPage(
      uri: continuation.uri,
      query: normalized,
      page: continuation.page,
      searchId: continuation.searchId,
      referer: _entryUri(normalized),
      operation: 'search.forum.nextPage',
    );
  }

  Future<DataReadResult<String, Object?>> _loadFormhash() async {
    final cached = _cachedFormhash;
    if (cached != null && cached.isNotEmpty) {
      return DataReadSuccess(
        data: cached,
        capabilities: null,
        metadata: const DataReadMetadata.network(),
      );
    }
    final result = await formhashProvider.loadFormhash(preferProfile: true);
    if (result case ForumFormhashError(:final failure)) {
      return DataReadFailure(
        kind: toReadFailureKind(failure.kind),
        code: 'forum_search_formhash_failed',
        statusCode: failure.statusCode,
        diagnosticMessage: 'forum_search_formhash_failed',
      );
    }
    final value = (result as ForumFormhashSuccess).value.trim();
    if (value.isEmpty) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'forum_search_formhash_empty',
        diagnosticMessage: 'forum_search_formhash_empty',
      );
    }
    _cachedFormhash = value;
    return DataReadSuccess(
      data: value,
      capabilities: null,
      metadata: const DataReadMetadata.network(),
    );
  }

  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>>
  _loadPage({
    required Uri uri,
    required ForumSearchQuery query,
    required int page,
    required String searchId,
    required Uri referer,
    required String operation,
  }) async {
    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: ForumRequestContext(operation: operation, pageKind: 'search'),
        headers: <String, String>{
          ...requestProfiles
              .resolve(ForumRequestProfileKind.mobileHtml)
              .headers,
          'referer': referer.toString(),
        },
      ),
    );
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _failure(failure, 'forum_search_result_failed');
    }
    final body =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response.body;
    if (body is! String) return _parseFailure('forum_search_response_invalid');
    try {
      final parsed = _parser.parse(
        html: body,
        pageUri: uri,
        query: query,
        requestedPage: page,
        expectedSearchContextId: searchId,
      );
      if (parsed.searchContextId != searchId || parsed.currentPage != page) {
        return _parseFailure('forum_search_result_identity_mismatch');
      }
      final next = parsed.nextPageUri == null
          ? null
          : _register(
              query: query,
              searchId: searchId,
              uri: parsed.nextPageUri!,
              page: _pageFrom(parsed.nextPageUri!),
            );
      final data = ForumSearchData(
        query: query,
        topics: parsed.topics,
        pagination: ForumSearchPagination(
          currentPage: page,
          nextPage: next,
          precision: next == null
              ? PaginationPrecision.unknown
              : PaginationPrecision.directional,
        ),
      );
      return DataReadSuccess(
        data: data,
        capabilities: _readCapabilities(data),
        metadata: const DataReadMetadata.network(),
      );
    } on DiscuzSearchUnauthorizedException {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'forum_search_unauthorized',
        diagnosticMessage: 'forum_search_unauthorized',
      );
    } on DiscuzSearchHtmlParseException catch (error) {
      return _parseFailure(error.code);
    } on FormatException {
      return _parseFailure('forum_search_parse_failed');
    }
  }

  ForumSearchPageIdentity _register({
    required ForumSearchQuery query,
    required String searchId,
    required Uri uri,
    required int page,
  }) {
    final token = 'search-${_nextToken++}';
    _continuations[token] = _Continuation(
      queryFingerprint: _fingerprint(query),
      searchId: searchId,
      uri: uri,
      page: page,
    );
    while (_continuations.length > 128) {
      _continuations.remove(_continuations.keys.first);
    }
    return ForumSearchPageIdentity(token: token, page: page);
  }

  ForumSearchQuery? _normalize(ForumSearchQuery query) {
    final value = query.normalized();
    if (value.normalizedKeyword.isEmpty ||
        (value.scope == ForumSearchScope.allForums &&
            value.normalizedForumId != null) ||
        (value.scope == ForumSearchScope.currentForum &&
            !_positive(value.normalizedForumId ?? ''))) {
      return null;
    }
    return value;
  }

  Uri _submitUri(ForumSearchQuery query) => _searchUri(query).replace(
    queryParameters: <String, String>{
      ..._searchUri(query).queryParameters,
      'searchsubmit': 'yes',
    },
  );

  Uri _entryUri(ForumSearchQuery query) => _searchUri(query);

  Uri _searchUri(ForumSearchQuery query) => _config.siteOrigin.replace(
    path: '/search.php',
    queryParameters: <String, String>{
      'mod': query.scope == ForumSearchScope.allForums ? 'forum' : 'curforum',
      if (query.normalizedForumId case final String fid) 'srhfid': fid,
      'mobile': '2',
    },
  );

  Uri? _resolveSearchUri(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    try {
      final uri = _resolver.resolve(value);
      return _resolver.isSameSite(uri) &&
              uri.path.toLowerCase() == '/search.php'
          ? uri
          : null;
    } on FormatException {
      return null;
    }
  }

  bool _matchesScope(Uri uri, ForumSearchQuery query) {
    final mods = uri.queryParametersAll['mod'] ?? const [];
    final forumIds = uri.queryParametersAll['srhfid'] ?? const [];
    if (mods.length != 1 || forumIds.length > 1) return false;
    return switch (query.scope) {
      ForumSearchScope.allForums => mods.single == 'forum' && forumIds.isEmpty,
      ForumSearchScope.currentForum =>
        mods.single == 'curforum' &&
            forumIds.length == 1 &&
            forumIds.single == query.normalizedForumId,
    };
  }

  ForumSearchReadCapabilities _readCapabilities(ForumSearchData data) {
    final topics = data.topics;
    DataCapabilitySupport complete(
      bool Function(ForumSearchTopicSummary) predicate,
    ) => topics.isNotEmpty && topics.every(predicate)
        ? DataCapabilitySupport.supported
        : DataCapabilitySupport.unsupported;
    final values =
        DataCapabilitySet<ForumSearchCapability>.from(
              supported: const [
                ForumSearchCapability.stableTopicIdentity,
                ForumSearchCapability.orderedTopics,
                ForumSearchCapability.topicTitle,
              ],
            )
            .withSupport(
              ForumSearchCapability.topicForum,
              complete((t) => t.forumId != null && t.forumName != null),
            )
            .withSupport(
              ForumSearchCapability.topicAuthor,
              complete((t) => t.authorName != null),
            )
            .withSupport(
              ForumSearchCapability.topicPublishedAt,
              complete((t) => t.publishedAtText != null),
            )
            .withSupport(
              ForumSearchCapability.directionalPagination,
              data.pagination.nextPage == null
                  ? DataCapabilitySupport.unsupported
                  : DataCapabilitySupport.supported,
            )
            .withSupport(
              ForumSearchCapability.searchContinuation,
              data.pagination.nextPage == null
                  ? DataCapabilitySupport.unsupported
                  : DataCapabilitySupport.supported,
            );
    return ForumSearchReadCapabilities(
      values: values,
      paginationPrecision: data.pagination.precision,
    );
  }

  DataReadFailure<ForumSearchData, ForumSearchReadCapabilities> _failure(
    ForumTransportFailure failure,
    String code,
  ) => DataReadFailure(
    kind: toReadFailureKind(failure.kind),
    code: code,
    statusCode: failure.statusCode,
    diagnosticMessage: code,
  );

  DataReadFailure<ForumSearchData, ForumSearchReadCapabilities> _parseFailure(
    String code,
  ) => DataReadFailure(
    kind: DataReadFailureKind.parse,
    code: code,
    diagnosticMessage: code,
  );

  DataReadFailure<ForumSearchData, ForumSearchReadCapabilities>
  _invalidQuery() => const DataReadFailure(
    kind: DataReadFailureKind.business,
    code: 'forum_search_query_invalid',
    diagnosticMessage: 'forum_search_query_invalid',
  );

  String _fingerprint(ForumSearchQuery query) =>
      '${query.scope.name}|${query.normalizedForumId ?? ''}|${query.normalizedKeyword}';
  int _pageFrom(Uri uri) =>
      int.tryParse(uri.queryParameters['page'] ?? '') ?? 0;
  bool _positive(String value) => (int.tryParse(value) ?? 0) > 0;
  String? _firstHeader(Map<String, List<String>> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase() &&
          entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }

  bool _loginLocation(String? raw) {
    final uri = Uri.tryParse(raw?.trim() ?? '');
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    return (path.endsWith('/member.php') &&
            uri.queryParameters['mod']?.toLowerCase() == 'logging') ||
        path.endsWith('/login.php');
  }

  bool _loginHtml(String html) => RegExp(
    r'''<input[^>]+name=["']password["']|id=["']lsform["']|class=["'][^"']*loginbox''',
    caseSensitive: false,
  ).hasMatch(html);
}

final class _Continuation {
  const _Continuation({
    required this.queryFingerprint,
    required this.searchId,
    required this.uri,
    required this.page,
  });
  final String queryFingerprint;
  final String searchId;
  final Uri uri;
  final int page;
}

final _searchCapabilities = ForumSearchSourceCapabilities(
  values: DataCapabilitySet.supported(ForumSearchCapability.values),
  paginationPrecision: PaginationPrecision.directional,
);
