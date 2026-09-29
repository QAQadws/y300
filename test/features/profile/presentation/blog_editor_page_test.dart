import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_sticker_image_cache_loader.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_quill_html_codec.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_navigation_fixture.dart';
import '../test_support/blog_operation_fixture.dart';

void main() {
  testWidgets('settings have one AppBar entry and a noninteractive summary', (
    tester,
  ) async {
    final service = BlogOperationFixture(autoPrepare: true);
    await _open(tester, service);
    final summary = find.byKey(const Key('blog-editor-settings-summary'));
    expect(summary, findsOneWidget);
    expect(find.byKey(const Key('blog-editor-settings')), findsOneWidget);
    expect(
      find.ancestor(of: summary, matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(find.byKey(const Key('blog-body-mode-menu')), findsNothing);
    expect(find.byKey(const Key('blog-insert-image')), findsNothing);
    await tester.tap(summary);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('blog-editor-settings-sheet')), findsNothing);
    await _openSettings(tester);
  });

  testWidgets(
    'bold italic underline and font size edit the selected visual text',
    (tester) async {
      final service = BlogOperationFixture(autoPrepare: true);
      await _open(tester, service);
      await _replaceBody(tester, 'formatted text');
      final body = _body(tester).controller;
      body.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 9),
        ChangeSource.local,
      );
      await tester.pump();
      for (final key in [
        'blog-format-bold',
        'blog-format-italic',
        'blog-format-underline',
      ]) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('blog-format-size')));
      await tester.pumpAndSettle();
      _expectNoSheetHandle(tester);
      await tester.tap(find.byKey(const Key('blog-font-size-4')));
      await tester.pumpAndSettle();
      await _save(tester);
      final html = service.editorSubmissions.single.input.bodyHtml;
      expect(html, contains('<b>'));
      expect(html, contains('<i>'));
      expect(html, contains('<u>'));
      expect(html, contains('<font size="4">'));
      expect(html, isNot(contains('style=')));
      expect(_plainText(html), 'formatted text');
      service.saved();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'the dedicated thirty-smiley picker inserts a journal HTML image',
    (tester) async {
      final service = BlogOperationFixture(autoPrepare: true);
      final smilies = List.generate(
        30,
        (index) => UserBlogSmiley(
          index: index + 1,
          imageUri: Uri.parse(
            'https://example.test/static/image/smiley/comcom/${index + 1}.gif',
          ),
        ),
      );
      service.editorForm = (target) =>
          blogEditorPreparation(target, bodyHtml: '', blogSmilies: smilies);
      await _open(tester, service);
      await tester.tap(find.byKey(const Key('blog-insert-smiley')));
      await tester.pumpAndSettle();
      final picker = find.byKey(const Key('blog-smiley-picker'));
      expect(picker, findsOneWidget);
      _expectNoSheetHandle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('blog-smiley-30')),
        200,
        scrollable: find
            .descendant(of: picker, matching: find.byType(Scrollable))
            .first,
      );
      await tester.tap(find.byKey(const Key('blog-smiley-30')));
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
      await _save(tester);
      final html = service.editorSubmissions.single.input.bodyHtml;
      expect(html, contains('<img src="${smilies.last.imageUri}">'));
      expect(html, isNot(contains('[attach')));
      service.saved();
      await tester.pumpAndSettle();
    },
  );

  for (final outcomeUnknown in [false, true]) {
    testWidgets(
      outcomeUnknown
          ? 'unknown image uploads stay uninserted and are not automatically replayed'
          : 'image selection uploads once then inserts its confirmed album receipt',
      (tester) async {
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('blog-upload-ui-'),
        ))!;
        addTearDown(() => directory.delete(recursive: true));
        final path = '${directory.path}/picked.png';
        await tester.runAsync(
          () => File(path).writeAsBytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
          ),
        );
        final service = BlogOperationFixture(autoPrepare: true);
        service.editorForm = (target) => blogEditorPreparation(
          target,
          bodyHtml: '',
          imageUploadLimits: const UserBlogImageUploadLimits(
            extensionRules: [
              ForumImageAttachmentExtensionRule(extension: 'png'),
            ],
          ),
        );
        final picker = _PageImagePicker(path);
        final media = _PageMediaService();
        await _open(tester, service, imagePicker: picker, media: media);
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const Key('blog-insert-image')));
          for (var i = 0; i < 100 && media.request == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        });
        await tester.pump();
        expect(picker.calls, 1);
        expect(media.request, isNotNull);
        expect(_submitButton(tester).onPressed, isNull);
        expect(_body(tester).controller.readOnly, isTrue);
        final image = UserBlogUploadedImage(
          picId: '41',
          imageUri: Uri.parse('https://example.test/album/41.png.thumb.jpg'),
          originalImageUri: Uri.parse('https://example.test/album/41.png'),
          token: _PageImageToken(),
        );
        media.result.complete(
          outcomeUnknown
              ? const DataCommandOutcomeUnknown(
                  DataCommandFailure(
                    kind: DataCommandFailureKind.network,
                    retryPolicy: DataCommandRetryPolicy.never,
                    code: 'blog_image_upload_outcome_unknown',
                    diagnosticMessage: 'blog_image_upload_outcome_unknown',
                  ),
                )
              : DataCommandApplied(image),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        expect(_body(tester).controller.readOnly, isFalse);
        if (outcomeUnknown) {
          expect(
            find.text(_l10n(tester).profileBlogImageUploadUnknown),
            findsOneWidget,
          );
          expect(media.calls, 1);
          expect(picker.calls, 1);
          expect(_body(tester).controller.document.toPlainText(), '\n');
          expect(service.editorSubmissions, isEmpty);
          return;
        }
        expect(
          const BlogQuillHtmlCodec().encodeDocument(
            _body(tester).controller.document,
          ),
          contains(image.imageUri.toString()),
        );
        await _save(tester);
        final submission = service.editorSubmissions.single.input;
        expect(submission.uploadedImages, [image]);
        expect(submission.bodyHtml, contains(image.imageUri.toString()));
        expect(submission.bodyHtml, isNot(contains(path)));
        expect(submission.bodyHtml, isNot(contains('[attach')));
        service.saved();
        await tester.pumpAndSettle();
      },
    );
  }

  for (final smileySheet in [false, true]) {
    testWidgets(
      'an empty editor rejects old ${smileySheet ? 'smiley' : 'size'} actions after account change',
      (tester) async {
        final service = BlogOperationFixture(autoPrepare: true);
        service.editorForm = (target) => blogEditorPreparation(
          target,
          bodyHtml: '',
          blogSmilies: [
            UserBlogSmiley(
              index: 1,
              imageUri: Uri.parse(
                'https://example.test/static/image/smiley/comcom/1.gif',
              ),
            ),
          ],
        );
        final host = await _open(tester, service);
        final original = _body(tester).controller;
        await tester.tap(
          find.byKey(
            Key(smileySheet ? 'blog-insert-smiley' : 'blog-format-size'),
          ),
        );
        await tester.pumpAndSettle();
        host.changeActor('202');
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(Key(smileySheet ? 'blog-smiley-1' : 'blog-font-size-4')),
        );
        await tester.pumpAndSettle();
        expect(original.document.toPlainText(), '\n');
        expect(
          original.getSelectionStyle().attributes[Attribute.size.key],
          isNull,
        );
        expect(find.byType(QuillEditor), findsNothing);
        expect(service.editorSubmissions, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'create prepares before input and saves exact plain content once',
    (tester) async {
      final service = BlogOperationFixture();
      final host = await _open(tester, service, create: true);
      expect(find.byType(TextField), findsNothing);
      expect(_submitButton(tester).onPressed, isNull);
      service.preparedEditor();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(QuillEditor), findsOneWidget);
      expect(find.byKey(const Key('blog-body-mode-menu')), findsNothing);
      expect(find.byKey(const Key('blog-editor-save')), findsNothing);
      expect(find.byKey(const Key('blog-editor-tags')), findsNothing);
      expect(
        find.byKey(const Key('blog-editor-settings-summary')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('blog-editor-subject')),
        'A new journal',
      );
      await _replaceBody(tester, '  第一行 <b>文字</b>\n\n第二行');
      await _save(tester);
      expect(service.editorSubmissions, hasLength(1));
      expect(
        _plainText(service.editorSubmissions.single.input.bodyHtml),
        '  第一行 <b>文字</b>\n\n第二行',
      );
      expect(_submitButton(tester).onPressed, isNull);
      service.saved();
      await tester.pumpAndSettle();
      expect((await host.result)?.receipt.blogId, '12');
      expect((await host.result)?.subject, 'A new journal');
      expect(host.container.read(blogMutationBusProvider).last?.blogId, '12');
    },
  );

  testWidgets(
    'preview does not rewrite HTML or submit and title-only edit preserves source',
    (tester) async {
      final service = BlogOperationFixture(autoPrepare: true);
      const html = '<p class="keep">繁體 <b>原文</b> &amp; literal</p>';
      service.editorForm = (target) => blogEditorPreparation(
        target,
        bodyHtml: html,
        visibility: UserBlogVisibility.passwordProtected,
        commentsEnabled: false,
      );
      final host = await _open(tester, service);
      await tester.enterText(
        find.byKey(const Key('blog-editor-subject')),
        'Title <not a tag>',
      );
      await tester.tap(find.byKey(const Key('blog-editor-preview-toggle')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ForumHtmlContentView>(find.byType(ForumHtmlContentView))
            .html,
        '<h2>Title &lt;not a tag&gt;</h2>$html',
      );
      expect(service.editorSubmissions, isEmpty);
      await tester.tap(find.byKey(const Key('blog-editor-preview-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(QuillEditor), findsOneWidget);
      await _save(tester);
      expect(service.editorSubmissions.single.input.bodyHtml, html);
      expect(
        service.editorSubmissions.single.input.preparation.visibility,
        UserBlogVisibility.passwordProtected,
      );
      expect(
        service.editorSubmissions.single.input.preparation.commentsEnabled,
        isFalse,
      );
      service.saved();
      await tester.pumpAndSettle();
      expect(await host.result, isNotNull);
    },
  );

  testWidgets(
    'category creation requires a name and passes metadata to the prepared form',
    (tester) async {
      final service = BlogOperationFixture(autoPrepare: true);
      await _open(tester, service);
      final l10n = _l10n(tester);
      await _choose(tester, 'blog-editor-site-category', 'Stories');
      await _choose(
        tester,
        'blog-editor-personal-category',
        l10n.profileBlogNewCategory,
      );
      await _save(tester);
      await tester.pumpAndSettle();
      expect(service.editorSubmissions, isEmpty);
      expect(
        find.byKey(const Key('blog-editor-settings-sheet')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('blog-editor-category-name')),
            )
            .decoration!
            .errorText,
        l10n.profileBlogNewCategoryNameRequired,
      );
      await tester.ensureVisible(
        find.byKey(const Key('blog-editor-category-name')),
      );
      await tester.enterText(
        find.byKey(const Key('blog-editor-category-name')),
        '新的分类',
      );
      await tester.ensureVisible(find.byKey(const Key('blog-editor-tags')));
      await tester.enterText(
        find.byKey(const Key('blog-editor-tags')),
        'one two',
      );
      await tester.ensureVisible(
        find.byKey(const Key('blog-editor-publish-feed')),
      );
      await tester.tap(find.byKey(const Key('blog-editor-publish-feed')));
      await tester.pump();
      await _save(tester);
      final input = service.editorSubmissions.single.input;
      expect(input.siteCategoryId, '8');
      expect(input.personalCategoryId, '0');
      expect(input.newPersonalCategory, '新的分类');
      expect(input.tags, 'one two');
      expect(input.publishFeed, isTrue);
      service.saved();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'settings update the draft immediately and survive closing and reopening',
    (tester) async {
      final service = BlogOperationFixture(autoPrepare: true);
      await _open(tester, service);
      await _openSettings(tester);
      await tester.ensureVisible(find.byKey(const Key('blog-editor-tags')));
      await tester.enterText(
        find.byKey(const Key('blog-editor-tags')),
        '新的标签, reading',
      );
      await _choose(tester, 'blog-editor-personal-category', 'Travel');
      await tester.ensureVisible(
        find.byKey(const Key('blog-editor-publish-feed')),
      );
      await tester.tap(find.byKey(const Key('blog-editor-publish-feed')));
      await _closeSettings(tester, tapBarrier: true);
      expect(service.editorSubmissions, isEmpty);
      await _openSettings(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('blog-editor-tags')))
            .controller!
            .text,
        '新的标签, reading',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('blog-editor-personal-category')),
          matching: find.text('Travel'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('blog-editor-publish-feed')),
            )
            .value,
        isTrue,
      );
      await _save(tester);
      final input = service.editorSubmissions.single.input;
      expect(input.tags, '新的标签, reading');
      expect(input.personalCategoryId, '9');
      expect(input.publishFeed, isTrue);
      service.saved();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('account change clears an open settings sheet and its input', (
    tester,
  ) async {
    final service = BlogOperationFixture(autoPrepare: true);
    final host = await _open(tester, service);
    final l10n = _l10n(tester);
    await _openSettings(tester);
    await tester.ensureVisible(find.byKey(const Key('blog-editor-tags')));
    await tester.enterText(
      find.byKey(const Key('blog-editor-tags')),
      'old account draft',
    );
    host.changeActor('202');
    await tester.pumpAndSettle();
    expect(find.byType(TextField, skipOffstage: false), findsNothing);
    expect(find.text('old account draft', skipOffstage: false), findsNothing);
    expect(find.text(l10n.forumWebViewAccountChanged), findsWidgets);
    expect(service.editorSubmissions, isEmpty);
    host.changeActor('101');
    await tester.pumpAndSettle();
    expect(find.byType(TextField, skipOffstage: false), findsNothing);
    expect(host.container.read(blogMutationBusProvider).last, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final visibility in UserBlogVisibility.values) {
    testWidgets(
      'native access settings submit $visibility and updated comment policy',
      (tester) async {
        final service = BlogOperationFixture(autoPrepare: true);
        service.editorForm = (target) => blogEditorPreparation(
          target,
          visibility: visibility == UserBlogVisibility.public
              ? UserBlogVisibility.friends
              : UserBlogVisibility.public,
          availableVisibilities: UserBlogVisibility.values,
          canEditComments: true,
          hasPassword: false,
        );
        await _open(tester, service);
        final l10n = _l10n(tester);
        await _choose(
          tester,
          'blog-editor-visibility',
          _visibilityLabel(l10n, visibility),
        );
        const names = 'Alice  Bob\n名字甲';
        const password = 'a new p@ssword';
        if (visibility == UserBlogVisibility.selectedFriends) {
          final field = find.byKey(const Key('blog-editor-target-names'));
          await tester.ensureVisible(field);
          await tester.enterText(field, names);
        }
        if (visibility == UserBlogVisibility.passwordProtected) {
          final field = find.byKey(const Key('blog-editor-password'));
          await tester.ensureVisible(field);
          expect(tester.widget<TextField>(field).obscureText, isTrue);
          await tester.enterText(field, password);
        }
        final comments = find.byKey(const Key('blog-editor-comments-enabled'));
        await tester.ensureVisible(comments);
        await tester.tap(comments);
        await tester.pump();
        await _closeSettings(tester);
        final summary = find.byKey(const Key('blog-editor-settings-summary'));
        expect(
          find.descendant(
            of: summary,
            matching: find.textContaining(_visibilityLabel(l10n, visibility)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: summary,
            matching: find.textContaining(l10n.profileBlogCommentsClosed),
          ),
          findsOneWidget,
        );
        await _save(tester);
        final input = service.editorSubmissions.single.input;
        expect(input.visibility, visibility);
        expect(input.commentsEnabled, isFalse);
        expect(
          input.password,
          visibility == UserBlogVisibility.passwordProtected ? password : null,
        );
        if (visibility == UserBlogVisibility.selectedFriends) {
          expect(input.targetNames, names);
        }
        service.saved();
        await tester.pumpAndSettle();
      },
    );
  }

  for (final visibility in [
    UserBlogVisibility.passwordProtected,
    UserBlogVisibility.selectedFriends,
  ]) {
    testWidgets(
      'empty private access input for $visibility reopens settings before submit',
      (tester) async {
        final service = BlogOperationFixture(autoPrepare: true);
        service.editorForm = (target) => blogEditorPreparation(
          target,
          availableVisibilities: UserBlogVisibility.values,
          hasPassword: false,
          targetNames: '',
        );
        await _open(tester, service);
        await _choose(
          tester,
          'blog-editor-visibility',
          _visibilityLabel(_l10n(tester), visibility),
        );
        final passwordMode = visibility == UserBlogVisibility.passwordProtected;
        final field = find.byKey(
          Key(
            passwordMode ? 'blog-editor-password' : 'blog-editor-target-names',
          ),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, passwordMode ? '   ' : ' \n ');
        await _save(tester);
        await tester.pumpAndSettle();
        expect(service.editorSubmissions, isEmpty);
        expect(
          find.byKey(const Key('blog-editor-settings-sheet')),
          findsOneWidget,
        );
        await tester.ensureVisible(field);
        await tester.enterText(
          field,
          passwordMode ? 'new password' : 'Alice Bob',
        );
        await _save(tester);
        expect(service.editorSubmissions, hasLength(1));
        service.saved();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'existing password is not filled and leaving it blank preserves it',
    (tester) async {
      final service = BlogOperationFixture(autoPrepare: true);
      service.editorForm = (target) => blogEditorPreparation(
        target,
        visibility: UserBlogVisibility.passwordProtected,
        availableVisibilities: UserBlogVisibility.values,
        hasPassword: true,
      );
      await _open(tester, service);
      await _openSettings(tester);
      final field = find.byKey(const Key('blog-editor-password'));
      await tester.ensureVisible(field);
      final password = tester.widget<TextField>(field);
      expect(password.obscureText, isTrue);
      expect(password.controller!.text, isEmpty);
      await _save(tester);
      final input = service.editorSubmissions.single.input;
      expect(input.visibility, UserBlogVisibility.passwordProtected);
      expect(input.password, isNull);
      service.saved();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('account switch clears a password entered in the open sheet', (
    tester,
  ) async {
    final service = BlogOperationFixture(autoPrepare: true);
    service.editorForm = (target) => blogEditorPreparation(
      target,
      availableVisibilities: UserBlogVisibility.values,
      hasPassword: false,
    );
    final host = await _open(tester, service);
    await _choose(
      tester,
      'blog-editor-visibility',
      _l10n(tester).profileBlogVisibilityPassword,
    );
    final field = find.byKey(const Key('blog-editor-password'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'old-account-private-secret');
    final input = tester.widget<TextField>(field).controller!;
    host.changeActor('202');
    await tester.pumpAndSettle();
    expect(input.text, isEmpty);
    expect(find.byType(TextField, skipOffstage: false), findsNothing);
    expect(service.editorSubmissions, isEmpty);
    host.changeActor('101');
    await tester.pumpAndSettle();
    expect(find.byType(TextField, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unknown submission keeps access settings readable but immutable',
    (tester) async {
      final service = BlogOperationFixture(autoPrepare: true);
      service.editorForm = (target) => blogEditorPreparation(
        target,
        visibility: UserBlogVisibility.passwordProtected,
        availableVisibilities: UserBlogVisibility.values,
        canEditComments: true,
        hasPassword: true,
      );
      await _open(tester, service);
      await _save(tester);
      service.editorSubmissions.single.result.complete(
        const DataCommandOutcomeUnknown(blogActionWriteFailure),
      );
      await tester.pumpAndSettle();
      await _openSettings(tester);
      final visibility = find.byKey(const Key('blog-editor-visibility'));
      final dropdown = find.descendant(
        of: visibility,
        matching: find.byType(DropdownButton<UserBlogVisibility>),
      );
      expect(
        tester.widget<DropdownButton<UserBlogVisibility>>(dropdown).onChanged,
        isNull,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('blog-editor-comments-enabled')),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('blog-editor-password')))
            .readOnly,
        isTrue,
      );
      expect(find.byKey(const Key('blog-editor-open-web')), findsNothing);
      await _closeSettings(tester);
      expect(_submitButton(tester).onPressed, isNull);
      expect(service.editorSubmissions, hasLength(1));
    },
  );

  for (final useServer in [false, true]) {
    testWidgets(
      'known failure retains input and server review useServer=$useServer',
      (tester) async {
        final service = BlogOperationFixture(autoPrepare: true);
        await _open(tester, service);
        await _replaceBody(tester, 'My version');
        await _save(tester);
        service.editorSubmissions.last.result.complete(
          const DataCommandRejected(blogActionWriteFailure),
        );
        await tester.pumpAndSettle();
        expect(_body(tester).controller.document.toPlainText(), 'My version\n');
        service.editorForm = (target) =>
            blogEditorPreparation(target, bodyHtml: '<p>Server version</p>');
        await _reveal(tester, find.byKey(const Key('blog-editor-retry')));
        await tester.tap(find.byKey(const Key('blog-editor-retry')));
        await tester.pumpAndSettle();
        expect(_submitButton(tester).onPressed, isNull);
        await _reveal(
          tester,
          find.byKey(const Key('blog-editor-show-server')),
          delta: -200,
        );
        await tester.tap(find.byKey(const Key('blog-editor-show-server')));
        await tester.pumpAndSettle();
        expect(find.byType(ForumHtmlContentView), findsOneWidget);
        final choice = find.byKey(
          Key(useServer ? 'blog-editor-use-server' : 'blog-editor-keep-local'),
        );
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(
          _body(tester).controller.document.toPlainText(),
          useServer ? 'Server version\n' : 'My version\n',
        );
        await _save(tester);
        expect(
          _plainText(service.editorSubmissions.last.input.bodyHtml),
          useServer ? 'Server version' : 'My version',
        );
        service.saved();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'unknown outcome retains copyable input without retry or browser resend',
    (tester) async {
      final service = BlogOperationFixture(autoPrepare: true);
      final host = await _open(tester, service);
      await _replaceBody(tester, 'Uncertain input');
      await _save(tester);
      service.editorSubmissions.last.result.complete(
        const DataCommandOutcomeUnknown(blogActionWriteFailure),
      );
      await tester.pumpAndSettle();
      expect(_body(tester).controller.readOnly, isTrue);
      expect(
        _body(tester).controller.document.toPlainText(),
        'Uncertain input\n',
      );
      expect(find.byKey(const Key('blog-editor-retry')), findsNothing);
      expect(find.byKey(const Key('blog-editor-open-web')), findsNothing);
      expect(_submitButton(tester).onPressed, isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('blog-editor-leave')));
      await tester.pumpAndSettle();
      expect(await host.result, isNull);
      expect(host.container.read(blogMutationBusProvider).last, isNull);
    },
  );

  testWidgets(
    'browser fallback requires input warning and destroys the old editor',
    (tester) async {
      final service = BlogOperationFixture(autoPrepare: true);
      final host = await _open(tester, service);
      await tester.enterText(
        find.byKey(const Key('blog-editor-subject')),
        'My changes',
      );
      final web = find.byKey(const Key('blog-editor-open-web'));
      await _openSettings(tester);
      await _reveal(tester, web);
      await tester.tap(web);
      await tester.pumpAndSettle();
      expect(host.webLaunches, isEmpty);
      await tester.tap(find.text(_l10n(tester).commonCancel));
      await tester.pumpAndSettle();
      await _openSettings(tester);
      await _reveal(tester, web);
      await tester.tap(web);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('blog-editor-confirm-web')));
      await tester.pumpAndSettle();
      expect(await host.result, isNull);
      expect(host.navigation.editorTarget!.action, UserBlogAction.edit);
      expect(host.webLaunches.single.expectedAccountId, '101');
      expect(find.byType(BlogEditorPage), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(BlogEditorPage), findsNothing);
      expect(service.editorSubmissions, isEmpty);
    },
  );

  testWidgets(
    'applied receipt waits for a leave dialog without popping the wrong route',
    (tester) async {
      final service = BlogOperationFixture(autoPrepare: true);
      final host = await _open(tester, service);
      await _save(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      service.saved();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(_l10n(tester).commonCancel));
      await tester.pumpAndSettle();
      expect((await host.result)?.receipt.blogId, '11');
      expect(find.byKey(const Key('open-editor')), findsOneWidget);
    },
  );

  testWidgets('applied receipt waits until a covered preview route returns', (
    tester,
  ) async {
    final service = BlogOperationFixture(autoPrepare: true);
    final host = await _open(tester, service);
    await _save(tester);
    host.navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(),
          body: const Text('image preview fixture'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    service.saved();
    await tester.pumpAndSettle();
    expect(find.text('image preview fixture'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect((await host.result)?.receipt.blogId, '11');
    expect(find.byKey(const Key('open-editor')), findsOneWidget);
  });

  for (final submitting in [false, true]) {
    testWidgets(
      'account change during ${submitting ? 'save' : 'prepare'} drops all input and receipts',
      (tester) async {
        final service = BlogOperationFixture(autoPrepare: submitting);
        final host = await _open(tester, service);
        if (submitting) await _save(tester);
        host.changeActor('202');
        await tester.pump();
        host.changeActor('101');
        await tester.pump();
        if (submitting) {
          service.saved();
        } else {
          service.preparedEditor();
        }
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(
          find.text(_l10n(tester).forumWebViewAccountChanged),
          findsOneWidget,
        );
        expect(host.container.read(blogMutationBusProvider).last, isNull);
      },
    );

    testWidgets(
      'return during ${submitting ? 'save' : 'prepare'} cancels and ignores late completion',
      (tester) async {
        final service = BlogOperationFixture(autoPrepare: submitting);
        final host = await _open(tester, service);
        if (submitting) await _save(tester);
        await tester.tap(find.byType(BackButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        if (submitting) {
          await tester.tap(find.byKey(const Key('blog-editor-leave')));
        }
        await tester.pumpAndSettle();
        final token = submitting
            ? service.editorSubmissions.last.input.cancellation
            : service.editorPreparations.last.cancellation;
        expect(token!.isCancelled, isTrue);
        if (submitting) {
          service.saved();
        } else {
          service.preparedEditor();
        }
        await tester.pumpAndSettle();
        expect(await host.result, isNull);
        expect(host.container.read(blogMutationBusProvider).last, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final family in AppThemeFamily.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'editor settings and preview fit $family $brightness with large text and keyboard',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 740));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final service = BlogOperationFixture(autoPrepare: true);
          await _open(
            tester,
            service,
            create: true,
            largeKeyboard: true,
            theme: AppTheme.build(family: family, brightness: brightness),
          );
          await tester.enterText(
            find.byKey(const Key('blog-editor-subject')),
            '长标题 ' * 12,
          );
          await tester.ensureVisible(find.byKey(const Key('blog-editor-body')));
          await _replaceBody(tester, '正文\n空行与换行\n\n' * 6);
          await _openSettings(tester);
          await _reveal(tester, find.byKey(const Key('blog-editor-open-web')));
          expect(
            find.byKey(const Key('blog-editor-open-web')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await _closeSettings(tester);
          await tester.tap(find.byKey(const Key('blog-editor-preview-toggle')));
          await tester.pumpAndSettle();
          expect(find.byType(ForumHtmlContentView), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _save(tester);
          service.saved();
          await tester.pumpAndSettle();
          expect(find.byType(BlogEditorPage), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

IconButton _submitButton(WidgetTester tester) =>
    tester.widget(find.byKey(const Key('blog-editor-submit')));
QuillEditor _body(WidgetTester tester) =>
    tester.widget(find.byKey(const Key('blog-editor-body')));
Future<void> _replaceBody(WidgetTester tester, String text) async {
  final controller = _body(tester).controller;
  controller.replaceText(
    0,
    controller.document.length - 1,
    text,
    TextSelection.collapsed(offset: text.length),
  );
  await tester.pump();
}

String _plainText(String html) {
  final text = const BlogQuillHtmlCodec().decodeDocument(html).toPlainText();
  return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BlogEditorPage)));
String _visibilityLabel(AppLocalizations l10n, UserBlogVisibility visibility) =>
    switch (visibility) {
      UserBlogVisibility.public => l10n.profileBlogVisibilityPublic,
      UserBlogVisibility.friends => l10n.profileBlogVisibilityFriends,
      UserBlogVisibility.selectedFriends => l10n.profileBlogVisibilitySelected,
      UserBlogVisibility.private => l10n.profileBlogVisibilityPrivate,
      UserBlogVisibility.passwordProtected =>
        l10n.profileBlogVisibilityPassword,
    };
Future<void> _save(WidgetTester tester) async {
  if (find
      .byKey(const Key('blog-editor-settings-sheet'))
      .evaluate()
      .isNotEmpty) {
    await _closeSettings(tester);
  }
  await tester.pump();
  await tester.tap(find.byKey(const Key('blog-editor-submit')));
  await tester.pump();
}

Future<void> _choose(WidgetTester tester, String key, String label) async {
  if (find.byKey(const Key('blog-editor-settings-sheet')).evaluate().isEmpty) {
    await _openSettings(tester);
  }
  final field = find.byKey(Key(key));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester) async {
  final entry = find.byKey(const Key('blog-editor-settings'));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('blog-editor-settings-sheet')), findsOneWidget);
  expect(find.byKey(const Key('blog-editor-settings-done')), findsNothing);
  _expectNoSheetHandle(tester);
}

void _expectNoSheetHandle(WidgetTester tester) {
  expect(
    tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
    isFalse,
  );
}

Future<void> _closeSettings(
  WidgetTester tester, {
  bool tapBarrier = false,
}) async {
  expect(find.byKey(const Key('blog-editor-settings-done')), findsNothing);
  if (tapBarrier) {
    final sheetTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
    expect(sheetTop, greaterThan(0));
    await tester.tapAt(Offset(8, sheetTop / 2));
  } else {
    await tester.binding.handlePopRoute();
  }
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('blog-editor-settings-sheet')), findsNothing);
}

Future<void> _reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 200,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find
        .descendant(
          of: find.byKey(
            Key(
              find
                      .byKey(const Key('blog-editor-settings-sheet'))
                      .evaluate()
                      .isEmpty
                  ? 'blog-editor-scroll'
                  : 'blog-editor-settings-sheet',
            ),
          ),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<_Host> _open(
  WidgetTester tester,
  BlogOperationFixture service, {
  bool create = false,
  ThemeData? theme,
  bool largeKeyboard = false,
  ComposerImagePicker? imagePicker,
  UserBlogMediaOperations? media,
}) async {
  final host = _Host(service, imagePicker: imagePicker, media: media);
  addTearDown(host.container.dispose);
  final target = UserBlogTarget(
    actorUserId: '101',
    ownerUserId: '101',
    action: create ? UserBlogAction.create : UserBlogAction.edit,
    blogId: create ? null : '11',
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: host.container,
      child: LocalizedTestApp(
        navigatorKey: host.navigator,
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: largeKeyboard,
            textScaler: TextScaler.linear(largeKeyboard ? 2 : 1),
            viewInsets: largeKeyboard
                ? const EdgeInsets.only(bottom: 260)
                : EdgeInsets.zero,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-editor'),
              onPressed: () {
                host.result = Navigator.of(context).push<BlogEditorResult>(
                  MaterialPageRoute(
                    builder: (_) => BlogEditorPage(target: target),
                  ),
                );
              },
              child: const Text('fixture open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-editor')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  if (service.autoPrepare) await tester.pumpAndSettle();
  return host;
}

final class _Host {
  _Host(this.service, {this.imagePicker, this.media}) {
    container = ProviderContainer(
      overrides: [
        blogAccountIdProvider.overrideWithValue('101'),
        userBlogOperationsProvider.overrideWithValue(service),
        userBlogMediaOperationsProvider.overrideWithValue(media),
        if (imagePicker != null)
          composerImagePickerProvider.overrideWithValue(imagePicker!),
        composerStickerImageCacheLoaderProvider.overrideWithValue(
          stickerLoader,
        ),
        userBlogNavigationProvider.overrideWithValue(navigation),
        forumImageRefererProvider.overrideWithValue('https://example.test/'),
        forumWebViewRouteFactoryProvider.overrideWithValue(_webRoute),
      ],
    );
  }
  final BlogOperationFixture service;
  final ComposerImagePicker? imagePicker;
  final UserBlogMediaOperations? media;
  final stickerLoader = ComposerStickerImageCacheLoader(
    imageCacheService: _NoImages(),
    networkGap: Duration.zero,
  );
  late final ProviderContainer container;
  final navigator = GlobalKey<NavigatorState>();
  final navigation = BlogNavigationFixture();
  final webLaunches = <ForumWebViewLaunchConfig>[];
  late Future<BlogEditorResult?> result;
  void changeActor(String? actor) => container.updateOverrides([
    blogAccountIdProvider.overrideWithValue(actor),
    userBlogOperationsProvider.overrideWithValue(service),
    userBlogMediaOperationsProvider.overrideWithValue(media),
    if (imagePicker != null)
      composerImagePickerProvider.overrideWithValue(imagePicker!),
    composerStickerImageCacheLoaderProvider.overrideWithValue(stickerLoader),
    userBlogNavigationProvider.overrideWithValue(navigation),
    forumImageRefererProvider.overrideWithValue('https://example.test/'),
    forumWebViewRouteFactoryProvider.overrideWithValue(_webRoute),
  ]);
  Route<Object?> _webRoute(ForumWebViewLaunchConfig config) {
    webLaunches.add(config);
    return MaterialPageRoute(
      builder: (_) =>
          Scaffold(appBar: AppBar(), body: const Text('browser fixture')),
    );
  }
}

final class _NoImages implements ImageCacheService {
  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async =>
      CachedImageResult.failed;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PageImagePicker implements ComposerImagePicker {
  _PageImagePicker(this.path);
  final String path;
  int calls = 0;
  @override
  Future<List<ComposerPickedImage>> pickImagesInOrder() async {
    calls++;
    return [
      ComposerPickedImage(
        path: path,
        fileName: 'picked.png',
        mimeType: 'image/png',
        originalIndex: 0,
      ),
    ];
  }
}

final class _PageMediaService implements UserBlogMediaOperations {
  UserBlogImageUploadSubmission? request;
  int calls = 0;
  final result = Completer<DataCommandResult<UserBlogUploadedImage>>();
  @override
  Future<DataCommandResult<UserBlogUploadedImage>> uploadImage(
    UserBlogImageUploadSubmission submission,
  ) {
    calls++;
    request = submission;
    return result.future;
  }
}

final class _PageImageToken implements UserBlogUploadedImageToken {}
