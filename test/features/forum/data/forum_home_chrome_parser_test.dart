import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/data/services/forum_home_chrome_parser.dart';

void main() {
  group('ForumHomeChromeParser', () {
    const parser = ForumHomeChromeParser();

    test('parses carousel items from home html', () {
      final result = parser.parse('''
<body id="forum">
  <div class="yami-swiper">
    <div class="swiper-slide">
      <a href="thread-999-1-1.html"><img src="data/attachment/block/ignored.jpg"></a>
    </div>
  </div>
  <div class="index-top-wrapper">
    <div class="yami-swiper">
      <div class="swiper-wrapper">
        <div class="swiper-slide">
          <a href="https://bbs.yamibo.com/thread-570956-1-1.html">
            <img src="data/attachment/block/95/banner.jpg">
          </a>
        </div>
        <div class="swiper-slide">
          <a href="forum.php?mod=viewthread&amp;tid=570889&amp;mobile=2">
            <img src="/data/attachment/block/17/banner.jpg">
          </a>
        </div>
        <div class="swiper-slide">
          <a href="//bbs.yamibo.com/thread-569253-1-1.html">
            <img src="//bbs.yamibo.com/data/attachment/block/2d/banner.jpg">
          </a>
        </div>
      </div>
    </div>
  </div>
</body>
''');

      expect(result.carouselItems, hasLength(3));
      expect(
        result.carouselItems[0].targetUrl,
        'https://bbs.yamibo.com/thread-570956-1-1.html',
      );
      expect(
        result.carouselItems[0].imageUrl,
        'https://bbs.yamibo.com/data/attachment/block/95/banner.jpg',
      );
      expect(
        result.carouselItems[1].targetUrl,
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=570889&mobile=2',
      );
      expect(
        result.carouselItems[2].imageUrl,
        'https://bbs.yamibo.com/data/attachment/block/2d/banner.jpg',
      );
    });

    test('parses carousel items from captured forum home sample', () {
      final html = File('docs/html/论坛首页.html').readAsStringSync();

      final result = parser.parse(html);

      expect(result.carouselItems, hasLength(3));
      expect(
        result.carouselItems.map((item) => item.targetUrl),
        containsAll(<String>[
          'https://bbs.yamibo.com/thread-570956-1-1.html',
          'https://bbs.yamibo.com/thread-570889-1-1.html',
          'https://bbs.yamibo.com/thread-569253-1-1.html',
        ]),
      );
      expect(
        result.carouselItems.every((item) {
          return item.imageUrl.startsWith(
            'https://bbs.yamibo.com/data/attachment/block/',
          );
        }),
        isTrue,
      );
      expect(result.favoriteForums, hasLength(3));
      expect(
        result.favoriteForums.map((item) => item.description),
        containsAll(<String>[
          '风声水起。',
          '爱的推广会。',
          '外文作品翻译的分享与赏析。',
        ]),
      );
    });

    test('returns empty data when carousel is missing', () {
      final result = parser.parse('<html><body><p>empty</p></body></html>');

      expect(result.carouselItems, isEmpty);
    });

    test('preserves missing today badge as null in favorite forums', () {
      final result = parser.parse('''
<body id="forum">
  <div id="sub-forum-myfav" class="sub-forum mlist1 cl">
    <ul>
      <li>
        <a href="forum.php?mod=forumdisplay&amp;fid=33&amp;mobile=2" class="murl">
          <p class="mtit">海域區</p>
          <p class="mtxt">风声水起。</p>
        </a>
      </li>
    </ul>
  </div>
</body>
''');

      expect(result.favoriteForums.single.todayPosts, isNull);
    });

    test('skips invalid carousel entries', () {
      final result = parser.parse('''
<div class="yami-swiper">
  <div class="swiper-slide"><a href="thread-1-1-1.html"></a></div>
  <div class="swiper-slide"><img src="data/attachment/block/a.jpg"></div>
  <div class="swiper-slide">
    <a href="thread-2-1-1.html"><img src="data/attachment/block/b.jpg"></a>
  </div>
</div>
''');

      expect(result.carouselItems, hasLength(1));
      expect(
        result.carouselItems.single.targetUrl,
        'https://bbs.yamibo.com/thread-2-1-1.html',
      );
    });
  });
}
