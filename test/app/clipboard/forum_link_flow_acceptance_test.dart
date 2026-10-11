import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/clipboard/forum_clipboard_link_host.dart';
import 'package:y300/app/clipboard/forum_clipboard_runtime.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/core/clipboard/clipboard_text_reader.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/application/auth_session_controller.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/repositories/thread_post_locator.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';
import 'package:y300/features/thread/presentation/services/thread_post_actions.dart';
import 'package:y300/features/thread/presentation/services/thread_post_navigation.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../test_support/localized_test_app.dart';

enum _Entry { plainText, selectedText, clipboard }

void main() {
  const thread = 'https://bbs.yamibo.com/thread-123-7-1.html';
  const floor =
      'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=123&pid=456';
  const managed =
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&page=7&authorid=101&unknown=1#pid456';
  const blog =
      'https://bbs.yamibo.com/home.php?mod=space&uid=101&do=blog&id=11';
  const notice = Key('forum-clipboard-link-notice');

  for (final entry in _Entry.values) {
    testWidgets('${entry.name} opens the same native thread and page', (
      tester,
    ) async {
      final fixture = _Fixture(thread, clipboard: entry == _Entry.clipboard);
      await fixture.mount(tester);
      await fixture.open(tester, entry);
      await tester.idle();
      final page = fixture.takeThreadRoute();
      expect(page.tid, '123');
      expect(page.initialPage, 7);
      expect(page.targetPid, isNull);
      expect(fixture.locator.requests, isEmpty);
      expect(fixture.webViewLaunches, isEmpty);
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.name} resolves the same floor only after opening', (
      tester,
    ) async {
      final fixture = _Fixture(floor, clipboard: entry == _Entry.clipboard);
      await fixture.mount(tester);
      expect(fixture.locator.requests, isEmpty);
      await fixture.open(tester, entry);
      await tester.pumpAndSettle();
      expect(fixture.observer.pushed, isEmpty);
      expect(fixture.locator.requests, hasLength(1));
      final request = fixture.locator.requests.single;
      expect(request.tid, '123');
      expect(request.pid, '456');
      expect(request.sourceUri.toString(), floor);
      request.result.complete(
        const ApiSuccess(
          ThreadPostLocation(tid: '123', pid: '456', page: 7, url: ''),
        ),
      );
      await tester.idle();
      final page = fixture.takeThreadRoute();
      expect(page.tid, '123');
      expect(page.targetPid, '456');
      expect(page.initialPage, 7);
      expect(fixture.webViewLaunches, isEmpty);
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.name} keeps unknown view fields in managed WebView', (
      tester,
    ) async {
      final fixture = _Fixture(managed, clipboard: entry == _Entry.clipboard);
      await fixture.mount(tester);
      await fixture.open(tester, entry);
      await tester.pumpAndSettle();
      expect(fixture.webViewLaunches, hasLength(1));
      final config = fixture.webViewLaunches.single;
      expect(config.initialUri.toString(), managed);
      expect(config.navigationPolicy, ForumWebViewNavigationPolicy.keepWebView);
      expect(config.popOnRootBack, isTrue);
      expect(find.byKey(const Key('local-webview-target')), findsOneWidget);
      expect(fixture.locator.requests, isEmpty);
      expect(fixture.observer.pushed, hasLength(1));
      expect(fixture.reader.reads, 1);
      expect(tester.takeException(), isNull);
    });

    for (final scenario
        in <
          ({
            String name,
            String suffix,
            int page,
            String? cid,
            bool last,
            bool focus,
          })
        >[
          (
            name: 'article',
            suffix: '',
            page: 1,
            cid: null,
            last: false,
            focus: false,
          ),
          (
            name: 'comment page',
            suffix: '&page=3',
            page: 3,
            cid: null,
            last: false,
            focus: false,
          ),
          (
            name: 'specific comment',
            suffix: '&cid=31',
            page: 1,
            cid: '31',
            last: false,
            focus: true,
          ),
          (
            name: 'last comment page',
            suffix: '&goto=last',
            page: 1,
            cid: null,
            last: true,
            focus: true,
          ),
          (
            name: 'comment section',
            suffix: '#comment',
            page: 1,
            cid: null,
            last: false,
            focus: true,
          ),
          (
            name: 'comment anchor',
            suffix: '#comment_31_li',
            page: 1,
            cid: '31',
            last: false,
            focus: true,
          ),
        ]) {
      testWidgets('${entry.name} opens native blog ${scenario.name}', (
        tester,
      ) async {
        final fixture = _Fixture(
          '$blog${scenario.suffix}',
          clipboard: entry == _Entry.clipboard,
        );
        await fixture.mount(tester);
        expect(fixture.observer.pushed, isEmpty);
        if (entry == _Entry.clipboard) {
          final l10n = AppLocalizations.of(tester.element(find.byKey(notice)));
          expect(find.text(l10n.clipboardLinkFoundBlog), findsOneWidget);
        }
        await fixture.open(tester, entry);
        await tester.idle();
        final page = fixture.takeBlogRoute();
        expect(page.ownerUserId, '101');
        expect(page.blogId, '11');
        expect(page.initialPage, scenario.page);
        expect(page.commentId, scenario.cid);
        expect(page.lastCommentPage, scenario.last);
        expect(page.focusComments, scenario.focus);
        expect(fixture.locator.requests, isEmpty);
        expect(fixture.webViewLaunches, isEmpty);
        expect(fixture.writes, isEmpty);
        await tester.pumpAndSettle();
        expect(fixture.observer.pushed, hasLength(1));
        expect(fixture.reader.reads, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scenario in {
    'different forum targets':
        '$thread https://bbs.yamibo.com/thread-124-7-1.html',
    'thread and blog targets': '$thread $blog',
    'different blog targets': '$blog ${blog.replaceFirst('id=11', 'id=12')}',
    'external target': 'https://example.test/thread-123-7-1.html',
    'forum action': '$thread?action=delete',
  }.entries) {
    testWidgets('${scenario.key} has no conditional menu or automatic notice', (
      tester,
    ) async {
      final fixture = _Fixture(scenario.value, clipboard: true);
      await fixture.mount(tester);
      expect(find.byKey(notice), findsNothing);
      expect(fixture.reader.reads, 1);
      await fixture.enterSelection(tester);
      await _selectAll(tester);
      expect(find.text(_openLabel(tester)), findsNothing);
      expect(find.text(_copyLabel(tester)), findsOneWidget);
      expect(fixture.locator.requests, isEmpty);
      expect(fixture.webViewLaunches, isEmpty);
      expect(fixture.observer.pushed, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'successful controlled copy suppresses notice but not selection',
    (tester) async {
      final fixture = _Fixture(thread);
      await fixture.mount(tester);
      await fixture.enterSelection(tester);
      await _selectAll(tester);
      await tester.tap(find.text(_copyLabel(tester)));
      await tester.pumpAndSettle();
      expect(fixture.writes, [thread]);
      expect(fixture.reader.text, thread);
      fixture.navigator.currentState!.pop();
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, 2);
      expect(find.byKey(notice), findsNothing);
      expect(fixture.webViewLaunches, isEmpty);
      expect(fixture.locator.requests, isEmpty);

      await fixture.open(tester, _Entry.selectedText);
      await tester.idle();
      final page = fixture.takeThreadRoute();
      expect(page.tid, '123');
      expect(page.initialPage, 7);
      await tester.pumpAndSettle();
      expect(fixture.writes, [thread]);
      expect(fixture.reader.reads, 2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in [_Entry.plainText, _Entry.selectedText]) {
    testWidgets(
      'unavailable automatic prompt still permits ${entry.name} navigation',
      (tester) async {
        final fixture = _Fixture(thread, clipboard: true, allowPrompt: false);
        await fixture.mount(tester);
        expect(fixture.reader.reads, 0);
        expect(find.byKey(notice), findsNothing);
        await fixture.open(tester, entry);
        await tester.idle();
        final page = fixture.takeThreadRoute();
        expect(page.tid, '123');
        expect(page.initialPage, 7);
        await tester.pumpAndSettle();
        expect(fixture.reader.reads, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _Fixture {
  _Fixture(String text, {bool clipboard = false, this.allowPrompt = true})
    : post = ThreadPost(
        pid: 'p1',
        author: 'Synthetic Author',
        authorId: '',
        message: '<p>${const HtmlEscape().convert(text)}</p>',
        number: 1,
        isFirst: false,
        dateline: 'date',
      ) {
    reader.text = clipboard ? text : null;
    container = ProviderContainer(
      overrides: [
        forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
          _PreferencesRepository(),
        ),
        authSessionControllerProvider.overrideWith(_AuthController.new),
        clipboardTextReaderProvider.overrideWithValue(reader),
        clipboardTextWriterProvider.overrideWith((ref) {
          // Keep the real successful-write registry, replace only platform IO.
          return PlatformClipboardTextWriter(
            selfCopyRegistry: ref.read(
              clipboardSelfCopyFingerprintRegistryProvider,
            ),
            platformWrite: (value) async {
              writes.add(value);
              reader.text = value;
            },
          );
        }),
        threadPostLocatorProvider.overrideWithValue(locator),
        forumWebViewRouteFactoryProvider.overrideWithValue((config) {
          webViewLaunches.add(config);
          return MaterialPageRoute<Object?>(
            builder: (_) => const Scaffold(
              key: Key('local-webview-target'),
              body: Text('Local WebView target'),
            ),
          );
        }),
      ],
    );
  }

  late final ProviderContainer container;
  final bool allowPrompt;
  final ThreadPost post;
  final _Reader reader = _Reader();
  final _Locator locator = _Locator();
  final _Observer observer = _Observer();
  final navigator = GlobalKey<NavigatorState>();
  final session = ThreadPostNavigationSession();
  final writes = <String>[];
  final webViewLaunches = <ForumWebViewLaunchConfig>[];

  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      session.dispose();
      container.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          navigatorKey: navigator,
          navigatorObservers: [
            container.read(forumClipboardRouteObserverProvider),
            observer,
          ],
          theme: ThemeData(platform: TargetPlatform.android),
          home: ForumClipboardLinkHost(
            isReady: true,
            allowPrompt: allowPrompt,
            builder: (context) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final navigation = ThreadPostNavigation(
                    context: context,
                    ref: ref,
                    tid: '100',
                    imageReferer: null,
                    isCurrent: () => context.mounted,
                    routeSession: session,
                  );
                  return ThreadDetailContent(
                    state: ThreadDetailPageState.initial(
                      tid: '100',
                      subject: 'synthetic fixture',
                    ).copyWith(posts: [post]),
                    imageReferer: '',
                    onLoadPreviousPage: () {},
                    onLoadNextPage: () {},
                    onLoadPageNumber: (_) {},
                    onOpenAuthorProfile: (_) {},
                    onOpenCommentAuthorProfile: (_) {},
                    onCopyActionUrl: (_, _) {},
                    onOpenPostLink: navigation.openLink,
                    onOpenPostActions: (_) => unawaited(
                      ThreadPostActions(
                        context: context,
                        ref: ref,
                        target: const ThreadPostActionContext(
                          tid: '100',
                          fid: '33',
                          subject: 'synthetic fixture',
                          page: 1,
                          capabilities: null,
                        ),
                        isCurrent: () => context.mounted,
                        imageReferer: null,
                        selectionRenderPreparer:
                            const DefaultForumHtmlRenderPreparer(
                              enablePlainTextLinks: true,
                            ),
                      ).show(sourcePost: post, displayPost: post),
                    ),
                    onTogglePollOption: (_, _) {},
                    onSubmitPollVote: (_) {},
                  );
                },
              ),
              bottomNavigationBar: const SizedBox(height: 56),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    observer.pushed.clear();
    expect(locator.requests, isEmpty);
    expect(webViewLaunches, isEmpty);
  }

  Future<void> enterSelection(WidgetTester tester) async {
    await tester.longPress(find.text(post.author));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('thread-post-select-copy-action')));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionArea), findsOneWidget);
    observer.pushed.clear();
  }

  Future<void> open(WidgetTester tester, _Entry entry) async {
    switch (entry) {
      case _Entry.plainText:
        observer.pushed.clear();
        await _tapBodyUrl(tester);
      case _Entry.selectedText:
        await enterSelection(tester);
        await _selectAll(tester);
        final label = _openLabel(tester);
        expect(find.text(label), findsOneWidget);
        await tester.tap(find.text(label));
      case _Entry.clipboard:
        expect(
          find.byKey(const Key('forum-clipboard-link-notice')),
          findsOneWidget,
        );
        observer.pushed.clear();
        await tester.tap(find.byKey(const Key('forum-clipboard-link-open')));
    }
  }

  ThreadDetailPage takeThreadRoute() {
    expect(observer.pushed, hasLength(1));
    final route = observer.pushed.single as MaterialPageRoute<void>;
    final page = route.builder(navigator.currentContext!) as ThreadDetailPage;
    // The real production route is inspected before mounting. This tests its
    // destination without touching forum IO, history or reader persistence.
    navigator.currentState!.removeRoute(route);
    return page;
  }

  ProfileBlogDetailPage takeBlogRoute() {
    expect(observer.pushed, hasLength(1));
    final route = observer.pushed.single as MaterialPageRoute<void>;
    final page =
        route.builder(navigator.currentContext!) as ProfileBlogDetailPage;
    // Inspect the production destination before mounting so no profile
    // controller, forum request or reading/history persistence is started.
    navigator.currentState!.removeRoute(route);
    return page;
  }
}

Future<void> _tapBodyUrl(WidgetTester tester) async {
  final finder = find
      .byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('https://'),
      )
      .first;
  await tester.ensureVisible(finder);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final start = paragraph.text.toPlainText().indexOf('https://');
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + 1),
      )
      .first;
  await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
}

Future<void> _selectAll(WidgetTester tester) async {
  tester
      .state<SelectionAreaState>(find.byType(SelectionArea))
      .selectableRegion
      .selectAll(SelectionChangedCause.toolbar);
  await tester.pumpAndSettle();
}

String _openLabel(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(SelectionArea)),
).selectionOpenForumLink;

String _copyLabel(WidgetTester tester) => MaterialLocalizations.of(
  tester.element(find.byType(SelectionArea)),
).copyButtonLabel;

final class _Reader implements ClipboardTextReader {
  String? text;
  int reads = 0;

  @override
  Future<String?> readText() async {
    reads++;
    return text;
  }
}

final class _Observer extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

final class _Locator implements ThreadPostLocator {
  final requests = <_FloorRequest>[];

  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) {
    final request = _FloorRequest(tid, pid, sourceUri);
    requests.add(request);
    return request.result.future;
  }
}

final class _FloorRequest {
  _FloorRequest(this.tid, this.pid, this.sourceUri);
  final String tid;
  final String pid;
  final Uri sourceUri;
  final result = Completer<ApiResult<ThreadPostLocation>>();
}

final class _PreferencesRepository
    implements ForumHtmlReaderPreferencesRepository {
  @override
  Future<ForumHtmlReaderPreferences> load() async =>
      ForumHtmlReaderPreferences.defaults();

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {}
}

class _AuthController extends AuthSessionController {
  @override
  Future<AuthSessionViewState> build() async =>
      const AuthSessionViewState.signedOut();
}
