import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/profile/data/profile_repository.dart';
import 'package:y300/features/search/data/discuz_search_html_parser.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/data/search_rate_limiter.dart';

class DiscuzSearchServiceException implements Exception {
  const DiscuzSearchServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DiscuzSearchResponse {
  const DiscuzSearchResponse({
    required this.items,
    required this.rateLimited,
    this.retryAfter = Duration.zero,
    this.nextPageUrl,
  });

  final List<DiscuzSearchResultItem> items;
  final bool rateLimited;
  final Duration retryAfter;
  final String? nextPageUrl;
}

abstract class ForumSearchService {
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  });

  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  });
}

class DiscuzSearchService implements ForumSearchService {
  DiscuzSearchService({
    required ProfileRepository profileRepository,
    required SearchRateLimiter rateLimiter,
    required CookieStore cookieStore,
    Dio? dio,
    DiscuzSearchHtmlParser? htmlParser,
  }) : _profileRepository = profileRepository,
       _rateLimiter = rateLimiter,
       _cookieStore = cookieStore,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: AppConfig.connectTimeout,
               receiveTimeout: AppConfig.receiveTimeout,
               followRedirects: false,
               validateStatus: (status) => status != null && status >= 200 && status < 400,
             ),
           ),
       _htmlParser = htmlParser ?? DiscuzSearchHtmlParser() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final cookieHeader = await _cookieStore.readCookieHeader(options.uri);
          if (cookieHeader != null && cookieHeader.isNotEmpty) {
            options.headers['cookie'] = cookieHeader;
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          final setCookie = response.headers.map['set-cookie'] ?? <String>[];
          await _cookieStore.saveFromSetCookie(response.requestOptions.uri, setCookie);
          handler.next(response);
        },
      ),
    );
  }

  final ProfileRepository _profileRepository;
  final SearchRateLimiter _rateLimiter;
  final CookieStore _cookieStore;
  final Dio _dio;
  final DiscuzSearchHtmlParser _htmlParser;

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      return const DiscuzSearchResponse(items: <DiscuzSearchResultItem>[], rateLimited: false);
    }

    if (enforceRateLimit) {
      final limit = await _rateLimiter.check();
      if (!limit.isAllowed) {
        return DiscuzSearchResponse(
          items: const <DiscuzSearchResultItem>[],
          rateLimited: true,
          retryAfter: limit.retryAfter,
        );
      }
    }

    final formhash = await _loadFormhash();
    final submitUrl = '${AppConfig.siteBaseUrl}/${_buildSubmitPath(context)}';
    final referer = _buildEntryUrl(context);
    final postResponse = await _guardedRequest(
      () => _dio.post<String>(
        submitUrl,
        data: <String, String>{
          'srchtxt': trimmed,
          'formhash': formhash,
          if ((context.srhfid ?? '').isNotEmpty) 'srhfid': context.srhfid!,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          headers: <String, String>{'referer': referer},
        ),
      ),
      action: '提交搜索请求',
    );

    final location = postResponse.headers.value('location');
    final searchResultUrl = _resolveSearchResultUrl(
      location: location,
      fallbackRequestUri: postResponse.requestOptions.uri,
    );
    if (searchResultUrl == null) {
      throw const DiscuzSearchServiceException('搜索结果重定向地址缺失');
    }

    final resultResponse = await _guardedRequest(
      () => _dio.get<String>(
        searchResultUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: <String, String>{'referer': referer},
        ),
      ),
      action: '获取搜索结果',
    );

    final parsed = _htmlParser.parse(resultResponse.data ?? '');
    if (enforceRateLimit) {
      await _rateLimiter.markTriggered();
    }
    return DiscuzSearchResponse(
      items: _filterItemsByContext(parsed.items, context),
      rateLimited: false,
      nextPageUrl: parsed.nextPageUrl,
    );
  }

  @override
  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  }) async {
    final trimmed = nextPageUrl.trim();
    if (trimmed.isEmpty) {
      return const DiscuzSearchResponse(items: <DiscuzSearchResultItem>[], rateLimited: false);
    }
    final response = await _guardedRequest(
      () => _dio.get<String>(
        trimmed,
        options: Options(
          responseType: ResponseType.plain,
          headers: <String, String>{'referer': _buildEntryUrl(context)},
        ),
      ),
      action: '获取搜索下一页',
    );
    final parsed = _htmlParser.parse(response.data ?? '');
    return DiscuzSearchResponse(
      items: _filterItemsByContext(parsed.items, context),
      rateLimited: false,
      nextPageUrl: parsed.nextPageUrl,
    );
  }

  Future<Response<String>> _guardedRequest(
    Future<Response<String>> Function() request, {
    required String action,
  }) async {
    try {
      return await request();
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 503) {
        throw const DiscuzSearchServiceException('搜索服务暂时不可用（HTTP 503），请稍后重试');
      }
      throw DiscuzSearchServiceException('$action失败：${error.message}');
    }
  }

  Future<String> _loadFormhash() async {
    final profile = await _profileRepository.getProfile();
    return profile.when(
      success: (data) {
        final formhash = data.formhash.trim();
        if (formhash.isEmpty) {
          throw const DiscuzSearchServiceException('formhash 为空，无法执行搜索');
        }
        return formhash;
      },
      failure: (error) => throw DiscuzSearchServiceException('获取 formhash 失败：${error.message}'),
    );
  }

  String? _resolveSearchResultUrl({
    required String? location,
    required Uri fallbackRequestUri,
  }) {
    if (location != null && location.trim().isNotEmpty) {
      final uri = Uri.tryParse(location.trim());
      if (uri != null) {
        if (uri.hasScheme) {
          return uri.toString();
        }
        return Uri.parse('${AppConfig.siteBaseUrl}/').resolveUri(uri).toString();
      }
    }
    return fallbackRequestUri.toString();
  }

  String _buildSubmitPath(DiscuzSearchContext context) {
    switch (context.scope) {
      case DiscuzSearchScope.forum:
        return 'search.php?mod=forum&searchsubmit=yes&mobile=2';
      case DiscuzSearchScope.curForum:
        final fid = context.srhfid ?? '';
        return 'search.php?mod=curforum&srhfid=$fid&searchsubmit=yes&mobile=2';
    }
  }

  String _buildEntryUrl(DiscuzSearchContext context) {
    switch (context.scope) {
      case DiscuzSearchScope.forum:
        return '${AppConfig.siteBaseUrl}/search.php?mod=forum&mobile=2';
      case DiscuzSearchScope.curForum:
        final fid = context.srhfid ?? '';
        return '${AppConfig.siteBaseUrl}/search.php?mod=curforum&srhfid=$fid&mobile=2';
    }
  }

  List<DiscuzSearchResultItem> _filterItemsByContext(
    List<DiscuzSearchResultItem> items,
    DiscuzSearchContext context,
  ) {
    final fid = context.srhfid?.trim();
    if (fid == null || fid.isEmpty) {
      return items;
    }
    return items.where((item) => item.fid == fid).toList(growable: false);
  }
}

final searchRateLimiterProvider = Provider<SearchRateLimiter>((ref) {
  return SearchRateLimiter();
});

final discuzSearchServiceProvider = Provider<ForumSearchService>((ref) {
  return DiscuzSearchService(
    profileRepository: ref.read(profileRepositoryProvider),
    rateLimiter: ref.read(searchRateLimiterProvider),
    cookieStore: ref.read(cookieStoreProvider),
  );
});
