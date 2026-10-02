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

  for (final action in [
    UserBlogAction.delete,
    UserBlogAction.pin,
    UserBlogAction.unpin,
  ]) {
    test(
      '$action verifies the article and confirmation before a single POST',
      () async {
        final network = BlogOperationNetwork(action);
        final commands = service(network);
        final prepared = await commands.prepareAction(
          blogOperationTarget(action),
        );
        expect(prepared.failureOrNull, isNull);
        expect(network.requests, hasLength(2));
        expect(network.posts, isEmpty);
        final result = await commands.executeAction(
          prepared.dataOrNull!,
          actorUserId: '101',
        );
        expect(result, isA<DataCommandApplied<UserBlogReceipt>>());
        expect(result.receiptOrNull!.blogId, '11');
        final post = network.posts.single;
        final fields = post.body! as Map<String, String>;
        expect(fields['formhash'], 'fixturehash');
        expect(
          fields['referer'],
          'https://example.test/home.php?mod=space&uid=101&do=blog&mobile=2&id=11',
        );
        expect(fields['blogsubmit'], isNull);
        expect(fields['btnsubmit'], isNull);
        if (action != UserBlogAction.delete) {
          expect(fields['sticksubmit'], 'true');
          expect(fields['stickflag'], action == UserBlogAction.pin ? '1' : '0');
        } else {
          expect(fields['deletesubmit'], 'true');
        }
        expect(post.followRedirects, isFalse);
        expect(post.context.silent, isTrue);
        expect(
          await commands.executeAction(
            prepared.dataOrNull!,
            actorUserId: '101',
          ),
          isA<DataCommandNotSent<UserBlogReceipt>>(),
        );
        expect(network.posts, hasLength(1));
      },
    );
  }

  test('deletion requires a server-advertised action', () async {
    final network = BlogOperationNetwork(UserBlogAction.delete)
      ..article = blogManagedArticle(deletionAllowed: false);
    final result = await service(
      network,
    ).prepareAction(blogOperationTarget(UserBlogAction.delete));
    expect(result.failureOrNull!.code, 'blog_action_denied');
    expect(network.requests, hasLength(1));
  });

  test(
    'a moderator can delete only after the article advertises deletion',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.delete)
        ..article = blogManagedArticle().replaceAll(
          "discuz_uid = '101'",
          "discuz_uid = '102'",
        )
        ..actionForm = blogActionForm(
          UserBlogAction.delete,
        ).replaceAll("discuz_uid = '101'", "discuz_uid = '102'");
      await loginBlogActor(sessions, '102');
      final commands = service(network);
      final ready = await commands.prepareAction(
        const UserBlogTarget(
          actorUserId: '102',
          ownerUserId: '101',
          blogId: '11',
          action: UserBlogAction.delete,
        ),
      );
      expect(ready.failureOrNull, isNull);
      expect(
        await commands.executeAction(ready.dataOrNull!, actorUserId: '102'),
        isA<DataCommandApplied<UserBlogReceipt>>(),
      );
    },
  );

  test(
    'pinning another author is denied before reading a confirmation',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.pin)
        ..article = blogManagedArticle().replaceAll(
          "discuz_uid = '101'",
          "discuz_uid = '102'",
        );
      await loginBlogActor(sessions, '102');
      final result = await service(network).prepareAction(
        const UserBlogTarget(
          actorUserId: '102',
          ownerUserId: '101',
          blogId: '11',
          action: UserBlogAction.pin,
        ),
      );
      expect(result.failureOrNull!.code, 'blog_action_denied');
      expect(network.requests, hasLength(1));
    },
  );

  for (final (label, change) in <(String, String Function(String))>[
    ('different article', (s) => s.replaceFirst('blogid=11', 'blogid=99')),
    ('different operation', (s) => s.replaceFirst('op=delete', 'op=stick')),
    (
      'foreign endpoint',
      (s) => s.replaceFirst(
        'action="home.php',
        'action="https://external.test/home.php',
      ),
    ),
    (
      'unexpected hidden editor flag',
      (s) => s.replaceFirst(
        '</form>',
        '<input type="hidden" name="blogsubmit" value="true"></form>',
      ),
    ),
    (
      'unknown plugin input',
      (s) => s.replaceFirst('</form>', '<input name="plugin_field"></form>'),
    ),
    (
      'unknown named button',
      (s) => s.replaceFirst(
        '</form>',
        '<button name="plugin_action">Do</button></form>',
      ),
    ),
    ('missing formhash', (s) => s.replaceFirst('fixturehash', '')),
    (
      'duplicate flag',
      (s) => s.replaceFirst(
        '</form>',
        '<input type="hidden" name="deletesubmit" value="true"></form>',
      ),
    ),
    (
      'unchecked flag',
      (s) => s.replaceFirst(
        'type="hidden" name="deletesubmit"',
        'type="checkbox" name="deletesubmit"',
      ),
    ),
    (
      'disabled flag',
      (s) =>
          s.replaceFirst('name="deletesubmit"', 'name="deletesubmit" disabled'),
    ),
  ]) {
    test('$label cannot authorize deletion', () async {
      final network = BlogOperationNetwork(UserBlogAction.delete)
        ..actionForm = change(blogActionForm(UserBlogAction.delete));
      final result = await service(
        network,
      ).prepareAction(blogOperationTarget(UserBlogAction.delete));
      expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
      expect(network.posts, isEmpty);
    });
  }

  test(
    'a stale inverse pin confirmation cannot authorize the requested action',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.pin)
        ..actionForm = blogActionForm(UserBlogAction.unpin);
      final result = await service(
        network,
      ).prepareAction(blogOperationTarget(UserBlogAction.pin));
      expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
      expect(network.posts, isEmpty);
    },
  );

  test(
    'a confirmation token cannot be retargeted or passed to another adapter',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.delete);
      final commands = service(network);
      final ready = (await commands.prepareAction(
        blogOperationTarget(UserBlogAction.delete),
      )).dataOrNull!;
      final changed = UserBlogActionPreparation(
        target: blogOperationTarget(UserBlogAction.pin),
        token: ready.token,
      );
      expect(
        await commands.executeAction(changed, actorUserId: '101'),
        isA<DataCommandNotSent<UserBlogReceipt>>(),
      );
      expect(
        await service(network).executeAction(ready, actorUserId: '101'),
        isA<DataCommandNotSent<UserBlogReceipt>>(),
      );
      expect(network.posts, isEmpty);
    },
  );

  test(
    'account changes between article and form discard preparation',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.delete);
      network.onRequest = (request) async {
        if (network.requests.length == 2) {
          await loginBlogActor(sessions, '102');
        }
      };
      final result = await service(
        network,
      ).prepareAction(blogOperationTarget(UserBlogAction.delete));
      expect(result.failureOrNull!.kind, DataReadFailureKind.cancelled);
      expect(network.posts, isEmpty);
    },
  );

  for (final during in [false, true]) {
    test(
      'cancellation ${during ? 'during' : 'before'} deletion is controlled',
      () async {
        final network = BlogOperationNetwork(UserBlogAction.delete);
        final commands = service(network);
        final ready = (await commands.prepareAction(
          blogOperationTarget(UserBlogAction.delete),
        )).dataOrNull!;
        final cancellation = ForumRequestCancellation();
        if (during) {
          network.onRequest = (_) => cancellation.cancel();
        } else {
          cancellation.cancel();
        }
        final result = await commands.executeAction(
          ready,
          actorUserId: '101',
          cancellation: cancellation,
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

  test(
    'server rejection and unknown deletion leave no reusable confirmation',
    () async {
      for (final body in [
        blogOperationCallback(UserBlogAction.delete, success: false),
        '<div>Success</div>',
      ]) {
        final network = BlogOperationNetwork(UserBlogAction.delete)
          ..postBody = body;
        final commands = service(network);
        final ready = (await commands.prepareAction(
          blogOperationTarget(UserBlogAction.delete),
        )).dataOrNull!;
        final result = await commands.executeAction(ready, actorUserId: '101');
        expect(result, isNot(isA<DataCommandApplied<UserBlogReceipt>>()));
        expect(
          result.failureOrNull!.diagnosticMessage,
          isNot(contains('private server')),
        );
        expect(
          await commands.executeAction(ready, actorUserId: '101'),
          isA<DataCommandNotSent<UserBlogReceipt>>(),
        );
        expect(network.posts, hasLength(1));
      }
    },
  );

  for (final (action, destination) in [
    (UserBlogAction.delete, 'home.php?mod=space&uid=101&do=blog&id=11'),
    (UserBlogAction.delete, 'home.php?mod=space&uid=102&do=blog&view=me'),
    (UserBlogAction.pin, 'home.php?mod=space&uid=101&do=blog&id=99'),
    (UserBlogAction.unpin, 'home.php?mod=space&uid=101&do=blog&view=me'),
  ]) {
    test('$action rejects an unrelated success destination', () async {
      final network = BlogOperationNetwork(action)
        ..postBody = blogOperationCallback(action, destination: destination);
      final commands = service(network);
      final ready = (await commands.prepareAction(
        blogOperationTarget(action),
      )).dataOrNull!;
      expect(
        await commands.executeAction(ready, actorUserId: '101'),
        isA<DataCommandOutcomeUnknown<UserBlogReceipt>>(),
      );
    });
  }
}
