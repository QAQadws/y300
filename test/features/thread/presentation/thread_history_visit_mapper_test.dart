import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/presentation/mappers/thread_history_visit_mapper.dart';
import 'package:y300/features/thread/presentation/services/thread_history_commit_guard.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';

void main() {
  const mapper = ThreadHistoryVisitMapper();

  test('maps parsed thread metadata and the first first-floor body image', () {
    final state = ThreadDetailPageState.initial(tid: '527325', subject: '')
        .copyWith(
          subject: '解析后的标题',
          forumName: '中文百合漫画区',
          currentPage: 1,
          desktopUrl: '/thread-527325-1-1.html',
          isLoadingInitial: false,
          posts: <ThreadPost>[
            ThreadPost(
              pid: 'first',
              author: 'alice',
              authorId: '1',
              message: '''
                <p><img src="/static/image/smilies/default/smile.gif"></p>
                <p><img data-original="/data/attachment/forum/cover.jpg"></p>
              ''',
              number: 1,
              isFirst: true,
              dateline: 'today',
              avatarUrl: '/uc_server/data/avatar/1.jpg',
            ),
          ],
        );

    final draft = mapper.map(state: state, routeTid: '527325');

    expect(
      draft.target,
      const HistoryTargetKey(type: HistoryTargetType.thread, id: '527325'),
    );
    expect(draft.surface, HistoryVisitSurface.threadNative);
    expect(draft.title, '解析后的标题');
    expect(draft.contextLabel, '中文百合漫画区');
    expect(draft.forumName, '中文百合漫画区');
    expect(draft.page, 1);
    expect(
      draft.canonicalUri,
      Uri.parse('https://bbs.yamibo.com/thread-527325-1-1.html'),
    );
    expect(
      draft.thumbnail?.remoteUrl,
      'https://bbs.yamibo.com/data/attachment/forum/cover.jpg',
    );
  });

  test('uses a placeholder when the first floor has no body image', () {
    final state = ThreadDetailPageState.initial(tid: '527325', subject: '')
        .copyWith(
          subject: '没有正文图片',
          currentPage: 1,
          isLoadingInitial: false,
          posts: <ThreadPost>[
            ThreadPost(
              pid: 'first',
              author: 'alice',
              authorId: '1',
              message: '<p>纯文字正文</p>',
              number: 1,
              isFirst: true,
              dateline: 'today',
              avatarUrl: '/uc_server/data/avatar/1.jpg',
            ),
          ],
        );

    final draft = mapper.map(state: state, routeTid: '527325');

    expect(draft.thumbnail, isNull);
  });

  test('uses route fallbacks without treating a reply as the first floor', () {
    final state = ThreadDetailPageState.initial(tid: '572278', subject: '')
        .copyWith(
          currentPage: 2,
          isLoadingInitial: false,
          posts: <ThreadPost>[
            ThreadPost(
              pid: 'reply',
              author: 'bob',
              authorId: '2',
              message: '<p>第二页回复</p>',
              number: 21,
              isFirst: false,
              dateline: 'today',
              avatarUrl: 'https://bbs.yamibo.com/avatar/reply.jpg',
            ),
          ],
        );

    final draft = mapper.map(
      state: state,
      routeTid: '572278',
      routeSubject: '路由标题',
      routePage: 2,
    );

    expect(draft.title, '路由标题');
    expect(draft.contextLabel, '第 2 页');
    expect(draft.page, 2);
    expect(draft.thumbnail, isNull);
    expect(
      draft.canonicalUri,
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=572278&page=2',
      ),
    );
  });

  test('route guard commits once per visible TID', () {
    final guard = ThreadHistoryCommitGuard();

    expect(guard.tryCommit(' 100 '), isTrue);
    expect(guard.tryCommit('100'), isFalse);
    expect(guard.tryCommit('101'), isTrue);
    expect(guard.tryCommit(''), isFalse);
  });
}
