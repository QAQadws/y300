import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/data/services/forum_display_html_parser.dart';

void main() {
  group('ForumDisplayHtmlParser', () {
    const parser = ForumDisplayHtmlParser();

    test('parses captured mobile forum display sample', () {
      final html = File('docs/html/某一个帖子列表页.html').readAsStringSync();

      final result = parser.parse(html, fallbackFid: '30', fallbackPage: 1);

      expect(result.fid, '30');
      expect(result.forumName, '中文百合漫画区');
      expect(result.forumIconUrl, contains('common_30_icon.gif'));
      expect(result.todayPosts, 105);
      expect(result.totalThreads, 52718);
      expect(result.rank, 1);
      expect(result.postUrl, contains('action=newthread'));
      expect(result.searchUrl, contains('search.php'));
      expect(result.favoriteUrl, contains('favoriteforum'));

      expect(result.primaryFilters.map((item) => item.label), [
        '全部',
        '最新',
        '热门',
        '新帖',
        '精华',
      ]);
      expect(result.primaryFilters.first.isSelected, isTrue);
      expect(result.typeFilters.first.label, '公告');
      expect(result.typeFilters.first.typeid, '65');

      expect(result.topEntries.first.title, '欢迎光临。');
      expect(result.topEntries.first.isAnnouncement, isTrue);
      expect(
        result.topEntries.where((entry) => entry.badgeLabel == '置顶'),
        isNotEmpty,
      );

      expect(result.threads.length, greaterThan(10));
      final first = result.threads.first;
      expect(first.tid, '519989');
      expect(first.author, 'hongyuny');
      expect(first.uid, '165700');
      expect(first.avatarUrl, contains('000/16/57/00_avatar_middle.jpg'));
      expect(first.subject, contains('中文百合漫画区漫画汇总'));
      expect(first.badgeLabel, '关闭的主题');
      expect(first.isLocked, isTrue);
      expect(first.sourceTagName, '公告');
      expect(first.typeid, '65');
      expect(first.views, 409965);
      expect(first.replies, 138);

      final second = result.threads[1];
      expect(second.tid, '572604');
      expect(second.author, 'nkdndixnx');
      expect(second.excerpt, contains('请勿随意转载'));
      expect(second.sourceTagName, '長篇連載');
      expect(second.views, 119);
      expect(second.replies, 0);

      expect(result.currentPage, 1);
      expect(result.lastPage, 2636);
      expect(result.nextPageUrl, contains('page=2'));
      expect(result.hasMore, isTrue);
    });

    test('returns fallback identity when document is empty', () {
      final result = parser.parse(
        '<html><body>empty</body></html>',
        fallbackFid: '99',
        fallbackPage: 3,
      );

      expect(result.fid, '99');
      expect(result.currentPage, 3);
      expect(result.threads, isEmpty);
      expect(result.topEntries, isEmpty);
      expect(result.hasMore, isFalse);
    });

    test('parses optional forum head image', () {
      final html = File('docs/html/海域区.html').readAsStringSync();

      final result = parser.parse(html, fallbackFid: '33', fallbackPage: 1);

      expect(result.fid, '33');
      expect(result.forumName, '海域區');
      expect(result.headImageUrl, contains('104621s5h1icczskxx5m5n.png'));
      expect(result.headImageUrl, startsWith('https://bbs.yamibo.com/'));
    });

    test('parses optional sub forum entries', () {
      final html = File('docs/html/动漫区.html').readAsStringSync();

      final result = parser.parse(html, fallbackFid: '5', fallbackPage: 1);

      expect(result.fid, '5');
      expect(result.forumName, '動漫區');
      expect(result.subForums, hasLength(1));

      final subForum = result.subForums.single;
      expect(subForum.fid, '52');
      expect(subForum.title, '百合会最萌世界杯专版！');
      expect(subForum.url, contains('fid=52'));
      expect(subForum.iconUrl, contains('common_52_icon.gif'));
      expect(subForum.iconUrl, startsWith('https://bbs.yamibo.com/'));
    });
  });
}
