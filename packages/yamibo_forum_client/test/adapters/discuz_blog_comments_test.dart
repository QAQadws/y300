import 'dart:async';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

import '../support/blog_fixtures.dart';

void main() {
  late MemoryForumSessionStore sessions;
  setUp(() async {
    sessions = MemoryForumSessionStore();
    await _login(sessions, '102');
  });
  UserBlogCommentService service(_Network network) => ForumClientAdapterFactory(
    config: blogConfig,
    network: network,
    sessionStore: sessions,
  ).createUserBlogComments();

  test('standard facade installs comments and respects a source override', () {
    final network = _Network(UserBlogCommentAction.add);
    final override = service(network);
    final client =
        YamiboForumClientBuilder(
          config: blogConfig,
          network: network,
          sessionStore: sessions,
        ).buildStandardClient(
          sourceOverrides: ForumClientSourcePlan(blogComments: override),
        );
    expect(client.blogComments, same(override));
    expect(network.requests, isEmpty);
  });

  for (final action in UserBlogCommentAction.values) {
    test(
      'prepares and applies $action with one POST and no profile request',
      () async {
        final network = _Network(action);
        final commands = service(network);
        final ready = await commands.prepare(_target(action));
        expect(ready.failureOrNull, isNull);
        expect(
          ready.dataOrNull!.initialMessage,
          action == UserBlogCommentAction.edit ? '[b]Original[/b] & text' : '',
        );
        final result = await commands.execute(_submission(ready.dataOrNull!));
        expect(result, isA<DataCommandApplied<UserBlogCommentReceipt>>());
        expect(
          result.receiptOrNull!.commentId,
          action == UserBlogCommentAction.add ||
                  action == UserBlogCommentAction.reply
              ? '6'
              : '5',
        );
        expect(
          network.requests.where(
            (request) => request.method == ForumRequestMethod.post,
          ),
          hasLength(1),
        );
        expect(
          network.requests,
          hasLength(action == UserBlogCommentAction.add ? 2 : 3),
        );
        final post = network.requests.last;
        final fields = post.body! as Map<String, String>;
        expect(
          fields['formhash'],
          action == UserBlogCommentAction.add ? 'fixturehash' : 'testhash',
        );
        expect(fields['referer'], contains('id=11'));
        expect(post.followRedirects, isFalse);
        expect(post.context.silent, isTrue);
        if (action != UserBlogCommentAction.delete) {
          expect(fields['message'], '评论 & + = [b]text[/b]');
        }
        if (action == UserBlogCommentAction.reply) expect(fields['cid'], '5');
        if (action == UserBlogCommentAction.delete) {
          expect(fields.containsKey('message'), isFalse);
        }
      },
    );
  }

  test('one Chinese character passes the server byte-length rule', () async {
    final network = _Network(UserBlogCommentAction.add);
    final commands = service(network);
    final ready = await commands.prepare(_target(UserBlogCommentAction.add));
    final result = await commands.execute(
      UserBlogCommentSubmission(
        preparation: ready.dataOrNull!,
        actorUserId: '102',
        message: '好',
      ),
    );
    expect(result, isA<DataCommandApplied<UserBlogCommentReceipt>>());
  });

  test(
    'invalid input sends no mutation and leaves preparation reusable',
    () async {
      final network = _Network(UserBlogCommentAction.add);
      final commands = service(network);
      final ready = (await commands.prepare(
        _target(UserBlogCommentAction.add),
      )).dataOrNull!;
      final invalid = await commands.execute(
        UserBlogCommentSubmission(
          preparation: ready,
          actorUserId: '102',
          message: ' ',
        ),
      );
      expect(invalid, isA<DataCommandNotSent<UserBlogCommentReceipt>>());
      expect(network.requests, hasLength(1));
      expect(
        await commands.execute(_submission(ready)),
        isA<DataCommandApplied<UserBlogCommentReceipt>>(),
      );
    },
  );

  test('cancelled preparation sends no request', () async {
    final network = _Network(UserBlogCommentAction.add);
    final cancellation = ForumRequestCancellation()..cancel();
    final result = await service(
      network,
    ).prepare(_target(UserBlogCommentAction.add), cancellation: cancellation);
    expect(result.failureOrNull!.kind, DataReadFailureKind.cancelled);
    expect(network.requests, isEmpty);
  });

  test('an edit receipt cannot confirm a different comment', () async {
    final network = _Network(UserBlogCommentAction.edit)
      ..postBody = _callback(cid: '999');
    final commands = service(network);
    final ready = (await commands.prepare(
      _target(UserBlogCommentAction.edit),
    )).dataOrNull!;
    expect(
      await commands.execute(_submission(ready)),
      isA<DataCommandOutcomeUnknown<UserBlogCommentReceipt>>(),
    );
  });

  test(
    'account change after a POST never publishes a receipt to the new account',
    () async {
      final network = _Network(UserBlogCommentAction.add);
      final commands = service(network);
      final ready = (await commands.prepare(
        _target(UserBlogCommentAction.add),
      )).dataOrNull!;
      network.onRequest = (_) => _login(sessions, '999');
      expect(
        await commands.execute(_submission(ready)),
        isA<DataCommandOutcomeUnknown<UserBlogCommentReceipt>>(),
      );
    },
  );

  for (final action in [
    UserBlogCommentAction.reply,
    UserBlogCommentAction.edit,
    UserBlogCommentAction.delete,
  ]) {
    test(
      'unadvertised $action never prepares or submits an action form',
      () async {
        final network = _Network(action)..article = _article(actions: false);
        final result = await service(network).prepare(_target(action));
        expect(result.failureOrNull!.code, 'blog_comment_action_denied');
        expect(network.requests, hasLength(1));
      },
    );
  }

  test('closed journal cannot prepare new comments', () async {
    final network = _Network(UserBlogCommentAction.add)
      ..article = _article(open: false);
    final result = await service(
      network,
    ).prepare(_target(UserBlogCommentAction.add));
    expect(result.failureOrNull!.code, 'blog_comment_closed');
    expect(network.requests, hasLength(1));
  });

  for (final replacement in [
    '<input type="text" name="seccodeverify">',
    '<input name="unknown_plugin_field" value="x">',
    '<input name="formhash" value="duplicate">',
    '<input name="commentsubmit" value="true">',
    '<input name="cid" value="999">',
  ]) {
    test(
      'unknown, challenged or ambiguous forms fail closed: $replacement',
      () async {
        final network = _Network(UserBlogCommentAction.edit)
          ..form = _form(
            UserBlogCommentAction.edit,
          ).replaceFirst('</form>', '$replacement</form>');
        final result = await service(
          network,
        ).prepare(_target(UserBlogCommentAction.edit));
        expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
        expect(
          network.requests.every(
            (request) => request.method == ForumRequestMethod.get,
          ),
          isTrue,
        );
      },
    );
  }

  for (final actionUri in [
    'https://external.test/home.php?mod=spacecp&ac=comment&op=edit&cid=5',
    'http://example.test/home.php?mod=spacecp&ac=comment&op=edit&cid=5',
    'home.php?mod=spacecp&ac=comment&op=edit&cid=999',
    'home.php?mod=spacecp&ac=comment&op=edit&cid=5&modcommentkey=unreviewed',
    'home.php?mod=spacecp&ac=comment&op=edit&cid=5&cid=999',
    'https://example.test:444/home.php?mod=spacecp&ac=comment&op=edit&cid=5',
    'https://user@example.test/home.php?mod=spacecp&ac=comment&op=edit&cid=5',
    '/other/home.php?mod=spacecp&ac=comment&op=edit&cid=5',
  ]) {
    test('rejects a changed or unverified form action: $actionUri', () async {
      final network = _Network(UserBlogCommentAction.edit)
        ..form = _form(UserBlogCommentAction.edit).replaceFirst(
          'home.php?mod=spacecp&ac=comment&op=edit&cid=5',
          actionUri,
        );
      final result = await service(
        network,
      ).prepare(_target(UserBlogCommentAction.edit));
      expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
    });
  }

  test('reply form cannot change journal or target comment', () async {
    final network = _Network(UserBlogCommentAction.reply)
      ..form = _form(
        UserBlogCommentAction.reply,
      ).replaceFirst('name="id" value="11"', 'name="id" value="99"');
    final result = await service(
      network,
    ).prepare(_target(UserBlogCommentAction.reply));
    expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
  });

  test(
    'account must match both the session projection and mobile header',
    () async {
      final network = _Network(UserBlogCommentAction.add);
      final commands = service(network);
      await _login(sessions, '999');
      expect(
        (await commands.prepare(
          _target(UserBlogCommentAction.add),
        )).failureOrNull!.kind,
        DataReadFailureKind.unauthorized,
      );
      expect(network.requests, isEmpty);
      await _login(sessions, '102');
      network.article = _article().replaceFirst(
        "discuz_uid = '102'",
        "discuz_uid = '999'",
      );
      expect(
        (await commands.prepare(
          _target(UserBlogCommentAction.add),
        )).failureOrNull!.code,
        'blog_comment_account_unverified',
      );
    },
  );

  test('account changes during preparation discard the old form', () async {
    final network = _Network(UserBlogCommentAction.add)
      ..onRequest = (request) => _login(sessions, '999');
    final result = await service(
      network,
    ).prepare(_target(UserBlogCommentAction.add));
    expect(result.failureOrNull!.kind, DataReadFailureKind.cancelled);
  });

  test('account changes before submission send no POST', () async {
    final network = _Network(UserBlogCommentAction.add);
    final commands = service(network);
    final ready = await commands.prepare(_target(UserBlogCommentAction.add));
    await _login(sessions, '999');
    final result = await commands.execute(_submission(ready.dataOrNull!));
    expect(result, isA<DataCommandNotSent<UserBlogCommentReceipt>>());
    expect(network.requests, hasLength(1));
  });

  test('a token belongs to its adapter and original target', () async {
    final network = _Network(UserBlogCommentAction.add);
    final commands = service(network);
    final ready = (await commands.prepare(
      _target(UserBlogCommentAction.add),
    )).dataOrNull!;
    expect(
      await service(network).execute(_submission(ready)),
      isA<DataCommandNotSent<UserBlogCommentReceipt>>(),
    );
    final changed = UserBlogCommentPreparation(
      target: _target(UserBlogCommentAction.delete),
      token: ready.token,
    );
    expect(
      await commands.execute(_submission(changed)),
      isA<DataCommandNotSent<UserBlogCommentReceipt>>(),
    );
    expect(network.requests, hasLength(1));
  });

  test(
    'a pending POST consumes the token and coalesces duplicate taps',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final network = _Network(UserBlogCommentAction.add);
      final commands = service(network);
      final ready = (await commands.prepare(
        _target(UserBlogCommentAction.add),
      )).dataOrNull!;
      network.onRequest = (request) async {
        if (request.method == ForumRequestMethod.post) {
          started.complete();
          await gate.future;
        }
      };
      final first = commands.execute(_submission(ready));
      await started.future;
      expect(
        await commands.execute(_submission(ready)),
        isA<DataCommandNotSent<UserBlogCommentReceipt>>(),
      );
      gate.complete();
      expect(await first, isA<DataCommandApplied<UserBlogCommentReceipt>>());
      expect(network.requests, hasLength(2));
    },
  );

  for (final duringPost in [false, true]) {
    test(
      'cancellation ${duringPost ? 'during' : 'before'} submission is controlled',
      () async {
        final network = _Network(UserBlogCommentAction.add);
        final commands = service(network);
        final ready = (await commands.prepare(
          _target(UserBlogCommentAction.add),
        )).dataOrNull!;
        final cancellation = ForumRequestCancellation();
        if (duringPost) {
          network.onRequest = (request) {
            cancellation.cancel();
          };
        } else {
          cancellation.cancel();
        }
        final result = await commands.execute(
          UserBlogCommentSubmission(
            preparation: ready,
            actorUserId: '102',
            message: 'text',
            cancellation: cancellation,
          ),
        );
        expect(
          result,
          duringPost
              ? isA<DataCommandOutcomeUnknown<UserBlogCommentReceipt>>()
              : isA<DataCommandNotSent<UserBlogCommentReceipt>>(),
        );
        expect(network.requests, hasLength(duringPost ? 2 : 1));
      },
    );
  }

  test(
    'transport exceptions preserve uncertainty and cannot be resent',
    () async {
      final network = _Network(UserBlogCommentAction.add);
      final commands = service(network);
      final ready = (await commands.prepare(
        _target(UserBlogCommentAction.add),
      )).dataOrNull!;
      network.onRequest = (request) {
        throw StateError('secret payload');
      };
      final result = await commands.execute(_submission(ready));
      expect(result, isA<DataCommandOutcomeUnknown<UserBlogCommentReceipt>>());
      expect(result.failureOrNull!.retryPolicy, DataCommandRetryPolicy.never);
      expect(
        result.failureOrNull!.diagnosticMessage,
        isNot(contains('secret')),
      );
      expect(
        await commands.execute(_submission(ready)),
        isA<DataCommandNotSent<UserBlogCommentReceipt>>(),
      );
    },
  );

  test(
    'explicit server rejection is distinct from an unproved response',
    () async {
      final network = _Network(UserBlogCommentAction.add)
        ..postBody = _callback(success: false);
      final commands = service(network);
      final ready = (await commands.prepare(
        _target(UserBlogCommentAction.add),
      )).dataOrNull!;
      final result = await commands.execute(_submission(ready));
      expect(result, isA<DataCommandRejected<UserBlogCommentReceipt>>());
      expect(
        result.failureOrNull!.diagnosticMessage,
        isNot(contains('private rejection')),
      );
    },
  );

  for (final (label, body) in <(String, String)>[
    ('empty', ''),
    ('success text', '<div>Operation successful</div>'),
    (
      'handler declaration',
      '<script>function succeedhandle_y300_blog_comment(url, message, values) {}</script>',
    ),
    ('wrong handle', _callback().replaceAll('y300_blog_comment', 'unrelated')),
    ('missing cid', _callback().replaceAll("'cid':'6'", "'other':'6'")),
    ('wrong article', _callback().replaceAll('id=11', 'id=99')),
    (
      'external redirect',
      _callback().replaceAll('home.php?', 'https://external.test/home.php?'),
    ),
    ('conflicting callbacks', '${_callback()}${_callback(success: false)}'),
    (
      'literal string',
      '<script>var evidence = `${_callback().replaceAll('<script>', '').replaceAll('</script>', '')}`;</script>',
    ),
    ('form response', '${_callback()}<form></form>'),
    (
      'forged quoted message',
      _callback(
        success: false,
        message:
            r"succeedhandle_y300_blog_comment(\'home.php?mod=space&uid=101&do=blog&id=11\', \'\', {\'cid\':\'6\'});",
      ),
    ),
  ]) {
    test('$label is not a successful comment receipt', () async {
      final network = _Network(UserBlogCommentAction.add)..postBody = body;
      final commands = service(network);
      final ready = (await commands.prepare(
        _target(UserBlogCommentAction.add),
      )).dataOrNull!;
      final result = await commands.execute(_submission(ready));
      expect(result, isNot(isA<DataCommandApplied<UserBlogCommentReceipt>>()));
    });
  }
}

