import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/forum/data/forum_display_repository.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('ForumDisplayHtmlRepository requests mobile forumdisplay HTML', () async {
    final adapter = _ForumDisplayHtmlTestAdapter();
    final repository = _buildRepository(adapter);

    final result = await repository.getForumDisplay(fid: '30', page: 2);

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull!.forumName, '中文百合漫画区');
    expect(result.dataOrNull!.threads.single.tid, '572604');
    final requested = Uri.parse(adapter.requestedUris.single);
    expect(requested.origin, 'https://bbs.yamibo.com');
    expect(requested.path, '/forum.php');
    expect(requested.queryParameters['mod'], 'forumdisplay');
    expect(requested.queryParameters['fid'], '30');
    expect(requested.queryParameters['page'], '2');
    expect(requested.queryParameters['mobile'], '2');
    expect(adapter.userAgents.single, contains('Mobile'));
  });

  test('ForumDisplayHtmlRepository keeps forumdisplay query parameters', () async {
    final adapter = _ForumDisplayHtmlTestAdapter();
    final repository = _buildRepository(adapter);

    final result = await repository.getForumDisplayByQuery(
      const ForumDisplayQuery(
        fid: '30',
        page: 3,
        parameters: <String, String>{
          'filter': 'typeid',
          'typeid': '69',
          'orderby': 'lastpost',
        },
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(adapter.requestedUris.single, contains('mod=forumdisplay'));
    expect(adapter.requestedUris.single, contains('fid=30'));
    expect(adapter.requestedUris.single, contains('page=3'));
    expect(adapter.requestedUris.single, contains('filter=typeid'));
    expect(adapter.requestedUris.single, contains('typeid=69'));
    expect(adapter.requestedUris.single, contains('orderby=lastpost'));
    expect(adapter.requestedUris.single, contains('mobile=2'));
  });

  test('ForumDisplayHtmlRepository wraps HTML request failure', () async {
    final adapter = _ForumDisplayHtmlTestAdapter(statusCode: 503);
    final repository = _buildRepository(adapter);

    final result = await repository.getForumDisplay(fid: '30');

    expect(result.isFailure, isTrue);
    expect(result.errorOrNull?.statusCode, 503);
    expect(result.errorOrNull?.message, contains('帖子列表 HTML 加载失败'));
  });
}

ForumDisplayHtmlRepository _buildRepository(
  _ForumDisplayHtmlTestAdapter adapter,
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
  return ForumDisplayHtmlRepository(
    htmlClient: YamiboHtmlClient(gateway: gateway),
  );
}

class _ForumDisplayHtmlTestAdapter implements HttpClientAdapter {
  _ForumDisplayHtmlTestAdapter({this.statusCode = 200});

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
<head><title>中文百合漫画区 - 百合会</title></head>
<body id="forum">
  <div class="forumdisplay-top cl">
    <h2><img src="data/attachment/common/34/common_30_icon.gif" alt="中文百合漫画区" />中文百合漫画区</h2>
    <p>今日: <span>105</span>主题: <span>52718</span>排名: <span>1</span></p>
  </div>
  <div class="threadlist_box mt10 cl">
    <div class="threadlist cl">
      <ul>
        <li class="list">
          <div class="threadlist_top cl">
            <a href="home.php?mod=space&amp;uid=732009&amp;mobile=2" class="mimg">
              <img src="https://bbs.yamibo.com/avatar.jpg">
            </a>
            <div class="muser">
              <h3><a href="home.php?mod=space&amp;uid=732009&amp;mobile=2" class="mmc">nkdndixnx</a></h3>
              <span class="mtime">2026-6-18 14:42</span>
            </div>
          </div>
          <a href="forum.php?mod=viewthread&amp;tid=572604&amp;mobile=2">
            <div class="threadlist_tit cl"><em>测试帖子</em></div>
          </a>
          <a href="forum.php?mod=viewthread&amp;tid=572604&amp;mobile=2">
            <div class="threadlist_mes cl">测试摘要</div>
          </a>
          <div class="threadlist_foot cl">
            <ul>
              <li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=typeid&amp;typeid=69&amp;mobile=2">#長篇連載</a></li>
              <li><i class="dm-eye-fill"></i>119</li>
              <li><i class="dm-chat-s-fill"></i>0</li>
            </ul>
          </div>
        </li>
      </ul>
    </div>
    <div class="pg"><strong>2</strong></div>
  </div>
</body>
</html>
''';
