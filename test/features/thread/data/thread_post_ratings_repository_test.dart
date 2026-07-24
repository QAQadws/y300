import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/thread/data/repositories/thread_post_ratings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ThreadPostRatingsHtmlParser', () {
    test('pairs optional reason rows with the preceding rating', () {
      const parser = ThreadPostRatingsHtmlParser();

      final details = parser.parse(_ratingsHtml(includeTotal: true));

      expect(details.participantCount, 3);
      expect(details.totalScoreText, '积分 +17 点');
      expect(details.ratings[0].userName, 'alice');
      expect(details.ratings[0].score, '+2');
      expect(details.ratings[0].dateline, '2026-1-16 11:36');
      expect(details.ratings[0].reason, '第一条理由');
      expect(details.ratings[1].userName, 'bob');
      expect(details.ratings[1].reason, isEmpty);
      expect(details.ratings[2].userName, 'carol');
      expect(details.ratings[2].reason, '第三条理由');
    });

    test('falls back to summing scores when the total row is absent', () {
      const parser = ThreadPostRatingsHtmlParser();

      final details = parser.parse(_ratingsHtml(includeTotal: false));

      expect(details.totalScoreText, '积分 +17 点');
    });

    test('parses a mobile list without depending on the popup wrapper', () {
      const parser = ThreadPostRatingsHtmlParser();
      final html = _ratingsHtml(
        includeTotal: true,
      ).replaceAll('id="floatlayout_topicadmin"', 'class="ratings-page"');

      final details = parser.parse(html);

      expect(details.ratings, hasLength(3));
      expect(details.totalScoreText, '积分 +17 点');
    });

    test('unwraps Discuz AJAX CDATA responses', () {
      const parser = ThreadPostRatingsHtmlParser();

      final details = parser.parse(
        '<?xml version="1.0"?><root><![CDATA[${_ratingsHtml(includeTotal: true)}]]></root>',
      );

      expect(details.ratings, hasLength(3));
      expect(details.ratings.first.reason, '第一条理由');
    });

    test('parses the desktop rating table as a compatibility fallback', () {
      const parser = ThreadPostRatingsHtmlParser();

      final details = parser.parse(_desktopRatingsHtml());

      expect(details.ratings, hasLength(2));
      expect(details.ratings.first.userName, 'alice');
      expect(details.ratings.first.dateline, '2026-1-16 11:36');
      expect(details.ratings.first.reason, '第一条理由');
      expect(details.totalScoreText, '积分 +7 点');
    });

    test('rejects a page without a rating list', () {
      const parser = ThreadPostRatingsHtmlParser();

      expect(
        () => parser.parse('<html><body>empty</body></html>'),
        throwsA(isA<ThreadPostRatingsParseException>()),
      );
    });
  });

  group('DiscuzThreadPostRatingsRepository', () {
    test('loads the authenticated mobile rating page', () async {
      final adapter = _RatingsTestAdapter(_ratingsHtml(includeTotal: true));
      final repository = DiscuzThreadPostRatingsRepository(
        htmlClient: YamiboHtmlClient(gateway: _buildGateway(adapter)),
      );

      final result = await repository.loadAll(
        'https://bbs.yamibo.com/forum.php?mod=misc&action=viewratings&tid=504393&pid=39506511',
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.ratings, hasLength(3));
      expect(adapter.requestCount, 1);
      expect(adapter.lastUri?.queryParameters['mobile'], '2');
      expect(adapter.lastUri?.queryParameters['tid'], '504393');
      expect(adapter.lastUri?.queryParameters['pid'], '39506511');
      expect(
        adapter.lastUserAgent,
        DiscuzImageRequestHeaderBuilder.mobileBrowserUserAgent,
      );
    });

    test('rejects cross-site and incomplete URLs before networking', () async {
      final adapter = _RatingsTestAdapter(_ratingsHtml(includeTotal: true));
      final repository = DiscuzThreadPostRatingsRepository(
        htmlClient: YamiboHtmlClient(gateway: _buildGateway(adapter)),
      );

      final crossSite = await repository.loadAll(
        'https://example.com/forum.php?mod=misc&action=viewratings&tid=1&pid=2',
      );
      final missingPid = await repository.loadAll(
        'https://bbs.yamibo.com/forum.php?mod=misc&action=viewratings&tid=1',
      );
      final wrongAction = await repository.loadAll(
        'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=1&pid=2',
      );

      expect(crossSite.isSuccess, isFalse);
      expect(missingPid.isSuccess, isFalse);
      expect(wrongAction.isSuccess, isFalse);
      expect(adapter.requestCount, 0);
    });
  });
}

String _ratingsHtml({required bool includeTotal}) {
  return '''
<html><body>
<div id="floatlayout_topicadmin">
  <ul class="post_box">
    <li class="flex-box mli">
      <div><span>积分</span></div>
      <div><span>用户名</span></div>
      <div><span>时间</span></div>
    </li>
    <li class="flex-box mli">
      <div><span>积分 +2 点</span></div>
      <div><span>alice</span></div>
      <div><span>2026-1-16 11:36</span></div>
    </li>
    <li class="flex-box mli"><div><span>第一条理由</span></div></li>
    <li class="flex-box mli">
      <div><span>积分 +5 点</span></div>
      <div><span>bob</span></div>
      <div><span>2025-1-1 08:00</span></div>
    </li>
    <li class="flex-box mli">
      <div><span>积分 +10 点</span></div>
      <div><span>carol</span></div>
      <div><span>2024-1-1 08:00</span></div>
    </li>
    <li class="flex-box mli"><div><span>第三条理由</span></div></li>
  </ul>
  ${includeTotal ? '<div class="o pns">总计:&nbsp;积分 +17 点&nbsp;</div>' : ''}
</div>
</body></html>
''';
}

String _desktopRatingsHtml() {
  return '''
<html><body>
  <h3>查看全部评分</h3>
  <table class="list">
    <tr><th>积分</th><th>用户名</th><th>时间</th><th>理由</th></tr>
    <tr><td>积分 +2 点</td><td>alice</td><td>2026-1-16 11:36</td><td>第一条理由</td></tr>
    <tr><td>积分 +5 点</td><td>bob</td><td>2025-1-1 08:00</td><td></td></tr>
  </table>
</body></html>
''';
}

YamiboHttpGateway _buildGateway(_RatingsTestAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com',
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return YamiboHttpGateway(
    cookieStore: CookieStore(),
    logger: Logger(
      printer: SimplePrinter(colors: false),
      output: _SilentLogOutput(),
      filter: ProductionFilter(),
    ),
    dio: dio,
    enableLog: false,
  );
}

final class _RatingsTestAdapter implements HttpClientAdapter {
  _RatingsTestAdapter(this.body);

  final String body;
  int requestCount = 0;
  Uri? lastUri;
  String? lastUserAgent;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount += 1;
    lastUri = options.uri;
    lastUserAgent = options.headers.entries
        .where((entry) => entry.key.toLowerCase() == 'user-agent')
        .map((entry) => entry.value?.toString())
        .firstOrNull;
    return ResponseBody.fromString(
      body,
      200,
      headers: const <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
      },
    );
  }
}

final class _SilentLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}
