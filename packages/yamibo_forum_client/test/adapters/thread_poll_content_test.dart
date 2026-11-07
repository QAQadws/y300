import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';
import 'package:yamibo_forum_client/src/adapters/thread_detail_snapshot_codec.dart';

String _page(String options, {required bool mobile}) => mobile
    ? '<body id="forum"><div class="viewthread"><div class="plc" id="pid1">'
          '<div class="authi"><div class="mtit"><span class="y">1#</span></div></div>'
          '<div class="message"><div class="poll"><form id="poll">'
          '<div class="poll_txt">单选投票，共有 2 人参与投票</div>'
          '<div class="poll_box">$options</div></form></div></div></div></div></body>'
    : '<body><div id="postlist"><div id="post_1"><form id="poll">'
          '<div class="pinf">单选投票，共有 2 人参与投票</div>'
          '<table summary="poll panel">$options</table></form>'
          '<div id="postmessage_1">Post</div></div></div></body>';

String _option(String body, {required bool mobile, String id = '71'}) => mobile
    ? '<p><input type="radio" name="pollanswers[]" value="$id" id="option_$id">'
          '$body<em style="color:#aabbcc">50% (1票)</em></p>'
    : '<tr><td><input type="radio" name="pollanswers[]" value="$id" id="option_$id"></td>'
          '<td style="color:#112233">$body</td></tr>'
          '<tr><td><div class="pbr"><div style="width:50%;background-color:#aabbcc"></div></div>'
          '50% (1)</td></tr>';

ThreadDetailData _parse(String source) => ThreadDetailHtmlParser(
  siteOrigin: Uri.parse('https://example.test'),
).parse(source, fallbackTid: '100', fallbackPage: 1);

List<String> _tokens(dom.Node root) {
  final result = <String>[];
  void visit(dom.Node node) {
    if (node is dom.Text) {
      final text = node.data.trim();
      if (text.isNotEmpty) result.add(text);
    } else if (node is dom.Element && node.localName == 'img') {
      result.add('image:${node.attributes['src']}');
    } else if (node is dom.Element && node.localName == 'br') {
      result.add('break');
    } else {
      for (final child in node.nodes) {
        visit(child);
      }
    }
  }

  visit(root);
  return result;
}

