import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:y300/features/profile/presentation/blog/blog_body_text_codec.dart';
import 'package:y300/features/profile/presentation/blog/blog_quill_html_codec.dart';

void main() {
  const codec = BlogQuillHtmlCodec();

  test('empty editor produces an empty body for validation', () {
    expect(codec.encodeDocument(codec.decodeDocument('')), '');
    expect(codec.encodeDocument(codec.decodeDocument('<div><br></div>')), '');
  });

  test('plain typing keeps newlines, edge spaces, entities and emoji', () {
    const text = '  开头 & <文字> 😀\n\n第二行  \n';
    final document = codec.decodeDocument(BlogBodyTextCodec.encode(text));
    expect(document.toPlainText(), '$text\n');
    final roundTrip = codec.decodeDocument(codec.encodeDocument(document));
    expect(roundTrip.toPlainText(), document.toPlainText());
  });

  test('nested bold italic underline and Discuz font sizes stay editable', () {
    final document = codec.decodeDocument(
      '<b><i><u><font size="4">格式</font></u></i></b>',
    );
    final operation = document.toDelta().first;
    expect(operation.data, '格式');
    expect(operation.attributes, {
      Attribute.bold.key: true,
      Attribute.italic.key: true,
      Attribute.underline.key: true,
      Attribute.size.key: '18',
    });
    final output = codec.encodeDocument(document);
    expect(output, contains('<font size="4"><b><i><u>格式</u></i></b></font>'));
    expect(output, isNot(contains('style=')));
  });

  for (final entry in {
    1: '12',
    2: '14',
    3: '16',
    4: '18',
    5: '20',
    6: '24',
    7: '28',
  }.entries) {
    test('font size ${entry.key} uses the shared editor mapping', () {
      final document = codec.decodeDocument(
        '<font size="${entry.key}">字号</font>',
      );
      expect(
        document.toDelta().first.attributes?[Attribute.size.key],
        entry.value,
      );
      expect(codec.encodeDocument(document), contains('size="${entry.key}"'));
    });
  }

  test('supported browser style formatting becomes Discuz-safe HTML', () {
    final document = codec.decodeDocument(
      '<span style="font-weight: bold; font-style: italic; '
      'text-decoration: underline; font-size:18px; color: red">样式</span>',
    );
    final output = codec.encodeDocument(document);
    expect(output, contains('<font size="4" color="#ff0000">'));
    expect(output, contains('<b><i><u>样式</u></i></b>'));
    expect(output, isNot(contains('style=')));
  });

  test('an image-only body retains source attributes and is not empty', () {
    const source =
        '<img src="https://example.com/photo.png?a=1&amp;b=2" width="240" alt="照片">';
    final document = codec.decodeDocument(source);
    final payload = blogQuillImagePayload(document.toDelta().first.data)!;
    expect(payload['src'], 'https://example.com/photo.png?a=1&b=2');
    expect(payload['html'], contains('width="240"'));
    final output = codec.encodeDocument(document);
    final image = html.parseFragment(output).querySelector('img')!;
    expect(image.attributes['src'], payload['src']);
    expect(image.attributes['width'], '240');
    expect(image.attributes['alt'], '照片');
  });

  test('home smileys remain inline image embeds among formatted text', () {
    final document = codec.decodeDocument(
      '你好<b><img src="static/image/smiley/comcom/30.gif"></b>😀',
    );
    final embeds = document.toDelta().toList().where(
      (op) => op.data is! String,
    );
    expect(embeds, hasLength(1));
    expect(
      blogQuillImagePayload(embeds.single.data)?['src'],
      endsWith('/30.gif'),
    );
    expect(embeds.single.attributes?[Attribute.bold.key], true);
    expect(
      codec.encodeDocument(document),
      contains('<b><img src="static/image/smiley/comcom/30.gif"></b>'),
    );
  });

  test(
    'new image helper escapes attributes and supports embed builder payload',
    () {
      final embed = blogQuillImageEmbed('https://example.com/a.png?x=1&y=2');
      expect(blogQuillImagePayload(embed), blogQuillImagePayload(embed.data));
      expect(blogQuillImagePayload(embed)?['html'], contains('&amp;'));
      final document = Document.fromDelta(
        Delta()
          ..insert(embed.toJson())
          ..insert('\n'),
      );
      expect(codec.encodeDocument(document), contains('<img src='));
    },
  );

  test('unsafe image schemes cannot be inserted as new images', () {
    for (final value in [
      'javascript:alert(1)',
      'data:image/png;base64,abc',
      'file:///tmp/a',
      '',
    ]) {
      expect(() => blogQuillImageEmbed(value), throwsArgumentError);
    }
  });

  test('links retain targets and attribute escaping', () {
    final document = codec.decodeDocument(
      '<a href="home.php?mod=space&amp;uid=42"><b>作者</b></a>',
    );
    final output = codec.encodeDocument(document);
    expect(
      html.parseFragment(output).querySelector('a')!.attributes['href'],
      'home.php?mod=space&uid=42',
    );
    expect(output, contains('<b>作者</b>'));
    final unsafe = Delta()
      ..insert('文字', {Attribute.link.key: 'javascript:alert(1)'})
      ..insert('\n');
    expect(codec.encodeDelta(unsafe), '<div>文字</div>');
  });

  test(
    'quote blocks, line breaks and lists survive an editable round trip',
    () {
      const source =
          '<div>正文</div><blockquote><div>引用一<br>引用二</div></blockquote>'
          '<ul><li>项目一</li><li><b>项目二</b></li></ul><div>结尾</div>';
      final document = codec.decodeDocument(source);
      expect(document.toPlainText(), '正文\n引用一\n引用二\n项目一\n项目二\n结尾\n');
      final output = codec.encodeDocument(document);
      expect(html.parseFragment(output).querySelectorAll('li'), hasLength(2));
      expect(output, contains('<blockquote>'));
      expect(codec.decodeDocument(output).toDelta(), document.toDelta());
    },
  );

  test('nested wrappers do not manufacture blank paragraphs', () {
    final document = codec.decodeDocument(
      '<div><div>一</div><div>二</div></div>',
    );
    expect(document.toPlainText(), '一\n二\n');
    expect(
      codec.decodeDocument(codec.encodeDocument(document)).toPlainText(),
      '一\n二\n',
    );
  });

  test(
    'unknown table attributes and unsupported styles are preserved previews',
    () {
      const table =
          '<table border="1"><tbody><tr><td colspan="2">表格</td></tr></tbody></table>';
      const styled =
          '<span style="letter-spacing: 3px; color: rebeccapurple">原样</span>';
      final document = codec.decodeDocument(
        '<div>前</div>$table$styled<div>后</div>',
      );
      final fragments = document
          .toDelta()
          .toList()
          .where((op) => op.data is! String)
          .map((op) => blogQuillHtmlSource(op.data))
          .whereType<String>()
          .toList();
      expect(fragments, contains(table));
      expect(fragments, contains(styled));
      final output = codec.encodeDocument(document);
      expect(output, contains(table));
      expect(output, contains(styled));
      expect(output, contains('前'));
      expect(output, contains('后'));
    },
  );

  test('preserved child HTML keeps its inherited inline formatting', () {
    const source = '<b><span style="letter-spacing: 3px">保留</span></b>';
    final document = codec.decodeDocument(source);
    expect(blogQuillHtmlSource(document.toDelta().first.data), source);
    expect(codec.encodeDocument(document), contains(source));
  });

  test(
    'editing text beside unknown inline HTML preserves it without adding a line',
    () {
      const source = '前<span style="letter-spacing: 3px">中</span>后';
      final document = codec.decodeDocument(source);
      document.insert(0, '新增');
      final output = codec.encodeDocument(document);
      expect(output, '<div>新增$source</div>');
      final delta = codec.decodeDelta(output).toList();
      expect(delta.where((operation) => operation.data is Map), hasLength(1));
      expect(document.toPlainText().split('\n'), hasLength(2));
    },
  );

  test(
    'complex lists and deeply nested markup are preserved without recursion loss',
    () {
      const nestedList = '<ol><li>一<ul><li>二</li></ul></li></ol>';
      expect(
        codec.encodeDocument(codec.decodeDocument(nestedList)),
        contains(nestedList),
      );
      final source =
          '${List.filled(80, '<span>').join()}深层${List.filled(80, '</span>').join()}';
      final document = codec.decodeDocument(source);
      expect(codec.encodeDocument(document), contains('深层'));
      expect(document.toDelta().toList().any((op) => op.data is Map), true);
    },
  );

  test('nested quotes and quote lists preserve the original structure', () {
    const source =
        '<blockquote>外层<blockquote>内层</blockquote>'
        '<ol><li>项目</li></ol></blockquote>';
    final document = codec.decodeDocument(source);
    expect(blogQuillHtmlSource(document.toDelta().first.data), source);
    expect(codec.encodeDocument(document), contains(source));
  });

  test(
    'unknown named colors stay preserved instead of reaching Quill color parsing',
    () {
      const source = '<font color="rebeccapurple">紫色</font>';
      final document = codec.decodeDocument(source);
      expect(blogQuillHtmlSource(document.toDelta().first.data), source);
    },
  );

  test(
    'unrecognized future document embeds fail without losing user content',
    () {
      final delta = Delta()
        ..insert({'future': 'data'})
        ..insert('\n');
      expect(() => codec.encodeDelta(delta), throwsFormatException);
    },
  );
}
