import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('locates a findpost target from returned desktop thread HTML', () async {
    final adapter = _ThreadPostLocatorAdapter(body: _threadPageHtml);
    final locator = HtmlThreadPostLocator(gateway: _buildGateway(adapter));

    final result = await locator.locate(
      tid: '572057',
      pid: '41560047',
      sourceUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=572057&pid=41560047',
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull?.tid, '572057');
    expect(result.dataOrNull?.pid, '41560047');
    expect(result.dataOrNull?.page, 3);
    expect(adapter.requestedUris.single.queryParameters['goto'], 'findpost');
    expect(adapter.followRedirects.single, isTrue);
  });

  test('fails when the located page does not contain the target post', () async {
    final adapter = _ThreadPostLocatorAdapter(body: _threadPageHtml);
    final locator = HtmlThreadPostLocator(gateway: _buildGateway(adapter));

    final result = await locator.locate(
      tid: '572057',
      pid: '99999999',
      sourceUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=572057&pid=99999999',
      ),
    );

    expect(result.isFailure, isTrue);
    expect(result.errorOrNull?.message, contains('目标楼层未出现在定位结果中'));
  });
}

YamiboHttpGateway _buildGateway(_ThreadPostLocatorAdapter adapter) {
  return YamiboHttpGateway(
    cookieStore: CookieStore(),
    logger: Logger(level: Level.off),
    dio: Dio(
      BaseOptions(
        baseUrl: 'https://bbs.yamibo.com',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    )..httpClientAdapter = adapter,
    enableLog: false,
  );
}

class _ThreadPostLocatorAdapter implements HttpClientAdapter {
  _ThreadPostLocatorAdapter({required this.body});

  final String body;
  final requestedUris = <Uri>[];
  final followRedirects = <bool>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUris.add(options.uri);
    followRedirects.add(options.followRedirects);
    return ResponseBody.fromString(
      body,
      200,
      headers: const <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
      },
    );
  }
}

const _threadPageHtml = '''
<html>
<body id="nv_forum" class="pg_viewthread">
  <div class="pg"><strong>3</strong><a class="nxt" href="thread-572057-4-1.html">下一页</a></div>
  <div id="postlist" class="pl bm">
    <table>
      <tr>
        <td class="pls"><div class="hm ptn"><span>查看:</span><span>12</span><span>回复:</span><span>6</span></div></td>
        <td class="plc ptm pbn vwthd">
          <h1 class="ts"><span id="thread_subject">楼层跳转测试</span></h1>
        </td>
      </tr>
    </table>
    <div id="post_41560047">
      <table id="pid41560047" class="plhin">
        <tr>
          <td class="pls">
            <div class="pi"><div class="authi"><a href="space-uid-10.html" class="xw1">alice</a></div></div>
          </td>
          <td class="plc">
            <div class="pi">
              <strong><a id="postnum41560047"><em>21</em><sup>#</sup></a></strong>
              <div class="pti"><div class="authi"><em id="authorposton41560047">发表于 2026-6-20 10:00</em></div></div>
            </div>
            <div class="pcb">
              <table><tr><td class="t_f" id="postmessage_41560047">目标楼层正文</td></tr></table>
            </div>
          </td>
        </tr>
      </table>
    </div>
  </div>
</body>
</html>
''';
