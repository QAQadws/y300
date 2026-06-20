import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_parser.dart';

void main() {
  group('ThreadPostBodyParser', () {
    const parser = ThreadPostBodyParser();

    test('parses text, links, and desktop attachment images into blocks', () {
      final document = parser.parse('''
<p>第一段 <strong>重点</strong></p>
<p><a href="thread-1-1-1.html">链接</a></p>
<ignore_js_op>
  <img aid="1597001"
       src="static/image/common/none.gif"
       zoomfile="data/attachment/forum/202606/03/070117ka05z5dcpjl0prsp.jpg"
       file="data/attachment/forum/202606/03/070117ka05z5dcpjl0prsp.jpg"
       width="900" />
</ignore_js_op>
''');

      expect(document.blocks, hasLength(3));
      final firstText = document.blocks[0] as ThreadPostTextBlock;
      expect(firstText.plainText, '第一段重点');
      expect(firstText.runs.last.isBold, isTrue);

      final secondText = document.blocks[1] as ThreadPostTextBlock;
      expect(secondText.plainText, '链接');
      expect(secondText.runs.single.linkUrl, contains('thread-1-1-1.html'));

      final image = document.blocks[2] as ThreadPostImageBlock;
      expect(image.aid, '1597001');
      expect(image.originalWidth, 900);
      expect(
        image.url,
        'https://bbs.yamibo.com/data/attachment/forum/202606/03/070117ka05z5dcpjl0prsp.jpg',
      );
    });

    test('filters forum chrome placeholder images', () {
      final document = parser.parse(
        '<img src="static/image/common/none.gif" />',
      );

      expect(document.blocks, isEmpty);
      expect(document.images, isEmpty);
    });
  });
}
