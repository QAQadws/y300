import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_history_coordinator.dart';

void main() {
  const validDocument = ForumThreadDocumentSnapshot(
    title: '主题',
    postCount: 20,
    menu: ForumThreadMenuSnapshot(),
  );

  test(
    'page-commit capability commits once regardless of gate order',
    () async {
      final commits = <ForumWebViewHistoryCandidate>[];
      final coordinator = ForumWebViewHistoryCoordinator(onCommit: commits.add)
        ..configure(supportsPageCommitVisible: true);
      final firstUri = _threadUri('101');

      coordinator.onPageStarted(generation: 1, uri: firstUri);
      await coordinator.onPageFinished(
        generation: 1,
        finalUri: firstUri,
        document: validDocument,
      );
      expect(commits, isEmpty);
      await coordinator.onPageCommitVisible(generation: 1, uri: firstUri);
      expect(commits.map((item) => item.tid), <String>['101']);

      final secondUri = _threadUri('202');
      coordinator.onPageStarted(generation: 2, uri: secondUri);
      await coordinator.onPageCommitVisible(generation: 2, uri: secondUri);
      expect(commits, hasLength(1));
      await coordinator.onPageFinished(
        generation: 2,
        finalUri: secondUri,
        document: validDocument,
      );
      expect(commits.map((item) => item.tid), <String>['101', '202']);
    },
  );

  test('stale generations and mismatched final urls are ignored', () async {
    final commits = <ForumWebViewHistoryCandidate>[];
    final coordinator = ForumWebViewHistoryCoordinator(onCommit: commits.add)
      ..configure(supportsPageCommitVisible: true);
    final firstUri = _threadUri('101');
    final secondUri = _threadUri('202');

    coordinator.onPageStarted(generation: 1, uri: firstUri);
    coordinator.onPageStarted(generation: 2, uri: secondUri);
    await coordinator.onPageCommitVisible(generation: 1, uri: firstUri);
    await coordinator.onPageFinished(
      generation: 1,
      finalUri: firstUri,
      document: validDocument,
    );
    await coordinator.onPageCommitVisible(generation: 2, uri: firstUri);
    await coordinator.onPageFinished(
      generation: 2,
      finalUri: firstUri,
      document: validDocument,
    );

    expect(commits, isEmpty);
  });

  test(
    'same tid operations dedupe while A to B to A records three visits',
    () async {
      final commits = <ForumWebViewHistoryCandidate>[];
      final coordinator = ForumWebViewHistoryCoordinator(onCommit: commits.add);

      await _finishLegacy(
        coordinator,
        generation: 1,
        uri: _threadUri('101'),
        document: validDocument,
      );
      await _finishLegacy(
        coordinator,
        generation: 2,
        uri: _threadUri('101', page: 2),
        document: validDocument,
      );
      await _finishLegacy(
        coordinator,
        generation: 3,
        uri: _threadUri('202'),
        document: validDocument,
      );
      await _finishLegacy(
        coordinator,
        generation: 4,
        uri: _threadUri('101'),
        document: validDocument,
      );

      expect(commits.map((item) => item.tid), <String>['101', '202', '101']);
    },
  );

  test('visible non-thread navigation resets same-tid route dedupe', () async {
    final commits = <ForumWebViewHistoryCandidate>[];
    final coordinator = ForumWebViewHistoryCoordinator(onCommit: commits.add);
    final threadUri = _threadUri('101');

    await _finishLegacy(
      coordinator,
      generation: 1,
      uri: threadUri,
      document: validDocument,
    );
    await _finishLegacy(
      coordinator,
      generation: 2,
      uri: Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
      document: null,
    );
    await _finishLegacy(
      coordinator,
      generation: 3,
      uri: threadUri,
      document: validDocument,
    );

    expect(commits.map((item) => item.tid), <String>['101', '101']);
  });

  test('error documents and non-thread resources never commit', () async {
    final commits = <ForumWebViewHistoryCandidate>[];
    final coordinator = ForumWebViewHistoryCoordinator(onCommit: commits.add);

    await _finishLegacy(
      coordinator,
      generation: 1,
      uri: _threadUri('101'),
      document: const ForumThreadDocumentSnapshot(
        title: '主题不存在',
        postCount: 0,
        menu: ForumThreadMenuSnapshot(),
      ),
    );
    await _finishLegacy(
      coordinator,
      generation: 2,
      uri: Uri.parse('https://bbs.yamibo.com/static/app.js'),
      document: validDocument,
    );

    expect(commits, isEmpty);
  });

  test(
    'final url supplies tid and tolerates legacy highlight encoding',
    () async {
      final commits = <ForumWebViewHistoryCandidate>[];
      final coordinator = ForumWebViewHistoryCoordinator(onCommit: commits.add);
      final uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=524596&highlight=%D2%B2%CE%DE',
      );

      await _finishLegacy(
        coordinator,
        generation: 1,
        uri: uri,
        document: validDocument,
      );

      expect(commits.single.tid, '524596');
      expect(commits.single.finalUri, uri);
    },
  );

  test('findpost redirect can finish on its same-tid final url', () async {
    final commits = <ForumWebViewHistoryCandidate>[];
    final coordinator = ForumWebViewHistoryCoordinator(onCommit: commits.add)
      ..configure(supportsPageCommitVisible: true);
    final redirectUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=404&pid=1&mobile=2',
    );
    final finalUri = _threadUri('404', page: 2);

    coordinator.onPageStarted(generation: 1, uri: redirectUri);
    await coordinator.onPageCommitVisible(generation: 1, uri: finalUri);
    await coordinator.onPageFinished(
      generation: 1,
      finalUri: finalUri,
      document: validDocument,
    );

    expect(commits.single.tid, '404');
    expect(commits.single.finalUri, finalUri);
  });

  test(
    'recorder failures are isolated after the visible target is consumed',
    () async {
      var attempts = 0;
      final coordinator = ForumWebViewHistoryCoordinator(
        onCommit: (_) {
          attempts += 1;
          throw StateError('write failed');
        },
      );

      await _finishLegacy(
        coordinator,
        generation: 1,
        uri: _threadUri('101'),
        document: validDocument,
      );
      await _finishLegacy(
        coordinator,
        generation: 2,
        uri: _threadUri('101'),
        document: validDocument,
      );

      expect(attempts, 1);
    },
  );

  test('reports structured reasons for skipped history visits', () async {
    final skips = <ForumWebViewHistorySkipReason>[];
    final coordinator = ForumWebViewHistoryCoordinator(
      onCommit: (_) {},
      onSkip: skips.add,
    );

    await _finishLegacy(
      coordinator,
      generation: 1,
      uri: _threadUri('101'),
      document: validDocument,
    );
    await _finishLegacy(
      coordinator,
      generation: 2,
      uri: _threadUri('101', page: 2),
      document: validDocument,
    );
    await _finishLegacy(
      coordinator,
      generation: 3,
      uri: Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
      document: null,
    );
    coordinator.onPageStarted(generation: 4, uri: _threadUri('404'));
    await coordinator.onPageFinished(
      generation: 3,
      finalUri: _threadUri('101'),
      document: validDocument,
    );

    expect(
      skips,
      containsAll(<ForumWebViewHistorySkipReason>[
        ForumWebViewHistorySkipReason.duplicateTarget,
        ForumWebViewHistorySkipReason.nonThreadDocument,
        ForumWebViewHistorySkipReason.staleGeneration,
      ]),
    );
  });
}

Future<void> _finishLegacy(
  ForumWebViewHistoryCoordinator coordinator, {
  required int generation,
  required Uri uri,
  required ForumThreadDocumentSnapshot? document,
}) async {
  coordinator.onPageStarted(generation: generation, uri: uri);
  await coordinator.onPageFinished(
    generation: generation,
    finalUri: uri,
    document: document,
  );
}

Uri _threadUri(String tid, {int? page}) {
  return Uri.parse('https://bbs.yamibo.com/forum.php').replace(
    queryParameters: <String, String>{
      'mod': 'viewthread',
      'tid': tid,
      if (page != null) 'page': page.toString(),
      'mobile': '2',
    },
  );
}
