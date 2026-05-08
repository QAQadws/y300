import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

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

      expect(
        images,
        <String>[
          'https://img.test/1.jpg',
          'https://img.test/2.jpg',
          'https://img.test/3.jpg',
          'https://img.test/4.jpg',
        ],
      );
    });

    test('filters forum chrome images by default', () {
      final images = extractor.extractImageSources('''
<img src="https://bbs.yamibo.com/static/image/common/smile.gif">
<img src="https://bbs.yamibo.com/uc_server/data/avatar/000/00/01.jpg">
<img src="https://img.test/content.jpg">
''');

      expect(images, <String>['https://img.test/content.jpg']);
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
      expect(anchors.single.normalizedUrl, 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123');
    });

    test('preserves br breaks in plain text', () {
      final text = extractor.extractPlainText(
        '<strong>001 珍贵之物，从手间滑落</strong><br />正文继续。',
      );

      expect(text, contains('\n正文继续。'));
    });
  });
}
