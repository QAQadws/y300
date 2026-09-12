import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_body_text_codec.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_navigation_fixture.dart';
import '../test_support/blog_operation_fixture.dart';

void main() {
  testWidgets(
    'create prepares before input and saves exact plain content once',
    (tester) async {
      final service = BlogOperationFixture();
      final host = await _open(tester, service, create: true);
      expect(find.byType(TextField), findsNothing);
      expect(_submitButton(tester).onPressed, isNull);
      service.preparedEditor();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('blog-editor-subject')),
        'A new journal',
      );
      await tester.enterText(
        find.byKey(const Key('blog-editor-body')),
        '  第一行 <b>文字</b>\n\n第二行',
      );
      await _save(tester);
      expect(service.editorSubmissions, hasLength(1));
      expect(
        BlogBodyTextCodec.decode(
          service.editorSubmissions.single.input.bodyHtml,
        ),
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
      expect(_body(tester).controller!.text, html);
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
      expect(service.editorSubmissions, isEmpty);
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

  for (final useServer in [false, true]) {
    testWidgets(
      'known failure retains input and server review useServer=$useServer',
      (tester) async {
        final service = BlogOperationFixture(autoPrepare: true);
        await _open(tester, service);
        await tester.enterText(
          find.byKey(const Key('blog-editor-body')),
          '<p>My version</p>',
        );
        await _save(tester);
        service.editorSubmissions.last.result.complete(
          const DataCommandRejected(blogActionWriteFailure),
        );
        await tester.pumpAndSettle();
        expect(_body(tester).controller!.text, '<p>My version</p>');
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
          _body(tester).controller!.text,
          useServer ? '<p>Server version</p>' : '<p>My version</p>',
        );
        await _save(tester);
        expect(
          service.editorSubmissions.last.input.bodyHtml,
          useServer ? '<p>Server version</p>' : '<p>My version</p>',
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
      await tester.enterText(
        find.byKey(const Key('blog-editor-body')),
        '<p>Uncertain input</p>',
      );
      await _save(tester);
      service.editorSubmissions.last.result.complete(
        const DataCommandOutcomeUnknown(blogActionWriteFailure),
      );
      await tester.pumpAndSettle();
      expect(_body(tester).readOnly, isTrue);
      expect(_body(tester).controller!.text, '<p>Uncertain input</p>');
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
      await _reveal(tester, web);
      await tester.tap(web);
      await tester.pumpAndSettle();
      expect(host.webLaunches, isEmpty);
      await tester.tap(find.text(_l10n(tester).commonCancel));
      await tester.pumpAndSettle();
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
        'editor and preview fit $family $brightness with large text and keyboard',
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
          await tester.enterText(
            find.byKey(const Key('blog-editor-body')),
            '正文\n空行与换行\n\n' * 6,
          );
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
TextField _body(WidgetTester tester) =>
    tester.widget(find.byKey(const Key('blog-editor-body')));
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BlogEditorPage)));
Future<void> _save(WidgetTester tester) async {
  await tester.pump();
  await tester.tap(find.byKey(const Key('blog-editor-submit')));
  await tester.pump();
}

Future<void> _choose(WidgetTester tester, String key, String label) async {
  final field = find.byKey(Key(key));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
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
          of: find.byKey(const Key('blog-editor-scroll')),
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
}) async {
  final host = _Host(service);
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
  _Host(this.service) {
    container = ProviderContainer(
      overrides: [
        blogAccountIdProvider.overrideWithValue('101'),
        userBlogOperationsProvider.overrideWithValue(service),
        userBlogNavigationProvider.overrideWithValue(navigation),
        forumImageRefererProvider.overrideWithValue('https://example.test/'),
        forumWebViewRouteFactoryProvider.overrideWithValue(_webRoute),
      ],
    );
  }
  final BlogOperationFixture service;
  late final ProviderContainer container;
  final navigator = GlobalKey<NavigatorState>();
  final navigation = BlogNavigationFixture();
  final webLaunches = <ForumWebViewLaunchConfig>[];
  late Future<BlogEditorResult?> result;
  void changeActor(String? actor) => container.updateOverrides([
    blogAccountIdProvider.overrideWithValue(actor),
    userBlogOperationsProvider.overrideWithValue(service),
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
