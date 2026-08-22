import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/services/novel_episode_discovery_service.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';

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

  test(
    'NovelEpisodeDiscoveryService extracts cover, intro and inline images',
    () {
      const service = NovelEpisodeDiscoveryService();

      final page = ThreadDetailData(
        tid: '101',
        fid: '49',
        subject: '带图小说',
        author: '楼主A',
        replies: 1,
        views: 10,
        currentPage: 1,
        perPage: 20,
        posts: <ThreadPost>[
          ThreadPost(
            pid: '6001',
            author: '楼主A',
            authorId: '1',
            message: '''
<p>这是简介第一段。</p>
<p>第十二章 开始</p>
<p>正文A</p>
<img data-src="https://img.test/cover.jpg" />
<img src="https://bbs.yamibo.com/static/image/common/smile.gif" />
''',
            number: 1,
            isFirst: true,
            dateline: '2026-05-03',
          ),
          ThreadPost(
            pid: '6002',
            author: '路人',
            authorId: '2',
            message: '<p>围观</p>',
            number: 2,
            isFirst: false,
            dateline: '2026-05-03',
          ),
        ],
      );

      final plan = service.buildPlan(novelId: 'novel:49:101', pages: [page]);

      expect(plan.episodes.length, 1);
      expect(plan.episodes.first.episodeTitle, '第十二章');
      expect(plan.coverImageUrl, 'https://img.test/cover.jpg');
      expect(plan.inlineImageUrls, <String>['https://img.test/cover.jpg']);
      expect(plan.intro, '这是简介第一段。');
      expect(plan.debugInfo, isNotNull);
    },
  );

  test(
    'NovelEpisodeDiscoveryService includes attachment-only images in cover and inline images',
    () {
      const service = NovelEpisodeDiscoveryService();

      final page = ThreadDetailData(
        tid: '101a',
        fid: '49',
        subject: '附件图小说',
        author: '楼主A',
        replies: 1,
        views: 10,
        currentPage: 1,
        perPage: 20,
        posts: <ThreadPost>[
          ThreadPost(
            pid: '6101',
            author: '楼主A',
            authorId: '1',
            message: '<p>第十三章 开始</p><p>正文A</p>',
            number: 1,
            isFirst: true,
            dateline: '2026-05-03',
            attachmentImages: const <ForumPostAttachmentImage>[
              ForumPostAttachmentImage(
                aid: '1',
                url: 'data/attachment/forum/',
                attachment: 'cover.jpg',
                filename: 'cover.jpg',
                attachimg: '1',
                ext: 'jpg',
              ),
            ],
          ),
        ],
      );

      final plan = service.buildPlan(novelId: 'novel:49:101a', pages: [page]);

      expect(plan.episodes.length, 1);
      expect(
        plan.coverImageUrl,
        'https://bbs.yamibo.com/data/attachment/forum/cover.jpg',
      );
      expect(plan.inlineImageUrls, <String>[
        'https://bbs.yamibo.com/data/attachment/forum/cover.jpg',
      ]);
      expect(plan.episodes.single.imageUrls, <String>[
        'https://bbs.yamibo.com/data/attachment/forum/cover.jpg',
      ]);
    },
  );

  test(
    'NovelEpisodeDiscoveryService prefers same-thread pid catalog links',
    () {
      const service = NovelEpisodeDiscoveryService();

      final page = ThreadDetailData(
        tid: '511960',
        fid: '49',
        subject: '目录型小说',
        author: '楼主A',
        replies: 3,
        views: 10,
        currentPage: 1,
        perPage: 20,
        posts: <ThreadPost>[
          ThreadPost(
            pid: '39840000',
            author: '楼主A',
            authorId: '1',
            message: '''
<font color="#ff8c00">contents</font>
<table><tr><td><a href="https://bbs.yamibo.com/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=511960&amp;pid=39844657&amp;fromuid=165700">序　章♥最后的任侠七番比试</a></td></tr>
<tr><td><a href="https://bbs.yamibo.com/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=511960&amp;pid=39845455&amp;fromuid=165700">第一话♥作战开始，神枝枫</a></td></tr></table>
''',
            number: 1,
            isFirst: true,
            dateline: '2026-05-01',
          ),
          ThreadPost(
            pid: '39844657',
            author: '楼主A',
            authorId: '1',
            message: '<p>序章正文</p>',
            number: 2,
            isFirst: false,
            dateline: '2026-05-02',
          ),
          ThreadPost(
            pid: '39845455',
            author: '楼主A',
            authorId: '1',
            message: '<strong>第一话♥作战开始，神枝枫</strong><p>第一话正文</p>',
            number: 3,
            isFirst: false,
            dateline: '2026-05-03',
          ),
        ],
      );

      final plan = service.buildPlan(novelId: 'novel:49:511960', pages: [page]);

      expect(plan.episodes.length, 2);
      expect(plan.episodes.map((e) => e.sourceTid), everyElement('511960'));
      expect(plan.episodes.map((e) => e.sourcePid), <String>[
        '39844657',
        '39845455',
      ]);
      expect(plan.episodes.map((e) => e.episodeTitle), <String>[
        '序　章♥最后的任侠七番比试',
        '第一话♥作战开始，神枝枫',
      ]);
      expect(plan.episodes.first.plainText, contains('序章正文'));
    },
  );

  test(
    'NovelEpisodeDiscoveryService falls back to OP post pids when catalog is missing',
    () {
      const service = NovelEpisodeDiscoveryService();

      final page = ThreadDetailData(
        tid: '521519',
        fid: '49',
        subject: '无目录小说',
        author: '楼主A',
        replies: 1,
        views: 10,
        currentPage: 1,
        perPage: 20,
        posts: <ThreadPost>[
          ThreadPost(
            pid: '40213902',
            author: '楼主A',
            authorId: '1',
            message: '<strong>001 珍贵之物，从手间滑落</strong><br />正文继续。',
            number: 1,
            isFirst: true,
            dateline: '2026-05-03',
          ),
        ],
      );

      final plan = service.buildPlan(novelId: 'novel:49:521519', pages: [page]);

      expect(plan.episodes.single.sourceTid, '521519');
      expect(plan.episodes.single.sourcePid, '40213902');
      expect(plan.episodes.single.episodeTitle, '001 珍贵之物，从手间滑落');
      expect(plan.episodes.single.plainText, contains('\n正文继续。'));
    },
  );

  test(
    'NovelEpisodeDiscoveryService recognizes specials and fallback prologue',
    () {
      const service = NovelEpisodeDiscoveryService();

      final page = ThreadDetailData(
        tid: '102',
        fid: '49',
        subject: '番外测试',
        author: '楼主A',
        replies: 1,
        views: 10,
        currentPage: 1,
        perPage: 20,
        posts: <ThreadPost>[
          ThreadPost(
            pid: '7001',
            author: '楼主A',
            authorId: '1',
            message: '<p>只是正文，没有标题。</p>',
            number: 1,
            isFirst: true,
            dateline: '2026-05-03',
          ),
          ThreadPost(
            pid: '7002',
            author: '楼主A',
            authorId: '1',
            message: '<strong>番外</strong><p>短篇正文。</p>',
            number: 2,
            isFirst: false,
            dateline: '2026-05-04',
          ),
        ],
      );

      final plan = service.buildPlan(novelId: 'novel:49:102', pages: [page]);

      expect(plan.episodes.length, 2);
      expect(plan.episodes.first.episodeTitle, '序章');
      expect(plan.episodes.last.episodeTitle, '番外');
    },
  );
}
