import 'package:test/test.dart';
import 'package:yamibo_forum_client/src/adapters/forum_home_html_parser.dart';

void main() {
  final parser = ForumHomeHtmlParser(
    siteOrigin: Uri.parse('https://bbs.yamibo.com'),
  );
  const path =
      'data/attachment/freeaddon_banner/slide/202611/01/233241zihxiqrhiioexhfg.jpg';
  const target = 'https://bbs.yamibo.com/forum-52-1.html';
  const albumImage =
      'https://bbs.yamibo.com/data/attachment/album/202611/15/150552n3ubkcl75ghlagr9.jpg';
  const albumTarget = 'https://bbs.yamibo.com/thread-579051-1-1.html';
  const banner =
      '<div class="wp cl"><a href="$target" target="_black">'
      '<img alt="2026年度萌战" src="$path" style="width:100%;height:100%;margin:0px;border:0px solid #CDCDCD;">'
      '</a></div>';
  String home(String content) =>
      '<html><body id="forum">$content'
      '<div class="forumlist"></div></body></html>';
  String slide(String image, String link) =>
      '<div class="swiper-slide">'
      '<a href="$link"><img src="$image"></a></div>';

  test('appends the standalone campaign image and resolves its link', () {
    final data = parser.parse(
      home(
        '$banner<div class="index-top-wrapper">'
        '<div class="yami-swiper">${slide('/first.jpg', 'thread-1-1-1.html')}'
        '${slide('/second.jpg', 'thread-2-1-1.html')}</div></div>',
      ),
    );
    expect(data.carousel.map((item) => item.imageUri.toString()), [
      'https://bbs.yamibo.com/first.jpg',
      'https://bbs.yamibo.com/second.jpg',
      'https://bbs.yamibo.com/$path',
    ]);
    expect(data.carousel.last.targetUri.toString(), target);
    expect(
      data.carousel.first.targetUri.toString(),
      'https://bbs.yamibo.com/thread-1-1-1.html',
    );
  });

  test('appends the November Moe banner after all three original slides', () {
    final campaign = banner
        .replaceFirst(path, albumImage)
        .replaceFirst(target, albumTarget);
    final data = parser.parse(
      home(
        '<div id="header-padding"></div>$campaign'
        '<div class="header cl"></div><div class="ann-box"></div>'
        '<div class="index-top-wrapper"><div class="yami-swiper">'
        '${slide('/data/attachment/block/c3/first.jpg', 'thread-578918-1-1.html')}'
        '${slide('/data/attachment/block/7c/second.jpg', 'thread-578579-1-1.html')}'
        '${slide('/data/attachment/block/8b/third.jpg', 'thread-575569-1-1.html')}'
        '</div></div>',
      ),
    );
    expect(data.carousel.map((item) => item.targetUri.path), [
      '/thread-578918-1-1.html',
      '/thread-578579-1-1.html',
      '/thread-575569-1-1.html',
      '/thread-579051-1-1.html',
    ]);
    expect(data.carousel.last.imageUri.toString(), albumImage);
    expect(data.carousel.last.targetUri.toString(), albumTarget);
  });

  for (final image in [
    albumImage,
    '/campaigns/new-image.png',
    'https://cdn.example.org/event.jpg',
  ]) {
    test(
      'recognizes banner structure independently of image storage: $image',
      () {
        final data = parser.parse(home(banner.replaceFirst(path, image)));
        expect(
          data.carousel.single.imageUri,
          Uri.parse('https://bbs.yamibo.com').resolve(image),
        );
      },
    );
  }

  test('accepts an explicit campaign container without generic wp classes', () {
    final data = parser.parse(
      home(
        banner.replaceFirst('class="wp cl"', 'class="home-campaign-banner"'),
      ),
    );
    expect(data.carousel.single.targetUri.toString(), target);
  });

  test('only appends standalone banners before the forum directory', () {
    final data = parser.parse(
      home(
        '$banner<div class="forumlist"></div>'
        '${banner.replaceFirst(target, 'thread-2-1-1.html')}'
        '<div class="footer">${banner.replaceFirst(target, 'thread-3-1-1.html')}</div>',
      ),
    );
    expect(data.carousel.map((item) => item.targetUri.toString()), [target]);
  });

  test('does not treat page chrome as a campaign even when it has wp cl', () {
    final chrome = [
      for (final name in ['header', 'footer', 'foot', 'nav'])
        banner
            .replaceFirst('wp cl', 'wp cl $name')
            .replaceFirst(target, 'thread-2-1-1.html'),
    ].join();
    final data = parser.parse(home('$banner$chrome'));
    expect(data.carousel.map((item) => item.targetUri.toString()), [target]);
  });

  test(
    'rejects homepage, navigation and fragment links as standalone banners',
    () {
      final rejected = [
        for (final link in [
          '/',
          'index.php?mobile=2',
          'forum.php?mobile=2',
          'forum.php?mod=index',
          'https://bbs.yamibo.com/#top',
          '?mobile=2',
          '#event',
          'member.php?mod=logging&action=login',
          'member.php?mod=register',
          'search.php?mod=forum&mobile=2',
        ])
          banner.replaceFirst(target, link),
      ].join();
      final data = parser.parse(home('$banner$rejected'));
      expect(data.carousel.map((item) => item.targetUri.toString()), [target]);
    },
  );

  test('retains the existing external campaign target behavior', () {
    final data = parser.parse(
      home(banner.replaceFirst(target, 'https://events.example.org/')),
    );
    expect(
      data.carousel.single.targetUri.toString(),
      'https://events.example.org/',
    );
  });

  test(
    'requires direct image-only links rather than a nested content scan',
    () {
      final rejected = [
        banner.replaceFirst('<a ', 'extra text<a '),
        banner.replaceFirst('<img ', 'caption<img '),
        banner
            .replaceFirst('<img ', '<span><img ')
            .replaceFirst('</a>', '</span></a>'),
        banner.replaceFirst('</a>', '<button>action</button></a>'),
      ].join();
      final data = parser.parse(home('$banner$rejected'));
      expect(data.carousel, hasLength(1));
    },
  );

  test(
    'allows several direct image links but skips explicitly hidden banners',
    () {
      final second = banner.replaceFirst(target, 'thread-2-1-1.html');
      final secondAnchor = second.substring(
        second.indexOf('<a'),
        second.lastIndexOf('</div>'),
      );
      final hiddenAnchor = secondAnchor
          .replaceFirst('<a ', '<a hidden ')
          .replaceFirst('thread-2-1-1.html', 'thread-999-1-1.html');
      final combined = banner.replaceFirst(
        '</div>',
        '$secondAnchor$hiddenAnchor</div>',
      );
      final data = parser.parse(
        home(
          '$combined${banner.replaceFirst('<div ', '<div hidden ')}'
          '${banner.replaceFirst('<a ', '<a hidden ')}${banner.replaceFirst('<img ', '<img hidden ')}',
        ),
      );
      expect(data.carousel.map((item) => item.targetUri.path), [
        '/forum-52-1.html',
        '/thread-2-1-1.html',
      ]);
    },
  );

  test(
    'deduplicates swiper and standalone entries by resolved image and target',
    () {
      final data = parser.parse(
        home(
          '$banner$banner<div class="yami-swiper">'
          '${slide('/$path', 'forum-52-1.html')}</div>',
        ),
      );
      expect(data.carousel, hasLength(1));
      expect(data.carousel.single.targetUri.toString(), target);
    },
  );

  test('keeps distinct targets for the same campaign image', () {
    final data = parser.parse(
      home('$banner${banner.replaceFirst(target, 'forum-53-1.html')}'),
    );
    expect(data.carousel.map((item) => item.targetUri.path), [
      '/forum-52-1.html',
      '/forum-53-1.html',
    ]);
  });

  test('supports a standalone banner when there is no swiper', () {
    final data = parser.parse(home(banner));
    expect(
      data.carousel.single.imageUri.toString(),
      'https://bbs.yamibo.com/$path',
    );
    expect(data.carousel.single.targetUri.toString(), target);
  });

  test('does not collect logos, forum icons or nested content banners', () {
    final data = parser.parse(
      home(
        '$banner'
        '<div class="wp cl"><a href="/"><img src="static/image/common/logo.png"></a></div>'
        '<div class="forumlist"><div class="wp cl"><a href="forum-54-1.html"><img src="$path"></a></div></div>'
        '<div class="wp cl"><div><a href="forum-55-1.html"><img src="$path"></a></div></div>',
      ),
    );
    expect(data.carousel, hasLength(1));
  });

  test('skips malformed or unsupported campaign URLs', () {
    final data = parser.parse(
      home(
        '$banner'
        '${banner.replaceFirst(target, 'javascript:alert(1)')}'
        '${banner.replaceFirst(target, '')}'
        '${banner.replaceFirst(target, 'https://[')}'
        '${banner.replaceFirst(path, 'data:image/png;base64,AA==')}'
        '${banner.replaceFirst(path, '')}',
      ),
    );
    expect(data.carousel, hasLength(1));
  });
}
