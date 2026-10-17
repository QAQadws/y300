import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

import 'package:yamibo_forum_client/src/parsing/discuz_html_document.dart';

import '../fixtures/message_attention_html_fixtures.dart';

final _origin = Uri.parse('https://forum.example.test');
const _marker = 'shared response marker';

void main() {
  final cases =
      <
        ({
          String name,
          String content,
          String selector,
          Future<String> Function(ForumClientAdapterFactory) read,
        })
      >[
        (
          name: 'thread detail',
          content: '''
<div class="viewthread"><div class="view_tit">Topic</div>
<div class="plc" id="pid7"><div class="message">Original body</div></div></div>
''',
          selector: '.message',
          read: (factory) async {
            final result = await factory
                .createHtmlThreadDetail()
                .getThreadDetail(tid: '1');
            expect(result.isSuccess, isTrue);
            return (result as DataReadSuccess).data.posts.single.message
                as String;
          },
        ),
        (
          name: 'forum display',
          content: '''
<div class="threadlist"><ul><li class="list">
<a href="forum.php?mod=viewthread&amp;tid=1"><div class="threadlist_tit">Original topic</div></a>
</li></ul></div>
''',
          selector: '.threadlist_tit',
          read: (factory) async {
            final result = await factory
                .createHtmlForumDisplay()
                .getForumDisplayByQuery(const ForumDisplayQuery(fid: '2'));
            expect(result.isSuccess, isTrue);
            return (result as DataReadSuccess).data.threads.single.subject
                as String;
          },
        ),
        (
          name: 'forum home',
          content: _directory,
          selector: '.mtit',
          read: (factory) async {
            final result = await factory.createHtmlForumHome().home.loadHome(
              const ForumHomeQuery(),
            );
            expect(result.isSuccess, isTrue);
            return (result as DataReadSuccess)
                    .data
                    .directory
                    .sections
                    .single
                    .forums
                    .single
                    .title
                as String;
          },
        ),
        (
          name: 'forum directory',
          content: _directory,
          selector: '.mtit',
          read: (factory) async {
            final result = await factory.createHtmlForumDirectory().load(
              const ForumDirectoryQuery(),
            );
            expect(result.isSuccess, isTrue);
            return (result as DataReadSuccess)
                    .data
                    .sections
                    .single
                    .forums
                    .single
                    .title
                as String;
          },
        ),
        (
          name: 'search',
          content: '''
<div class="threadlist"><ul><li class="list">
<a href="forum.php?mod=viewthread&amp;tid=1"><div class="threadlist_tit">Original topic</div></a>
</li></ul></div>
''',
          selector: '.threadlist_tit',
          read: (factory) async {
            final result = await factory
                .createForumSearch(const _Formhash())
                .load(const ForumSearchQuery(keyword: 'fixture'));
            expect(result.isSuccess, isTrue);
            return (result as DataReadSuccess).data.topics.single.title
                as String;
          },
        ),
        (
          name: 'tags',
          content: '''
<div id="pt"><a href="misc.php?mod=tag&amp;id=3">Original tag</a></div>
<div class="bm tl"><table></table></div>
''',
          selector: '#pt a',
          read: (factory) async {
            final result = await factory.createForumTagDirectory().load(
              const ForumTagDirectoryQuery(tagId: '3'),
            );
            expect(result.isSuccess, isTrue);
            return (result as DataReadSuccess).data.tag.name as String;
          },
        ),
      ];

  for (final entry in cases) {
    test(
      '${entry.name} consumes the observer DOM without rebuilding or mutating it',
      () async {
        final network = _Network(
          mobileAttentionHtml(
            messageDot: true,
            content: entry.content,
          ).replaceFirst('<body>', '<body id="forum">'),
        );
        final observer = _Observer(network, entry.selector);
        final factory = ForumClientAdapterFactory(
          config: ForumClientConfig(
            siteOrigin: _origin,
            apiOrigin: _origin.resolve('/api/mobile/index.php'),
            userAgent: 'test',
          ),
          network: network,
          messageAttentionObserver: observer,
        );

        // The observer changes only its already parsed DOM as a test probe. A
        // second parse of the untouched response body cannot see this marker.
        final output = await entry.read(factory);
        expect(output, contains(_marker));
        expect(observer.deliveries, 1);
        expect(network.sends, entry.name == 'search' ? 2 : 1);
        expect(network.response!.body, isNot(contains(_marker)));
        expect(
          DiscuzHtmlDocument.forResponse(network.response!).document.outerHtml,
          observer.observedHtml,
          reason: 'Business cleanup must clone its own subtrees.',
        );
      },
    );
  }

  test(
    'valid navigation publishes even when thread extraction fails',
    () async {
      final network = _Network(mobileAttentionHtml(messageDot: true));
      final observer = _Observer(network, '#ct p');
      final factory = ForumClientAdapterFactory(
        config: ForumClientConfig(
          siteOrigin: _origin,
          apiOrigin: _origin.resolve('/api/mobile/index.php'),
          userAgent: 'test',
        ),
        network: network,
        messageAttentionObserver: observer,
      );

      final result = await factory.createHtmlThreadDetail().getThreadDetail(
        tid: '1',
      );
      expect(result.failureOrNull?.code, 'thread_detail_posts_missing');
      expect(observer.deliveries, 1);
      expect(network.sends, 1);
    },
  );
}

const _directory = '''
<div class="forumlist">
<a class="subforumshow" href="#section"><h2>Section</h2></a>
<div id="section"><a class="murl" href="forum.php?mod=forumdisplay&amp;fid=2">
<span class="mtit">Original forum</span></a></div></div>
''';

final class _Network implements ForumClientNetwork {
  _Network(this.body);
  final String body;
  ForumResponse<Object?>? response;
  int sends = 0;

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    sends++;
    if (request.method == ForumRequestMethod.post) {
      return ForumTransportSuccess(
        ForumResponse<Object?>(
          uri: request.uri,
          statusCode: 302,
          headers: const {
            'location': ['search.php?mod=forum&searchid=7&searchsubmit=yes'],
          },
          body: '',
        ),
      );
    }
    return ForumTransportSuccess(
      response = ForumResponse<Object?>(
        uri: request.uri,
        statusCode: 200,
        headers: const {},
        body: body,
      ),
    );
  }
}

final class _Formhash implements ForumFormhashProvider {
  const _Formhash();

  @override
  Future<ForumFormhashResult> loadFormhash({
    bool preferProfile = true,
    ForumRequestCancellation? cancellation,
  }) async => const ForumFormhashSuccess('fixture-formhash');
}

final class _Observer implements ForumMessageAttentionObserver {
  _Observer(this.network, this.selector);
  final _Network network;
  final String selector;
  int deliveries = 0;
  String? observedHtml;

  @override
  ForumMessageAttentionRequestContext captureRequest() =>
      const ForumMessageAttentionRequestContext(
        viewerUserId: '42',
        requestSequence: 1,
        ownerToken: 'owner',
      );

  @override
  void onObservation(
    ForumMessageAttentionObservation observation, {
    required ForumMessageAttentionRequestContext context,
  }) {
    deliveries++;
    final document = DiscuzHtmlDocument.forResponse(network.response!).document;
    document.querySelector(selector)!.text = _marker;
    observedHtml = document.outerHtml;
  }
}
