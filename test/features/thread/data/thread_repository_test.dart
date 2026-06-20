import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/thread/data/thread_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('ThreadDetailHtmlRepository requests desktop viewthread HTML', () async {
    final adapter = _ThreadDetailHtmlTestAdapter();
    final repository = _buildRepository(adapter);

    final result = await repository.getThreadDetail(tid: '572529', page: 3);

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull!.subject, '测试帖子');
    expect(result.dataOrNull!.posts.single.author, 'alice');
    final requested = Uri.parse(adapter.requestedUris.single);
    expect(requested.origin, 'https://bbs.yamibo.com');
    expect(requested.path, '/forum.php');
    expect(requested.queryParameters['mod'], 'viewthread');
    expect(requested.queryParameters['tid'], '572529');
    expect(requested.queryParameters['page'], '3');
    expect(requested.queryParameters.containsKey('mobile'), isFalse);
    expect(adapter.userAgents.single, isNot(contains('Mobile')));
  });

  test(
    'ThreadDetailHtmlRepository wraps desktop HTML request failure',
    () async {
      final adapter = _ThreadDetailHtmlTestAdapter(statusCode: 503);
      final repository = _buildRepository(adapter);

      final result = await repository.getThreadDetail(tid: '572529');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.statusCode, 503);
      expect(result.errorOrNull?.message, contains('帖子详情 HTML 加载失败'));
    },
  );
}

ThreadDetailHtmlRepository _buildRepository(
  _ThreadDetailHtmlTestAdapter adapter,
) {
  final gateway = YamiboHttpGateway(
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
  return ThreadDetailHtmlRepository(
    htmlClient: YamiboHtmlClient(gateway: gateway),
  );
}

class _ThreadDetailHtmlTestAdapter implements HttpClientAdapter {
  _ThreadDetailHtmlTestAdapter({this.statusCode = 200});

  final int statusCode;
  final requestedUris = <String>[];
  final userAgents = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUris.add(options.uri.toString());
    userAgents.add(options.headers['User-Agent']?.toString() ?? '');
    return ResponseBody.fromString(
      statusCode == 200 ? _html : 'unavailable',
      statusCode,
    );
  }
}

const _html = '''
<html>
<body id="nv_forum" class="pg_viewthread">
  <a href="javascript:;" rel="curforum" fid="33" class="curtype">本版</a>
  <div id="postlist" class="pl bm">
    <table>
      <tr>
        <td class="pls"><div class="hm ptn"><span>查看:</span> <span>12</span><span>回复:</span> <span>1</span></div></td>
        <td class="plc ptm pbn vwthd">
          <h1 class="ts">
            <a href="forum.php?mod=forumdisplay&amp;fid=33&amp;filter=typeid&amp;typeid=410">[理性探讨]</a>
            <span id="thread_subject">测试帖子</span>
          </h1>
        </td>
      </tr>
    </table>
    <div id="post_1">
      <table id="pid1" class="plhin">
        <tr>
          <td class="pls">
            <div class="pi"><div class="authi"><a href="space-uid-10.html" class="xw1">alice</a></div></div>
            <div class="avatar"><a><img src="https://bbs.yamibo.com/avatar.jpg" class="user_avatar"></a></div>
          </td>
          <td class="plc">
            <div class="pi">
              <strong><a id="postnum1"><em>1</em><sup>#</sup></a></strong>
              <div class="pti"><div class="authi"><em id="authorposton1">发表于 2026-6-20 10:00</em></div></div>
            </div>
            <div class="pcb"><table><tr><td class="t_f" id="postmessage_1">正文</td></tr></table></div>
          </td>
        </tr>
      </table>
    </div>
  </div>
</body>
</html>
''';
