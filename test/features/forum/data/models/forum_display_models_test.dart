import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/data/services/forum_display_snapshot_codec.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';

void main() {
  group('ForumDisplayQuery', () {
    test('parses forumdisplay URL and preserves filter parameters', () {
      final query = ForumDisplayQuery.fromUrl(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30&filter=typeid&typeid=69&page=2&mobile=2',
        fallbackFid: '1',
      );

      expect(query.fid, '30');
      expect(query.page, 2);
      expect(query.parameters['filter'], 'typeid');
      expect(query.parameters['typeid'], '69');
      expect(query.parameters.containsKey('mod'), isFalse);
      expect(query.parameters.containsKey('mobile'), isFalse);
      expect(query.toRequestParameters(), containsPair('mod', 'forumdisplay'));
      expect(query.toRequestParameters(), containsPair('mobile', '2'));
    });

    test('copyWithPage keeps current filter query', () {
      const query = ForumDisplayQuery(
        fid: '30',
        page: 1,
        parameters: <String, String>{'filter': 'digest', 'digest': '1'},
      );

      final next = query.copyWithPage(4);

      expect(next.page, 4);
      expect(next.parameters['filter'], 'digest');
      expect(next.parameters['digest'], '1');
      expect(next.toRequestParameters()['page'], '4');
    });
  });

  group('ForumDisplayData.fromVariables', () {
    test('parses forum_threadlist and tpp from forumdisplay response', () {
      final variables = <String, dynamic>{
        'forum': <String, dynamic>{
          'fid': '5',
          'name': '动漫区',
          'threads': '27956',
        },
        'page': '1',
        'tpp': '20',
        'forum_threadlist': <Map<String, dynamic>>[
          <String, dynamic>{
            'tid': '533721',
            'typeid': '400',
            'subject': '如何找回账号/如何修改密码',
            'author': 'hongyuny',
            'replies': '3',
            'views': '69864',
            'dateline': '2023-3-13 02:21',
          },
        ],
      };

      final data = ForumDisplayData.fromVariables(variables, page: 99);

      expect(data.fid, '5');
      expect(data.forumName, '动漫区');
      expect(data.currentPage, 1);
      expect(data.perPage, 20);
      expect(data.totalThreads, 27956);
      expect(data.threads, hasLength(1));
      expect(data.threads.first.tid, '533721');
      expect(data.threads.first.typeid, '400');
      expect(data.threads.first.subject, '如何找回账号/如何修改密码');
      expect(data.threads.first.author, 'hongyuny');
      expect(data.threads.first.replies, 3);
      expect(data.threads.first.views, 69864);
      expect(data.threads.first.dateline, '2023-3-13 02:21');
    });

    test('supports fallback keys threadlist and perpage', () {
      final variables = <String, dynamic>{
        'forum': <String, dynamic>{'fid': '9', 'name': '测试区', 'threads': '1'},
        'perpage': '10',
        'threadlist': <Map<String, dynamic>>[
          <String, dynamic>{
            'tid': '100',
            'subject': '兼容字段',
            'authorname': 'fallback-author',
            'replies': '0',
            'views': '1',
            'dbdateline': '1700000000',
          },
        ],
      };

      final data = ForumDisplayData.fromVariables(variables, page: 2);

      expect(data.currentPage, 2);
      expect(data.perPage, 10);
      expect(data.threads, hasLength(1));
      expect(data.threads.first.author, 'fallback-author');
      expect(data.threads.first.dateline, '1700000000');
    });
  });

  group('ForumDisplaySnapshotCodec', () {
    test('round trips parsed forum display data', () {
      final source = ForumDisplayData(
        fid: '30',
        forumName: '中文百合漫画区',
        currentPage: 2,
        perPage: 20,
        totalThreads: 100,
        headImageUrl: 'head',
        forumIconUrl: 'icon',
        todayPosts: 8,
        rank: 1,
        postUrl: 'post',
        searchUrl: 'search',
        favoriteUrl: 'favorite',
        favoriteAction: ForumDisplayFavoriteAction.unfavorite,
        previousPageUrl: 'prev',
        nextPageUrl: 'next',
        lastPage: 5,
        hasMoreOverride: true,
        primaryFilters: const <ForumDisplayFilterItem>[
          ForumDisplayFilterItem(label: '全部', url: 'all', isSelected: true),
        ],
        typeFilters: const <ForumDisplayFilterItem>[
          ForumDisplayFilterItem(label: '長篇連載', url: 'type', typeid: '69'),
        ],
        subForums: const <ForumDisplaySubForum>[
          ForumDisplaySubForum(fid: '31', title: '子版块', url: 'sub'),
        ],
        topEntries: const <ForumDisplayTopEntry>[
          ForumDisplayTopEntry(
            title: '公告',
            url: 'announcement',
            tid: '1',
            badgeLabel: '公告',
            titleColorHex: '#531104',
            isAnnouncement: true,
          ),
        ],
        threads: <ForumThreadSummary>[
          ForumThreadSummary(
            tid: '572604',
            typeid: '69',
            sourceTagName: '長篇連載',
            subject: '测试帖子',
            author: 'alice',
            replies: 1,
            views: 12,
            dateline: '2026-6-18',
            uid: '10',
            avatarUrl: 'avatar',
            authorUrl: 'author',
            threadUrl: 'thread',
            excerpt: '摘要',
            sourceTagUrl: 'tag',
            badgeLabel: '投票',
            titleColorHex: '#E92725',
            isLocked: true,
          ),
        ],
      );
      const codec = ForumDisplaySnapshotCodec();

      final decoded = codec.decode(codec.encode(source));

      expect(decoded.forumName, source.forumName);
      expect(decoded.primaryFilters.single.isSelected, isTrue);
      expect(decoded.typeFilters.single.typeid, '69');
      expect(decoded.subForums.single.title, '子版块');
      expect(decoded.topEntries.single.isAnnouncement, isTrue);
      expect(decoded.threads.single.sourceTagName, '長篇連載');
      expect(decoded.threads.single.isLocked, isTrue);
      expect(decoded.favoriteAction, ForumDisplayFavoriteAction.unfavorite);
    });

    test('legacy snapshot with favoriteUrl defaults to favorite only', () {
      final decoded = const ForumDisplaySnapshotCodec().decode({
        'fid': '30',
        'forumName': '论坛',
        'currentPage': 1,
        'perPage': 20,
        'totalThreads': 0,
        'favoriteUrl': 'home.php?mod=spacecp&ac=favorite',
        'threads': const <Object?>[],
      });

      expect(decoded.favoriteAction, ForumDisplayFavoriteAction.favorite);
    });

    test('legacy snapshot without favorite metadata stays unknown', () {
      final decoded = const ForumDisplaySnapshotCodec().decode({
        'fid': '30',
        'forumName': '论坛',
        'currentPage': 1,
        'perPage': 20,
        'totalThreads': 0,
        'threads': const <Object?>[],
      });

      expect(decoded.favoriteAction, ForumDisplayFavoriteAction.unknown);
    });
  });
}