void main() {
  for (final mobile in [true, false]) {
    final platform = mobile ? 'mobile' : 'desktop';
    test('$platform retains all image occurrences and text outside the label', () {
      final detail = _parse(
        _page(
          _option(
            '<img file="/before.png" src="placeholder.gif">'
            '<label for="option_71"><b>1</b>. <span style="color:red">A</span>'
            '<img src="/same.png"><br><a href="https://example.test/read">B</a></label>'
            '<img src="/same.png">C',
            mobile: mobile,
          ),
          mobile: mobile,
        ),
      );
      final poll = detail.posts.single.poll!;
      final option = poll.options.single;
      expect(option.id, '71');
      expect(option.label, 'ABC');
      expect(option.voteCount, 1);
      expect(option.percent, 50);
      expect(poll.canVote, isTrue);
      final content = html.parseFragment(option.contentHtml!);
      expect(_tokens(content), [
        'image:/before.png',
        'A',
        'image:/same.png',
        'break',
        'B',
        'image:/same.png',
        'C',
      ]);
      expect(content.querySelector('span[style="color:red"]'), isNotNull);
      expect(
        content.querySelector('a')?.attributes['href'],
        'https://example.test/read',
      );
      expect(
        content.querySelector('input, label, script, button, .pbr'),
        isNull,
      );
      expect(option.contentHtml, isNot(contains('50%')));
    });

    test(
      '$platform retains pure image choices with actual ids and descriptions',
      () {
        final detail = _parse(
          _page(
            _option(
                  '<label for="option_71">1.</label><img src="/a.png" alt="A">'
                  '<img src="/b.png" title="B">',
                  mobile: mobile,
                ) +
                _option(
                  '<label for="option_72">2.<img src="/c.png"></label>',
                  mobile: mobile,
                  id: '72',
                ),
            mobile: mobile,
          ),
        );
        final poll = detail.posts.single.poll!;
        expect(poll.options.map((option) => option.id), ['71', '72']);
        expect(poll.options.map((option) => option.label), ['A B', '']);
        expect(
          poll.options.map(
            (option) => html
                .parseFragment(option.contentHtml!)
                .querySelectorAll('img')
                .length,
          ),
          [2, 1],
        );
        expect(poll.canVote, isTrue);
      },
    );

    test(
      '$platform excludes controls, hidden content and jammer without mutating source',
      () {
        final source = html.parse(
          _page(
            _option(
              '<label for="option_71">1.<strong>Text</strong><font class="jammer">noise</font>'
              '<span hidden>hidden</span><img style="display:none" src="hidden.png">'
              '<script>private-token</script><button>vote</button></label>',
              mobile: mobile,
            ),
            mobile: mobile,
          ),
        );
        final original = source.outerHtml;
        final detail = ThreadDetailHtmlParser(
          siteOrigin: Uri.parse('https://example.test'),
        ).parseDocument(source, fallbackTid: '100', fallbackPage: 1);
        expect(source.outerHtml, original);
        final option = detail.posts.single.poll!.options.single;
        expect(option.label, 'Text');
        expect(_tokens(html.parseFragment(option.contentHtml!)), ['Text']);
        expect(option.contentHtml, isNot(contains('private-token')));
      },
    );

    test(
      '$platform snapshot preserves option HTML and missing legacy HTML stays absent',
      () {
        const codec = ThreadDetailSnapshotCodec();
        final detail = _parse(
          _page(
            _option(
              '<label for="option_71">1.<b>A &amp; B</b><img src="/a.png"></label>',
              mobile: mobile,
            ),
            mobile: mobile,
          ),
        );
        final encoded = codec.encode(detail) as Map<String, Object?>;
        final restored = codec
            .decode(encoded)
            .posts
            .single
            .poll!
            .options
            .single;
        expect(
          restored.contentHtml,
          detail.posts.single.poll!.options.single.contentHtml,
        );
        expect(restored.label, 'A & B');
        final post = (encoded['posts'] as List).single as Map;
        final option = ((post['poll'] as Map)['options'] as List).single as Map;
        option.remove('contentHtml');
        final legacy = codec.decode(encoded).posts.single.poll!.options.single;
        expect(legacy.contentHtml, isNull);
        expect(legacy.label, 'A & B');
        expect(
          codec.canDecodeVersion(codecVersion: 1, parserVersion: 2),
          isTrue,
        );
        option['contentHtml'] = 42;
        expect(
          codec.decode(encoded).posts.single.poll!.options.single.contentHtml,
          isNull,
        );
      },
    );
  }

  test('mobile statistics outside labels do not replace authored emphasis', () {
    final detail = _parse(
      _page(
        '<p><input type="radio" name="pollanswers[]" value="71">'
        '<label>1.<em style="color:red">50% (author)</em></label>'
        '<span><em>25%</em><em>(2票)</em></span></p>',
        mobile: true,
      ),
    );
    final option = detail.posts.single.poll!.options.single;
    expect(option.label, '50% (author)');
    expect(option.voteCount, 2);
    expect(option.percent, 25);
    expect(_tokens(html.parseFragment(option.contentHtml!)), ['50% (author)']);
  });

  test('desktop nested option tables cannot become extra poll result rows', () {
    final detail = _parse(
      _page(
        _option(
          '<label for="option_71">1.A<table><tr><td>B</td></tr></table>C</label>',
          mobile: false,
        ),
        mobile: false,
      ),
    );
    final option = detail.posts.single.poll!.options.single;
    expect(option.label, 'ABC');
    expect(option.voteCount, 1);
    expect(option.percent, 50);
    expect(
      html.parseFragment(option.contentHtml!).querySelector('table'),
      isNotNull,
    );
  });

  test(
    'cached raw HTML recovers option content and warms the same snapshot',
    () async {
      final origin = Uri.parse('https://example.test');
      final keys = ForumCacheKeyCanonicalizer(siteOrigin: origin);
      final documents = MemoryForumDocumentStore();
      final snapshots = MemoryForumSnapshotStore();
      const codec = ThreadDetailSnapshotCodec();
      final source = _page(
        _option(
          '<label for="option_71">1.A<img src="/a.png"></label>'
          '<img src="/b.png">',
          mobile: true,
        ),
        mobile: true,
      );
      final encoded = codec.encode(_parse(source)) as Map<String, Object?>;
      final option =
          ((((encoded['posts'] as List).single as Map)['poll']
                          as Map)['options']
                      as List)
                  .single
              as Map;
      option.remove('contentHtml');
      await snapshots.put(
        keys.threadDetailSnapshot(tid: '100', page: 1),
        codec.decode(encoded),
        codec,
        policy: const ForumSnapshotPolicy(
          freshFor: Duration.zero,
          keepStaleFor: Duration(days: 1),
        ),
      );
      final descriptor = keys.threadDetail(tid: '100', page: 1);
      final now = DateTime.now();
      await documents.put(
        ForumCachedDocument(
          descriptor: descriptor,
          body: source,
          fetchedAt: now,
          updatedAt: now,
        ),
      );
      final network = _OfflineNetwork();
      final reader = ForumClientAdapterFactory(
        config: ForumClientConfig(
          siteOrigin: origin,
          apiOrigin: origin.resolve('/api/mobile/index.php'),
          userAgent: 'test',
          desktopUserAgent: 'test',
        ),
        network: network,
        documentStore: documents,
        snapshotStore: snapshots,
      ).createHtmlThreadDetail();
      final first = (await reader.getThreadDetail(tid: '100')).dataOrNull!;
      expect(
        _tokens(
          html.parseFragment(
            first.posts.single.poll!.options.single.contentHtml!,
          ),
        ),
        ['A', 'image:/a.png', 'image:/b.png'],
      );
      expect(network.calls, 1);
      final warm = (await reader.getThreadDetail(tid: '100')).dataOrNull!;
      expect(
        warm.posts.single.poll!.options.single.contentHtml,
        first.posts.single.poll!.options.single.contentHtml,
      );
      expect(network.calls, 1);
    },
  );
}

final class _OfflineNetwork implements ForumClientNetwork {
  var calls = 0;
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    calls++;
    return const ForumTransportError(
      ForumTransportFailure(
        kind: ForumTransportFailureKind.network,
        code: 'offline',
      ),
    );
  }
}
