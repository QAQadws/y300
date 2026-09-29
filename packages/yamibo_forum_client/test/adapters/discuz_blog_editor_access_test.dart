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

  Future<UserBlogEditorPreparation> prepare(
    UserBlogOperations commands,
  ) async => (await commands.prepareEditor(
    blogOperationTarget(UserBlogAction.edit),
  )).dataOrNull!;

  Map<String, String> postedFields(BlogOperationNetwork network) =>
      Map.fromEntries(
        (network.posts.single.body! as ForumMultipartFields).entries,
      );

  test(
    'preparation exposes source choices and only a password presence flag',
    () async {
      for (final visibility in UserBlogVisibility.values) {
        final network = BlogOperationNetwork(UserBlogAction.edit)
          ..editor = blogEditorForm(visibility: visibility.index);
        final ready = await prepare(service(network));
        expect(ready.availableVisibilities, UserBlogVisibility.values);
        expect(ready.canEditComments, isTrue);
        expect(
          ready.hasPassword,
          visibility == UserBlogVisibility.passwordProtected,
        );
        expect(ready.targetNames, 'Reader One Reader Two');
      }
    },
  );

  test('disabled options and groups do not advertise access changes', () async {
    final network = BlogOperationNetwork(UserBlogAction.edit)
      ..editor = blogEditorForm().replaceFirst(
        RegExp(r'<select name="friend">.*?</select>'),
        '<select name="friend"><option value="0" selected>Public</option>'
        '<option value="1" disabled>Friends</option>'
        '<optgroup disabled><option value="2">Selected</option></optgroup>'
        '<option value="3">Private</option><option value="4" disabled>Password</option></select>',
      );
    final commands = service(network);
    final ready = await prepare(commands);
    expect(ready.availableVisibilities, [
      UserBlogVisibility.public,
      UserBlogVisibility.private,
    ]);
    for (final visibility in [
      UserBlogVisibility.friends,
      UserBlogVisibility.selectedFriends,
      UserBlogVisibility.passwordProtected,
    ]) {
      expect(
        await commands.save(
          blogEditorSubmission(
            ready,
            visibility: visibility,
            password: visibility == UserBlogVisibility.passwordProtected
                ? 'new.secret'
                : null,
          ),
        ),
        isA<DataCommandNotSent<UserBlogReceipt>>(),
      );
    }
    expect(network.posts, isEmpty);
    expect(
      await commands.save(
        blogEditorSubmission(ready, visibility: UserBlogVisibility.private),
      ),
      isA<DataCommandApplied<UserBlogReceipt>>(),
    );
  });

  for (final original in UserBlogVisibility.values) {
    for (final next in UserBlogVisibility.values) {
      test(
        'access policy $original can become $next without unrelated secrets',
        () async {
          final network = BlogOperationNetwork(UserBlogAction.edit)
            ..editor = blogEditorForm(visibility: original.index);
          final commands = service(network);
          final ready = await prepare(commands);
          expect(
            await commands.save(
              blogEditorSubmission(
                ready,
                visibility: next,
                password: next == UserBlogVisibility.passwordProtected
                    ? '  new.secret  '
                    : null,
                targetNames: next == UserBlogVisibility.selectedFriends
                    ? 'Alice 李明'
                    : null,
              ),
            ),
            isA<DataCommandApplied<UserBlogReceipt>>(),
          );
          final fields = postedFields(network);
          expect(fields['friend'], '${next.index}');
          expect(fields['noreply'], '0');
          expect(
            fields['password'],
            next == UserBlogVisibility.passwordProtected
                ? 'new.secret'
                : original == next
                ? 'fixture.password'
                : '',
          );
          expect(
            fields['target_names'],
            next == UserBlogVisibility.selectedFriends
                ? 'Alice 李明'
                : original == next
                ? 'Reader One Reader Two'
                : '',
          );
        },
      );
    }
  }

  for (final commentsEnabled in [false, true]) {
    test('comment preference changes to $commentsEnabled', () async {
      final network = BlogOperationNetwork(UserBlogAction.edit)
        ..editor = blogEditorForm(commentsEnabled: !commentsEnabled);
      final commands = service(network);
      final ready = await prepare(commands);
      expect(
        await commands.save(
          blogEditorSubmission(ready, commentsEnabled: commentsEnabled),
        ),
        isA<DataCommandApplied<UserBlogReceipt>>(),
      );
      final fields = postedFields(network);
      expect(fields['noreply'], commentsEnabled ? '0' : '1');
      expect(fields['friend'], '0');
      expect(fields['password'], 'fixture.password');
      expect(fields['target_names'], 'Reader One Reader Two');
    });
  }

  test('existing password is retained only by a null password edit', () async {
    final network = BlogOperationNetwork(UserBlogAction.edit)
      ..editor = blogEditorForm(visibility: 4);
    final commands = service(network);
    final ready = await prepare(commands);
    for (final password in ['', ' \t ']) {
      expect(
        await commands.save(blogEditorSubmission(ready, password: password)),
        isA<DataCommandNotSent<UserBlogReceipt>>(),
      );
    }
    expect(network.posts, isEmpty);
    expect(
      await commands.save(
        blogEditorSubmission(
          ready,
          visibility: UserBlogVisibility.passwordProtected,
          commentsEnabled: false,
        ),
      ),
      isA<DataCommandApplied<UserBlogReceipt>>(),
    );
    expect(postedFields(network)['password'], 'fixture.password');
  });

  test(
    'switching to password protection requires an explicit new password',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.edit);
      final commands = service(network);
      final ready = await prepare(commands);
      expect(ready.hasPassword, isFalse);
      for (final password in [null, '', '  ']) {
        expect(
          await commands.save(
            blogEditorSubmission(
              ready,
              visibility: UserBlogVisibility.passwordProtected,
              password: password,
            ),
          ),
          isA<DataCommandNotSent<UserBlogReceipt>>(),
        );
      }
      expect(network.posts, isEmpty);
      expect(
        await commands.save(
          blogEditorSubmission(
            ready,
            visibility: UserBlogVisibility.passwordProtected,
            password: 'explicit.password',
          ),
        ),
        isA<DataCommandApplied<UserBlogReceipt>>(),
      );
    },
  );

  test(
    'specified users require a nonempty list and allow correcting the same ticket',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.edit)
        ..editor = blogEditorForm().replaceFirst('Reader One Reader Two', '');
      final commands = service(network);
      final ready = await prepare(commands);
      for (final names in [null, '', ' \n ']) {
        expect(
          await commands.save(
            blogEditorSubmission(
              ready,
              visibility: UserBlogVisibility.selectedFriends,
              targetNames: names,
            ),
          ),
          isA<DataCommandNotSent<UserBlogReceipt>>(),
        );
      }
      expect(network.posts, isEmpty);
      expect(
        await commands.save(
          blogEditorSubmission(
            ready,
            visibility: UserBlogVisibility.selectedFriends,
            targetNames: '甲\n乙 丙',
          ),
        ),
        isA<DataCommandApplied<UserBlogReceipt>>(),
      );
      expect(postedFields(network)['target_names'], '甲\n乙 丙');
    },
  );

  test(
    'caller metadata cannot turn retained hidden fields into editable controls',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.edit)
        ..editor = blogEditorForm(visibility: 4)
            .replaceFirst(
              RegExp(r'<select name="friend">.*?</select>'),
              '<input type="hidden" name="friend" value="4">',
            )
            .replaceFirst(
              '<input type="checkbox" name="noreply" value="1">',
              '<input type="hidden" name="noreply" value="0">',
            );
      final commands = service(network);
      final ready = await prepare(commands);
      expect(ready.availableVisibilities, isEmpty);
      expect(ready.canEditComments, isFalse);
      final forged = _advertiseAllAccess(ready);
      for (final submission in [
        blogEditorSubmission(forged, visibility: UserBlogVisibility.public),
        blogEditorSubmission(forged, commentsEnabled: false),
        blogEditorSubmission(forged, password: 'new.secret'),
      ]) {
        expect(
          await commands.save(submission),
          isA<DataCommandNotSent<UserBlogReceipt>>(),
        );
      }
      expect(network.posts, isEmpty);
      expect(
        await commands.save(
          blogEditorSubmission(
            ready,
            visibility: ready.visibility,
            commentsEnabled: ready.commentsEnabled,
          ),
        ),
        isA<DataCommandApplied<UserBlogReceipt>>(),
      );
      expect(postedFields(network)['password'], 'fixture.password');
    },
  );

  test(
    'readonly specified-user lists cannot be edited through a forged preparation',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.edit)
        ..editor = blogEditorForm(visibility: 2).replaceFirst(
          RegExp(r'<select name="friend">.*?</select>'),
          '<input type="hidden" name="friend" value="2">',
        );
      final commands = service(network);
      final ready = await prepare(commands);
      expect(
        await commands.save(
          blogEditorSubmission(
            _advertiseAllAccess(ready),
            targetNames: 'Someone else',
          ),
        ),
        isA<DataCommandNotSent<UserBlogReceipt>>(),
      );
      expect(network.posts, isEmpty);
    },
  );

  test(
    'values for a different policy cannot be submitted as stray access edits',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.edit);
      final commands = service(network);
      final ready = await prepare(commands);
      for (final submission in [
        blogEditorSubmission(ready, password: 'unexpected.password'),
        blogEditorSubmission(ready, targetNames: 'Unexpected user'),
      ]) {
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
    },
  );

  for (final options in [
    '<option value="0" selected>Public</option><option value="5">Unknown</option>',
    '<option value="0" selected>Public</option><option value="0">Duplicate</option>',
  ]) {
    test(
      'ambiguous or unknown access choices are unsupported: $options',
      () async {
        final network = BlogOperationNetwork(UserBlogAction.edit)
          ..editor = blogEditorForm().replaceFirst(
            RegExp(r'<select name="friend">.*?</select>'),
            '<select name="friend">$options</select>',
          );
        final result = await service(
          network,
        ).prepareEditor(blogOperationTarget(UserBlogAction.edit));
        expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
        expect(network.posts, isEmpty);
      },
    );
  }

  for (final during in [false, true]) {
    test(
      'access edits respect account change ${during ? 'during' : 'before'} POST',
      () async {
        final network = BlogOperationNetwork(UserBlogAction.edit);
        final commands = service(network);
        final ready = await prepare(commands);
        if (during) {
          network.onRequest = (_) => loginBlogActor(sessions, '102');
        } else {
          await loginBlogActor(sessions, '102');
        }
        final result = await commands.save(
          blogEditorSubmission(
            ready,
            visibility: UserBlogVisibility.passwordProtected,
            password: 'private.password',
            commentsEnabled: false,
          ),
        );
        expect(
          result,
          during
              ? isA<DataCommandOutcomeUnknown<UserBlogReceipt>>()
              : isA<DataCommandNotSent<UserBlogReceipt>>(),
        );
        expect(network.posts, hasLength(during ? 1 : 0));
        expect(
          result.failureOrNull!.diagnosticMessage,
          isNot(contains('private.password')),
        );
      },
    );
  }

  test(
    'uncertain access writes are never automatically submitted again',
    () async {
      final network = BlogOperationNetwork(UserBlogAction.edit);
      final commands = service(network);
      final ready = await prepare(commands);
      network.onRequest = (_) => throw StateError('private.password');
      final submission = blogEditorSubmission(
        ready,
        visibility: UserBlogVisibility.passwordProtected,
        password: 'private.password',
      );
      final result = await commands.save(submission);
      expect(result, isA<DataCommandOutcomeUnknown<UserBlogReceipt>>());
      expect(result.failureOrNull!.retryPolicy, DataCommandRetryPolicy.never);
      expect(
        result.failureOrNull!.diagnosticMessage,
        isNot(contains('private.password')),
      );
      expect(
        await commands.save(submission),
        isA<DataCommandNotSent<UserBlogReceipt>>(),
      );
      expect(network.posts, hasLength(1));
    },
  );
}

UserBlogEditorPreparation _advertiseAllAccess(
  UserBlogEditorPreparation ready,
) => UserBlogEditorPreparation(
  target: ready.target,
  token: ready.token,
  subject: ready.subject,
  bodyHtml: ready.bodyHtml,
  tags: ready.tags,
  siteCategories: ready.siteCategories,
  personalCategories: ready.personalCategories,
  siteCategoryId: ready.siteCategoryId,
  personalCategoryId: ready.personalCategoryId,
  siteCategoryRequired: ready.siteCategoryRequired,
  canCreateCategory: ready.canCreateCategory,
  canPublishFeed: ready.canPublishFeed,
  publishFeed: ready.publishFeed,
  visibility: ready.visibility,
  commentsEnabled: ready.commentsEnabled,
  availableVisibilities: UserBlogVisibility.values,
  canEditComments: true,
  hasPassword: true,
  targetNames: ready.targetNames,
);
