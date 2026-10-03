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
      expect(firstText.plainText, '第一段 重点');
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

    test('preserves collapsed spaces across inline styles and links', () {
      final document = parser.parse('''
<p>  Hello <b>  styled </b> <a href="thread-1-1-1.html"> link </a> ! </p>
<p><b>A</b> <i>B</i></p>
''');

      final first = document.blocks.first as RichTextBlock;
      expect(first.plainText, 'Hello styled link !');
      expect(first.runs.singleWhere((run) => run.isBold).text, 'styled ');
      expect(
        first.runs.singleWhere((run) => run.linkUrl != null).text,
        'link ',
      );
      expect((document.blocks.last as RichTextBlock).plainText, 'A B');
    });

    test('preserves spaces around an inline smiley', () {
      final document = parser.parse(
        '<p> 前文 <img src="static/image/smiley/comcom/2.gif" alt="[笑]"> 后文 </p>',
      );

      final text = document.blocks.single as RichTextBlock;
      expect(text.plainText, '前文 [笑] 后文');
      expect(text.runs[1].inlineImage?.altText, '[笑]');
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
