import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void main() {
  group('ForumPostDomExtractor', () {
    const extractor = ForumPostDomExtractor();

    test('extracts image sources from common lazy-load attributes', () {
      final images = extractor.extractImageSources('''
<img src="https://img.test/1.jpg">
<img data-src="https://img.test/2.jpg">
<img data-original="https://img.test/3.jpg">
<img file="https://img.test/4.jpg">
''');

      expect(images, <String>[
        'https://img.test/1.jpg',
        'https://img.test/2.jpg',
        'https://img.test/3.jpg',
        'https://img.test/4.jpg',
      ]);
    });

    test(
      'normalizes relative and protocol-relative image sources to site urls',
      () {
        final images = extractor.extractImageSources('''
<img src="data/attachment/forum/a.jpg">
<img data-src="//bbs.yamibo.com/data/attachment/forum/b.jpg">
<img file="/data/attachment/forum/c.jpg">
''');

        expect(images, <String>[
          'https://bbs.yamibo.com/data/attachment/forum/a.jpg',
          'https://bbs.yamibo.com/data/attachment/forum/b.jpg',
          'https://bbs.yamibo.com/data/attachment/forum/c.jpg',
        ]);
      },
    );

    test('filters forum chrome images by default', () {
      final images = extractor.extractImageSources('''
<img src="https://bbs.yamibo.com/static/image/common/smile.gif">
<img src="https://bbs.yamibo.com/uc_server/data/avatar/000/00/01.jpg">
<img src="https://img.test/content.jpg">
''');

      expect(images, <String>['https://img.test/content.jpg']);
    });

    test('extracts Yamibo attachment images from post html fragments', () {
      final images = extractor.extractImageSources('''
<font color="#6e2b19">
  <div class="img">
    <img src="https://bbs.yamibo.com/data/attachment/forum/201801/06/120746m4incxj78sh7cjcn.jpg" attach="39074461" />
  </div>
</font>
''');

      expect(images, <String>[
        'https://bbs.yamibo.com/data/attachment/forum/201801/06/120746m4incxj78sh7cjcn.jpg',
      ]);
    });

    test('normalizes Discuz pseudo absolute sinaimg image sources', () {
      final images = extractor.extractImageSources('''
<div class="img">
  <img src="http://data/attachment/sinaimg/tid503019/pid39465469/uid365616/63c446acd7a9d.jpg" />
</div>
''');

      expect(images, <String>[
        'https://bbs.yamibo.com/data/attachment/sinaimg/tid503019/pid39465469/uid365616/63c446acd7a9d.jpg',
      ]);
    });

    test('extracts thread tids only from DOM anchors', () {
      final tids = extractor.extractThreadTids('''
plain text thread-999-1-1.html should not count
<a href="thread-123-1-1.html">上一话</a>
<a href=";tid=456&amp;highlight=x">损坏链接</a>
''');

      expect(tids, <String>['123', '456']);
    });

    test('normalizes damaged tid links', () {
      final anchors = extractor.extractAnchors('<a href=";tid=123">上一话</a>');

      expect(anchors.single.tid, '123');
      expect(
        anchors.single.normalizedUrl,
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123',
      );
    });

    test('drops legacy encoded highlight from viewthread links', () {
      final anchors = extractor.extractAnchors('''
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;amp;tid=524596&amp;amp;highlight=%D2%B2%CE%DE%B7%E7%D3%EA">图源</a>
''');

      expect(anchors.single.tid, '524596');
      expect(
        anchors.single.normalizedUrl,
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=524596',
      );
      expect(anchors.single.normalizedUrl, isNot(contains('highlight')));
    });

    test('skips one malformed href without dropping valid anchors', () {
      final safeExtractor = ForumPostDomExtractor(
        urlParser: _ThrowingThreadUrlParser(),
      );
      final anchors = safeExtractor.extractAnchors('''
<a href="bad://boom">坏链接</a>
<a href="thread-123-1-1.html">第1话</a>
''');

      expect(anchors.map((anchor) => anchor.tid).toList(), <String?>['123']);
    });

    test('preserves br breaks in plain text', () {
      final text = extractor.extractPlainText(
        '<strong>001 珍贵之物，从手间滑落</strong><br />正文继续。',
      );

      expect(text, contains('\n正文继续。'));
    });
  });
}

class _ThrowingThreadUrlParser extends ForumReferenceResolver {
  const _ThrowingThreadUrlParser();

  @override
  String? normalizeHref(String href, {String? baseUrl}) {
    if (href.contains('bad://boom')) {
      throw const FormatException('bad href');
    }
    return super.normalizeHref(href, baseUrl: baseUrl);
  }
}
