import 'dart:io';

import 'package:html/dom.dart';
import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_blog_access.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_blog_editor_form.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_blog_editor_media.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_blog_mutation_session.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_profile_html_parsers.dart';
import 'package:yamibo_forum_client/src/parsing/discuz_html_document.dart';

import '../support/blog_fixtures.dart';
import '../support/blog_operation_fixtures.dart';

void main() {
  test(
    'profile login check, sampling and projection use the response DOM',
    () async {
      final source = _shell('''
<div class="userinfo"><h2 class="name">Original profile</h2></div>
<div class="myinfo_list"><ul><li><b>Profile</b></li><li>UID<span>101</span></li></ul></div>
''');
      final network = _SharedResponseNetwork(source, (document) {
        document.querySelector('h2.name')!.text = 'Shared profile';
      });
      final observer = _Observer();
      final result = await _factory(network, observer)
          .createForumUserProfile()
          .load(
            const ForumUserProfileQuery(
              userId: '101',
              view: ForumUserProfileView.self,
            ),
          );
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.identity.displayName, 'Shared profile');
      expect(observer.samples, hasLength(1));
      network.expectUnchanged();
    },
  );

  test(
    'blog access checks and directory/detail projections reuse the DOM',
    () async {
      for (final detail in [false, true]) {
        final source = _shell(detail ? blogArticle() : blogFeed());
        final selector = detail ? '.view_tit' : '.threadlist_tit';
        final network = _SharedResponseNetwork(source, (document) {
          document.querySelector(selector)!.text = 'Shared blog';
        });
        final observer = _Observer();
        final factory = _factory(network, observer);
        if (detail) {
          final result = await factory.createUserBlogDetail().load(
            const UserBlogDetailQuery(ownerUserId: '101', blogId: '11'),
          );
          expect(result.failureOrNull, isNull);
          expect(result.dataOrNull!.title, 'Shared blog');
        } else {
          final result = await factory.createUserBlogDirectory().load(
            const UserBlogDirectoryQuery.public(),
          );
          expect(result.failureOrNull, isNull);
          expect(result.dataOrNull!.items.single.title, 'Shared blog');
        }
        expect(observer.samples, hasLength(1));
        network.expectUnchanged();
      }
    },
  );

  test(
    'user thread login/access checks and rows reuse the response DOM',
    () async {
      final source = _shell('''
<div class="header"><h2>我的主题</h2></div>
<div class="threadlist"><ul><li class="list">
<a href="forum.php?mod=viewthread&tid=42"><div class="threadlist_tit"><em>Original topic</em></div></a>
</li></ul></div>
''');
      final network = _SharedResponseNetwork(source, (document) {
        document.querySelector('.threadlist_tit em')!.text = 'Shared topic';
      });
      final observer = _Observer();
      final result = await _factory(network, observer)
          .createUserThreadDirectory()
          .load(const UserThreadDirectoryQuery(userId: '101'));
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.items.single.title, 'Shared topic');
      expect(observer.samples, hasLength(1));
      network.expectUnchanged();
    },
  );

  test(
    'account summary DOM sharing does not replay samples from snapshots',
    () async {
      final source = File(
        'test/fixtures/account_summary/desktop.html',
      ).readAsStringSync().replaceFirst('</body>', '${_footer('42')}</body>');
      final network = _SharedResponseNetwork(source, (document) {
        final heading = document.querySelector('.u_profile h2')!;
        heading.nodes.first.replaceWith(Text('Shared account'));
      });
      final observer = _Observer(uid: '42');
      final snapshots = MemoryForumSnapshotStore();
      final client = YamiboForumClientBuilder(
        config: blogConfig,
        network: network,
        snapshotStore: snapshots,
        messageAttentionObserver: observer,
      ).buildStandardClient();
      const query = CurrentAccountSummaryQuery(userId: '42');
      final fresh = await client.loadCurrentAccountSummary(query);
      expect(fresh.failureOrNull, isNull);
      expect(fresh.dataOrNull!.identity.displayName, 'Shared account');
      expect(observer.samples, hasLength(1));
      final cached = await client.readCachedCurrentAccountSummary(query);
      expect(cached!.data.identity.displayName, 'Shared account');
      expect(observer.samples, hasLength(1));
      expect(network.responses, hasLength(1));
      network.expectUnchanged();
    },
  );

  test(
    'mutation boundary retains the response context through editor consumers',
    () async {
      final sessions = MemoryForumSessionStore();
      await loginBlogActor(sessions, '101');
      final source = _shell(blogEditorForm());
      final network = _SharedResponseNetwork(source, (document) {
        document.querySelector('input[name="subject"]')!.attributes['value'] =
            'Shared editor';
      });
      final boundary = DiscuzBlogMutationSession(
        config: blogConfig,
        network: network,
        profiles: DefaultForumRequestProfileResolver(blogConfig),
        sessions: sessions,
      );
      final uri = blogConfig.siteOrigin.resolve(
        'home.php?mod=spacecp&ac=blog&op=edit&blogid=11&mobile=no',
      );
      final read = await boundary.read(
        uri,
        actor: '101',
        referer: uri,
        operation: 'fixture',
      );
      expect(read.failureOrNull, isNull);
      final context = read.dataOrNull!;
      expect(
        context,
        same(DiscuzHtmlDocument.forResponse(network.responses.single)),
      );
      final document = context.document;
      final before = document.outerHtml;
      expect(DiscuzProfileAuthPageDetector.isLoginDocument(document), isFalse);
      expect(
        DiscuzBlogAccess.failureDocument<Object?, Object?>(document),
        isNull,
      );
      final target = blogOperationTarget(UserBlogAction.edit);
      final form = DiscuzBlogEditorForm.parseDocument(
        document,
        siteOrigin: blogConfig.siteOrigin,
        target: target,
      );
      expect(form.fields['subject'], 'Shared editor');
      expect(
        DiscuzBlogEditorMedia.parseDocument(
          document,
          siteOrigin: blogConfig.siteOrigin,
          actor: '101',
        ),
        isNull,
      );
      expect(
        DiscuzBlogEditorMedia.smileysDocument(document, blogConfig.siteOrigin),
        isEmpty,
      );
      expect(document.outerHtml, before);
      expect(context.source, source);
      network.expectUnchanged();
    },
  );

  test(
    'login gates also consume the shared DOM before business projection',
    () async {
      final source = _shell('<p>Access fixture</p>');
      final network = _SharedResponseNetwork(source, (document) {
        document.body!.append(Element.tag('form')..id = 'loginform');
      });
      final factory = _factory(network, _Observer());
      final reads = [
        await factory.createForumUserProfile().load(
          const ForumUserProfileQuery(
            userId: '101',
            view: ForumUserProfileView.self,
          ),
        ),
        await factory.createUserBlogDirectory().load(
          const UserBlogDirectoryQuery.public(),
        ),
        await factory.createUserBlogDetail().load(
          const UserBlogDetailQuery(ownerUserId: '101', blogId: '11'),
        ),
        await factory.createUserThreadDirectory().load(
          const UserThreadDirectoryQuery(userId: '101'),
        ),
      ];
      for (final result in reads) {
        expect(result.failureOrNull!.kind, DataReadFailureKind.unauthorized);
      }
      expect(network.responses, hasLength(4));
      network.expectUnchanged();
    },
  );

  test(
    'blog parser String compatibility and Document entry preserve output and DOM',
    () {
      final source = _shell(blogArticle());
      final context = DiscuzHtmlDocument.fromSource(source);
      final before = context.document.outerHtml;
      final parser = UserBlogDetailHtmlParser(
        siteOrigin: blogConfig.siteOrigin,
      );
      const query = UserBlogDetailQuery(ownerUserId: '101', blogId: '11');
      final legacy = parser.parse(html: source, query: query);
      final shared = parser.parseDocument(context.document, query: query);
      expect(shared.title, legacy.title);
      expect(shared.bodyHtml, legacy.bodyHtml);
      expect(
        shared.comments.map((item) => (item.commentId, item.bodyHtml)),
        legacy.comments.map((item) => (item.commentId, item.bodyHtml)),
      );
      expect(shared.actions, legacy.actions);
      expect(shared.socialActions, legacy.socialActions);
      expect(context.document.outerHtml, before);
    },
  );
}

