import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/presentation/blog/blog_body_text_codec.dart';

void main() {
  for (final text in [
    '',
    'plain text',
    '<a> & "quoted"',
    '  第一行\n\n第二行  ',
    'a   b\n  c\n',
    '繁體 简体 😀',
  ]) {
    test('plain text round-trips without interpreting user markup: $text', () {
      final html = BlogBodyTextCodec.encode(text);
      expect(BlogBodyTextCodec.decode(html), text);
      if (text.contains('<a>')) expect(html, contains('&lt;a&gt;'));
    });
  }
  test('mobile line breaks do not duplicate retained PHP newlines', () {
    expect(
      BlogBodyTextCodec.decode('a<br />\nb<br>\n<br>\nc<br>'),
      'a\nb\n\nc\n',
    );
    expect(BlogBodyTextCodec.decode('a&lt;b &amp; c'), 'a<b & c');
  });
  test('plain layout uses only attributes-free markup accepted by Discuz', () {
    expect(
      BlogBodyTextCodec.encode('  a b\n\nc  '),
      '&nbsp;&nbsp;a b<br>\n<br>\nc&nbsp;&nbsp;',
    );
    expect(
      BlogBodyTextCodec.encode('<div style="color:red">text</div>'),
      '&lt;div style="color:red"&gt;text&lt;/div&gt;',
    );
  });
  for (final source in [
    '<b>bold</b>',
    '<p>paragraph</p>',
    '<img src="x.png">',
    '<br class="styled">',
    'before<!--keep-->after',
    '<div style="color:red">red</div>',
    '<div style="white-space: pre-wrap"><a href="x">link</a></div>',
    '<div style="white-space: pre-wrap" data-extra="keep">text</div>',
  ]) {
    test('rich or hidden markup remains in HTML mode: $source', () {
      expect(BlogBodyTextCodec.decode(source), isNull);
    });
  }
}
