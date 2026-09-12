import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_controller.dart';

import '../test_support/blog_comment_fixture.dart';

void main() {
  late BlogCommentFixture service;
  String? actor;
  BlogCommentController controller({
    UserBlogCommentAction action = UserBlogCommentAction.add,
  }) {
    final result = BlogCommentController(
      target: blogCommentTarget(action),
      service: service,
      currentActor: () => actor,
    );
    addTearDown(result.dispose);
    return result;
  }

  setUp(() {
    service = BlogCommentFixture();
    actor = '101';
  });

  test(
    'preparation is read-only, duplicate prepares and submits send once',
    () async {
      final edit = controller(action: UserBlogCommentAction.edit);
      service.initialMessage = '[b]原始文字[/b]\n第二行';
      final preparing = edit.prepare();
      await edit.prepare();
      await edit.submit();
      expect(service.preparations, hasLength(1));
      expect(service.submissions, isEmpty);
      service.prepared();
      await preparing;
      expect(edit.value.message, service.initialMessage);
      expect(edit.value.dirty, isFalse);
      edit.updateMessage('[b]修改[/b]\n第二行');
      final submitting = edit.submit();
      expect(await edit.submit(), isNull);
      expect(service.submissions.single.input.message, '[b]修改[/b]\n第二行');
      service.applied();
      expect((await submitting)!.commentId, '31');
      await edit.prepare();
      await edit.submit();
      expect(service.preparations, hasLength(1));
      expect(service.submissions, hasLength(1));
    },
  );

  test(
    'blank input keeps the proof and allows a corrected explicit submit',
    () async {
      final form = controller();
      final preparing = form.prepare();
      service.prepared();
      await preparing;
      form.updateMessage('  \n');
      expect(await form.submit(), isNull);
      expect(form.value.phase, BlogCommentPhase.ready);
      expect(service.submissions, isEmpty);
      form.updateMessage('好');
      final submit = form.submit();
      service.applied();
      await submit;
      expect(service.preparations, hasLength(1));
    },
  );

  test(
    'rejected submits keep edited input but require new preparation',
    () async {
      final form = controller(action: UserBlogCommentAction.edit);
      service.initialMessage = '原文';
      var preparing = form.prepare();
      service.prepared();
      await preparing;
      form.updateMessage('保留我的修改');
      var submit = form.submit();
      service.submissions.last.result.complete(
        const DataCommandRejected(blogCommentWriteFailure),
      );
      expect(await submit, isNull);
      await form.submit();
      expect(service.submissions, hasLength(1));
      preparing = form.prepare();
      service.initialMessage = '服务器更新过的文字';
      service.prepared();
      await preparing;
      expect(form.value.message, '保留我的修改');
      expect(form.value.initialMessage, '原文');
      submit = form.submit();
      service.applied();
      await submit;
      expect(service.submissions, hasLength(2));
      expect(
        service.submissions[0].input.preparation.token,
        isNot(same(service.submissions[1].input.preparation.token)),
      );
    },
  );

  test(
    'typing after a failed initial read survives a preparation retry',
    () async {
      final form = controller();
      var preparing = form.prepare();
      service.preparations.last.result.complete(blogCommentReadFailure);
      await preparing;
      form.updateMessage('先写好的评论');
      preparing = form.prepare();
      service.prepared();
      await preparing;
      expect(form.value.message, '先写好的评论');
      expect(form.value.dirty, isTrue);
    },
  );

  for (final throws in [false, true]) {
    test(
      'uncertain submission (throws=$throws) preserves input and cannot resend',
      () async {
        final form = controller();
        final preparing = form.prepare();
        service.prepared();
        await preparing;
        form.updateMessage('只发一次');
        final submit = form.submit();
        if (throws) {
          service.submissions.last.result.completeError(
            StateError('fixture transport'),
          );
        } else {
          service.submissions.last.result.complete(
            const DataCommandOutcomeUnknown(blogCommentWriteFailure),
          );
        }
        expect(await submit, isNull);
        expect(form.value.phase, BlogCommentPhase.unknown);
        expect(form.value.message, '只发一次');
        await form.prepare();
        await form.submit();
        expect(service.preparations, hasLength(1));
        expect(service.submissions, hasLength(1));
      },
    );
  }

  test(
    'read exceptions become safe failures and can be prepared again',
    () async {
      final form = controller();
      final preparing = form.prepare();
      service.preparations.last.result.completeError(
        StateError('private fixture payload'),
      );
      await preparing;
      expect(
        (form.value.failure as DataReadFailure).diagnosticMessage,
        'blog_comment_prepare_failed',
      );
      final retry = form.prepare();
      service.prepared();
      await retry;
      expect(form.value.phase, BlogCommentPhase.ready);
    },
  );

  for (final preparing in [true, false]) {
    test(
      'account changes clear inputs and discard late ${preparing ? 'prepare' : 'POST'}',
      () async {
        final form = controller();
        final prepare = form.prepare();
        Future<UserBlogCommentReceipt?>? submit;
        if (!preparing) {
          service.prepared();
          await prepare;
          form.updateMessage('旧账号私密内容');
          submit = form.submit();
        }
        actor = '303';
        form.expire();
        expect(form.value.message, isEmpty);
        expect(form.value.phase, BlogCommentPhase.expired);
        if (preparing) {
          expect(service.preparations.single.cancellation!.isCancelled, isTrue);
          service.prepared();
          await prepare;
        } else {
          expect(
            service.submissions.single.input.cancellation!.isCancelled,
            isTrue,
          );
          service.applied();
          expect(await submit, isNull);
        }
        actor = '101';
        await form.prepare();
        await form.submit();
        expect(form.value.phase, BlogCommentPhase.expired);
        expect(form.value.message, isEmpty);
      },
    );
  }

  test('actor is rechecked even without a provider notification', () async {
    final form = controller();
    final prepare = form.prepare();
    service.prepared();
    await prepare;
    form.updateMessage('评论');
    actor = null;
    await form.submit();
    expect(service.submissions, isEmpty);
    expect(form.value.phase, BlogCommentPhase.expired);
  });

  test(
    'a foreign preparation or missing capability never enables sending',
    () async {
      final form = controller();
      var prepare = form.prepare();
      service.prepared(target: blogCommentTarget(UserBlogCommentAction.reply));
      await prepare;
      expect(form.value.phase, BlogCommentPhase.failed);
      prepare = form.prepare();
      service.prepared(supported: false);
      await prepare;
      await form.submit();
      expect(form.value.phase, BlogCommentPhase.failed);
      expect(service.submissions, isEmpty);
    },
  );

  for (final foreignId in ['', '0', 'bad', '32']) {
    test(
      'an edit receipt for invalid/different comment $foreignId is unproven',
      () async {
        final form = controller(action: UserBlogCommentAction.edit);
        final prepare = form.prepare();
        service.prepared();
        await prepare;
        form.updateMessage('修改');
        final submit = form.submit();
        service.applied(commentId: foreignId);
        expect(await submit, isNull);
        expect(form.value.phase, BlogCommentPhase.unknown);
      },
    );
  }

  test(
    'delete ignores editor text and still requires a confirmed target',
    () async {
      final form = controller(action: UserBlogCommentAction.delete);
      final prepare = form.prepare();
      service.prepared();
      await prepare;
      form.updateMessage('ignored');
      final submit = form.submit();
      expect(service.submissions.single.input.message, isEmpty);
      service.applied(target: blogCommentTarget(UserBlogCommentAction.edit));
      expect(await submit, isNull);
      expect(form.value.phase, BlogCommentPhase.unknown);
    },
  );

  test('disposal cancels preparation and late results never notify', () async {
    final form = BlogCommentController(
      target: blogCommentFixtureTarget,
      service: service,
      currentActor: () => actor,
    );
    var notifications = 0;
    form.addListener(() => notifications++);
    final prepare = form.prepare();
    form.dispose();
    expect(service.preparations.single.cancellation!.isCancelled, isTrue);
    final before = notifications;
    service.prepared();
    await prepare;
    expect(notifications, before);
  });
}
