import 'dart:async';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

import '../support/blog_fixtures.dart';
import '../support/blog_operation_fixtures.dart';

void main() {
  late MemoryForumSessionStore sessions;
  setUp(() async {
    sessions = MemoryForumSessionStore();
    await loginBlogActor(sessions, '101');
  });
  UserBlogOperations service(BlogOperationNetwork network) =>
      ForumClientAdapterFactory(
        config: blogConfig,
        network: network,
        sessionStore: sessions,
      ).createUserBlogOperations();

  test('standard facade installs operations and respects source overrides', () {
    final network = BlogOperationNetwork(UserBlogAction.create);
    final override = service(network);
    final client =
        YamiboForumClientBuilder(
          config: blogConfig,
          network: network,
          sessionStore: sessions,
        ).buildStandardClient(
          sourceOverrides: ForumClientSourcePlan(blogOperations: override),
        );
    expect(client.blogOperations, same(override));
    expect(network.requests, isEmpty);
  });

  for (final action in [UserBlogAction.create, UserBlogAction.edit]) {
    test(
      '$action uses the complete form and sends HTML exactly once',
      () async {
        final network = BlogOperationNetwork(action);
        final commands = service(network);
        final prepared = await commands.prepareEditor(
          blogOperationTarget(action),
        );
        expect(prepared.failureOrNull, isNull);
        final ready = prepared.dataOrNull!;
        expect(ready.subject, 'Title & text');
        expect(ready.bodyHtml, blogEditorHtml);
        expect(ready.personalCategories.map((c) => c.id), ['0', '3']);
        expect(ready.siteCategories.map((c) => c.id), ['0', '8', '9']);
        expect(ready.siteCategoryId, '0');
        expect(ready.siteCategoryRequired, isFalse);
        expect(ready.visibility, UserBlogVisibility.public);
        expect(ready.canCreateCategory, isTrue);
        expect(network.requests.single.uri.queryParameters['mobile'], 'no');
        expect(network.requests.single.headers['User-Agent'], 'desktop-test');
        final result = await commands.save(blogEditorSubmission(ready));
        expect(result, isA<DataCommandApplied<UserBlogReceipt>>());
        expect(
          result.receiptOrNull!.blogId,
          action == UserBlogAction.create ? '12' : '11',
        );
        expect(network.requests, hasLength(2));
        final post = network.posts.single;
        final fields = Map.fromEntries(
          (post.body! as ForumMultipartFields).entries,
        );
        expect(fields['subject'], 'Updated 标题');
        expect(fields['message'], blogEditorHtml);
        expect(fields['plaintext'], isNull);
        expect(fields['blogsubmit'], 'true');
        expect(fields['formhash'], 'fixturehash');
        expect(fields['tag'], 'updated,tag');
        expect(fields['selectgroup'], isNull);
        expect(fields['savealbumid'], isNull);
        expect(post.uri.queryParameters['mobile'], 'no');
        expect(post.uri.queryParameters['inajax'], '1');
        expect(post.followRedirects, isFalse);
        expect(post.context.silent, isTrue);
        expect(
          await commands.save(blogEditorSubmission(ready)),
          isA<DataCommandNotSent<UserBlogReceipt>>(),
        );
        expect(network.posts, hasLength(1));
      },
    );
  }

  for (final visibility in UserBlogVisibility.values) {
    test('editing preserves $visibility and closed comments', () async {
      final network = BlogOperationNetwork(UserBlogAction.edit)
        ..editor = blogEditorForm(
          visibility: visibility.index,
          commentsEnabled: false,
        );
      final commands = service(network);
      final ready = (await commands.prepareEditor(
        blogOperationTarget(UserBlogAction.edit),
      )).dataOrNull!;
      expect(ready.visibility, visibility);
      expect(ready.commentsEnabled, isFalse);
      await commands.save(
        blogEditorSubmission(ready, bodyHtml: '<p>Only content changed</p>'),
      );
      final fields = Map.fromEntries(
        (network.posts.single.body! as ForumMultipartFields).entries,
      );
      expect(fields['friend'], '${visibility.index}');
      expect(fields['password'], 'fixture.password');
      expect(fields['target_names'], 'Reader One Reader Two');
      expect(fields['noreply'], '1');
      expect(fields['hot'], '7');
      expect(fields['message'], '<p>Only content changed</p>');
    });
  }

  test(
    'required categories reject zero while accepting an advertised child',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.create)
        ..editor = blogEditorForm(create: true, siteCategoryRequired: true);
      final commands = service(network);
      final ready = (await commands.prepareEditor(
        blogOperationTarget(UserBlogAction.create),
      )).dataOrNull!;
      expect(ready.siteCategoryRequired, isTrue);
      expect(ready.siteCategoryId, '8');
      for (final invalid in ['0', '99', '-1']) {
        expect(
          await commands.save(
            blogEditorSubmission(ready, siteCategory: invalid),
          ),
          isA<DataCommandNotSent<UserBlogReceipt>>(),
        );
      }
      expect(network.posts, isEmpty);
      expect(
        await commands.save(blogEditorSubmission(ready, siteCategory: '9')),
        isA<DataCommandApplied<UserBlogReceipt>>(),
      );
    },
  );

  test(
    'disabled feed and absent site categories stay absent in the UI contract',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.create)
        ..editor = blogEditorForm(create: true, categories: false, feed: false);
      final commands = service(network);
      final ready = (await commands.prepareEditor(
        blogOperationTarget(UserBlogAction.create),
      )).dataOrNull!;
      expect(ready.siteCategories, isEmpty);
      expect(ready.canPublishFeed, isFalse);
      expect(
        await commands.save(blogEditorSubmission(ready, feed: true)),
        isA<DataCommandNotSent<UserBlogReceipt>>(),
      );
      expect(
        await commands.save(blogEditorSubmission(ready)),
        isA<DataCommandApplied<UserBlogReceipt>>(),
      );
      final fields = Map.fromEntries(
        (network.posts.single.body! as ForumMultipartFields).entries,
      );
      expect(fields.containsKey('makefeed'), isFalse);
    },
  );

  test('new personal category uses the source-defined new prefix', () async {
    final network = BlogOperationNetwork(UserBlogAction.create);
    final commands = service(network);
    final ready = (await commands.prepareEditor(
      blogOperationTarget(UserBlogAction.create),
    )).dataOrNull!;
    expect(
      await commands.save(
        blogEditorSubmission(ready, newCategory: ' 日常 & 写作 '),
      ),
      isA<DataCommandApplied<UserBlogReceipt>>(),
    );
    final fields = Map.fromEntries(
      (network.posts.single.body! as ForumMultipartFields).entries,
    );
    expect(fields['classid'], 'new:日常 & 写作');
  });

  test('editing another author cannot create a personal category', () async {
    final network = BlogOperationNetwork(UserBlogAction.edit)
      ..editor = blogEditorForm(owner: '102', canCreateCategory: false);
    final commands = service(network);
    final ready = (await commands.prepareEditor(
      const UserBlogTarget(
        actorUserId: '101',
        ownerUserId: '102',
        action: UserBlogAction.edit,
        blogId: '11',
      ),
    )).dataOrNull!;
    expect(ready.canCreateCategory, isFalse);
    expect(
      await commands.save(blogEditorSubmission(ready, newCategory: 'Bad')),
      isA<DataCommandNotSent<UserBlogReceipt>>(),
    );
    expect(network.posts, isEmpty);
  });

  test('invalid input retains the ticket for correction', () async {
    final network = BlogOperationNetwork(UserBlogAction.create);
    final commands = service(network);
    final ready = (await commands.prepareEditor(
      blogOperationTarget(UserBlogAction.create),
    )).dataOrNull!;
    final invalid = [
      blogEditorSubmission(ready, subject: '  '),
      blogEditorSubmission(ready, bodyHtml: ''),
      blogEditorSubmission(ready, personalCategory: '99'),
      blogEditorSubmission(ready, newCategory: '  '),
      blogEditorSubmission(ready, personalCategory: '3', newCategory: 'New'),
    ];
    for (final submission in invalid) {
      expect(
        await commands.save(submission),
        isA<DataCommandNotSent<UserBlogReceipt>>(),
      );
    }
    expect(network.posts, isEmpty);
    expect(
      await commands.save(blogEditorSubmission(ready)),
      isA<DataCommandApplied<UserBlogReceipt>>(),
    );
  });

  for (final (label, change) in <(String, String Function(String))>[
    ('mobile-only editor', (s) => s.replaceAll('ttHtmlEditor', 'postform')),
    (
      'missing owner proof',
      (s) => s.replaceAll('uid=101&do=blog&id=11', 'uid=999&do=blog&id=11'),
    ),
    (
      'missing privacy',
      (s) => s.replaceFirst('name="friend"', 'data-name="friend"'),
    ),
    (
      'duplicate formhash',
      (s) => s.replaceFirst(
        '</form>',
        '<input name="formhash" value="other"></form>',
      ),
    ),
    (
      'captcha',
      (s) => s.replaceFirst('</form>', '<input name="seccodeverify"></form>'),
    ),
    (
      'plugin field',
      (s) => s.replaceFirst('</form>', '<input name="plugin_secret"></form>'),
    ),
    (
      'picture attachment',
      (s) => s.replaceFirst(
        '</form>',
        '<input name="picids[4]" value="1"></form>',
      ),
    ),
    (
      'unexpected hidden operation',
      (s) => s.replaceFirst(
        '</form>',
        '<input name="deletesubmit" value="true"></form>',
      ),
    ),
    ('changed action ID', (s) => s.replaceFirst('blogid=11', 'blogid=99')),
    (
      'external endpoint',
      (s) => s.replaceFirst(
        'action="home.php',
        'action="https://external.test/home.php',
      ),
    ),
    (
      'downgraded endpoint',
      (s) => s.replaceFirst(
        'action="home.php',
        'action="http://example.test/home.php',
      ),
    ),
    (
      'duplicate query target',
      (s) => s.replaceFirst('blogid=11', 'blogid=11&blogid=99'),
    ),
    (
      'moderation key',
      (s) => s.replaceFirst('blogid=11', 'blogid=11&modblogkey=unverified'),
    ),
    (
      'unknown category option',
      (s) => s.replaceFirst('value="8"', 'value="other"'),
    ),
    (
      'multiple selections',
      (s) => s
          .replaceFirst('<option value="9">', '<option value="9" selected>')
          .replaceFirst('<option value="8">', '<option value="8" selected>'),
    ),
  ]) {
    test('$label cannot produce a usable editor ticket', () async {
      final network = BlogOperationNetwork(UserBlogAction.edit)
        ..editor = change(blogEditorForm());
      final result = await service(
        network,
      ).prepareEditor(blogOperationTarget(UserBlogAction.edit));
      expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
      expect(network.posts, isEmpty);
    });
  }

  for (final visibility in [2, 4]) {
    test(
      'missing protected state for policy $visibility is not silently reset',
      () async {
        final network = BlogOperationNetwork(UserBlogAction.edit)
          ..editor = blogEditorForm(visibility: visibility)
              .replaceFirst('fixture.password', '')
              .replaceFirst('Reader One Reader Two', '');
        final result = await service(
          network,
        ).prepareEditor(blogOperationTarget(UserBlogAction.edit));
        expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
      },
    );
  }

  test('creation cannot target a different author or an existing ID', () async {
    final network = BlogOperationNetwork(UserBlogAction.create);
    final commands = service(network);
    for (final target in [
      const UserBlogTarget(
        actorUserId: '101',
        ownerUserId: '102',
        action: UserBlogAction.create,
      ),
      const UserBlogTarget(
        actorUserId: '101',
        ownerUserId: '101',
        action: UserBlogAction.create,
        blogId: '11',
      ),
    ]) {
      expect((await commands.prepareEditor(target)).failureOrNull, isNotNull);
    }
    expect(network.requests, isEmpty);
  });

  test('the local account and complete form header must agree', () async {
    final network = BlogOperationNetwork(UserBlogAction.create);
    final commands = service(network);
    await loginBlogActor(sessions, '102');
    expect(
      (await commands.prepareEditor(
        blogOperationTarget(UserBlogAction.create),
      )).failureOrNull,
      isNotNull,
    );
    expect(network.requests, isEmpty);
    await loginBlogActor(sessions, '101');
    network.editor = blogEditorForm(
      create: true,
    ).replaceFirst("discuz_uid = '101'", "discuz_uid = '102'");
    expect(
      (await commands.prepareEditor(
        blogOperationTarget(UserBlogAction.create),
      )).failureOrNull!.kind,
      DataReadFailureKind.unauthorized,
    );
  });

  for (final changeAccount in [false, true]) {
    test(
      'preparation drops a late ${changeAccount ? 'account' : 'cancelled'} result',
      () async {
        final cancellation = ForumRequestCancellation();
        final network = BlogOperationNetwork(UserBlogAction.create)
          ..onRequest = (_) async {
            if (changeAccount) {
              await loginBlogActor(sessions, '102');
            } else {
              cancellation.cancel();
            }
          };
        final result = await service(network).prepareEditor(
          blogOperationTarget(UserBlogAction.create),
          cancellation: cancellation,
        );
        expect(result.failureOrNull!.kind, DataReadFailureKind.cancelled);
      },
    );
  }

  test('another adapter cannot use a prepared ticket', () async {
    final network = BlogOperationNetwork(UserBlogAction.create);
    final ready = (await service(
      network,
    ).prepareEditor(blogOperationTarget(UserBlogAction.create))).dataOrNull!;
    expect(
      await service(network).save(blogEditorSubmission(ready)),
      isA<DataCommandNotSent<UserBlogReceipt>>(),
    );
    expect(network.posts, isEmpty);
  });

  test('a pending POST consumes the ticket before a second tap', () async {
    final network = BlogOperationNetwork(UserBlogAction.create);
    final commands = service(network);
    final ready = (await commands.prepareEditor(
      blogOperationTarget(UserBlogAction.create),
    )).dataOrNull!;
    final started = Completer<void>();
    final gate = Completer<void>();
    network.onRequest = (_) async {
      started.complete();
      await gate.future;
    };
    final first = commands.save(blogEditorSubmission(ready));
    await started.future;
    expect(
      await commands.save(blogEditorSubmission(ready)),
      isA<DataCommandNotSent<UserBlogReceipt>>(),
    );
    gate.complete();
    expect(await first, isA<DataCommandApplied<UserBlogReceipt>>());
    expect(network.posts, hasLength(1));
  });

  for (final during in [false, true]) {
    for (final changeAccount in [false, true]) {
      test(
        '${changeAccount ? 'account change' : 'cancellation'} ${during ? 'during' : 'before'} POST preserves its outcome',
        () async {
          final network = BlogOperationNetwork(UserBlogAction.edit);
          final commands = service(network);
          final ready = (await commands.prepareEditor(
            blogOperationTarget(UserBlogAction.edit),
          )).dataOrNull!;
          final cancellation = ForumRequestCancellation();
          Future<void> interrupt() async {
            if (changeAccount) {
              await loginBlogActor(sessions, '102');
            } else {
              cancellation.cancel();
            }
          }

          if (during) {
            network.onRequest = (_) => interrupt();
          } else {
            await interrupt();
          }
          final result = await commands.save(
            blogEditorSubmission(ready, cancellation: cancellation),
          );
          expect(
            result,
            during
                ? isA<DataCommandOutcomeUnknown<UserBlogReceipt>>()
                : isA<DataCommandNotSent<UserBlogReceipt>>(),
          );
          expect(network.posts, hasLength(during ? 1 : 0));
        },
      );
    }
  }

  test(
    'transport failure never exposes raw payload or reuses the consumed form',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.create);
      final commands = service(network);
      final ready = (await commands.prepareEditor(
        blogOperationTarget(UserBlogAction.create),
      )).dataOrNull!;
      network.onRequest = (_) => throw StateError('secret response');
      final result = await commands.save(blogEditorSubmission(ready));
      expect(result, isA<DataCommandOutcomeUnknown<UserBlogReceipt>>());
      expect(result.failureOrNull!.retryPolicy, DataCommandRetryPolicy.never);
      expect(
        result.failureOrNull!.diagnosticMessage,
        isNot(contains('secret')),
      );
      expect(
        await commands.save(blogEditorSubmission(ready)),
        isA<DataCommandNotSent<UserBlogReceipt>>(),
      );
      expect(network.posts, hasLength(1));
    },
  );

  test('explicit error callback is a rejection without server text', () async {
    final network = BlogOperationNetwork(UserBlogAction.create)
      ..postBody = blogOperationCallback(UserBlogAction.create, success: false);
    final commands = service(network);
    final ready = (await commands.prepareEditor(
      blogOperationTarget(UserBlogAction.create),
    )).dataOrNull!;
    final result = await commands.save(blogEditorSubmission(ready));
    expect(result, isA<DataCommandRejected<UserBlogReceipt>>());
    expect(
      result.failureOrNull!.diagnosticMessage,
      isNot(contains('private server')),
    );
  });

  for (final destination in [
    'https://external.test/home.php?mod=space&uid=101&do=blog&id=11',
    'home.php?mod=space&uid=999&do=blog&id=11',
    'home.php?mod=space&uid=101&do=blog&id=99',
    'home.php?mod=space&uid=101&do=blog&id=11&id=99',
    'home.php?mod=space&uid=101&do=topic&id=11',
    'home.php?mod=space&uid=101&do=blog&view=me',
    '',
  ]) {
    test('unproved edit receipt $destination remains unknown', () async {
      final network = BlogOperationNetwork(UserBlogAction.edit)
        ..postBody = blogOperationCallback(
          UserBlogAction.edit,
          destination: destination,
        );
      final commands = service(network);
      final ready = (await commands.prepareEditor(
        blogOperationTarget(UserBlogAction.edit),
      )).dataOrNull!;
      final result = await commands.save(blogEditorSubmission(ready));
      expect(result, isA<DataCommandOutcomeUnknown<UserBlogReceipt>>());
      expect(result.failureOrNull!.retryPolicy, DataCommandRetryPolicy.never);
    });
  }
}