ForumClientAdapterFactory _factory(
  _SharedResponseNetwork network,
  _Observer observer,
) => ForumClientAdapterFactory(
  config: blogConfig,
  network: network,
  messageAttentionObserver: observer,
);

String _shell(String body) => '''<!doctype html><html><head>
<script>var STYLEID = '1', discuz_uid = '101';</script>
</head><body>$body${_footer('101')}</body></html>''';

String _footer(String uid) =>
    '''<div class="foot flex-box">
<a class="flex" href="index.php"><span>Home</span></a>
<a class="flex" href="home.php?mod=space&do=pm"><span class="foot-ico"><em class="mb"><i class="ico_msg"></i></em></span></a>
<a class="flex" href="home.php?mod=space&uid=$uid&do=profile&mycenter=1"><span class="foot-ico"><em class="me"></em></span></a>
</div>''';

final class _SharedResponseNetwork implements ForumClientNetwork {
  _SharedResponseNetwork(this.source, this.editDocument);
  final String source;
  final void Function(Document) editDocument;
  final responses = <ForumResponse<Object?>>[];
  final snapshots = <String>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    final response = ForumResponse<Object?>(
      uri: request.uri,
      statusCode: 200,
      headers: const {},
      body: source,
    );
    final document = DiscuzHtmlDocument.forResponse(response).document;
    // A sentinel exists only in the parsed DOM. Falling back to source text
    // would erase it, detecting hidden reparses without production test hooks.
    editDocument(document);
    responses.add(response);
    snapshots.add(document.outerHtml);
    return ForumTransportSuccess(response);
  }

  void expectUnchanged() {
    for (var index = 0; index < responses.length; index++) {
      final response = responses[index];
      expect(response.body, source);
      expect(
        DiscuzHtmlDocument.forResponse(response).document.outerHtml,
        snapshots[index],
      );
    }
  }
}

final class _Observer implements ForumMessageAttentionObserver {
  _Observer({this.uid = '101'});
  final String uid;
  final samples = <ForumMessageAttentionObservation>[];
  int _sequence = 0;

  @override
  ForumMessageAttentionRequestContext? captureRequest() =>
      ForumMessageAttentionRequestContext(
        viewerUserId: uid,
        requestSequence: ++_sequence,
        ownerToken: this,
      );

  @override
  void onObservation(
    ForumMessageAttentionObservation observation, {
    required ForumMessageAttentionRequestContext context,
  }) => samples.add(observation);
}