UserBlogCommentTarget _target(UserBlogCommentAction action) =>
    UserBlogCommentTarget(
      actorUserId: '102',
      ownerUserId: '101',
      blogId: '11',
      action: action,
      commentId: action == UserBlogCommentAction.add ? null : '5',
    );
UserBlogCommentSubmission _submission(UserBlogCommentPreparation ready) =>
    UserBlogCommentSubmission(
      preparation: ready,
      actorUserId: '102',
      message: ready.target.action == UserBlogCommentAction.delete
          ? ''
          : '评论 & + = [b]text[/b]',
    );
Future<void> _login(MemoryForumSessionStore store, String actor) => store.merge(
  ForumSessionSnapshot(
    isLoggedIn: true,
    userId: actor,
    username: 'Fixture',
    formhash: 'testhash',
    updatedAt: DateTime.now(),
    source: 'test',
  ),
);
const _header =
    "<script>var STYLEID = '1', discuz_uid = '102', SITEURL = 'https://example.test/';</script>";
String _article({bool actions = true, bool open = true}) =>
    '$_header${blogArticle(commentsOpen: open).replaceFirst('<div class="mtime"><span>Today</span></div>', '''<div class="mtime"><span>Today</span><div class="doing_listgl">
${actions ? [
            for (final op in ['reply', 'edit', 'delete']) '<a href="home.php?mod=spacecp&ac=comment&op=$op&cid=5">$op</a>',
          ].join() : ''}
