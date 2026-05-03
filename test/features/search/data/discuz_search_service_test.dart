import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/profile/data/models/profile_models.dart';
import 'package:y300/features/profile/data/profile_repository.dart';
import 'package:y300/features/search/data/discuz_search_service.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/data/search_rate_limiter.dart';

void main() {
  group('DiscuzSearchService', () {
    test('returns parsed fid=30 items and marks limiter when allowed', () async {
      final profileRepository = _FakeProfileRepository.success(
        formhash: 'fh_123',
      );
      final limiter = _FakeSearchRateLimiter(
        checkResult: const _LimiterState.allowed(),
      );
      final adapter = _DiscuzSearchTestAdapter(
        locationHeader: 'search.php?mod=forum&searchid=777&orderby=lastpost&ascdesc=desc&searchsubmit=yes',
        searchResultHtml: _sampleSearchHtml(),
      );
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
          followRedirects: false,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
      )..httpClientAdapter = adapter;

      final service = DiscuzSearchService(
        profileRepository: profileRepository,
        rateLimiter: limiter,
        cookieStore: CookieStore(),
        dio: dio,
      );

      final result = await service.searchForum(keyword: '百合情结');

      expect(result.rateLimited, isFalse);
      expect(result.items.length, 1);
      expect(result.items.first.tid, '570616');
      expect(result.items.first.fid, '30');
      expect(limiter.markTriggeredCount, 1);
    });

    test('returns rate limited response and does not send network request', () async {
      final profileRepository = _FakeProfileRepository.success(
        formhash: 'fh_123',
      );
      final limiter = _FakeSearchRateLimiter(
        checkResult: const _LimiterState.blocked(Duration(seconds: 8)),
      );
      final adapter = _DiscuzSearchTestAdapter(
        locationHeader: null,
        searchResultHtml: '',
      );
      final dio = Dio()..httpClientAdapter = adapter;

      final service = DiscuzSearchService(
        profileRepository: profileRepository,
        rateLimiter: limiter,
        cookieStore: CookieStore(),
        dio: dio,
      );

      final result = await service.searchForum(keyword: '百合');

      expect(result.rateLimited, isTrue);
      expect(result.retryAfter.inSeconds, 8);
      expect(result.items, isEmpty);
      expect(adapter.requestCount, 0);
      expect(limiter.markTriggeredCount, 0);
    });

    test('throws when formhash is empty', () async {
      final profileRepository = _FakeProfileRepository.success(formhash: '');
      final limiter = _FakeSearchRateLimiter(
        checkResult: const _LimiterState.allowed(),
      );
      final adapter = _DiscuzSearchTestAdapter(
        locationHeader: null,
        searchResultHtml: '',
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = DiscuzSearchService(
        profileRepository: profileRepository,
        rateLimiter: limiter,
        cookieStore: CookieStore(),
        dio: dio,
      );

      expect(
        () => service.searchForum(keyword: '百合'),
        throwsA(
          isA<DiscuzSearchServiceException>().having(
            (e) => e.message,
            'message',
            contains('formhash'),
          ),
        ),
      );
    });
  });
}

String _sampleSearchHtml() {
  return '''
<li class="list">
  <a href="forum.php?mod=viewthread&amp;tid=570616&amp;extra=&amp;mobile=2">
    <div class="threadlist_tit cl"><em>【提黄灯喵汉化组】百合情结 14</em></div>
  </a>
  <div class="threadlist_foot cl">
    <ul><li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">#中文百合漫画区</a></li></ul>
  </div>
</li>
<li class="list">
  <a href="forum.php?mod=viewthread&amp;tid=570617&amp;extra=&amp;mobile=2">
    <div class="threadlist_tit cl"><em>不属于漫画区</em></div>
  </a>
  <div class="threadlist_foot cl">
    <ul><li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=55&amp;mobile=2">#轻小说译文区</a></li></ul>
  </div>
</li>
''';
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository.success({required String formhash})
    : _result = ApiSuccess<ProfileData>(
        ProfileData(
          uid: '1',
          username: 'tester',
          avatar: '',
          groupId: '10',
          credits: 0,
          posts: 0,
          threads: 0,
          formhash: formhash,
        ),
      );

  final ApiResult<ProfileData> _result;

  @override
  Future<ApiResult<ProfileData>> getProfile() async {
    return _result;
  }
}

class _FakeSearchRateLimiter extends SearchRateLimiter {
  _FakeSearchRateLimiter({
    required _LimiterState checkResult,
  }) : _checkResult = checkResult,
       super(
         cooldown: const Duration(seconds: 10),
       );

  final _LimiterState _checkResult;
  int markTriggeredCount = 0;

  @override
  Future<SearchRateLimitResult> check() async {
    if (_checkResult.isAllowed) {
      return const SearchRateLimitResult.allowed();
    }
    return SearchRateLimitResult.blocked(_checkResult.retryAfter);
  }

  @override
  Future<void> markTriggered() async {
    markTriggeredCount += 1;
  }
}

class _LimiterState {
  const _LimiterState.allowed() : isAllowed = true, retryAfter = Duration.zero;

  const _LimiterState.blocked(this.retryAfter) : isAllowed = false;

  final bool isAllowed;
  final Duration retryAfter;
}

class _DiscuzSearchTestAdapter implements HttpClientAdapter {
  _DiscuzSearchTestAdapter({
    required this.locationHeader,
    required this.searchResultHtml,
  });

  final String? locationHeader;
  final String searchResultHtml;
  int requestCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount += 1;
    final uri = options.uri;

    if (options.method == 'POST' &&
        uri.path.endsWith('/search.php') &&
        uri.queryParameters['mod'] == 'forum' &&
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
        uri.queryParameters['mod'] == 'forum' &&
        uri.queryParameters.containsKey('searchid')) {
      return ResponseBody.fromString(
        searchResultHtml,
        200,
        headers: const <String, List<String>>{},
      );
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
      headers: const <String, List<String>>{},
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
