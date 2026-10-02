import 'dart:async';
import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import '../support/blog_favorite_fixtures.dart';
import '../support/blog_fixtures.dart';
import '../support/blog_operation_fixtures.dart';

void main() {
  late MemoryForumSessionStore sessions;
  setUp(() async {
    sessions = MemoryForumSessionStore();
    await loginBlogActor(sessions, '101');
  });
  YamiboForumClient client(BlogFavoriteNetwork network) =>
      YamiboForumClientBuilder(
        config: blogConfig,
        network: network,
        sessionStore: sessions,
      ).buildStandardClient();
  UserBlogFavoriteService service(BlogFavoriteNetwork network) =>
      client(network).blogFavorites!;

  test(
    'source overlays preserve and independently replace bookmark services',
    () {
      final original = service(BlogFavoriteNetwork());
      final replacement = service(BlogFavoriteNetwork());
      final plan = ForumClientSourcePlan(blogFavorites: original);
      expect(
        plan.overlay(const ForumClientSourcePlan()).blogFavorites,
        same(original),
      );
      expect(
        plan
            .overlay(ForumClientSourcePlan(blogFavorites: replacement))
            .blogFavorites,
        same(replacement),
      );
    },
  );

  test(
    'any signed-in reader may bookmark another author without impersonating them',
    () async {
      await loginBlogActor(sessions, '102');
      final network = BlogFavoriteNetwork();
      network.article = network.article.replaceFirst(
        "discuz_uid = '101'",
        "discuz_uid = '102'",
      );
      network.form = network.form.replaceFirst(
        "discuz_uid = '101'",
        "discuz_uid = '102'",
      );
      final favorites = service(network);
      const target = UserBlogFavoriteTarget(
        actorUserId: '102',
        ownerUserId: '101',
        blogId: '11',
      );
      final ready = await favorites.prepare(target);
      expect(ready.failureOrNull, isNull);
      final result = await favorites.add(
        ready.dataOrNull!,
        actorUserId: '102',
        description: '',
      );
      expect(result.receiptOrNull!.target, target);
      expect(network.posts.single.uri.queryParameters['spaceuid'], '101');
    },
  );

  test(
    'a missing toolbar capability prevents even opening the bookmark form',
    () async {
      final network = BlogFavoriteNetwork();
      network.article = network.article.replaceFirst(
        'spaceuid=101',
        'spaceuid=102',
      );
      final result = await service(network).prepare(blogFavoriteTarget);
      expect(result.failureOrNull!.code, 'blog_favorite_denied');
      expect(network.requests, hasLength(1));
    },
  );

  test('a server-reported account mismatch cannot prepare a ticket', () async {
    final network = BlogFavoriteNetwork();
    network.form = network.form.replaceFirst(
      "discuz_uid = '101'",
      "discuz_uid = '102'",
    );
    final result = await service(network).prepare(blogFavoriteTarget);
    expect(result.failureOrNull!.kind, DataReadFailureKind.unauthorized);
    expect(network.posts, isEmpty);
  });

  test(
    'privacy and login gates still fail closed when handling a form notice',
    () async {
      for (final page in [
        '$blogOperationHeader<form id="loginform"></form>',
        '$blogOperationHeader<form id="invalueform"><input name="viewpwd"></form>',
      ]) {
        final network = BlogFavoriteNetwork()..form = page;
        final result = await service(network).prepare(blogFavoriteTarget);
        expect(result.dataOrNull, isNull);
        expect(network.requests, hasLength(2));
        expect(network.posts, isEmpty);
      }
    },
  );

  test(
    'standard facade verifies the article and form before posting the raw note once',
    () async {
      final network = BlogFavoriteNetwork();
      final favorites = service(network);
      final result = await favorites.prepare(blogFavoriteTarget);
      expect(result.failureOrNull, isNull);
      expect(network.requests, hasLength(2));
      expect(network.posts, isEmpty);
      expect(result.dataOrNull!.existingFavoriteId, isNull);
      const note = '原文 & <markup>\n second line  ';
      final saved = await favorites.add(
        result.dataOrNull!,
        actorUserId: '101',
        description: note,
      );
      expect(saved, isA<DataCommandApplied<UserBlogFavoriteReceipt>>());
      expect(saved.receiptOrNull!.target, blogFavoriteTarget);
      expect(saved.receiptOrNull!.favoriteId, '55');
      final post = network.posts.single;
      expect(post.uri.queryParameters, containsPair('spaceuid', '101'));
      expect(post.uri.queryParameters['op'], isNull);
      expect(post.body, {
        'favoritesubmit': 'true',
        'formhash': 'fixturehash',
        'description': note,
        'referer':
            'https://example.test/home.php?mod=space&uid=101&do=blog&id=11&mobile=2',
        'handlekey': 'y300_blog_favorite',
      });
      expect(post.context.silent, isTrue);
      expect(post.followRedirects, isFalse);
      expect(
        await favorites.add(
          result.dataOrNull!,
          actorUserId: '101',
          description: note,
        ),
        isA<DataCommandNotSent<UserBlogFavoriteReceipt>>(),
      );
      expect(network.posts, hasLength(1));
    },
  );

  test(
    'a notice requires an exact targeted existing-record read and never authorizes deletion',
    () async {
      final network = BlogFavoriteNetwork()
        ..form =
            '$blogOperationHeader<div class="jump_c"><p>Duplicate notice</p></div>';
      final favorites = service(network);
      final result = await favorites.prepare(blogFavoriteTarget);
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.existingFavoriteId, '55');
      expect(result.dataOrNull!.token, isNull);
      expect(network.requests.last.uri.queryParameters, {
        'mod': 'spacecp',
        'ac': 'favorite',
        'type': 'blog',
        'id': '11',
        'op': 'delete',
        'mobile': '2',
      });
      expect(network.requests, hasLength(3));
      expect(
        await favorites.add(
          result.dataOrNull!,
          actorUserId: '101',
          description: '',
        ),
        isA<DataCommandNotSent<UserBlogFavoriteReceipt>>(),
      );
      expect(network.posts, isEmpty);
    },
  );

  for (final existing in [
    '$blogOperationHeader<div class="jump_c"><p>No bookmark</p></div>',
    blogFavoriteForm(existing: true).replaceAll('favid=55', 'favid=0'),
    blogFavoriteForm(existing: true).replaceFirst('type=blog', 'type=thread'),
    blogFavoriteForm(
      existing: true,
    ).replaceFirst('favoriteform_55', 'favoriteform_66'),
    blogFavoriteForm(
      existing: true,
    ).replaceFirst('deletesubmit', 'favoritesubmit'),
    blogFavoriteForm(
      existing: true,
    ).replaceFirst("discuz_uid = '101'", "discuz_uid = '102'"),
  ]) {
    test('an unproved existing bookmark remains a failure', () async {
      final network = BlogFavoriteNetwork()
        ..form = '$blogOperationHeader<div class="jump_c">Already saved</div>'
        ..existing = existing;
      expect(
        (await service(network).prepare(blogFavoriteTarget)).dataOrNull,
        isNull,
      );
      expect(network.posts, isEmpty);
    });
  }

  for (final (label, change) in <(String, String Function(String))>[
    ('different owner', (s) => s.replaceFirst('spaceuid=101', 'spaceuid=102')),
    ('different article', (s) => s.replaceFirst('id=11', 'id=99')),
    ('duplicate article', (s) => s.replaceFirst('id=11', 'id=11&id=99')),
    (
      'delete action',
      (s) => s.replaceFirst('ac=favorite', 'ac=favorite&op=delete'),
    ),
    (
      'foreign destination',
      (s) => s.replaceFirst(
        'action="home.php',
        'action="https://outside.test/home.php',
      ),
    ),
    (
      'http downgrade',
      (s) => s.replaceFirst(
        'action="home.php',
        'action="http://example.test/home.php',
      ),
    ),
    (
      'different port',
      (s) => s.replaceFirst(
        'action="home.php',
        'action="https://example.test:444/home.php',
      ),
    ),
    (
      'missing flag',
      (s) => s.replaceFirst('name="favoritesubmit"', 'name="unused"'),
    ),
    ('wrong method', (s) => s.replaceFirst('method="post"', 'method="get"')),
    ('empty hash', (s) => s.replaceFirst('value="fixturehash"', 'value=""')),
    (
      'duplicate hash',
      (s) => s.replaceFirst(
        '</form>',
        '<input type="hidden" name="formhash" value="other"></form>',
      ),
    ),
    (
      'captcha',
      (s) => s.replaceFirst('</form>', '<input name="seccodeverify"></form>'),
    ),
    (
      'plugin',
      (s) => s.replaceFirst('</form>', '<input name="plugin_field"></form>'),
    ),
    (
      'custom submit code',
      (s) => s.replaceFirst(
        'method="post"',
        'method="post" onsubmit="preparePlugin()"',
      ),
    ),
    (
      'button endpoint override',
      (s) => s.replaceFirst(
        'name="favoritesubmit_btn"',
        'name="favoritesubmit_btn" formaction="home.php?mod=spacecp&ac=share"',
      ),
    ),
    (
      'external form control',
      (s) => '$s<input form="favoriteform_11" name="plugin_field">',
    ),
    (
      'disabled description',
      (s) => s.replaceFirst('<textarea', '<textarea disabled'),
    ),
    (
      'missing description',
      (s) => s.replaceFirst('name="description"', 'name="unexpected"'),
    ),
    ('duplicate form', (s) => '$s$s'),
  ]) {
    test(
      '$label fails closed without a write or guessed existing bookmark',
      () async {
        final network = BlogFavoriteNetwork()
          ..form = change(blogFavoriteForm());
        final result = await service(network).prepare(blogFavoriteTarget);
        expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
        expect(network.requests, hasLength(2));
        expect(network.posts, isEmpty);
      },
    );
  }

  for (final (label, body) in [
    ('literal success text', '<p>Saved</p>'),
    ('wrong item', blogFavoriteCallback(values: "'id':'99','favid':'55'")),
    ('missing favorite', blogFavoriteCallback(values: "'id':'11'")),
    ('invalid favorite', blogFavoriteCallback(values: "'id':'11','favid':'0'")),
    (
      'duplicate item',
      blogFavoriteCallback(values: "'id':'11','id':'99','favid':'55'"),
    ),
    (
      'other author',
      blogFavoriteCallback(
        destination: 'home.php?mod=space&uid=102&do=blog&id=11',
      ),
    ),
    (
      'other article',
      blogFavoriteCallback(
        destination: 'home.php?mod=space&uid=101&do=blog&id=99',
      ),
    ),
    (
      'foreign redirect',
      blogFavoriteCallback(
        destination:
            'https://outside.test/home.php?mod=space&uid=101&do=blog&id=11',
      ),
    ),
    (
      'unknown redirect state',
      blogFavoriteCallback(
        destination: 'home.php?mod=space&uid=101&do=blog&id=11&from=unknown',
      ),
    ),
    (
      'wrong handler',
      blogFavoriteCallback().replaceAll('y300_blog_favorite', 'another_action'),
    ),
    ('returned form', blogFavoriteForm()),
  ]) {
    test('$label is unknown after POST and cannot reuse its ticket', () async {
      final network = BlogFavoriteNetwork()..postBody = body;
      final favorites = service(network);
      final ready = (await favorites.prepare(blogFavoriteTarget)).dataOrNull!;
      final result = await favorites.add(
        ready,
        actorUserId: '101',
        description: 'note',
      );
      expect(result, isA<DataCommandOutcomeUnknown<UserBlogFavoriteReceipt>>());
      expect(
        await favorites.add(ready, actorUserId: '101', description: 'note'),
        isA<DataCommandNotSent<UserBlogFavoriteReceipt>>(),
      );
      expect(network.posts, hasLength(1));
    });
  }

  test(
    'an explicit rejection consumes its ticket but is distinct from uncertainty',
    () async {
      final network = BlogFavoriteNetwork()
        ..postBody = blogFavoriteCallback(applied: false);
      final favorites = service(network);
      final ready = (await favorites.prepare(blogFavoriteTarget)).dataOrNull!;
      final result = await favorites.add(
        ready,
        actorUserId: '101',
        description: '',
      );
      expect(result, isA<DataCommandRejected<UserBlogFavoriteReceipt>>());
      expect(
        result.failureOrNull!.diagnosticMessage,
        isNot(contains('private server message')),
      );
      expect(
        await favorites.add(ready, actorUserId: '101', description: ''),
        isA<DataCommandNotSent<UserBlogFavoriteReceipt>>(),
      );
    },
  );

  test(
    'pending POST coalesces taps and a transport exception remains unknown',
    () async {
      final network = BlogFavoriteNetwork();
      final favorites = service(network);
      final ready = (await favorites.prepare(blogFavoriteTarget)).dataOrNull!;
      final gate = Completer<void>();
      network.onRequest = (_) async {
        await gate.future;
        throw StateError('network failed');
      };
      final pending = favorites.add(
        ready,
        actorUserId: '101',
        description: 'note',
      );
      expect(
        await favorites.add(ready, actorUserId: '101', description: 'note'),
        isA<DataCommandNotSent<UserBlogFavoriteReceipt>>(),
      );
      gate.complete();
      expect(
        await pending,
        isA<DataCommandOutcomeUnknown<UserBlogFavoriteReceipt>>(),
      );
      expect(network.posts, hasLength(1));
    },
  );

  test('a ticket cannot change adapter, actor or article', () async {
    final network = BlogFavoriteNetwork();
    final favorites = service(network);
    final ready = (await favorites.prepare(blogFavoriteTarget)).dataOrNull!;
    expect(
      await service(network).add(ready, actorUserId: '101', description: ''),
      isA<DataCommandNotSent<UserBlogFavoriteReceipt>>(),
    );
    expect(
      await favorites.add(ready, actorUserId: '102', description: ''),
      isA<DataCommandNotSent<UserBlogFavoriteReceipt>>(),
    );
    final forged = UserBlogFavoritePreparation.ready(
      target: const UserBlogFavoriteTarget(
        actorUserId: '101',
        ownerUserId: '101',
        blogId: '99',
      ),
      token: ready.token!,
    );
    expect(
      await favorites.add(forged, actorUserId: '101', description: ''),
      isA<DataCommandNotSent<UserBlogFavoriteReceipt>>(),
    );
    expect(network.posts, isEmpty);
    expect(
      await favorites.add(ready, actorUserId: '101', description: ''),
      isA<DataCommandApplied<UserBlogFavoriteReceipt>>(),
    );
  });

  for (final phase in ['article', 'form', 'submit']) {
    test(
      'cancellation during $phase never returns a usable late result',
      () async {
        final network = BlogFavoriteNetwork();
        final favorites = service(network);
        final cancellation = ForumRequestCancellation();
        if (phase == 'submit') {
          final ready = (await favorites.prepare(
            blogFavoriteTarget,
          )).dataOrNull!;
          network.onRequest = (_) => cancellation.cancel();
          expect(
            await favorites.add(
              ready,
              actorUserId: '101',
              description: '',
              cancellation: cancellation,
            ),
            isA<DataCommandOutcomeUnknown<UserBlogFavoriteReceipt>>(),
          );
        } else {
          network.onRequest = (r) {
            if ((r.uri.queryParameters['mod'] == 'space') ==
                (phase == 'article')) {
              cancellation.cancel();
            }
          };
          final result = await favorites.prepare(
            blogFavoriteTarget,
            cancellation: cancellation,
          );
          expect(result.failureOrNull!.kind, DataReadFailureKind.cancelled);
          expect(network.posts, isEmpty);
        }
      },
    );
    test(
      'account change during $phase rejects the old account result',
      () async {
        final network = BlogFavoriteNetwork();
        final favorites = service(network);
        if (phase == 'submit') {
          final ready = (await favorites.prepare(
            blogFavoriteTarget,
          )).dataOrNull!;
          network.onRequest = (_) => loginBlogActor(sessions, '102');
          expect(
            await favorites.add(ready, actorUserId: '101', description: ''),
            isA<DataCommandOutcomeUnknown<UserBlogFavoriteReceipt>>(),
          );
        } else {
          network.onRequest = (r) async {
            if ((r.uri.queryParameters['mod'] == 'space') ==
                (phase == 'article')) {
              await loginBlogActor(sessions, '102');
            }
          };
          expect(
            (await favorites.prepare(blogFavoriteTarget)).dataOrNull,
            isNull,
          );
          expect(network.posts, isEmpty);
        }
      },
    );
  }

  test(
    'a canceled preparation and an invalid target do not start network work',
    () async {
      final network = BlogFavoriteNetwork();
      final favorites = service(network);
      final canceled = ForumRequestCancellation()..cancel();
      expect(
        (await favorites.prepare(
          blogFavoriteTarget,
          cancellation: canceled,
        )).dataOrNull,
        isNull,
      );
      expect(
        (await favorites.prepare(
          const UserBlogFavoriteTarget(
            actorUserId: '101',
            ownerUserId: '0',
            blogId: '11',
          ),
        )).dataOrNull,
        isNull,
      );
      expect(network.requests, isEmpty);
    },
  );

  test(
    'an existing-record redirect cannot prove a different article bookmark',
    () async {
      final network = BlogFavoriteNetwork()
        ..form = '$blogOperationHeader<div class="jump_c">Duplicate</div>';
      network.onRequest = (r) {
        if (r.uri.queryParameters['op'] == 'delete') {
          network.responseUri = r.uri.replace(
            queryParameters: {...r.uri.queryParameters, 'id': '99'},
          );
        }
      };
      expect(
        (await service(network).prepare(blogFavoriteTarget)).dataOrNull,
        isNull,
      );
      expect(network.posts, isEmpty);
    },
  );
}
