import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/presentation/mappers/forum_webview_history_visit_mapper.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_history_coordinator.dart';
import 'package:y300/features/history/domain/models/history_models.dart';

void main() {
  test('maps visible thread metadata and strips legacy highlight query', () {
    final draft = const ForumWebViewHistoryVisitMapper().map(
      ForumWebViewHistoryCandidate(
        tid: '524596',
        finalUri: Uri.parse(
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=524596&page=3&highlight=%D2%B2%CE%DE',
        ),
        forumName: '中文百合小说区',
        document: ForumThreadDocumentSnapshot(
          title: '测试主题',
          canonicalUri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=524596&highlight=%BC%AB%CF%DE',
          ),
          firstPostAvatarUrl: 'https://bbs.yamibo.com/avatar.jpg',
          postCount: 20,
          menu: const ForumThreadMenuSnapshot(),
        ),
      ),
    );

    expect(
      draft.target,
      const HistoryTargetKey(type: HistoryTargetType.thread, id: '524596'),
    );
    expect(draft.surface, HistoryVisitSurface.threadWebView);
    expect(draft.title, '测试主题');
    expect(draft.contextLabel, '中文百合小说区');
    expect(draft.page, 3);
    expect(draft.forumName, '中文百合小说区');
    expect(draft.thumbnail?.remoteUrl, 'https://bbs.yamibo.com/avatar.jpg');
    expect(
      draft.canonicalUri.toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=524596',
    );
    expect(draft.canonicalUri.toString(), isNot(contains('highlight')));
  });

  test(
    'uses pretty thread path page and leaves empty metadata for normalizer',
    () {
      final draft = const ForumWebViewHistoryVisitMapper().map(
        ForumWebViewHistoryCandidate(
          tid: '123',
          finalUri: Uri.parse('https://bbs.yamibo.com/thread-123-4-1.html'),
          document: const ForumThreadDocumentSnapshot(
            title: null,
            postCount: 1,
            menu: ForumThreadMenuSnapshot(),
          ),
        ),
      );

      expect(draft.page, 4);
      expect(draft.contextLabel, '第 4 页');
      expect(draft.title, isNull);
      expect(draft.thumbnail, isNull);
    },
  );
}
