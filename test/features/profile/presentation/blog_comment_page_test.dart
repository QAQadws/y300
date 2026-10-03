import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/services/composer_sticker_image_cache_loader.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_sticker_text_codec.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_editor.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_comment_fixture.dart';
import '../test_support/blog_navigation_fixture.dart';

void main() {
  testWidgets(
    'only a confirmed comment publishes account-scoped invalidation',
    (tester) async {
      final service = BlogCommentFixture(autoPrepare: true);
      final host = await _open(tester, service);
      expect(host.container.read(blogMutationBusProvider).last, isNull);
      await _enter(tester, 'comment fixture');
      await _submit(tester);
      expect(host.container.read(blogMutationBusProvider).last, isNull);
      service.applied();
      await tester.pumpAndSettle();
      final event = host.container.read(blogMutationBusProvider).last!;
      expect(event.commentAction, UserBlogCommentAction.add);
      expect(
        event.ownerUserId,
        blogCommentTarget(UserBlogCommentAction.add).ownerUserId,
      );
      expect(event.blogId, blogCommentTarget(UserBlogCommentAction.add).blogId);
      expect(event.articleAction, isNull);
      expect(event.origin, isNull);
    },
  );

  testWidgets(
    'unsupported forms open an account-bound browser without a POST or receipt',
    (tester) async {
      final service = BlogCommentFixture();
      final host = await _open(tester, service);
      service.preparations.single.result.complete(
        const DataReadFailure(
          kind: DataReadFailureKind.unsupported,
          diagnosticMessage: 'fixture_captcha',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('blog-comment-open-web')));
      await tester.pumpAndSettle();
      expect(
        host.navigation.commentTarget,
        blogCommentTarget(UserBlogCommentAction.add),
      );
      expect(host.webLaunches.single.expectedAccountId, '101');
      expect(host.webLaunches.single.initialUri, host.navigation.uri);
      expect(host.webLaunches.single.popOnRootBack, isTrue);
      expect(await host.receipt, isNull);
      expect(find.byType(BlogCommentPage), findsNothing);
      expect(service.submissions, isEmpty);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(BlogCommentPage), findsNothing);
    },
  );

  testWidgets(
    'browser fallback warns about unsent input and can be cancelled',
    (tester) async {
      final service = BlogCommentFixture(autoPrepare: true);
      final host = await _open(tester, service);
      final l10n = _l10n(tester);
      await _enter(tester, '还没有提交的修改');
      await _submit(tester);
      service.submissions.single.result.complete(
        const DataCommandRejected(blogCommentWriteFailure),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('blog-comment-open-web')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.profileBlogWebInputNotice), findsOneWidget);
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(_source(tester), '还没有提交的修改');
      expect(host.webLaunches, isEmpty);
      await tester.tap(find.byKey(const Key('blog-comment-open-web')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('blog-comment-confirm-web')));
      await tester.pumpAndSettle();
      expect(host.webLaunches, hasLength(1));
      expect(service.submissions, hasLength(1));
      expect(await host.receipt, isNull);
      expect(find.byType(BlogCommentPage), findsNothing);
    },
  );
  testWidgets('empty comments explain the missing input without submitting', (
    tester,
  ) async {
    final service = BlogCommentFixture(autoPrepare: true);
    await _open(tester, service);
    final l10n = _l10n(tester);
    await _submit(tester);
    expect(find.text(l10n.profileBlogCommentInputRequired), findsOneWidget);
    expect(service.submissions, isEmpty);
    await _enter(tester, '填写评论');
    await _submit(tester);
    service.applied();
    await tester.pumpAndSettle();
    expect(service.preparations, hasLength(1));
  });

  testWidgets('opening and leaving a pending form sends no command', (
    tester,
  ) async {
    final service = BlogCommentFixture();
    await _open(tester, service);
    expect(
      find.text(_l10n(tester).profileBlogPreparingComment),
      findsOneWidget,
    );
    expect(service.submissions, isEmpty);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(service.preparations.single.cancellation!.isCancelled, isTrue);
    service.prepared();
    await tester.pumpAndSettle();
    expect(find.byType(BlogCommentPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('raw edit text is retained and a confirmed receipt closes once', (
    tester,
  ) async {
    final service = BlogCommentFixture(
      autoPrepare: true,
      initialMessage: '[b]原始文字[/b]\n下一行',
    );
    final host = await _open(
      tester,
      service,
      action: UserBlogCommentAction.edit,
    );
    expect(_source(tester), service.initialMessage);
    await _enter(tester, '[b]修改文字[/b]\n下一行');
    await _submit(tester);
    await _submit(tester);
    expect(service.submissions.single.input.message, '[b]修改文字[/b]\n下一行');
    service.applied();
    await tester.pumpAndSettle();
    expect((await host.receipt)!.commentId, '31');
    expect(find.byType(BlogCommentPage), findsNothing);
  });

  testWidgets(
    'a rejected POST requires explicit preparation then explicit send',
    (tester) async {
      final service = BlogCommentFixture(autoPrepare: true);
      await _open(tester, service);
      await _enter(tester, '保留修改');
      await _submit(tester);
      service.submissions.last.result.complete(
        const DataCommandRejected(blogCommentWriteFailure),
      );
      await tester.pumpAndSettle();
      expect(_source(tester), '保留修改');
      await tester.tap(find.byKey(const Key('blog-comment-retry')));
      await tester.pumpAndSettle();
      expect(service.preparations, hasLength(2));
      expect(service.submissions, hasLength(1));
      expect(_source(tester), '保留修改');
      await _submit(tester);
      service.applied();
      await tester.pumpAndSettle();
      expect(service.submissions, hasLength(2));
    },
  );

  testWidgets('unknown results keep selectable source and expose no resend', (
    tester,
  ) async {
    final service = BlogCommentFixture(autoPrepare: true);
    await _open(tester, service);
    final l10n = _l10n(tester);
    await _enter(tester, '需要核对的内容');
    await _submit(tester);
    service.submissions.single.result.complete(
      const DataCommandOutcomeUnknown(blogCommentWriteFailure),
    );
    await tester.pumpAndSettle();
    expect(_source(tester), '需要核对的内容');
    expect(_input(tester).controller.readOnly, isTrue);
    expect(find.text(l10n.profileBlogCommentOutcomeUnknown), findsOneWidget);
    expect(find.byKey(const Key('blog-comment-retry')), findsNothing);
    expect(find.byKey(const Key('blog-comment-submit')), findsNothing);
    expect(find.byKey(const Key('blog-comment-open-web')), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.profileBlogLeavePendingCommentBody), findsOneWidget);
    await tester.tap(find.byKey(const Key('blog-comment-leave')));
    await tester.pumpAndSettle();
    expect(find.byType(BlogCommentPage), findsNothing);
  });

  testWidgets('leaving edited input can be cancelled without losing it', (
    tester,
  ) async {
    final service = BlogCommentFixture(autoPrepare: true);
    await _open(tester, service);
    final l10n = _l10n(tester);
    await _enter(tester, '尚未提交');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.profileBlogLeaveCommentBody), findsOneWidget);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(_source(tester), '尚未提交');
    expect(service.submissions, isEmpty);
  });

  testWidgets(
    'confirmation above an in-flight POST cannot swallow its receipt',
    (tester) async {
      final service = BlogCommentFixture(autoPrepare: true);
      final host = await _open(tester, service);
      final l10n = _l10n(tester);
      await _enter(tester, '成功发送');
      await _submit(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      service.applied();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
      expect((await host.receipt)!.commentId, '41');
      expect(find.byType(BlogCommentPage), findsNothing);
      expect(find.byKey(const Key('open-comment')), findsOneWidget);
    },
  );

  testWidgets(
    'leaving an in-flight POST cancels ownership and ignores success',
    (tester) async {
      final service = BlogCommentFixture(autoPrepare: true);
      final host = await _open(tester, service);
      await _enter(tester, '等待发送');
      await _submit(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('blog-comment-leave')));
      await tester.pumpAndSettle();
      expect(await host.receipt, isNull);
      expect(
        service.submissions.single.input.cancellation!.isCancelled,
        isTrue,
      );
      service.applied();
      await tester.pumpAndSettle();
      expect(find.byType(BlogCommentPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account switches clear visible inputs and discard a late receipt',
    (tester) async {
      final service = BlogCommentFixture(autoPrepare: true);
      final host = await _open(tester, service);
      final l10n = _l10n(tester);
      await _enter(tester, '旧账号内容');
      await _submit(tester);
      host.changeActor('303');
      await tester.pumpAndSettle();
      expect(find.byType(QuillEditor), findsNothing);
      expect(find.text('旧账号内容'), findsNothing);
      expect(find.text(l10n.profileBlogCommentSessionChanged), findsOneWidget);
      host.changeActor('101');
      await tester.pumpAndSettle();
      service.applied();
      await tester.pumpAndSettle();
      expect(find.byType(BlogCommentPage), findsOneWidget);
      expect(find.byType(QuillEditor), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(await host.receipt, isNull);
    },
  );

  testWidgets(
    'delete has an explicit confirmation and never submits while preparing',
    (tester) async {
      final service = BlogCommentFixture();
      await _open(tester, service, action: UserBlogCommentAction.delete);
      expect(find.byType(QuillEditor), findsNothing);
      expect(
        find.text(_l10n(tester).profileBlogDeleteCommentBody),
        findsOneWidget,
      );
      await _submit(tester);
      expect(service.submissions, isEmpty);
      service.prepared();
      await tester.pumpAndSettle();
      await _submit(tester);
      expect(service.submissions.single.input.message, isEmpty);
      service.applied();
      await tester.pumpAndSettle();
      expect(find.byType(BlogCommentPage), findsNothing);
    },
  );

  testWidgets(
    'reduced motion uses a live status without an animated indicator',
    (tester) async {
      final service = BlogCommentFixture();
      await _open(tester, service, reducedMotion: true);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.text(_l10n(tester).profileBlogPreparingComment),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .any((s) => s.properties.liveRegion == true),
        isTrue,
      );
      service.prepared();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'smiley insertion replaces the selected text and submits its source code',
    (tester) async {
      final service = BlogCommentFixture(
        autoPrepare: true,
        smilies: blogCommentFixtureSmilies,
      );
      await _open(tester, service);
      await _enter(tester, '前替换后');
      final controller = _input(tester).controller;
      controller.updateSelection(
        const TextSelection(baseOffset: 1, extentOffset: 3),
        ChangeSource.local,
      );
      await _pickSmiley(tester, 1);
      expect(_source(tester), '前[em:1:]后');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
      expect(
        controller.document.toDelta().toList().any(
          (operation) =>
              composerQuillEmbedData(
                operation.data,
                composerQuillStickerEmbedType,
              ) ==
              '[em:1:]',
        ),
        isTrue,
      );
      await _submit(tester);
      expect(service.submissions.single.input.message, '前[em:1:]后');
      service.applied();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'known smileys stay inline while unknown source markup remains lossless',
    (tester) async {
      const source = '[b]原始文字[/b] [em:1:] [em:999:]\n[custom=x]内容[/custom]\n';
      final service = BlogCommentFixture(
        autoPrepare: true,
        initialMessage: source,
        smilies: blogCommentFixtureSmilies,
      );
      await _open(tester, service, action: UserBlogCommentAction.edit);
      expect(_source(tester), source);
      final controller = _input(tester).controller;
      expect(controller.document.toPlainText(), contains('[em:999:]'));
      expect(controller.document.toPlainText(), contains('[b]原始文字[/b]'));
      expect(
        controller.document.toDelta().toList().every(
          (operation) => operation.attributes?.isEmpty ?? true,
        ),
        isTrue,
      );
      controller.replaceText(
        0,
        0,
        '修改 ',
        const TextSelection.collapsed(offset: 3),
      );
      await tester.pump();
      expect(_source(tester), '修改 $source');
      await _submit(tester);
      expect(service.submissions.single.input.message, '修改 $source');
      service.applied();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('reply context is shown without being copied into the message', (
    tester,
  ) async {
    final service = BlogCommentFixture(
      autoPrepare: true,
      replyTo: const UserBlogComment(
        commentId: '31',
        authorUserId: '404',
        authorName: '回复对象',
        bodyHtml:
            '<div class="quote"><blockquote>更早的引用</blockquote></div><p>原评论内容</p>',
      ),
      smilies: blogCommentFixtureSmilies,
    );
    await _open(tester, service, action: UserBlogCommentAction.reply);
    expect(find.byKey(const Key('blog-comment-reply-context')), findsOneWidget);
    expect(
      find.text(
        _l10n(tester).profileBlogCommentReplyTo(service.replyTo!.authorName),
      ),
      findsOneWidget,
    );
    expect(_source(tester), isEmpty);
    expect(find.text('原评论内容'), findsOneWidget);
    expect(find.textContaining('更早的引用'), findsNothing);
    await _enter(tester, '新的回复');
    await _pickSmiley(tester, 2);
    await _submit(tester);
    expect(service.submissions.single.input.message, '新的回复[em:2:]');
    service.applied();
    await tester.pumpAndSettle();
  });

  testWidgets('the smiley action stays disabled until a catalog is prepared', (
    tester,
  ) async {
    final service = BlogCommentFixture();
    await _open(tester, service);
    expect(_smileyButton(tester).onPressed, isNull);
    await tester.tap(find.byKey(const Key('blog-comment-smiley')));
    await tester.pump();
    expect(find.byKey(const Key('blog-comment-smiley-picker')), findsNothing);
    service.prepared();
    await tester.pumpAndSettle();
    expect(_smileyButton(tester).onPressed, isNull);
    expect(service.preparations, hasLength(1));
    expect(service.submissions, isEmpty);
  });

  testWidgets('account changes dismiss the picker and clear its old contents', (
    tester,
  ) async {
    final service = BlogCommentFixture(
      autoPrepare: true,
      smilies: blogCommentFixtureSmilies,
    );
    final host = await _open(tester, service);
    await _enter(tester, '旧账号内容');
    await _showSmilies(tester);
    expect(find.byKey(const Key('blog-comment-smiley-1')), findsOneWidget);
    host.changeActor('303');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('blog-comment-smiley-picker')), findsNothing);
    expect(find.byType(QuillEditor), findsNothing);
    expect(find.byKey(const Key('blog-comment-smiley-1')), findsNothing);
    expect(service.submissions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a late prepared catalog cannot reopen a changed account editor',
    (tester) async {
      final service = BlogCommentFixture(smilies: blogCommentFixtureSmilies);
      final host = await _open(tester, service);
      host.changeActor('303');
      await tester.pumpAndSettle();
      expect(service.preparations.single.cancellation!.isCancelled, isTrue);
      service.prepared();
      await tester.pumpAndSettle();
      expect(find.byType(QuillEditor), findsNothing);
      expect(find.byKey(const Key('blog-comment-smiley-picker')), findsNothing);
      expect(service.submissions, isEmpty);
    },
  );

  testWidgets(
    'account expiry before the first picker frame shows no old catalog',
    (tester) async {
      final service = BlogCommentFixture(
        autoPrepare: true,
        smilies: blogCommentFixtureSmilies,
      );
      final host = await _open(tester, service);
      _smileyButton(tester).onPressed!();
      host.changeActor('303');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blog-comment-smiley-picker')), findsNothing);
      expect(find.byType(QuillEditor), findsNothing);
      expect(service.submissions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'submitting invalidates an open picker before an unknown result',
    (tester) async {
      final service = BlogCommentFixture(
        autoPrepare: true,
        smilies: blogCommentFixtureSmilies,
      );
      await _open(tester, service);
      await _enter(tester, '保留内容');
      await _showSmilies(tester);
      // A stale callback must be harmless even when a modal covers the editor.
      tester
          .widget<FilledButton>(find.byKey(const Key('blog-comment-submit')))
          .onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('blog-comment-smiley-picker')), findsNothing);
      expect(_smileyButton(tester).onPressed, isNull);
      service.submissions.single.result.complete(
        const DataCommandOutcomeUnknown(blogCommentWriteFailure),
      );
      await tester.pumpAndSettle();
      expect(_source(tester), '保留内容');
      expect(_input(tester).controller.readOnly, isTrue);
      expect(find.byKey(const Key('blog-comment-smiley')), findsNothing);
      expect(find.byKey(const Key('blog-comment-submit')), findsNothing);
      expect(service.submissions, hasLength(1));
    },
  );

  testWidgets('long comments scroll inside the editor with publishing fixed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = BlogCommentFixture(autoPrepare: true);
    await _open(tester, service, largeKeyboard: true);
    final text = List.generate(80, (index) => '第${index + 1}行评论内容').join('\n');
    await _enter(tester, text);
    final input = _input(tester);
    final scrolling = input.scrollController;
    expect(scrolling.hasClients, isTrue);
    expect(scrolling.position.maxScrollExtent, greaterThan(0));
    scrolling.jumpTo(0);
    await tester.pump();
    final button = find.byKey(const Key('blog-comment-submit'));
    final buttonBounds = tester.getRect(button);
    await tester.drag(
      find.byKey(const Key('blog-comment-input')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(scrolling.offset, greaterThan(0));
    expect(tester.getRect(button), buttonBounds);
    expect(button.hitTestable(), findsOneWidget);
    expect(_source(tester), text);
    expect(tester.takeException(), isNull);
  });

  testWidgets('orientation changes keep the action above a short keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = BlogCommentFixture(autoPrepare: true);
    await _open(tester, service, textScale: 2, keyboardInset: 140);
    await _enter(tester, '横屏仍保留输入\n继续评论');
    tester.view.physicalSize = const Size(700, 360);
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('blog-comment-submit'));
    expect(button.hitTestable(), findsOneWidget);
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(220));
    expect(_source(tester), '横屏仍保留输入\n继续评论');
    expect(tester.takeException(), isNull);
    await _submit(tester);
    service.applied();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'landscape smiley sheet fits while keyboard dismissal retains old insets',
    (tester) async {
      tester.view.physicalSize = const Size(700, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final stickerLoader = ComposerStickerImageCacheLoader(
        imageCacheService: _NoImages(),
        networkGap: Duration.zero,
      );
      final smilies = List.generate(
        55,
        (index) => UserBlogCommentSmiley(
          index: index + 1,
          code: '[em:${index + 1}:]',
          imageUri: Uri.parse(
            'https://bbs.yamibo.com/image/face/${index + 1}.gif',
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            composerStickerImageCacheLoaderProvider.overrideWithValue(
              stickerLoader,
            ),
          ],
          child: LocalizedTestApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 280),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  key: const Key('open-smiley-sheet'),
                  onPressed: () => showModalBottomSheet<UserBlogCommentSmiley>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    showDragHandle: false,
                    builder: (_) => BlogCommentSmileySheet(smilies: smilies),
                  ),
                  child: const Text('fixture open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-smiley-sheet')));
      await tester.pumpAndSettle();
      final sheet = find.byType(BlogCommentSmileySheet);
      final l10n = AppLocalizations.of(tester.element(sheet));
      final grid = find.byKey(const Key('blog-comment-smiley-picker'));
      expect(find.text(l10n.composerSticker), findsOneWidget);
      expect(grid, findsOneWidget);
      expect(tester.getRect(grid).height, greaterThan(32));
      expect(tester.getRect(grid).bottom, lessThanOrEqualTo(360));
      expect(
        find.byKey(const Key('blog-comment-smiley-1')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final family in AppThemeFamily.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'comment input fits narrow keyboard layout: $family $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(320, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final service = BlogCommentFixture(autoPrepare: true);
          final theme = AppTheme.build(family: family, brightness: brightness);
          await _open(tester, service, theme: theme, largeKeyboard: true);
          await _enter(tester, '窄屏输入\n多行内容' * 6);
          expect(
            _input(tester).config.customStyles!.paragraph!.style.color,
            theme.y300NativeContent.body,
          );
          final button = find.byKey(const Key('blog-comment-submit'));
          expect(button.hitTestable(), findsOneWidget);
          expect(tester.getRect(button).bottom, lessThanOrEqualTo(420));
          final input = tester.getRect(
            find.byKey(const Key('blog-comment-input')),
          );
          final toolbar = tester.getRect(
            find.byKey(const Key('blog-comment-toolbar')),
          );
          expect(input.height, greaterThan(30));
          expect(input.bottom, lessThanOrEqualTo(toolbar.top));
          expect(toolbar.right, lessThanOrEqualTo(320));
          await _submit(tester);
          service.applied();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BlogCommentPage)));
QuillEditor _input(WidgetTester tester) =>
    tester.widget(find.byKey(const Key('blog-comment-input')));

String _source(WidgetTester tester) => const ComposerStickerTextCodec()
    .encodeDocument(_input(tester).controller.document);

Future<void> _enter(WidgetTester tester, String text) async {
  final controller = _input(tester).controller;
  controller.replaceText(
    0,
    controller.document.length - 1,
    text,
    TextSelection.collapsed(offset: text.length),
  );
  await tester.pump();
}

IconButton _smileyButton(WidgetTester tester) =>
    tester.widget(find.byKey(const Key('blog-comment-smiley')));

Future<void> _showSmilies(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('blog-comment-smiley')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('blog-comment-smiley-picker')), findsOneWidget);
}

Future<void> _pickSmiley(WidgetTester tester, int index) async {
  await _showSmilies(tester);
  await tester.tap(find.byKey(Key('blog-comment-smiley-$index')));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.pump();
  final button = find.byKey(const Key('blog-comment-submit'));
  await tester.tap(button);
  await tester.pump();
}

Future<_Host> _open(
  WidgetTester tester,
  BlogCommentFixture service, {
  UserBlogCommentAction action = UserBlogCommentAction.add,
  ThemeData? theme,
  bool reducedMotion = false,
  bool largeKeyboard = false,
  double? textScale,
  double? keyboardInset,
}) async {
  final host = _Host(service);
  addTearDown(host.container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: host.container,
      child: LocalizedTestApp(
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(textScale ?? (largeKeyboard ? 2 : 1)),
            viewInsets: EdgeInsets.only(
              bottom: keyboardInset ?? (largeKeyboard ? 280 : 0),
            ),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-comment'),
              onPressed: () {
                host.receipt = Navigator.of(context)
                    .push<UserBlogCommentReceipt>(
                      MaterialPageRoute(
                        builder: (_) =>
                            BlogCommentPage(target: blogCommentTarget(action)),
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
  await tester.tap(find.byKey(const Key('open-comment')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  if (service.autoPrepare) await tester.pumpAndSettle();
  return host;
}

final class _Host {
  _Host(this.service) {
    container = ProviderContainer(
      overrides: [
        blogAccountIdProvider.overrideWithValue('101'),
        userBlogCommentServiceProvider.overrideWithValue(service),
        userBlogNavigationProvider.overrideWithValue(navigation),
        forumWebViewRouteFactoryProvider.overrideWithValue(_webRoute),
        composerStickerImageCacheLoaderProvider.overrideWithValue(
          stickerLoader,
        ),
      ],
    );
  }
  final BlogCommentFixture service;
  final stickerLoader = ComposerStickerImageCacheLoader(
    imageCacheService: _NoImages(),
    networkGap: Duration.zero,
  );
  late final ProviderContainer container;
  final navigation = BlogNavigationFixture();
  final webLaunches = <ForumWebViewLaunchConfig>[];
  late Future<UserBlogCommentReceipt?> receipt;
  void changeActor(String? actor) => container.updateOverrides([
    blogAccountIdProvider.overrideWithValue(actor),
    userBlogCommentServiceProvider.overrideWithValue(service),
    userBlogNavigationProvider.overrideWithValue(navigation),
    forumWebViewRouteFactoryProvider.overrideWithValue(_webRoute),
    composerStickerImageCacheLoaderProvider.overrideWithValue(stickerLoader),
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
