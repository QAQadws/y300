import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../test_support/blog_operation_fixture.dart';

void main() {
  late BlogOperationFixture service;
  String? actor;
  BlogEditorController make({UserBlogAction action = UserBlogAction.edit}) {
    final controller = BlogEditorController(
      target: UserBlogTarget(
        actorUserId: '101',
        ownerUserId: '101',
        action: action,
        blogId: action == UserBlogAction.create ? null : '11',
      ),
      service: service,
      currentActor: () => actor,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<BlogEditorController> ready({
    UserBlogAction action = UserBlogAction.edit,
  }) async {
    final controller = make(action: action);
    final pending = controller.prepare();
    service.preparedEditor();
    await pending;
    return controller;
  }

  setUp(() {
    service = BlogOperationFixture();
    actor = '101';
  });

  test(
    'creation validates locally before consuming one submission proof',
    () async {
      final editor = await ready(action: UserBlogAction.create);
      expect(editor.value.dirty, isFalse);
      await editor.submit();
      expect(editor.value.issue, BlogEditorIssue.subjectRequired);
      editor.update(editor.value.draft.copyWith(subject: 'New title'));
      await editor.submit();
      expect(editor.value.issue, BlogEditorIssue.bodyRequired);
      expect(service.editorSubmissions, isEmpty);
      editor.update(editor.value.draft.copyWith(bodyHtml: '<p>新文章</p>'));
      final submit = editor.submit();
      await editor.submit();
      await editor.prepare();
      service.saved();
      expect((await submit)?.blogId, '12');
      await editor.submit();
      await editor.prepare();
      expect(service.editorPreparations, hasLength(1));
      expect(service.editorSubmissions, hasLength(1));
    },
  );

  test(
    'title-only edit preserves exact HTML and the complete privacy ticket',
    () async {
      const html =
          '<DIV class="original" data-legacy="1">繁體&nbsp;<a href="/x?a=1&amp;b=2">链接</a><img src="/i.png"></DIV>\r\n';
      service.editorForm = (target) => blogEditorPreparation(
        target,
        bodyHtml: html,
        visibility: UserBlogVisibility.passwordProtected,
        commentsEnabled: false,
      );
      final editor = await ready();
      expect(
        editor.value.options!.visibility,
        UserBlogVisibility.passwordProtected,
      );
      expect(editor.value.options!.commentsEnabled, isFalse);
      expect(editor.value.draft.bodyHtml, html);
      editor.update(editor.value.draft.copyWith(subject: 'Changed title'));
      final submit = editor.submit();
      final input = service.editorSubmissions.single.input;
      expect(input.bodyHtml, html);
      expect(input.preparation.bodyHtml, html);
      expect(
        input.preparation.visibility,
        UserBlogVisibility.passwordProtected,
      );
      expect(input.preparation.commentsEnabled, isFalse);
      service.saved();
      expect((await submit)?.blogId, '11');
    },
  );

  test(
    'pending preparation coalesces and cannot lose edits through updates',
    () async {
      final editor = make();
      final prepare = editor.prepare();
      await editor.prepare();
      await editor.submit();
      editor.update(const BlogEditorDraft(subject: 'too early'));
      expect(editor.value.draft.subject, isEmpty);
      service.preparedEditor();
      await prepare;
      expect(editor.value.draft.subject, 'Original title');
      expect(service.editorPreparations, hasLength(1));
      expect(service.editorSubmissions, isEmpty);
    },
  );

  for (final keepLocal in [false, true]) {
    test(
      'changed server version requires explicit review keepLocal=$keepLocal',
      () async {
        final editor = await ready();
        editor.update(
          editor.value.draft.copyWith(
            bodyHtml: '<p>My version</p>',
            tags: 'new tag',
          ),
        );
        final first = editor.submit();
        service.editorSubmissions.last.result.complete(
          const DataCommandRejected(blogActionWriteFailure),
        );
        expect(await first, isNull);
        service.editorForm = (target) =>
            blogEditorPreparation(target, bodyHtml: '<p>Server changed</p>');
        final reload = editor.prepare();
        service.preparedEditor();
        await reload;
        expect(editor.value.draft.bodyHtml, '<p>My version</p>');
        expect(editor.value.serverVersion!.bodyHtml, '<p>Server changed</p>');
        expect(editor.value.canSubmit, isFalse);
        await editor.submit();
        expect(editor.value.issue, BlogEditorIssue.serverChanged);
        expect(service.editorSubmissions, hasLength(1));
        editor.reviewServerVersion(keepLocal: keepLocal);
        expect(editor.value.dirty, keepLocal);
        expect(editor.value.canSubmit, isTrue);
        final submit = editor.submit();
        expect(
          service.editorSubmissions.last.input.bodyHtml,
          keepLocal ? '<p>My version</p>' : '<p>Server changed</p>',
        );
        expect(
          service.editorSubmissions.last.input.preparation.token,
          isNot(same(service.editorSubmissions.first.input.preparation.token)),
        );
        service.saved();
        expect(await submit, isNotNull);
      },
    );
  }

  test(
    'unchanged server reprepare preserves all user edits without extra review',
    () async {
      final editor = await ready();
      final edited = editor.value.draft.copyWith(
        subject: 'Mine',
        bodyHtml: '<p>我的正文</p>',
        tags: 'a b',
        siteCategoryId: '8',
        newPersonalCategory: 'New group',
        publishFeed: true,
      );
      editor.update(edited);
      final submit = editor.submit();
      service.editorSubmissions.last.result.complete(
        const DataCommandNotSent(blogActionWriteFailure),
      );
      await submit;
      await editor.submit();
      final reload = editor.prepare();
      service.preparedEditor();
      await reload;
      expect(editor.value.draft, edited);
      expect(editor.value.needsReview, isFalse);
      expect(service.editorSubmissions, hasLength(1));
      final retry = editor.submit();
      expect(
        service.editorSubmissions.last.input.newPersonalCategory,
        'New group',
      );
      expect(service.editorSubmissions.last.input.publishFeed, isTrue);
      service.saved();
      await retry;
    },
  );

  for (final scenario in [
    'site-required',
    'unknown-site',
    'unknown-personal',
    'new-forbidden',
    'category-conflict',
    'feed-forbidden',
  ]) {
    test(
      '$scenario keeps proof until inputs match current form options',
      () async {
        service.editorForm = (target) => blogEditorPreparation(
          target,
          siteCategoryRequired: scenario == 'site-required',
          canCreateCategory: scenario != 'new-forbidden',
          canPublishFeed: scenario != 'feed-forbidden',
        );
        final editor = await ready();
        final input = editor.value.draft;
        editor.update(switch (scenario) {
          'unknown-site' => input.copyWith(siteCategoryId: '99'),
          'unknown-personal' => input.copyWith(personalCategoryId: '99'),
          'new-forbidden' => input.copyWith(newPersonalCategory: 'New'),
          'category-conflict' => input.copyWith(
            newPersonalCategory: 'New',
            personalCategoryId: '9',
          ),
          'feed-forbidden' => input.copyWith(publishFeed: true),
          _ => input,
        });
        await editor.submit();
        expect(editor.value.issue, isNotNull);
        expect(service.editorSubmissions, isEmpty);
        editor.update(input.copyWith(siteCategoryId: '8'));
        final submit = editor.submit();
        service.saved();
        expect(await submit, isNotNull);
        expect(service.editorPreparations, hasLength(1));
      },
    );
  }

  for (final failure in ['unknown', 'throw', 'wrong-id', 'wrong-target']) {
    test('$failure after saving retains input but cannot replay', () async {
      final editor = await ready();
      editor.update(
        editor.value.draft.copyWith(bodyHtml: '<p>Keep my work</p>'),
      );
      final submit = editor.submit();
      switch (failure) {
        case 'unknown':
          service.editorSubmissions.last.result.complete(
            const DataCommandOutcomeUnknown(blogActionWriteFailure),
          );
        case 'throw':
          service.editorSubmissions.last.result.completeError(
            StateError('fixture transport error'),
          );
        case 'wrong-id':
          service.saved(blogId: '999');
        case 'wrong-target':
          service.saved(target: blogActionTarget(UserBlogAction.delete));
      }
      expect(await submit, isNull);
      expect(editor.value.phase, BlogEditorPhase.unknown);
      editor.update(const BlogEditorDraft());
      await editor.prepare();
      await editor.submit();
      expect(editor.value.draft.bodyHtml, '<p>Keep my work</p>');
      expect(service.editorPreparations, hasLength(1));
      expect(service.editorSubmissions, hasLength(1));
    });
  }

  for (final failure in ['unsupported', 'wrong-target', 'throw']) {
    test(
      '$failure during preparation cannot expose an editable form',
      () async {
        final editor = make();
        final prepare = editor.prepare();
        if (failure == 'throw') {
          service.editorPreparations.last.result.completeError(
            StateError('fixture error'),
          );
        } else {
          service.preparedEditor(
            supported: failure != 'unsupported',
            form: failure == 'wrong-target'
                ? blogEditorPreparation(blogActionTarget(UserBlogAction.create))
                : null,
          );
        }
        await prepare;
        await editor.submit();
        expect(editor.value.phase, BlogEditorPhase.failed);
        expect(editor.value.options, isNull);
        expect(service.editorSubmissions, isEmpty);
      },
    );
  }

  for (final submitting in [false, true]) {
    test(
      'account change during ${submitting ? 'save' : 'prepare'} clears all source and stays expired',
      () async {
        final editor = make();
        final prepare = editor.prepare();
        Future<UserBlogReceipt?>? submit;
        if (submitting) {
          service.preparedEditor();
          await prepare;
          submit = editor.submit();
        }
        actor = '202';
        editor.expire();
        actor = '101';
        if (submitting) {
          service.saved();
          expect(await submit, isNull);
        } else {
          service.preparedEditor();
          await prepare;
        }
        expect(editor.value.phase, BlogEditorPhase.expired);
        expect(editor.value.draft.bodyHtml, isEmpty);
        expect(editor.value.original.bodyHtml, isEmpty);
        expect(editor.value.options, isNull);
        expect(editor.value.serverVersion, isNull);
        await editor.prepare();
        await editor.submit();
        expect(service.editorPreparations, hasLength(1));
        final cancellation = submitting
            ? service.editorSubmissions.last.input.cancellation
            : service.editorPreparations.last.cancellation;
        expect(cancellation!.isCancelled, isTrue);
      },
    );
  }

  test(
    'changing account without a listener is also caught before saving',
    () async {
      final editor = await ready();
      actor = null;
      await editor.submit();
      expect(editor.value.phase, BlogEditorPhase.expired);
      expect(service.editorSubmissions, isEmpty);
    },
  );

  for (final submitting in [false, true]) {
    test(
      'disposing during ${submitting ? 'save' : 'prepare'} drops late results',
      () async {
        final editor = BlogEditorController(
          target: blogActionTarget(UserBlogAction.edit),
          service: service,
          currentActor: () => actor,
        );
        final prepare = editor.prepare();
        Future<UserBlogReceipt?>? submit;
        if (submitting) {
          service.preparedEditor();
          await prepare;
          submit = editor.submit();
        }
        editor.dispose();
        final token = submitting
            ? service.editorSubmissions.last.input.cancellation
            : service.editorPreparations.last.cancellation;
        expect(token!.isCancelled, isTrue);
        if (submitting) {
          service.saved();
          expect(await submit, isNull);
        } else {
          service.preparedEditor();
          await prepare;
        }
      },
    );
  }

  test(
    'changed category options validate the preserved selection on retry',
    () async {
      final editor = await ready();
      editor.update(editor.value.draft.copyWith(siteCategoryId: '8'));
      final first = editor.submit();
      service.editorSubmissions.last.result.complete(
        const DataCommandNotSent(blogActionWriteFailure),
      );
      await first;
      service.editorForm = (target) => blogEditorPreparation(
        target,
        siteCategories: const [UserBlogCategory(id: '0', name: 'None')],
      );
      final prepare = editor.prepare();
      service.preparedEditor();
      await prepare;
      expect(editor.value.draft.siteCategoryId, '8');
      await editor.submit();
      expect(editor.value.issue, BlogEditorIssue.categoryUnavailable);
      expect(service.editorSubmissions, hasLength(1));
    },
  );
}
