import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/auth/domain/services/formhash_provider.dart';
import 'package:y300/features/search/data/services/discuz_search_service.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/data/services/search_rate_limiter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('DiscuzSearchService', () {
    test('searchForum returns parsed items and next page', () async {
      final service = _buildService(
        adapter: _DiscuzSearchTestAdapter(
          locationHeader: 'search.php?mod=forum&searchid=777&searchsubmit=yes',
          searchResultHtml: _sampleSearchHtmlWithNext(),
        ),
      );

      final result = await service.searchForum(
        keyword: '百合',
        context: const DiscuzSearchContext.curForum(srhfid: '30'),
      );

      expect(result.rateLimited, isFalse);
      expect(result.items.length, 1);
      expect(result.items.first.tid, '570616');
      expect(result.nextPageUrl, isNotNull);
    });

    test('fetchNextPage parses next page list', () async {
      final service = _buildService(
        adapter: _DiscuzSearchTestAdapter(
          locationHeader: 'search.php?mod=forum&searchid=777&searchsubmit=yes',
          searchResultHtml: _sampleSearchHtmlWithNext(),
          nextPageHtml: _sampleNextPageHtml(),
        ),
      );

      final result = await service.fetchNextPage(
        nextPageUrl:
            'https://bbs.yamibo.com/search.php?mod=forum&searchid=777&page=2&mobile=2',
        context: const DiscuzSearchContext.curForum(srhfid: '30'),
      );
      expect(result.items.length, 1);
      expect(result.items.first.tid, '570700');
    });
  });
}

DiscuzSearchService _buildService({required _DiscuzSearchTestAdapter adapter}) {
  final formhashProvider = _FakeFormhashProvider(formhash: 'fh_123');
  final limiter = _FakeSearchRateLimiter(
    checkResult: const _LimiterState.allowed(),
  );
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      followRedirects: false,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return DiscuzSearchService(
    formhashProvider: formhashProvider,
    rateLimiter: limiter,
    gateway: YamiboHttpGateway(
      cookieStore: CookieStore(),
      logger: Logger(level: Level.off),
      dio: dio,
      enableLog: false,
    ),
  );
}

String _sampleSearchHtmlWithNext() {
  return '''
<li class="list">
  <a href="forum.php?mod=viewthread&amp;tid=570616&amp;mobile=2">
    <div class="threadlist_tit cl"><em>标题1</em></div>
  </a>
  <div class="threadlist_foot cl">
    <ul><li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></li></ul>
  </div>
</li>
<div class="pg"><a class="nxt" href="search.php?mod=forum&amp;searchid=777&amp;page=2&amp;mobile=2">下一页</a></div>
''';
}

String _sampleNextPageHtml() {
  return '''
<li class="list">
  <a href="forum.php?mod=viewthread&amp;tid=570700&amp;mobile=2">
    <div class="threadlist_tit cl"><em>标题2</em></div>
  </a>
  <div class="threadlist_foot cl">
    <ul><li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></li></ul>
  </div>
</li>
''';
}

class _FakeFormhashProvider implements FormhashProvider {
  _FakeFormhashProvider({required this.formhash});

  final String formhash;

  @override
  Future<ApiResult<String>> loadFormhash({bool preferProfile = false}) async {
    expect(preferProfile, isTrue);
    return ApiSuccess<String>(formhash);
  }
}

class _FakeSearchRateLimiter extends SearchRateLimiter {
  _FakeSearchRateLimiter({required _LimiterState checkResult})
    : _checkResult = checkResult,
      super(cooldown: const Duration(seconds: 10));

  final _LimiterState _checkResult;

  @override
  Future<SearchRateLimitResult> check() async {
    if (_checkResult.isAllowed) {
      return const SearchRateLimitResult.allowed();
    }
    return SearchRateLimitResult.blocked(_checkResult.retryAfter);
  }

  @override
  Future<void> markTriggered() async {}
}

class _LimiterState {
  const _LimiterState.allowed() : isAllowed = true, retryAfter = Duration.zero;

  final bool isAllowed;
  final Duration retryAfter;
}

class _DiscuzSearchTestAdapter implements HttpClientAdapter {
  _DiscuzSearchTestAdapter({
    required this.locationHeader,
    required this.searchResultHtml,
    this.nextPageHtml = '',
  });

  final String? locationHeader;
  final String searchResultHtml;
  final String nextPageHtml;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    if (options.method == 'POST' &&
        uri.path.endsWith('/search.php') &&
        uri.queryParameters['searchsubmit'] == 'yes') {
      return ResponseBody.fromString(
        '',
        302,
        headers: <String, List<String>>{
          if (locationHeader != null) 'location': <String>[locationHeader!],
        },
      );
    }
    if (options.method == 'GET' &&
        uri.path.endsWith('/search.php') &&
        uri.queryParameters['searchid'] == '777' &&
        !uri.queryParameters.containsKey('page')) {
      return ResponseBody.fromString(searchResultHtml, 200);
    }
    if (options.method == 'GET' &&
        uri.path.endsWith('/search.php') &&
        uri.queryParameters['searchid'] == '777' &&
        uri.queryParameters['page'] == '2') {
      return ResponseBody.fromString(nextPageHtml, 200);
    }

    final body = await _readRequestBody(requestStream);
    return ResponseBody.fromString(
      jsonEncode(<String, String>{
        'error': 'Unexpected request',
        'method': options.method,
        'url': options.uri.toString(),
        'body': body,
      }),
      404,
    );
  }

  Future<String> _readRequestBody(Stream<Uint8List>? requestStream) async {
    if (requestStream == null) {
      return '';
    }
    final chunks = await requestStream.toList();
    final bytes = <int>[];
    for (final chunk in chunks) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) {
      return '';
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
