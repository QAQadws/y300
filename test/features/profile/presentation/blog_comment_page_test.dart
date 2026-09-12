import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_comment_fixture.dart';
import '../test_support/blog_navigation_fixture.dart';

void main() {
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
      await tester.enterText(find.byType(TextField), '还没有提交的修改');
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
      expect(_input(tester).controller!.text, '还没有提交的修改');
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
    await tester.enterText(find.byType(TextField), '填写评论');
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
    expect(_input(tester).controller!.text, service.initialMessage);
    await tester.enterText(find.byType(TextField), '[b]修改文字[/b]\n下一行');
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
      await tester.enterText(find.byType(TextField), '保留修改');
      await _submit(tester);
      service.submissions.last.result.complete(
        const DataCommandRejected(blogCommentWriteFailure),
      );
      await tester.pumpAndSettle();
      expect(_input(tester).controller!.text, '保留修改');
      await tester.tap(find.byKey(const Key('blog-comment-retry')));
      await tester.pumpAndSettle();
      expect(service.preparations, hasLength(2));
      expect(service.submissions, hasLength(1));
      expect(_input(tester).controller!.text, '保留修改');
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
    await tester.enterText(find.byType(TextField), '需要核对的内容');
    await _submit(tester);
    service.submissions.single.result.complete(
      const DataCommandOutcomeUnknown(blogCommentWriteFailure),
    );
    await tester.pumpAndSettle();
    expect(_input(tester).controller!.text, '需要核对的内容');
    expect(_input(tester).readOnly, isTrue);
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
    await tester.enterText(find.byType(TextField), '尚未提交');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.profileBlogLeaveCommentBody), findsOneWidget);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(_input(tester).controller!.text, '尚未提交');
    expect(service.submissions, isEmpty);
  });

  testWidgets(
    'confirmation above an in-flight POST cannot swallow its receipt',
    (tester) async {
      final service = BlogCommentFixture(autoPrepare: true);
      final host = await _open(tester, service);
      final l10n = _l10n(tester);
      await tester.enterText(find.byType(TextField), '成功发送');
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
      await tester.enterText(find.byType(TextField), '等待发送');
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
      await tester.enterText(find.byType(TextField), '旧账号内容');
      await _submit(tester);
      host.changeActor('303');
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('旧账号内容'), findsNothing);
      expect(find.text(l10n.profileBlogCommentSessionChanged), findsOneWidget);
      host.changeActor('101');
      await tester.pumpAndSettle();
      service.applied();
      await tester.pumpAndSettle();
      expect(find.byType(BlogCommentPage), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
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
      expect(find.byType(TextField), findsNothing);
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
          await tester.enterText(find.byType(TextField), '窄屏输入\n多行内容' * 6);
          expect(_input(tester).decoration!.border, isNull);
          expect(_input(tester).style!.color, theme.y300NativeContent.body);
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
TextField _input(WidgetTester tester) => tester.widget(find.byType(TextField));

Future<void> _submit(WidgetTester tester) async {
  await tester.pump();
  final button = find.byKey(const Key('blog-comment-submit'));
  await tester.scrollUntilVisible(
    button,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
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
            textScaler: TextScaler.linear(largeKeyboard ? 2 : 1),
            viewInsets: largeKeyboard
                ? const EdgeInsets.only(bottom: 280)
                : EdgeInsets.zero,
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
      ],
    );
  }
  final BlogCommentFixture service;
  late final ProviderContainer container;
  final navigation = BlogNavigationFixture();
  final webLaunches = <ForumWebViewLaunchConfig>[];
  late Future<UserBlogCommentReceipt?> receipt;
  void changeActor(String? actor) => container.updateOverrides([
    blogAccountIdProvider.overrideWithValue(actor),
    userBlogCommentServiceProvider.overrideWithValue(service),
    userBlogNavigationProvider.overrideWithValue(navigation),
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
