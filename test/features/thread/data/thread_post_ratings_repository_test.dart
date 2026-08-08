import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/thread/data/repositories/thread_post_ratings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ThreadPostRatingsHtmlParser', () {
    test('parses Discuz AJAX CDATA rating fragment', () {
      const parser = ThreadPostRatingsHtmlParser();

      final details = parser.parse(_ajaxRatingsResponse());

      expect(details.participantCount, 12);
      expect(details.totalScoreText, '积分 +149 点');
      expect(details.ratings.first.userName, 'Sylvie0721');
      expect(details.ratings.first.score, '+2');
      expect(details.ratings.first.dateline, '2026-8-1 15:32');
      expect(details.ratings.first.reason, '我很赞同');
      expect(details.ratings[1].reason, isEmpty);
      expect(details.ratings.last.userName, 'Ando.');
    });

    test('sums scores when the AJAX total row is absent', () {
      const parser = ThreadPostRatingsHtmlParser();

      final details = parser.parse(_ajaxRatingsResponse(includeTotal: false));

      expect(details.totalScoreText, '积分 +149 点');
    });

    test('requires the root CDATA envelope and rating table', () {
      const parser = ThreadPostRatingsHtmlParser();

      expect(
        () => parser.parse(_ratingsTableHtml()),
        throwsA(isA<ThreadPostRatingsParseException>()),
      );
      expect(
        () => parser.parse(
          '<?xml version="1.0"?><root><![CDATA[<div class="f_c">empty</div>]]></root>',
        ),
        throwsA(isA<ThreadPostRatingsParseException>()),
      );
      expect(
        () => parser.parse(_ajaxRatingsResponse(tableClass: 'other')),
        throwsA(isA<ThreadPostRatingsParseException>()),
      );
    });

    test('does not accept the previous mobile list response', () {
      const parser = ThreadPostRatingsHtmlParser();

      expect(
        () => parser.parse('<ul class="post_box"><li>old response</li></ul>'),
        throwsA(isA<ThreadPostRatingsParseException>()),
      );
    });
  });

  group('DiscuzThreadPostRatingsRepository', () {
    test('loads the fixed AJAX rating fragment endpoint', () async {
      final adapter = _RatingsTestAdapter(_ajaxRatingsResponse());
      final repository = DiscuzThreadPostRatingsRepository(
        gateway: _buildGateway(adapter),
      );

      final result = await repository.loadAll(
        'https://bbs.yamibo.com/forum.php?mod=misc&action=viewratings&tid=573833&pid=41584212&mobile=2&ignored=value',
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.ratings, hasLength(12));
      expect(adapter.requestCount, 1);
      expect(adapter.lastUri?.path, '/forum.php');
      expect(adapter.lastUri?.queryParameters, <String, String>{
        'mod': 'misc',
        'action': 'viewratings',
        'tid': '573833',
        'pid': '41584212',
        'infloat': 'yes',
        'handlekey': 'viewratings',
        'inajax': '1',
        'ajaxtarget': 'fwin_content_viewratings',
      });
      expect(
        adapter.lastUserAgent,
        DiscuzImageRequestHeaderBuilder.browserUserAgent,
      );
      expect(adapter.header('referer'), contains('mod=viewthread'));
      expect(adapter.header('referer'), contains('tid=573833'));
    });

    test('rejects cross-site and incomplete URLs before networking', () async {
      final adapter = _RatingsTestAdapter(_ajaxRatingsResponse());
      final repository = DiscuzThreadPostRatingsRepository(
        gateway: _buildGateway(adapter),
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

String _ajaxRatingsResponse({
  bool includeTotal = true,
  String tableClass = 'list',
}) {
  final total = includeTotal
      ? '<div class="o pns">总计:&nbsp;积分 +149 点&nbsp;</div>'
      : '';
  return '''
<?xml version="1.0"?>
<root>
<![CDATA[
<div class="f_c">
  <h3 class="flb"><em id="return_viewratings">查看全部评分</em></h3>
  <div class="c floatwrap">
    <table class="$tableClass" cellspacing="0" cellpadding="0">
      <thead>
        <tr><td>积分</td><td>用户名</td><td>时间</td><td>理由</td></tr>
      </thead>
      <tr><td>积分 +2 点</td><td><a href="space-uid-743407.html">Sylvie0721</a></td><td>2026-8-1 15:32</td><td>我很赞同</td></tr>
      <tr><td>积分 +2 点</td><td><a href="space-uid-742772.html">喜欢闲着</a></td><td>2026-7-29 13:48</td><td></td></tr>
      <tr><td>积分 +5 点</td><td><a href="space-uid-615797.html">krelinnbios</a></td><td>2026-7-26 19:36</td><td></td></tr>
      <tr><td>积分 +99 点</td><td><a href="space-uid-8.html">筱林透</a></td><td>2026-7-25 19:28</td><td></td></tr>
      <tr><td>积分 +5 点</td><td><a href="space-uid-656245.html">abcdefg39</a></td><td>2026-7-24 01:44</td><td></td></tr>
      <tr><td>积分 +5 点</td><td><a href="space-uid-682586.html">花生酱酱酱</a></td><td>2026-7-20 17:55</td><td>我很赞同</td></tr>
      <tr><td>积分 +5 点</td><td><a href="space-uid-607769.html">keepy</a></td><td>2026-7-20 02:58</td><td>好强好强</td></tr>
      <tr><td>积分 +5 点</td><td><a href="space-uid-491520.html">tomaron</a></td><td>2026-7-19 20:30</td><td></td></tr>
      <tr><td>积分 +4 点</td><td><a href="space-uid-277164.html">小狮子cylinder</a></td><td>2026-7-19 13:12</td><td></td></tr>
      <tr><td>积分 +5 点</td><td><a href="space-uid-728650.html">青柠味香气</a></td><td>2026-7-19 07:58</td><td></td></tr>
      <tr><td>积分 +10 点</td><td><a href="space-uid-651603.html">wmsywl1</a></td><td>2026-7-18 23:46</td><td>我很赞同</td></tr>
      <tr><td>积分 +2 点</td><td><a href="space-uid-698995.html">Ando.</a></td><td>2026-7-18 20:29</td><td></td></tr>
    </table>
  </div>
  $total
</div>
]]>
</root>
''';
}

String _ratingsTableHtml() {
  return '''
<div class="f_c">
  <table class="list">
    <tr><td>积分</td><td>用户名</td><td>时间</td><td>理由</td></tr>
    <tr><td>积分 +2 点</td><td>alice</td><td>2026-1-1</td><td></td></tr>
  </table>
</div>
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
  Map<String, dynamic> lastHeaders = const <String, dynamic>{};

  String? header(String name) {
    final entry = lastHeaders.entries.where(
      (entry) => entry.key.toLowerCase() == name.toLowerCase(),
    );
    return entry.isEmpty ? null : entry.first.value?.toString();
  }

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
    lastHeaders = Map<String, dynamic>.from(options.headers);
    lastUserAgent = options.headers.entries
        .where((entry) => entry.key.toLowerCase() == 'user-agent')
        .map((entry) => entry.value?.toString())
        .firstOrNull;
    return ResponseBody.fromString(
      body,
      200,
      headers: const <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/xml; charset=utf-8'],
      },
    );
  }
}

final class _SilentLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}
