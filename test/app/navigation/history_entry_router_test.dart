import 'package:flutter/material.dart';
import '../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/navigation/history_entry_router.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/history/domain/models/history_models.dart';

void main() {
  testWidgets('opens thread in the current native forum mode', (tester) async {
    String? capturedTid;
    String? capturedSubject;
    int? capturedPage;
    final router = HistoryEntryRouter(
      loadForumMode: () async => ForumShellMode.native,
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

  testWidgets('opens thread webview with a minimal normalized URL', (
    tester,
  ) async {
    Uri? capturedUri;
    final router = HistoryEntryRouter(
      loadForumMode: () async => ForumShellMode.webview,
      comicWorkExists: _workExists,
      novelWorkExists: _workExists,
      webViewPageBuilder: (uri) {
        capturedUri = uri;
        return const _DestinationPage(label: 'webview-thread');
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
        id: '527325',
        title: '帖子',
        page: 4,
        canonicalUri: Uri.parse(
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=527325'
          '&highlight=%D2%B2%CE%DE&auth=secret',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(result, isA<HistoryOpenSuccess>());
    expect(capturedUri?.path, '/forum.php');
    expect(capturedUri?.queryParameters, <String, String>{
      'mod': 'viewthread',
      'tid': '527325',
      'page': '4',
      'mobile': '2',
    });
    expect(capturedUri.toString(), isNot(contains('highlight')));
  });

  testWidgets('opens comic and novel records with their local work ids', (
    tester,
  ) async {
    final opened = <String>[];
    final router = HistoryEntryRouter(
      loadForumMode: () async => ForumShellMode.native,
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

  testWidgets('old thread records follow forum mode changes', (tester) async {
    var mode = ForumShellMode.native;
    final destinations = <String>[];
    final router = HistoryEntryRouter(
      loadForumMode: () async => mode,
      comicWorkExists: _workExists,
      novelWorkExists: _workExists,
      nativeThreadPageBuilder: (tid, subject, page) {
        destinations.add('native:$tid');
        return const _DestinationPage(label: 'native-thread');
      },
      webViewPageBuilder: (uri) {
        destinations.add('webview:${uri.queryParameters['tid']}');
        return const _DestinationPage(label: 'webview-thread');
      },
    );
    late BuildContext context;
    await tester.pumpWidget(
      _routerHarness(onContext: (value) => context = value),
    );
    final entry = _entry(
      type: HistoryTargetType.thread,
      id: '527325',
      title: '帖子',
    );

    await router.open(context, entry);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(_DestinationPage))).pop();
    await tester.pumpAndSettle();

    mode = ForumShellMode.webview;
    await router.open(context, entry);
    await tester.pumpAndSettle();

    expect(destinations, <String>['native:527325', 'webview:527325']);
  });

  testWidgets('returns stable unavailable codes for invalid history targets', (
    tester,
  ) async {
    final router = HistoryEntryRouter(
      loadForumMode: () async => ForumShellMode.native,
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
      loadForumMode: () async => ForumShellMode.native,
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
      loadForumMode: () async => ForumShellMode.native,
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
      loadForumMode: () async => ForumShellMode.native,
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

Widget _routerHarness({required ValueChanged<BuildContext> onContext}) {
  return LocalizedTestApp(
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
}) {
  return HistoryEntry(
    target: HistoryTargetKey(type: type, id: id),
    title: title,
    contextLabel: '详情',
    sourceTid: sourceTid,
    canonicalUri: canonicalUri,
    lastSurface: switch (type) {
      HistoryTargetType.thread => HistoryVisitSurface.threadNative,
      HistoryTargetType.comic => HistoryVisitSurface.comicDetail,
      HistoryTargetType.novel => HistoryVisitSurface.novelDetail,
    },
    firstVisitedAt: DateTime.utc(2026, 7, 16),
    lastVisitedAt: DateTime.utc(2026, 7, 16),
    lastPage: page,
    visitCount: 1,
  );
}

Future<bool> _workExists(String workId) async => true;

class _DestinationPage extends StatelessWidget {
  const _DestinationPage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}
