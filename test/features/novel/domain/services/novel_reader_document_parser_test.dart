import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';

void main() {
  const parser = DiscuzNovelReaderDocumentParser();

  test('parses paragraphs and preserves br as line breaks', () {
    final document = parser.parse(
      episodeId: 'ep1',
      rawHtml: '<p>第一行<br>第二行</p><div>第三段</div>',
      fallbackParagraphs: const <String>[],
    );

    expect(document.nodes.length, 2);
    expect(document.nodes.first.type, NovelReaderNodeType.paragraph);
    expect(document.nodes.first.text, '第一行\n第二行');
    expect(document.nodes.last.text, '第三段');
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

    expect(document.nodes.map((node) => node.type), <NovelReaderNodeType>[
      NovelReaderNodeType.heading,
      NovelReaderNodeType.quote,
      NovelReaderNodeType.divider,
      NovelReaderNodeType.image,
      NovelReaderNodeType.link,
    ]);
    expect(document.nodes[0].text, '标题');
    expect(document.nodes[1].text, '引用内容');
    expect(
      document.nodes[3].image?.url,
      'https://bbs.yamibo.com/data/attachment/forum/novel.jpg',
    );
    expect(document.nodes[3].image?.altText, '插图');
    expect(document.nodes[4].link?.tid, '123');
  });

  test('parses image file attribute as image node', () {
    final document = parser.parse(
      episodeId: 'ep1',
      rawHtml: '<img file="//bbs.yamibo.com/data/attachment/forum/file-image.png">',
      fallbackParagraphs: const <String>[],
    );

    expect(document.nodes.single.type, NovelReaderNodeType.image);
    expect(
      document.nodes.single.image?.url,
      'https://bbs.yamibo.com/data/attachment/forum/file-image.png',
    );
  });

  test('drops dangerous link href but keeps link text as paragraph', () {
    final document = parser.parse(
      episodeId: 'ep1',
      rawHtml: '<a href="javascript:alert(1)">危险链接</a>',
      fallbackParagraphs: const <String>[],
    );

    expect(document.nodes.single.type, NovelReaderNodeType.paragraph);
    expect(document.nodes.single.text, '危险链接');
    expect(document.nodes.single.link, isNull);
  });

  test('keeps paragraph wrapped single link as link node', () {
    final document = parser.parse(
      episodeId: 'ep1',
      rawHtml: '<p><a href="forum.php?mod=viewthread&amp;tid=200">跳转原帖</a></p>',
      fallbackParagraphs: const <String>[],
    );

    expect(document.nodes.single.type, NovelReaderNodeType.link);
    expect(document.nodes.single.text, '跳转原帖');
    expect(document.nodes.single.link?.tid, '200');
  });

  test('falls back to paragraphs when raw html is empty or invalid', () {
    final document = parser.parse(
      episodeId: 'ep1',
      rawHtml: '   ',
      fallbackParagraphs: const <String>['第一段', '第二段'],
    );

    expect(document.nodes.length, 2);
    expect(document.nodes.first.type, NovelReaderNodeType.paragraph);
    expect(document.nodes.first.text, '第一段');
    expect(document.plainText, '第一段\n第二段');
  });
}
