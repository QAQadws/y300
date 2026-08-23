import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_http_response.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/auth/data/providers/auth_formhash_provider.dart';
import 'package:y300/features/auth/domain/services/formhash_provider.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/search/data/services/discuz_search_html_parser.dart';
import 'package:y300/features/search/domain/models/forum_search_models.dart';
import 'package:y300/features/search/domain/repositories/forum_search_repository.dart';

final class DiscuzForumSearchRepository implements ForumSearchRepository {
  DiscuzForumSearchRepository({
    required FormhashProvider formhashProvider,
    required YamiboHttpGateway gateway,
    DiscuzSearchHtmlParser parser = const DiscuzSearchHtmlParser(),
  }) : _formhashProvider = formhashProvider,
       _gateway = gateway,
       _parser = parser;

  final FormhashProvider _formhashProvider;
  final YamiboHttpGateway _gateway;
  final DiscuzSearchHtmlParser _parser;
  final Map<String, _ContinuationEntry> _continuations =
      <String, _ContinuationEntry>{};
  String? _cachedFormhash;
  int _nextToken = 0;

  ForumSearchSourceCapabilities get capabilities => _htmlCapabilities;

  @override
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>> load(
    ForumSearchQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final normalized = _normalizeAndValidateQuery(query);
    if (normalized == null) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'forum_search_query_invalid',
        diagnosticMessage: 'Forum search query is invalid.',
      );
    }

    final formhashResult = await _loadFormhash();
    if (formhashResult case DataReadFailure<String, Object?> failure) {
      return failure.retype<ForumSearchData, ForumSearchReadCapabilities>();
    }
    final formhash = (formhashResult as DataReadSuccess<String, Object?>).data;
    final submitUri = _submitUri(normalized);
    final entryUri = _entryUri(normalized);

    final postResult = await _gateway.postForm(
      submitUri,
      data: <String, String>{
        'srchtxt': normalized.normalizedKeyword,
        'formhash': formhash,
        if (normalized.normalizedForumId != null)
          'srhfid': normalized.normalizedForumId!,
      },
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'search.forum.submit',
        pageKind: 'search',
      ),
      headers: <String, String>{'referer': entryUri.toString()},
      followRedirects: false,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    );
    if (postResult case ApiFailure<YamiboHttpResponse<String>> failure) {
      return _apiFailure(failure.error, code: 'forum_search_submit_failed');
    }

    final postResponse =
        (postResult as ApiSuccess<YamiboHttpResponse<String>>).data;
    final location = _firstHeader(postResponse.headers, 'location');
    if (_looksLikeLoginLocation(location) ||
        _looksLikeLoginHtml(postResponse.body)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'forum_search_unauthorized',
        diagnosticMessage: 'Forum search requires authentication.',
      );
    }
    final resultUri = _resolveSearchUri(location);
    if (resultUri == null) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_search_context_missing',
        diagnosticMessage: 'Forum search context redirect is invalid.',
      );
    }
    final searchContextValues =
        resultUri.queryParametersAll['searchid'] ?? const <String>[];
    final searchContextId = searchContextValues.length == 1
        ? searchContextValues.single.trim()
        : '';
    final pageValues = resultUri.queryParametersAll['page'] ?? const <String>[];
    final initialPage = pageValues.isEmpty
        ? 1
        : pageValues.length == 1
        ? int.tryParse(pageValues.single.trim())
        : null;
    if (searchContextId.isEmpty ||
        initialPage != 1 ||
        !_matchesScope(resultUri, normalized)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_search_context_invalid',
        diagnosticMessage: 'Forum search context is invalid.',
      );
    }

    return _loadResultPage(
      uri: resultUri,
      query: normalized,
      requestedPage: 1,
      searchContextId: searchContextId,
      referer: entryUri,
    );
  }

  @override
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>>
  loadNextPage(
    ForumSearchQuery query,
    ForumSearchPageIdentity page, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final normalized = _normalizeAndValidateQuery(query);
    if (normalized == null || page.token.trim().isEmpty || page.page < 2) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'forum_search_continuation_invalid',
        diagnosticMessage: 'Forum search continuation is invalid.',
      );
    }
    final continuation = _continuations[page.token];
    if (continuation == null ||
        continuation.page != page.page ||
        continuation.queryFingerprint != _queryFingerprint(normalized)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'forum_search_continuation_expired',
        diagnosticMessage: 'Forum search continuation is no longer valid.',
      );
    }

    final responseResult = await _gateway.getText(
      continuation.uri,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'search.forum.nextPage',
        pageKind: 'search',
      ),
      headers: <String, String>{'referer': _entryUri(normalized).toString()},
    );
    if (responseResult case ApiFailure<String> failure) {
      return _apiFailure(failure.error, code: 'forum_search_next_page_failed');
    }
    final response =
        (responseResult as ApiSuccess<YamiboHttpResponse<String>>).data;
    return _parseResultPage(
      html: response.body,
      uri: continuation.uri,
      query: normalized,
      requestedPage: continuation.page,
      searchContextId: continuation.searchContextId,
    );
  }

  Future<DataReadResult<String, Object?>> _loadFormhash() async {
    final cached = _cachedFormhash;
    if (cached != null && cached.isNotEmpty) {
      return DataReadSuccess<String, Object?>(
        data: cached,
        capabilities: null,
        metadata: const DataReadMetadata.network(),
      );
    }
    final result = await _formhashProvider.loadFormhash(preferProfile: true);
    if (result case ApiFailure<String> failure) {
      final mapped = _apiFailure<String, Object?>(
        failure.error,
        code: 'forum_search_formhash_failed',
      );
      return mapped;
    }
    final value = (result as ApiSuccess<String>).data.trim();
    if (value.isEmpty) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'forum_search_formhash_empty',
        diagnosticMessage: 'Forum search formhash is empty.',
      );
    }
    _cachedFormhash = value;
    return DataReadSuccess<String, Object?>(
      data: value,
      capabilities: null,
      metadata: const DataReadMetadata.network(),
    );
  }

  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>>
  _loadResultPage({
    required Uri uri,
    required ForumSearchQuery query,
    required int requestedPage,
    required String searchContextId,
    required Uri referer,
  }) async {
    final responseResult = await _gateway.getText(
      uri,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'search.forum.result',
        pageKind: 'search',
      ),
      headers: <String, String>{'referer': referer.toString()},
    );
    if (responseResult case ApiFailure<String> failure) {
      return _apiFailure(failure.error, code: 'forum_search_result_failed');
    }
    final response =
        (responseResult as ApiSuccess<YamiboHttpResponse<String>>).data;
    return _parseResultPage(
      html: response.body,
      uri: uri,
      query: query,
      requestedPage: requestedPage,
      searchContextId: searchContextId,
    );
  }

  DataReadResult<ForumSearchData, ForumSearchReadCapabilities>
  _parseResultPage({
    required String html,
    required Uri uri,
    required ForumSearchQuery query,
    required int requestedPage,
    required String searchContextId,
  }) {
    try {
      final parsed = _parser.parse(
        html: html,
        pageUri: uri,
        query: query,
        requestedPage: requestedPage,
        expectedSearchContextId: searchContextId,
      );
      if (parsed.searchContextId != searchContextId ||
          parsed.currentPage != requestedPage) {
        return const DataReadFailure(
          kind: DataReadFailureKind.parse,
          code: 'forum_search_result_identity_mismatch',
          diagnosticMessage: 'Forum search result identity does not match.',
        );
      }
      final nextPage = parsed.nextPageUri == null
          ? null
          : _registerContinuation(
              query: query,
              searchContextId: searchContextId,
              uri: parsed.nextPageUri!,
              page: _pageFromUri(parsed.nextPageUri!),
            );
      final data = ForumSearchData(
        query: query,
        topics: parsed.topics,
        pagination: ForumSearchPagination(
          currentPage: parsed.currentPage,
          nextPage: nextPage,
          precision: nextPage == null
              ? PaginationPrecision.unknown
              : PaginationPrecision.directional,
        ),
      );
      return DataReadSuccess(
        data: data,
        capabilities: _readCapabilitiesFor(data),
        metadata: const DataReadMetadata.network(),
      );
    } on DiscuzSearchUnauthorizedException {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'forum_search_unauthorized',
        diagnosticMessage: 'Forum search requires authentication.',
      );
    } on DiscuzSearchHtmlParseException catch (error) {
      return DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: error.code,
        diagnosticMessage: 'Forum search HTML parsing failed.',
      );
    } catch (_) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_search_parse_failed',
        diagnosticMessage: 'Forum search HTML parsing failed.',
      );
    }
  }

  ForumSearchPageIdentity _registerContinuation({
    required ForumSearchQuery query,
    required String searchContextId,
    required Uri uri,
    required int page,
  }) {
    final token = 'search-${_nextToken++}';
    _continuations[token] = _ContinuationEntry(
      queryFingerprint: _queryFingerprint(query),
      searchContextId: searchContextId,
      uri: uri,
      page: page,
    );
    while (_continuations.length > 128) {
      _continuations.remove(_continuations.keys.first);
    }
    return ForumSearchPageIdentity(token: token, page: page);
  }

  ForumSearchQuery? _normalizeAndValidateQuery(ForumSearchQuery query) {
    final normalized = query.normalized();
    if (normalized.normalizedKeyword.isEmpty) {
      return null;
    }
    if (normalized.scope == ForumSearchScope.allForums &&
        normalized.normalizedForumId != null) {
      return null;
    }
    if (normalized.scope == ForumSearchScope.currentForum &&
        !_isPositiveInteger(normalized.normalizedForumId ?? '')) {
      return null;
    }
    return normalized;
  }

  String _queryFingerprint(ForumSearchQuery query) {
    return '${query.scope.name}|${query.normalizedForumId ?? ''}|${query.normalizedKeyword}';
  }

  bool _matchesScope(Uri uri, ForumSearchQuery query) {
    final modValues = uri.queryParametersAll['mod'] ?? const <String>[];
    if (modValues.length != 1) {
      return false;
    }
    final mod = modValues.single.trim().toLowerCase();
    final forumIds = uri.queryParametersAll['srhfid'] ?? const <String>[];
    if (forumIds.length > 1) {
      return false;
    }
    return switch (query.scope) {
      ForumSearchScope.allForums => mod == 'forum' && forumIds.isEmpty,
      ForumSearchScope.currentForum =>
        mod == 'curforum' &&
            forumIds.length == 1 &&
            forumIds.single == query.normalizedForumId,
    };
  }

  Uri _submitUri(ForumSearchQuery query) {
    return Uri.parse(AppConfig.siteBaseUrl).replace(
      path: '/search.php',
      queryParameters: <String, String>{
        'mod': query.scope == ForumSearchScope.allForums ? 'forum' : 'curforum',
        if (query.normalizedForumId != null) 'srhfid': query.normalizedForumId!,
        'searchsubmit': 'yes',
        'mobile': '2',
      },
    );
  }

  Uri _entryUri(ForumSearchQuery query) {
    return Uri.parse(AppConfig.siteBaseUrl).replace(
      path: '/search.php',
      queryParameters: <String, String>{
        'mod': query.scope == ForumSearchScope.allForums ? 'forum' : 'curforum',
        if (query.normalizedForumId != null) 'srhfid': query.normalizedForumId!,
        'mobile': '2',
      },
    );
  }

  Uri? _resolveSearchUri(String? rawLocation) {
    final location = rawLocation?.trim() ?? '';
    if (location.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(location);
    if (parsed == null) {
      return null;
    }
    final origin = Uri.parse('${AppConfig.siteBaseUrl}/');
    final resolved = parsed.hasScheme ? parsed : origin.resolveUri(parsed);
    if (resolved.scheme.toLowerCase() != origin.scheme ||
        resolved.host.toLowerCase() != origin.host.toLowerCase() ||
        resolved.path.toLowerCase() != '/search.php') {
      return null;
    }
    return resolved;
  }

  int _pageFromUri(Uri uri) =>
      int.tryParse(uri.queryParameters['page']?.trim() ?? '') ?? 0;

  String? _firstHeader(Map<String, List<String>> headers, String name) {
    final values = headers.entries
        .where((entry) => entry.key.toLowerCase() == name.toLowerCase())
        .expand((entry) => entry.value)
        .toList(growable: false);
    return values.isEmpty ? null : values.first;
  }

  bool _isPositiveInteger(String value) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed > 0;
  }

  bool _looksLikeLoginLocation(String? rawLocation) {
    final location = rawLocation?.trim() ?? '';
    if (location.isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(location);
    if (uri == null) {
      return false;
    }
    final path = uri.path.toLowerCase();
    final action = uri.queryParameters['mod']?.toLowerCase();
    return (path.endsWith('/member.php') && action == 'logging') ||
        path.endsWith('/login.php');
  }

  bool _looksLikeLoginHtml(String html) {
    return RegExp(
      r'''<input[^>]+name=["']password["']|id=["']lsform["']|class=["'][^"']*loginbox''',
      caseSensitive: false,
    ).hasMatch(html);
  }

  ForumSearchReadCapabilities _readCapabilitiesFor(ForumSearchData data) {
    final topics = data.topics;
    DataCapabilitySupport complete(
      bool Function(ForumSearchTopicSummary topic) predicate,
    ) {
      return topics.isNotEmpty && topics.every(predicate)
          ? DataCapabilitySupport.supported
          : DataCapabilitySupport.unsupported;
    }

    final values =
        DataCapabilitySet<ForumSearchCapability>.from(
              supported: <ForumSearchCapability>[
                ForumSearchCapability.stableTopicIdentity,
                ForumSearchCapability.orderedTopics,
                ForumSearchCapability.topicTitle,
              ],
            )
            .withSupport(
              ForumSearchCapability.topicForum,
              complete(
                (topic) =>
                    topic.forumId?.trim().isNotEmpty == true &&
                    topic.forumName?.trim().isNotEmpty == true,
              ),
            )
            .withSupport(
              ForumSearchCapability.topicAuthor,
              complete((topic) => topic.authorName?.trim().isNotEmpty == true),
            )
            .withSupport(
              ForumSearchCapability.topicPublishedAt,
              complete(
                (topic) => topic.publishedAtText?.trim().isNotEmpty == true,
              ),
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

  DataReadFailure<T, C> _apiFailure<T, C>(
    ApiError error, {
    required String code,
  }) {
    final mapped = dataReadFailureFromApiError<T, C>(error);
    return DataReadFailure<T, C>(
      kind: mapped.kind,
      code: code,
      statusCode: mapped.statusCode,
      diagnosticMessage: 'Forum search request failed.',
    );
  }
}

final class _ContinuationEntry {
  const _ContinuationEntry({
    required this.queryFingerprint,
    required this.searchContextId,
    required this.uri,
    required this.page,
  });

  final String queryFingerprint;
  final String searchContextId;
  final Uri uri;
  final int page;
}

final _htmlCapabilities = ForumSearchSourceCapabilities(
  values: DataCapabilitySet<ForumSearchCapability>.supported(
    ForumSearchCapability.values,
  ),
  paginationPrecision: PaginationPrecision.directional,
);

final forumSearchRepositoryProvider = Provider<ForumSearchRepository>((ref) {
  return DiscuzForumSearchRepository(
    formhashProvider: ref.read(formhashProvider),
    gateway: ref.read(yamiboHttpGatewayProvider),
  );
});
