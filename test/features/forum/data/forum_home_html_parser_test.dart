import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/data/forum_home_html_parser.dart';

void main() {
  group('ForumHomeHtmlParser', () {
    const parser = ForumHomeHtmlParser();

    test('parses carousel, favorite section, and regular sections', () {
      final result = parser.parse('''
<body id="forum">
  <div class="index-top-wrapper">
    <div class="yami-swiper">
      <div class="swiper-slide">
        <a href="thread-570956-1-1.html">
          <img src="data/attachment/block/95/banner.jpg">
        </a>
      </div>
    </div>
  </div>
  <div class="forumlist cl">
    <div class="subforumshow cl" href="#sub-forum-myfav">
      <h2><a href="javascript:;">我收藏的版块</a></h2>
    </div>
    <div id="sub-forum-myfav" class="sub-forum mlist1 cl">
      <ul>
        <li>
          <span class="micon">
            <a href="forum.php?mod=forumdisplay&amp;fid=33&amp;mobile=2">
              <img src="data/attachment/common/18/common_33_icon.gif" alt="海域區">
            </a>
          </span>
          <a href="forum.php?mod=forumdisplay&amp;fid=33&amp;mobile=2" class="murl">
            <p class="mtit">海域區<span class="mnum">今日 88</span></p>
            <p class="mtxt">风声水起。</p>
          </a>
        </li>
      </ul>
    </div>
    <div class="subforumshow cl" href="#sub-forum_14">
      <h2><a href="javascript:;">庙堂</a></h2>
    </div>
    <div id="sub-forum_14" class="sub-forum mlist1 cl">
      <ul>
        <li>
          <a href="forum.php?mod=forumdisplay&amp;fid=16&amp;mobile=2" class="murl">
            <p class="mtit">管理版<span class="mnum">今日 5</span></p>
            <p class="mtxt">既无论先民后主，何必辩你们我们。</p>
          </a>
        </li>
        <li>
          <a href="/forum.php?mod=forumdisplay&amp;fid=370&amp;mobile=2" class="murl">
            <p class="mtit">使用指南</p>
            <p class="mtxt">使用问题看本版</p>
          </a>
        </li>
      </ul>
    </div>
  </div>
</body>
''');

      expect(result.carouselItems, hasLength(1));
      expect(
        result.carouselItems.single.imageUrl,
        'https://bbs.yamibo.com/data/attachment/block/95/banner.jpg',
      );
      expect(
        result.carouselItems.single.targetUrl,
        'https://bbs.yamibo.com/thread-570956-1-1.html',
      );
      expect(result.sections, hasLength(2));
      expect(result.sections.first.title, '我收藏的版块');
      expect(result.sections.first.isFavoriteSection, isTrue);
      expect(result.sections.first.items.single.fid, '33');
      expect(result.sections.first.items.single.title, '海域區');
      expect(result.sections.first.items.single.description, '风声水起。');
      expect(result.sections.first.items.single.todayPosts, 88);
      expect(
        result.sections.first.items.single.iconUrl,
        'https://bbs.yamibo.com/data/attachment/common/18/common_33_icon.gif',
      );
      expect(result.sections.last.title, '庙堂');
      expect(result.sections.last.isFavoriteSection, isFalse);
      expect(result.sections.last.items.map((item) => item.fid), ['16', '370']);
      expect(result.sections.last.items.last.todayPosts, 0);
    });

    test('parses captured forum home sample', () {
      final html = File('docs/html/论坛首页.html').readAsStringSync();

      final result = parser.parse(html);

      expect(result.carouselItems, hasLength(3));
      expect(result.sections, hasLength(3));
      expect(result.sections.map((section) => section.title), [
        '我收藏的版块',
        '庙堂',
        '江湖',
      ]);
      expect(result.sections.first.isFavoriteSection, isTrue);
      expect(result.sections.first.items.map((item) => item.fid), [
        '33',
        '30',
        '55',
      ]);
      expect(result.sections.last.items.map((item) => item.fid), [
        '5',
        '33',
        '13',
        '49',
        '44',
        '379',
        '19',
      ]);
      expect(
        result.sections.last.items.first.description,
        '请不要在莉莉安女子学院里狂奔……你给我站住！！',
      );
    });

    test('returns empty sections when forum list is missing', () {
      final result = parser.parse('<html><body>empty</body></html>');

      expect(result.carouselItems, isEmpty);
      expect(result.sections, isEmpty);
    });
  });
}
