import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';

void main() {
  group('HtmlComicParserService', () {
    test('extracts images and episode links with deduplication', () {
      final parser = HtmlComicParserService();
      final result = parser.parse(
        message: '''
<div>作者: 测试组</div>
<img src="https://img.test/1.jpg" />
<img src="https://img.test/1.jpg" />
<img src="https://img.test/smilies/face.png" />
<a href="https://bbs.yamibo.com/thread-100-1-1.html?from=foo">1</a>
<a href="thread-101-1-1.html">第2话</a>
<a href="https://bbs.yamibo.com/thread-200-1-1.html">目录</a>
''',
      );

      expect(result.imageUrls.length, 1);
      expect(result.imageUrls.first, 'https://img.test/1.jpg');
      expect(result.episodeLinks.length, 3);
      expect(result.episodeLinks.first.url, 'https://bbs.yamibo.com/thread-100-1-1.html');
      expect(result.episodeLinks.first.episodeTitle, '1');
      expect(result.catalogUrl, 'https://bbs.yamibo.com/thread-200-1-1.html');
      expect(result.inferredAuthor, '测试组');
      expect(result.plainTextSummary, contains('作者: 测试组'));
    });
  });
}
