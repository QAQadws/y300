import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';

void main() {
  const parser = DiscuzNovelReaderDocumentParser();

  test('parses paragraphs and preserves br as line breaks', () {
    final document = parser.parse(
      episodeId: 'ep1',
      rawHtml: '<p>第一行<br>第二行</p><div>第三段</div>',
      fallbackParagraphs: const <String>[],
    );

    expect(document.blocks.length, 2);
    final first = document.blocks.first as RichTextBlock;
    expect(first.isHeading, isFalse);
    expect(first.novelPlainText, '第一行\n第二行');
    expect((document.blocks.last as RichTextBlock).novelPlainText, '第三段');
  });

  test('parses headings quotes dividers images and links', () {
    final document = parser.parse(
      episodeId: 'ep1',
      rawHtml: '''
<h2>标题</h2>
<blockquote>引用内容</blockquote>
<hr>
<p><img data-original="//bbs.yamibo.com/data/attachment/forum/novel.jpg" alt="插图"></p>
<p><img src="https://bbs.yamibo.com/static/image/common/smile.gif"></p>
<a href="forum.php?mod=viewthread&amp;tid=123">原帖链接</a>
''',
      fallbackParagraphs: const <String>[],
    );

    final heading = document.blocks[0] as RichTextBlock;
    expect(heading.isHeading, isTrue);
    expect(heading.novelPlainText, '标题');

    expect(document.blocks[1], isA<RichQuoteBlock>());
    expect((document.blocks[1] as RichQuoteBlock).novelPlainText, '引用内容');

    expect(document.blocks[2], isA<RichDividerBlock>());

    final image = document.blocks[3] as RichImageBlock;
    expect(image.url, 'https://bbs.yamibo.com/data/attachment/forum/novel.jpg');
    expect(image.altText, '插图');

    final link = document.blocks[4] as RichTextBlock;
    expect(link.isNovelLinkButton, isTrue);
    expect(link.runs.single.linkTid, '123');
  });

  test('parses image file attribute as image block', () {
    final document = parser.parse(
      episodeId: 'ep1',
      rawHtml: '<img file="//bbs.yamibo.com/data/attachment/forum/file-image.png">',
      fallbackParagraphs: const <String>[],
    );

    final image = document.blocks.single as RichImageBlock;
    expect(
      image.url,
      'https://bbs.yamibo.com/data/attachment/forum/file-image.png',
    );
  });

  test('preserves img aid for later attachment resolution', () {
    final document = parser.parse(
      episodeId: 'ep1',
      rawHtml:
          '<img aid="4567" width="800" height="1200" src="https://bbs.yamibo.com/data/attachment/forum/p.jpg">',
      fallbackParagraphs: const <String>[],
    );

    final image = document.blocks.single as RichImageBlock;
    expect(image.aid, '4567');
    expect(image.originalWidth, 800);
    expect(image.originalHeight, 1200);
  });

  test('drops dangerous link href but keeps link text as paragraph', () {
    final document = parser.parse(
      episodeId: 'ep1',
      rawHtml: '<a href="javascript:alert(1)">危险链接</a>',
      fallbackParagraphs: const <String>[],
    );

    final block = document.blocks.single as RichTextBlock;
    expect(block.isNovelLinkButton, isFalse);
    expect(block.novelPlainText, '危险链接');
    expect(block.runs.single.linkUrl, isNull);
  });

  test('keeps paragraph wrapped single link as link block', () {
    final document = parser.parse(
      episodeId: 'ep1',
      rawHtml: '<p><a href="forum.php?mod=viewthread&amp;tid=200">跳转原帖</a></p>',
      fallbackParagraphs: const <String>[],
    );

    final block = document.blocks.single as RichTextBlock;
    expect(block.isNovelLinkButton, isTrue);
    expect(block.novelPlainText, '跳转原帖');
    expect(block.runs.single.linkTid, '200');
  });

  test('falls back to paragraphs when raw html is empty or invalid', () {
    final document = parser.parse(
      episodeId: 'ep1',
      rawHtml: '   ',
      fallbackParagraphs: const <String>['第一段', '第二段'],
    );

    expect(document.blocks.length, 2);
    expect((document.blocks.first as RichTextBlock).novelPlainText, '第一段');
    expect(document.plainText, '第一段\n第二段');
  });
}
