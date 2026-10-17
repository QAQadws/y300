import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

import '../fixtures/message_attention_html_fixtures.dart';

void main() {
  final shells = <String, String>{
    'custom touch': mobileAttentionHtml(messageDot: true),
    'default touch profile-only': mobileAttentionHtml(
      defaultTouchProfileOnly: true,
      profileDot: true,
    ),
    'custom desktop': desktopAttentionHtml(privateMessageDot: true),
    'default desktop': desktopAttentionHtml(
      defaultTemplate: true,
      privateMessageDot: true,
    ),
  };
  final newlySupportedPages = <String>[
    '/search.php?mod=forum&searchid=9&searchsubmit=yes&page=2',
    '/search.php?mod=curforum&srhfid=6&searchid=9&searchsubmit=yes',
    '/misc.php?mod=tag&id=3&page=2',
    '/misc.php?mod=faq&action=faq&id=3',
    '/portal.php?mod=view&aid=4',
    '/group.php?mod=my&view=groupthread',
    '/forum.php?mod=post&action=newthread&fid=6',
    '/forum.php?mod=post&action=reply&tid=7',
    '/forum.php?mod=post&action=edit&tid=7&pid=8&cedit=yes',
    '/home.php?mod=spacecp&ac=blog&blogid=9',
    '/home.php?mod=spacecp&ac=friend&op=add&uid=8',
    '/thread-7-2-1.html',
    '/forum-6-2.html',
    '/article-4-2.html',
    '/blog-8-9.html',
    '/space-uid-8.html?do=profile',
  ];

  for (final shell in shells.entries) {
    group('${shell.key} network observation', () {
      for (final path in newlySupportedPages) {
        test('samples the existing successful read once: $path', () async {
          final uri = _site.resolve(path);
          final response = _success(shell.value, uri);
          final network = _Network(response);
          final observer = _Observer();
          final request = _request(uri);
          final result = await _client(network, observer).network.send(request);

          expect(result, same(response));
          expect(network.requests.single, same(request));
          expect(response.response.body, same(shell.value));
          expect(observer.captures, 1);
          expect(observer.deliveries.single.observation.viewerUserId, '42');
          expect(
            observer.deliveries.single.observation.combined,
            ForumMessageAttentionState.present,
          );
          expect(observer.deliveries.single.context, same(observer.context));
        });
      }

      for (final path in <String>[
        '/home.php?mod=space&do=pm',
        '/home.php?mod=space&do=notice',
        '/home.php?mod=follow&do=follower',
        '/home.php?mod=space&do=follow&uid=42',
      ]) {
        test(
          'a consuming request cannot be rescued by a safe final URI: $path',
          () async {
            final network = _Network(
              _success(shell.value, _site.resolve(newlySupportedPages.first)),
            );
            final observer = _Observer();
            await _client(
              network,
              observer,
            ).network.send(_request(_site.resolve(path)));

            expect(network.requests, hasLength(1));
            expect(observer.captures, 0);
            expect(observer.deliveries, isEmpty);
          },
        );

        test(
          'a safe request cannot sample a consuming final URI: $path',
          () async {
            final network = _Network(
              _success(shell.value, _site.resolve(path)),
            );
            final observer = _Observer();
            await _client(
              network,
              observer,
            ).network.send(_request(_site.resolve(newlySupportedPages.first)));

            expect(network.requests, hasLength(1));
            expect(observer.captures, 1);
            expect(observer.deliveries, isEmpty);
          },
        );
      }

      for (final path in <String>[
        '/plugin.php?id=unknown:page',
        '/forum.php?mod=post&action=reply&tid=7&replysubmit=yes',
        '/forum.php?mod=post&action=edit&tid=7&editsubmit=yes',
        '/forum.php?mod=group&action=join&fid=6',
        '/home.php?mod=spacecp&ac=friend&op=addconfirm&key=opaque',
        '/home.php?mod=spacecp&ac=pm&op=checknewpm',
        '/misc.php?mod=tag&id=3&inajax=1',
        '/home.php?mod=space&do=index&uid=8&additional=removevlog',
        '/space-uid-8.html',
        '/thread-7-2-1.html?mod=post&action=reply',
      ]) {
        test(
          'full public chrome does not turn an excluded GET into a sample: $path',
          () async {
            final uri = _site.resolve(path);
            final response = _success(shell.value, uri);
            final network = _Network(response);
            final observer = _Observer();
            expect(
              await _client(network, observer).network.send(_request(uri)),
              same(response),
            );
            expect(observer.captures, 0);
            expect(observer.deliveries, isEmpty);
          },
        );
      }

      test(
        'a final response outside the configured origin remains unknown',
        () async {
          final network = _Network(
            _success(
              shell.value,
              Uri.parse('https://other.example.test/misc.php?mod=tag&id=3'),
            ),
          );
          final observer = _Observer();
          await _client(
            network,
            observer,
          ).network.send(_request(_site.resolve(newlySupportedPages.first)));
          expect(observer.captures, 1);
          expect(observer.deliveries, isEmpty);
        },
      );
    });
  }

  for (final entry in <String, String>{
    'nofooter': mobileAttentionHtml(includeFooter: false),
    'profile-only negative': mobileAttentionHtml(defaultTouchProfileOnly: true),
    'desktop without public message entries': attentionHtmlDocument(
      '<div id="toptb"><a href="home.php?mod=space">Viewer</a></div>',
    ),
    'error shell': mobileAttentionHtml(
      content: '<div id="messagetext">Request failed.</div>',
    ),
    'mobile error shell': mobileAttentionHtml(
      content: '<div class="jump_c">Request failed.</div>',
    ),
    'wrong viewer': mobileAttentionHtml(viewerUserId: '43', messageDot: true),
    'truncated page': mobileAttentionHtml().replaceFirst('</html>', ''),
  }.entries) {
    test('${entry.key} does not manufacture negative evidence', () async {
      final uri = _site.resolve('/misc.php?mod=tag&id=3');
      final response = _success(entry.value, uri);
      final network = _Network(response);
      final observer = _Observer();
      expect(
        await _client(network, observer).network.send(_request(uri)),
        same(response),
      );
      expect(observer.captures, 1);
      expect(observer.deliveries, isEmpty);
    });
  }

  for (final pageKind in <String>['authentication', 'formhash']) {
    test(
      'a newly supported read still respects the $pageKind exclusion',
      () async {
        final uri = _site.resolve('/home.php?mod=spacecp&ac=blog');
        final network = _Network(_success(mobileAttentionHtml(), uri));
        final observer = _Observer();
        await _client(network, observer).network.send(
          ForumRequest(
            method: ForumRequestMethod.get,
            uri: uri,
            context: ForumRequestContext(
              operation: 'fixture.html',
              pageKind: pageKind,
            ),
          ),
        );
        expect(observer.captures, 0);
        expect(observer.deliveries, isEmpty);
      },
    );
  }
}

