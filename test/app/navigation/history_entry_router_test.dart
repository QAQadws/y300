import 'package:flutter/material.dart';
import '../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/navigation/history_entry_router.dart';
import 'package:y300/features/history/domain/models/blog_history_target.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';

void main() {
  testWidgets('opens thread identity and saved page in the shared native UI', (
    tester,
  ) async {
    String? capturedTid;
    String? capturedSubject;
    int? capturedPage;
    final router = HistoryEntryRouter(
      comicWorkExists: _workExists,
      novelWorkExists: _workExists,
      nativeThreadPageBuilder: (tid, subject, page) {
        capturedTid = tid;
        capturedSubject = subject;
        capturedPage = page;
        return const _DestinationPage(label: 'native-thread');
      },
    );
    late BuildContext context;
    await tester.pumpWidget(
      _routerHarness(onContext: (value) => context = value),
    );

    final result = await router.open(
      context,
      _entry(type: HistoryTargetType.thread, id: '100', title: '主题标题', page: 3),
    );
    await tester.pumpAndSettle();

    expect(result, isA<HistoryOpenSuccess>());
    expect(capturedTid, '100');
    expect(capturedSubject, '主题标题');
    expect(capturedPage, 3);
    expect(find.text('native-thread'), findsOneWidget);
  });

  testWidgets('blog history opens natively from its stored identity', (
    tester,
  ) async {
    ({String ownerUserId, String blogId, String title})? destination;
    final router = HistoryEntryRouter(
      comicWorkExists: (_) async => throw StateError('unexpected lookup'),
      novelWorkExists: (_) async => throw StateError('unexpected lookup'),
      nativeBlogPageBuilder:
          ({required ownerUserId, required blogId, required title}) {
            destination = (
              ownerUserId: ownerUserId,
              blogId: blogId,
              title: title,
            );
            return const _DestinationPage(label: 'native-blog');
          },
    );
    late BuildContext context;
    await tester.pumpWidget(
      _routerHarness(onContext: (value) => context = value),
    );

    final result = await router.open(
      context,
      _entry(
        type: HistoryTargetType.blog,
        id: BlogHistoryTarget(ownerUserId: '101', blogId: '11').encodedId,
        title: '日志标题',
        page: 9,
        canonicalUri: Uri.parse(
          'https://unrelated.test/home.php?mod=space&uid=999&do=blog'
          '&id=99&cid=777&page=9#comment_777',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(result, isA<HistoryOpenSuccess>());
    expect(destination, (ownerUserId: '101', blogId: '11', title: '日志标题'));
    expect(find.text('native-blog'), findsOneWidget);
  });

  testWidgets('default blog destination starts at the article without a URL', (
    tester,
  ) async {
    final observer = _RouteObserver();
    final router = HistoryEntryRouter(
      comicWorkExists: (_) async => throw StateError('unexpected lookup'),
      novelWorkExists: (_) async => throw StateError('unexpected lookup'),
    );
    late BuildContext context;
    await tester.pumpWidget(
      _routerHarness(
        onContext: (value) => context = value,
        observers: [observer],
      ),
    );

    final result = await router.open(
      context,
      _entry(
        type: HistoryTargetType.blog,
        id: ' 00101:00011 ',
        title: '日志标题',
        page: 9,
      ),
    );
    final route = observer.routes.last as MaterialPageRoute<void>;
    final destination = route.builder(context) as ProfileBlogDetailPage;

    expect(result, isA<HistoryOpenSuccess>());
    expect(destination.ownerUserId, '101');
    expect(destination.blogId, '11');
    expect(destination.initialTitle, '日志标题');
    expect(destination.initialPage, 1);
    expect(destination.commentId, isNull);
    expect(destination.lastCommentPage, isFalse);
    expect(destination.focusComments, isFalse);
    // The route arguments are under test; do not mount a live detail reader.
    Navigator.of(context).removeRoute(route);
    await tester.pumpAndSettle();
  });

  testWidgets('invalid blog identity cannot fall back to a canonical URL', (
    tester,
  ) async {
    var destinationsBuilt = 0;
    final observer = _RouteObserver();
    final router = HistoryEntryRouter(
      comicWorkExists: (_) async => throw StateError('unexpected lookup'),
      novelWorkExists: (_) async => throw StateError('unexpected lookup'),
      nativeBlogPageBuilder:
          ({required ownerUserId, required blogId, required title}) {
            destinationsBuilt += 1;
            return const _DestinationPage(label: 'native-blog');
          },
    );
    late BuildContext context;
    await tester.pumpWidget(
      _routerHarness(
        onContext: (value) => context = value,
        observers: [observer],
      ),
    );

    for (final id in ['', '11', '0:11', '101:0', '101:bad', '101:11:12']) {
      final result = await router.open(
        context,
        _entry(
          type: HistoryTargetType.blog,
          id: id,
          title: '日志',
          canonicalUri: Uri.parse(
            'https://bbs.yamibo.com/home.php?mod=space&uid=101&do=blog&id=11',
          ),
        ),
      );
      expect(
        result,
        isA<HistoryOpenUnavailable>()
            .having(
              (value) => value.code,
              'code',
              HistoryOpenUnavailableCode.targetMissing,
            )
            .having(
              (value) => value.targetType,
              'targetType',
              HistoryTargetType.blog,
            ),
        reason: id,
      );
    }
    await tester.pumpAndSettle();

    expect(destinationsBuilt, 0);
    expect(observer.routes, hasLength(1));
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('opens comic and novel records with their local work ids', (
    tester,
  ) async {
    final opened = <String>[];
    final router = HistoryEntryRouter(
      comicWorkExists: _workExists,
      novelWorkExists: _workExists,
      comicPageBuilder: (workId) {
        opened.add('comic:$workId');
        return const _DestinationPage(label: 'comic-detail');
      },
      novelPageBuilder: (workId) {
        opened.add('novel:$workId');
        return const _DestinationPage(label: 'novel-detail');
      },
    );
    late BuildContext context;
    await tester.pumpWidget(
      _routerHarness(onContext: (value) => context = value),
    );

    await router.open(
      context,
      _entry(type: HistoryTargetType.comic, id: 'comic-work', title: '漫画'),
    );
    await tester.pumpAndSettle();
    expect(find.text('comic-detail'), findsOneWidget);
    Navigator.of(tester.element(find.byType(_DestinationPage))).pop();
    await tester.pumpAndSettle();

    await router.open(
      context,
      _entry(type: HistoryTargetType.novel, id: 'novel-work', title: '小说'),
    );
    await tester.pumpAndSettle();

    expect(find.text('novel-detail'), findsOneWidget);
    expect(opened, <String>['comic:comic-work', 'novel:novel-work']);
  });

  testWidgets(
    'old WebView thread records reopen natively without losing the page',
    (tester) async {
      ({String tid, int? page})? destination;
      final router = HistoryEntryRouter(
        comicWorkExists: _workExists,
        novelWorkExists: _workExists,
        nativeThreadPageBuilder: (tid, subject, page) {
          destination = (tid: tid, page: page);
          return const _DestinationPage(label: 'native-thread');
        },
      );
      late BuildContext context;
      await tester.pumpWidget(
        _routerHarness(onContext: (value) => context = value),
      );
      final result = await router.open(
        context,
        _entry(
          type: HistoryTargetType.thread,
          id: '00527325',
          title: 'server subject',
          page: 4,
          surface: HistoryVisitSurface.threadWebView,
          canonicalUri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=527325&auth=old',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(result, isA<HistoryOpenSuccess>());
      expect(destination, (tid: '527325', page: 4));
      expect(find.text('native-thread'), findsOneWidget);
    },
  );

  testWidgets('returns stable unavailable codes for invalid history targets', (
    tester,
  ) async {
    const router = HistoryEntryRouter(
      comicWorkExists: _workExists,
      novelWorkExists: _workExists,
    );
    late BuildContext context;
    await tester.pumpWidget(
      _routerHarness(onContext: (value) => context = value),
    );

    final missingWork = await router.open(
      context,
      _entry(type: HistoryTargetType.comic, id: ' ', title: '漫画'),
    );
    final expiredThread = await router.open(
      context,
      _entry(type: HistoryTargetType.thread, id: 'not-a-tid', title: '帖子'),
    );

    expect(
      missingWork,
      isA<HistoryOpenUnavailable>().having(
        (result) => result.code,
        'code',
        HistoryOpenUnavailableCode.targetMissing,
      ),
    );
    expect(
      expiredThread,
      isA<HistoryOpenUnavailable>().having(
        (result) => result.code,
        'code',
        HistoryOpenUnavailableCode.threadExpired,
      ),
    );
  });

  testWidgets('returns page-closed code when the source context is gone', (
    tester,
  ) async {
    final router = HistoryEntryRouter(
      comicWorkExists: _workExists,
      novelWorkExists: _workExists,
      nativeThreadPageBuilder: (tid, subject, page) {
        return const _DestinationPage(label: 'native-thread');
      },
    );
    late BuildContext context;
    await tester.pumpWidget(
      _routerHarness(onContext: (value) => context = value),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    final result = await router.open(
      context,
      _entry(type: HistoryTargetType.thread, id: '100', title: '帖子'),
    );

    expect(
      result,
      isA<HistoryOpenUnavailable>().having(
        (value) => value.code,
        'code',
        HistoryOpenUnavailableCode.pageClosed,
      ),
    );
  });

  testWidgets('returns source fallback when a local work was removed', (
    tester,
  ) async {
    final builtWorks = <String>[];
    final router = HistoryEntryRouter(
      comicWorkExists: (_) async => false,
      novelWorkExists: (_) async => false,
      comicPageBuilder: (workId) {
        builtWorks.add(workId);
        return const _DestinationPage(label: 'comic-detail');
      },
      novelPageBuilder: (workId) {
        builtWorks.add(workId);
        return const _DestinationPage(label: 'novel-detail');
      },
    );
    late BuildContext context;
    await tester.pumpWidget(
      _routerHarness(onContext: (value) => context = value),
    );

    final comicResult = await router.open(
      context,
      _entry(
        type: HistoryTargetType.comic,
        id: 'comic-work',
        title: '漫画',
        sourceTid: '000527325',
      ),
    );
    final novelResult = await router.open(
      context,
      _entry(
        type: HistoryTargetType.novel,
        id: 'novel-work',
        title: '小说',
        sourceTid: 'bad-tid',
      ),
    );

    expect(
      comicResult,
      isA<HistoryOpenUnavailable>()
          .having(
            (result) => result.code,
            'code',
            HistoryOpenUnavailableCode.localWorkRemoved,
          )
          .having(
            (result) => result.targetType,
            'targetType',
            HistoryTargetType.comic,
          )
          .having((result) => result.fallbackTid, 'fallbackTid', '527325'),
    );
    expect(
      novelResult,
      isA<HistoryOpenUnavailable>()
          .having(
            (result) => result.code,
            'code',
            HistoryOpenUnavailableCode.localWorkRemoved,
          )
          .having(
            (result) => result.targetType,
            'targetType',
            HistoryTargetType.novel,
          )
          .having((result) => result.fallbackTid, 'fallbackTid', isNull),
    );
    expect(builtWorks, isEmpty);
    expect(find.byType(_DestinationPage), findsNothing);
  });

  testWidgets('returns a structured failure when availability lookup fails', (
    tester,
  ) async {
    final router = HistoryEntryRouter(
      comicWorkExists: (_) async => throw StateError('database unavailable'),
      novelWorkExists: _workExists,
    );
    late BuildContext context;
    await tester.pumpWidget(
      _routerHarness(onContext: (value) => context = value),
    );

    final result = await router.open(
      context,
      _entry(type: HistoryTargetType.comic, id: 'comic-work', title: '漫画'),
    );

    expect(
      result,
      isA<HistoryOpenFailure>().having(
        (value) => value.error,
        'error',
        isA<StateError>(),
      ),
    );
    expect(find.byType(_DestinationPage), findsNothing);
  });
}

Widget _routerHarness({
  required ValueChanged<BuildContext> onContext,
  List<NavigatorObserver> observers = const [],
}) {
  return LocalizedTestApp(
    navigatorObservers: observers,
    home: Builder(
      builder: (context) {
        onContext(context);
        return const Scaffold(body: Text('home'));
      },
    ),
  );
}

HistoryEntry _entry({
  required HistoryTargetType type,
  required String id,
  required String title,
  int? page,
  String? sourceTid,
  Uri? canonicalUri,
  HistoryVisitSurface? surface,
}) {
  return HistoryEntry(
    target: HistoryTargetKey(type: type, id: id),
    title: title,
    contextLabel: '详情',
    sourceTid: sourceTid,
    canonicalUri: canonicalUri,
    lastSurface:
        surface ??
        switch (type) {
          HistoryTargetType.thread => HistoryVisitSurface.threadNative,
          HistoryTargetType.comic => HistoryVisitSurface.comicDetail,
          HistoryTargetType.novel => HistoryVisitSurface.novelDetail,
          HistoryTargetType.blog => HistoryVisitSurface.blogDetail,
        },
    firstVisitedAt: DateTime.utc(2026, 7, 16),
    lastVisitedAt: DateTime.utc(2026, 7, 16),
    lastPage: page,
    visitCount: 1,
  );
}

Future<bool> _workExists(String workId) async => true;

class _RouteObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}

class _DestinationPage extends StatelessWidget {
  const _DestinationPage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}
