import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_http_response.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/profile/data/profile_repository.dart';
import 'package:y300/features/search/data/discuz_search_html_parser.dart';
import 'package:y300/features/search/data/forum_search_service.dart';
import 'package:y300/features/search/data/forum_search_scheduler.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/data/search_rate_limiter.dart';

export 'package:y300/features/search/data/forum_search_service.dart';

class DiscuzSearchService implements ForumSearchService {
  DiscuzSearchService({
    required ProfileRepository profileRepository,
    required SearchRateLimiter rateLimiter,
    required YamiboHttpGateway gateway,
    DiscuzSearchHtmlParser? htmlParser,
  }) : _profileRepository = profileRepository,
       _rateLimiter = rateLimiter,
       _gateway = gateway,
       _htmlParser = htmlParser ?? DiscuzSearchHtmlParser();

  final ProfileRepository _profileRepository;
  final SearchRateLimiter _rateLimiter;
  final YamiboHttpGateway _gateway;
  final DiscuzSearchHtmlParser _htmlParser;
  // bbs.yamibo.com 的 formhash 与登录会话绑定，重复 GET profile 拉到的
  // 永远是同一个值——首次同步阶段一连发 70 次 search，每次都先去拉 profile
  // 是纯净的浪费。这里只缓存 hash 字符串，避免把整段 ProfileData 留在内存。
  String? _cachedFormhash;

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      return const DiscuzSearchResponse(
        items: <DiscuzSearchResultItem>[],
        rateLimited: false,
      );
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
    final submitUrl = Uri.parse(
      '${AppConfig.siteBaseUrl}/${_buildSubmitPath(context)}',
    );
    final referer = _buildEntryUrl(context);
    final postResponse = await _guardedRequest(
      () => _gateway.postForm(
        submitUrl,
        data: <String, String>{
          'srchtxt': trimmed,
          'formhash': formhash,
          if ((context.srhfid ?? '').isNotEmpty) 'srhfid': context.srhfid!,
        },
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.html,
          operation: 'search.forum.submit',
          pageKind: 'search',
        ),
        headers: <String, String>{'referer': referer},
        followRedirects: false,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
      action: '提交搜索请求',
    );

    final locationValues = postResponse.headers['location'];
    final location = locationValues == null || locationValues.isEmpty
        ? null
        : locationValues.first;
    final searchResultUrl = _resolveSearchResultUrl(
      location: location,
      fallbackRequestUri: postResponse.uri,
    );
    if (searchResultUrl == null) {
      throw const DiscuzSearchServiceException('搜索结果重定向地址缺失');
    }

    final resultResponse = await _guardedRequest(
      () => _gateway.getText(
        Uri.parse(searchResultUrl),
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.html,
          operation: 'search.forum.result',
          pageKind: 'search',
        ),
        headers: <String, String>{'referer': referer},
      ),
      action: '获取搜索结果',
    );

    final parsed = _htmlParser.parse(resultResponse.body);
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
      return const DiscuzSearchResponse(
        items: <DiscuzSearchResultItem>[],
        rateLimited: false,
      );
    }
    final response = await _guardedRequest(
      () => _gateway.getText(
        Uri.parse(trimmed),
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.html,
          operation: 'search.forum.nextPage',
          pageKind: 'search',
        ),
        headers: <String, String>{'referer': _buildEntryUrl(context)},
      ),
      action: '获取搜索下一页',
    );
    final parsed = _htmlParser.parse(response.body);
    return DiscuzSearchResponse(
      items: _filterItemsByContext(parsed.items, context),
      rateLimited: false,
      nextPageUrl: parsed.nextPageUrl,
    );
  }

  Future<YamiboHttpResponse<String>> _guardedRequest(
    Future<ApiResult<YamiboHttpResponse<String>>> Function() request, {
    required String action,
  }) async {
    final result = await request();
    if (result case ApiSuccess(:final data)) {
      return data;
    }
    final error = (result as ApiFailure<YamiboHttpResponse<String>>).error;
    if (error.statusCode == 503) {
      throw const DiscuzSearchServiceException('搜索服务暂时不可用（HTTP 503），请稍后重试');
    }
    throw DiscuzSearchServiceException('$action失败：${error.message}');
  }

  Future<String> _loadFormhash() async {
    final cached = _cachedFormhash;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final profile = await _profileRepository.getProfile();
    return profile.when(
      success: (data) {
        final formhash = data.formhash.trim();
        if (formhash.isEmpty) {
          throw const DiscuzSearchServiceException('formhash 为空，无法执行搜索');
        }
        _cachedFormhash = formhash;
        return formhash;
      },
      failure: (error) =>
          throw DiscuzSearchServiceException('获取 formhash 失败：${error.message}'),
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
        return Uri.parse(
          '${AppConfig.siteBaseUrl}/',
        ).resolveUri(uri).toString();
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

final rawDiscuzSearchServiceProvider = Provider<ForumSearchService>((ref) {
  return DiscuzSearchService(
    profileRepository: ref.read(profileRepositoryProvider),
    rateLimiter: ref.read(searchRateLimiterProvider),
    gateway: ref.read(yamiboHttpGatewayProvider),
  );
});

final forumSearchSchedulerProvider = Provider<ForumSearchScheduler>((ref) {
  final scheduler = ForumSearchScheduler(
    rawService: ref.read(rawDiscuzSearchServiceProvider),
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

final discuzSearchServiceProvider = Provider<ForumSearchService>((ref) {
  return ref.watch(forumSearchSchedulerProvider);
});
