import 'package:flutter/material.dart';
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
}

Widget _routerHarness({required ValueChanged<BuildContext> onContext}) {
  return MaterialApp(
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
}) {
  return HistoryEntry(
    target: HistoryTargetKey(type: type, id: id),
    title: title,
    contextLabel: '详情',
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

class _DestinationPage extends StatelessWidget {
  const _DestinationPage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}