final _site = Uri.parse('https://forum.example.test');

ForumRequest _request(Uri uri) => ForumRequest(
  method: ForumRequestMethod.get,
  uri: uri,
  context: const ForumRequestContext(operation: 'fixture.html'),
);

ForumTransportSuccess<ForumResponse<Object?>> _success(String body, Uri uri) =>
    ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: uri,
        statusCode: 200,
        headers: const <String, List<String>>{},
        body: body,
      ),
    );

YamiboForumClient _client(_Network network, _Observer observer) =>
    YamiboForumClientBuilder(
      config: ForumClientConfig(
        siteOrigin: _site,
        apiOrigin: _site.resolve('/api/mobile/index.php'),
      ),
      network: network,
      messageAttentionObserver: observer,
    ).buildStandardClient();

final class _Network implements ForumClientNetwork {
  _Network(this.result);

  final ForumTransportResult<ForumResponse<Object?>> result;
  final requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    return result;
  }
}

final class _Observer implements ForumMessageAttentionObserver {
  final context = const ForumMessageAttentionRequestContext(
    viewerUserId: '42',
    requestSequence: 1,
    ownerToken: 'fixture-owner',
  );
  var captures = 0;
  final deliveries =
      <
        ({
          ForumMessageAttentionObservation observation,
          ForumMessageAttentionRequestContext context,
        })
      >[];

  @override
  ForumMessageAttentionRequestContext? captureRequest() {
    captures++;
    return context;
  }

  @override
  void onObservation(
    ForumMessageAttentionObservation observation, {
    required ForumMessageAttentionRequestContext context,
  }) => deliveries.add((observation: observation, context: context));
}
