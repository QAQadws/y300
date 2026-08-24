import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  late _TextNetwork network;
  late ForumClientAdapterFactory factory;

  setUp(() {
    network = _TextNetwork();
    factory = ForumClientAdapterFactory(
      config: ForumClientConfig(
        siteOrigin: Uri.parse('https://example.test'),
        apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
        userAgent: 'mobile-test',
        desktopUserAgent: 'desktop-test',
      ),
      network: network,
    );
  });

  test('HTML forum display returns stable identity and rich summary', () async {
    network.body = _forumDisplayHtml;

    final result = await factory
        .createHtmlForumDisplay()
        .getForumDisplayByQuery(const ForumDisplayQuery(fid: '30', page: 2));

    final success =
        result
            as DataReadSuccess<ForumDisplayData, ForumDisplayReadCapabilities>;
    expect(success.data.fid, '30');
    expect(success.data.threads.single.tid, '572604');
    expect(success.data.threads.single.author, 'fixture-author');
    expect(success.metadata, isA<DataReadMetadata>());
    expect(success.metadata.origin, DataReadOrigin.network);
    expect(network.requests.single.uri.queryParameters['fid'], '30');
    expect(network.requests.single.uri.queryParameters['page'], '2');
  });

  test(
    'API forum display rejects unsupported query before transport',
    () async {
      final result = await factory
          .createApiForumDisplay()
          .getForumDisplayByQuery(
            const ForumDisplayQuery(
              fid: '30',
              parameters: {'filter': 'typeid'},
            ),
          );

      expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
      expect(network.requests, isEmpty);
    },
  );

  test('HTML thread detail provides stable ordered posts', () async {
    network.body = _threadHtml;

    final result = await factory.createHtmlThreadDetail().getThreadDetail(
      tid: '100',
    );

    final success =
        result
            as DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>;
    expect(success.data.tid, '100');
    expect(success.data.fid, '33');
    expect(success.data.posts.single.pid, '1');
    expect(success.data.posts.single.isFirst, isTrue);
    expect(
      success.capabilities.supports(ThreadDetailCapability.ratingAction),
      isTrue,
    );
    expect(success.metadata.origin, DataReadOrigin.network);
  });

  test(
    'HTML thread detail fails closed for a document without posts',
    () async {
      network.body = '<html><body><h1>empty</h1></body></html>';

      final result = await factory.createHtmlThreadDetail().getThreadDetail(
        tid: '100',
      );

      expect(result.failureOrNull!.kind, DataReadFailureKind.parse);
    },
  );
}

final class _TextNetwork implements ForumClientNetwork {
  Object? body;
  final List<ForumRequest> requests = [];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    return ForumTransportSuccess(
      ForumResponse(
        uri: request.uri,
        statusCode: 200,
        headers: const {},
        body: body,
      ),
    );
  }
}

const _forumDisplayHtml = '''
<html><body id="forum">
  <div class="forumdisplay-top cl">
    <h2>Fixture forum</h2><p>今日: <span>1</span>主题: <span>2</span>排名: <span>3</span></p>
  </div>
  <div class="threadlist_box mt10 cl"><div class="threadlist cl"><ul>
    <li class="list">
      <div class="threadlist_top cl">
        <a href="home.php?mod=space&amp;uid=10" class="mimg"><img src="/avatar.jpg"></a>
        <div class="muser"><h3><a href="home.php?mod=space&amp;uid=10" class="mmc">fixture-author</a></h3>
        <span class="mtime">2026-01-01</span></div>
      </div>
      <a href="forum.php?mod=viewthread&amp;tid=572604"><div class="threadlist_tit cl"><em>Fixture topic</em></div></a>
      <a href="forum.php?mod=viewthread&amp;tid=572604"><div class="threadlist_mes cl">Summary</div></a>
      <div class="threadlist_foot cl"><ul><li><i class="dm-eye-fill"></i>12</li><li><i class="dm-chat-s-fill"></i>3</li></ul></div>
    </li>
  </ul></div><div class="pg"><strong>2</strong></div></div>
</body></html>
''';

const _threadHtml = '''
<html><body id="nv_forum" class="pg_viewthread">
  <a href="javascript:;" rel="curforum" fid="33" class="curtype">Forum</a>
  <div id="postlist" class="pl bm">
    <table><tr><td class="pls"><div class="hm ptn"><span>Views:</span><span>12</span><span>Replies:</span><span>1</span></div></td>
      <td class="plc ptm pbn vwthd"><h1 class="ts"><span id="thread_subject">Fixture thread</span></h1></td></tr></table>
    <div id="post_1"><table id="pid1" class="plhin"><tr>
      <td class="pls"><div class="pi"><div class="authi"><a href="space-uid-10.html" class="xw1">fixture-author</a></div></div></td>
      <td class="plc"><div class="pi"><strong><a id="postnum1"><em>1</em><sup>#</sup></a></strong>
        <div class="pti"><div class="authi"><em id="authorposton1">2026-01-01</em></div></div></div>
        <div class="pcb"><table><tr><td class="t_f" id="postmessage_1">Body</td></tr></table></div>
      </td>
    </tr></table></div>
  </div>
</body></html>
''';
