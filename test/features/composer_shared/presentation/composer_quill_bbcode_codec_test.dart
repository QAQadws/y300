import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_bbcode_codec.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';

void main() {
  const codec = ComposerQuillBbCodeCodec();

  test('encodes stacked inline formatting in stable Discuz order', () {
    final delta = Delta()
      ..insert('文字', {
        Attribute.bold.key: true,
        Attribute.italic.key: true,
        Attribute.underline.key: true,
        Attribute.strikeThrough.key: true,
        Attribute.size.key: '18',
        Attribute.color.key: '#ff0000',
        Attribute.background.key: '#fff3b0',
      })
      ..insert('\n');

    expect(
      codec.encodeDelta(delta),
      '[b][i][u][s][size=4][color=#ff0000][backcolor=#fff3b0]文字[/backcolor][/color][/size][/s][/u][/i][/b]',
    );
  });

  test('encodes align, quote and link', () {
    final delta = Delta()
      ..insert('链接', {Attribute.link.key: 'https://example.com'})
      ..insert('\n', {
        Attribute.align.key: 'center',
        Attribute.blockQuote.key: true,
      });

    expect(
      codec.encodeDelta(delta),
      '[align=center][quote][url=https://example.com]链接[/url][/quote][/align]',
    );
  });

  test('encodes continuous quoted lines as a single quote block', () {
    final delta = Delta()
      ..insert('第一行')
      ..insert('\n', {Attribute.blockQuote.key: true})
      ..insert('第二行')
      ..insert('\n', {Attribute.blockQuote.key: true});

    expect(codec.encodeDelta(delta), '[quote]第一行\n第二行[/quote]');
  });

  test('keeps separated quote blocks distinct', () {
    final delta = Delta()
      ..insert('第一行')
      ..insert('\n', {Attribute.blockQuote.key: true})
      ..insert('普通行')
      ..insert('\n')
      ..insert('第二行')
      ..insert('\n', {Attribute.blockQuote.key: true});

    expect(
      codec.encodeDelta(delta),
      '[quote]第一行[/quote]\n普通行\n[quote]第二行[/quote]',
    );
  });

  test('keeps quote blocks split by a normal blank line distinct', () {
    final delta = Delta()
      ..insert('旧引用')
      ..insert('\n', {Attribute.blockQuote.key: true})
      ..insert('\n')
      ..insert('新引用')
      ..insert('\n', {Attribute.blockQuote.key: true});

    expect(codec.encodeDelta(delta), '[quote]旧引用[/quote]\n[quote]新引用[/quote]');
  });

  test('preserves normal blank lines in body text', () {
    final delta = Delta()
      ..insert('第一行')
      ..insert('\n')
      ..insert('\n')
      ..insert('第二行')
      ..insert('\n');

    expect(codec.encodeDelta(delta), '第一行\n\n第二行');
  });

  test('wraps continuous align and quote block once', () {
    final delta = Delta()
      ..insert('第一行')
      ..insert('\n', {
        Attribute.align.key: 'center',
        Attribute.blockQuote.key: true,
      })
      ..insert('第二行')
      ..insert('\n', {
        Attribute.align.key: 'center',
        Attribute.blockQuote.key: true,
      });

    expect(
      codec.encodeDelta(delta),
      '[align=center][quote]第一行\n第二行[/quote][/align]',
    );
  });

  test('encodes sticker and uploaded image embeds', () {
    final delta = Delta()
      ..insert('A')
      ..insert(composerQuillStickerEmbedData('{:9_656:}'))
      ..insert(composerQuillAttachEmbedData('123456'))
      ..insert('\n');

    expect(codec.encodeDelta(delta), 'A{:9_656:}[attach]123456[/attach]');
  });

  test('encodes attachimg embeds with their original tag kind', () {
    final delta = Delta()
      ..insert(
        composerQuillAttachEmbedData(
          '1624572',
          ComposerAttachTagKind.attachImg,
        ),
      )
      ..insert('\n');

    expect(codec.encodeDelta(delta), '[attachimg]1624572[/attachimg]');
  });

  test('decodes prototype-generated BBCode subset back to Delta', () {
    const source =
        '[align=center][quote][b][color=#ff0000]文字[/color][/b][/quote][/align]\n'
        '{:9_656:}[attach]123456[/attach]';

    final document = codec.decodeDocument(source);
    final json = document.toDelta().toJson();

    expect(codec.encodeDocument(document), source);
    final textOperation = json.firstWhere(
      (operation) => operation['insert'] == '文字',
    );
    expect(textOperation['attributes'], containsPair('bold', true));
    expect(textOperation['attributes'], containsPair('color', '#ff0000'));
    expect(textOperation['attributes'], isNot(containsPair('size', '4')));
    final lineOperation = json.firstWhere(
      (operation) =>
          operation['insert'] == '\n' && operation['attributes'] != null,
    );
    expect(lineOperation['attributes'], containsPair('blockquote', true));
    expect(lineOperation['attributes'], containsPair('align', 'center'));
    expect(
      json.any((operation) {
        final insert = operation['insert'];
        return insert is Map && insert['sticker'] == '{:9_656:}';
      }),
      isTrue,
    );
    expect(
      json.any((operation) {
        final insert = operation['insert'];
        return insert is Map &&
            insert['attach'] is Map &&
            insert['attach']['aid'] == '123456' &&
            insert['attach']['tag'] == 'attach';
      }),
      isTrue,
    );
  });

  test('decodes a legal attach code into an atomic embed', () {
    final document = codec.decodeDocument('[ATTACH]1626084[/attach]');
    final json = document.toDelta().toJson();

    expect(
      json.any((operation) {
        final insert = operation['insert'];
        return insert is Map &&
            insert['attach'] is Map &&
            insert['attach']['aid'] == '1626084' &&
            insert['attach']['tag'] == 'attach';
      }),
      isTrue,
    );
    expect(codec.encodeDocument(document), '[attach]1626084[/attach]');
  });

  test('decodes attachimg and preserves its tag kind', () {
    final document = codec.decodeDocument('[attachimg]1624572[/attachimg]');
    final json = document.toDelta().toJson();
    final operation = json.firstWhere(
      (operation) => operation['insert'] is Map,
    );

    expect(
      operation['insert'],
      containsPair('attach', containsPair('aid', '1624572')),
    );
    expect(codec.encodeDocument(document), '[attachimg]1624572[/attachimg]');
  });

  test('encodes legacy string attachment embeds as attach', () {
    final delta = Delta()
      ..insert(<String, String>{'attach': '7'})
      ..insert('\n');

    expect(codec.encodeDelta(delta), '[attach]7[/attach]');
  });

  test('new attachment embeds persist aid and tag kind', () {
    final embed = composerQuillAttachEmbed('7');

    expect(embed.data, <String, String>{'aid': '7', 'tag': 'attach'});
    expect(
      composerQuillAttachEmbedTagKind(embed),
      ComposerAttachTagKind.attach,
    );
    expect(
      composerQuillAttachEmbedTagKind(
        Embeddable(composerQuillAttachEmbedType, '7'),
      ),
      ComposerAttachTagKind.attach,
    );
  });

  test('keeps illegal attach codes as editable text', () {
    for (final source in const [
      '[attach]abc[/attach]',
      '[attach][/attach]',
      '[attach] 12 [/attach]',
    ]) {
      final document = codec.decodeDocument(source);

      expect(
        document.toDelta().toJson().every(
          (operation) => operation['insert'] is String,
        ),
        isTrue,
        reason: '$source 不应变成 embed',
      );
      expect(codec.encodeDocument(document), source);
    }
  });

  test('maps Quill visual sizes to Discuz sizes and keeps legacy raw sizes', () {
    final delta = Delta()
      ..insert('一', {Attribute.size.key: '12'})
      ..insert('二', {Attribute.size.key: '14'})
      ..insert('三', {Attribute.size.key: '16'})
      ..insert('四', {Attribute.size.key: '18'})
      ..insert('五', {Attribute.size.key: '20'})
      ..insert('六', {Attribute.size.key: '24'})
      ..insert('七', {Attribute.size.key: '28'})
      ..insert('旧', {Attribute.size.key: '4'})
      ..insert('\n');

    expect(
      codec.encodeDelta(delta),
      '[size=1]一[/size][size=2]二[/size][size=3]三[/size][size=4]四[/size][size=5]五[/size][size=6]六[/size][size=7]七[/size][size=4]旧[/size]',
    );
  });

  test('decodes Discuz size into Quill visual size', () {
    final document = codec.decodeDocument('[size=4]文字[/size]');
    final textOperation = document.toDelta().toJson().firstWhere(
      (operation) => operation['insert'] == '文字',
    );

    expect(textOperation['attributes'], containsPair('size', '18'));
  });

  test('ignores invalid size and color values', () {
    final delta = Delta()
      ..insert('文字', {
        Attribute.size.key: '99',
        Attribute.color.key: 'red',
        Attribute.background.key: '#abc',
      })
      ..insert('\n');

    expect(codec.encodeDelta(delta), '[backcolor=#aabbcc]文字[/backcolor]');
  });
}
