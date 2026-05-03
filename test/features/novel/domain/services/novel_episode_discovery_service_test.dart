import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/services/novel_episode_discovery_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  test('NovelEpisodeDiscoveryService builds chapter plan from OP posts', () {
    const service = NovelEpisodeDiscoveryService();

    final page = ThreadDetailData(
      tid: '100',
      fid: '49',
      subject: '测试小说',
      author: '楼主A',
      replies: 2,
      views: 10,
      currentPage: 1,
      perPage: 20,
      posts: <ThreadPost>[
        ThreadPost(
          pid: '5001',
          author: '楼主A',
          authorId: '1',
          message: '<p>第1章 开始</p><p>正文A</p>',
          number: 1,
          isFirst: true,
          dateline: '2026-05-03',
        ),
        ThreadPost(
          pid: '5002',
          author: '楼主A',
          authorId: '1',
          message: '<p>第2章 继续</p><p>正文B</p>',
          number: 2,
          isFirst: false,
          dateline: '2026-05-04',
        ),
        ThreadPost(
          pid: '5003',
          author: '路人',
          authorId: '2',
          message: '<p>围观</p>',
          number: 3,
          isFirst: false,
          dateline: '2026-05-04',
        ),
      ],
    );

    final plan = service.buildPlan(novelId: 'novel:49:100', pages: [page]);

    expect(plan.episodes.length, 2);
    expect(plan.episodes.first.episodeTitle, '第1章');
    expect(plan.episodes.first.paragraphs, isNotEmpty);
    expect(plan.episodes.last.sourcePid, '5002');
  });
}