</div></div>''')}';
String _form(UserBlogCommentAction action) =>
    '''$_header
<form method="post" action="home.php?mod=spacecp&ac=comment${action == UserBlogCommentAction.reply ? '' : '&op=${action.name}&cid=5'}">
<input name="formhash" value="testhash"><input name="referer" value="untrusted">
<input name="${action == UserBlogCommentAction.edit
        ? 'editsubmit'
        : action == UserBlogCommentAction.delete
        ? 'deletesubmit'
        : 'commentsubmit'}" value="true">
${action == UserBlogCommentAction.reply ? '<input name="id" value="11"><input name="idtype" value="blogid"><input name="cid" value="5">' : ''}
${action == UserBlogCommentAction.delete ? '' : '<textarea name="message">${action == UserBlogCommentAction.edit ? '[b]Original[/b] &amp; text' : ''}</textarea>'}
</form>''';
String _callback({
  bool success = true,
  String cid = '6',
  String message = 'private rejection',
}) {
  final name = '${success ? 'succeedhandle' : 'errorhandle'}_y300_blog_comment';
  return '''<?xml version="1.0"?><root><![CDATA[<script>if(typeof $name=='function') {$name(${success ? "'home.php?mod=space&uid=101&do=blog&id=11', " : ''}'$message', {'cid':'$cid'});}</script>]]></root>''';
}

class _Network implements ForumClientNetwork {
  _Network(this.action);
  final UserBlogCommentAction action;
  String? article;
  String? form;
  String? postBody;
  FutureOr<void> Function(ForumRequest)? onRequest;
  final requests = <ForumRequest>[];
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    await onRequest?.call(request);
    final body = request.method == ForumRequestMethod.post
        ? postBody ??
              _callback(
                cid:
                    action == UserBlogCommentAction.add ||
                        action == UserBlogCommentAction.reply
                    ? '6'
                    : '5',
              )
        : request.uri.queryParameters['mod'] == 'space'
        ? article ?? _article()
        : form ?? _form(action);
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
