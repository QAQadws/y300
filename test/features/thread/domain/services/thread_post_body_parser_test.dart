import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';
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
      final firstText = document.blocks[0] as RichTextBlock;
      expect(firstText.plainText, '第一段重点');
      expect(firstText.anchorId, startsWith('text-'));
      expect(firstText.runs.last.isBold, isTrue);

      final secondText = document.blocks[1] as RichTextBlock;
      expect(secondText.plainText, '链接');
      expect(secondText.runs.single.linkUrl, contains('thread-1-1-1.html'));

      final image = document.blocks[2] as RichImageBlock;
      expect(image.anchorId, startsWith('image-'));
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

    test('parses smiley dimensions when present', () {
      final document = parser.parse(
        '喜欢 <img src="static/image/smiley/comcom/2.gif" width="32" height="18" />',
      );

      final text = document.blocks.single as RichTextBlock;
      final smiley = text.runs.last.inlineImage;
      expect(smiley, isNotNull);
      expect(smiley!.url, endsWith('/static/image/smiley/comcom/2.gif'));
      expect(smiley.originalWidth, 32);
      expect(smiley.originalHeight, 18);
    });

    test('parses smiley without dimensions', () {
      final document = parser.parse(
        '喜欢 <img src="static/image/smiley/comcom/2.gif" />',
      );

      final text = document.blocks.single as RichTextBlock;
      final smiley = text.runs.last.inlineImage;
      expect(smiley, isNotNull);
      expect(smiley!.originalWidth, isNull);
      expect(smiley.originalHeight, isNull);
    });
  });
}
