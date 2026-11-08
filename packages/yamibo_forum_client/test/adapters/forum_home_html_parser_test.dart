import 'package:test/test.dart';
import 'package:yamibo_forum_client/src/adapters/forum_home_html_parser.dart';

void main() {
  final parser = ForumHomeHtmlParser(
    siteOrigin: Uri.parse('https://bbs.yamibo.com'),
  );
  const path =
      'data/attachment/freeaddon_banner/slide/202611/01/233241zihxiqrhiioexhfg.jpg';
  const target = 'https://bbs.yamibo.com/forum-52-1.html';
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
