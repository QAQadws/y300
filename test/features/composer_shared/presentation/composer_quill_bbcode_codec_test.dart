import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_bbcode_codec.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_selection_adapter.dart';

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
  test('decodes nested collapse embeds and preserves attachment tag kind', () {
    const source =
        '[collapse=0,外层]\n'
        '正文\n'
        '[collapse=0,内层]\n'
        '[attachimg]1629685[/attachimg][/collapse]\n'
        '[/collapse]';
    final document = codec.decodeDocument(source);
    final collapse = document.toDelta().toList().firstWhere(
      (operation) =>
          operation.data is Map &&
          (operation.data as Map).containsKey('collapse'),
    );
    final payload = composerQuillCollapseEmbedPayload(collapse.data);

    expect(payload, isNotNull);
    expect(payload!['title'], '外层');
    expect(payload['body'], contains('[attachimg]1629685[/attachimg]'));
    expect(codec.encodeDocument(document), source);
  });

  test('round-trips supported recursive collapse layouts through Quill', () {
    for (final source in const [
      '[collapse=0,外层标题]\n'
          '外层内容。\n'
          '[collapse=0,内层标题]\n'
          '内层隐藏内容。\n'
          '[/collapse]\n'
          '外层继续。\n'
          '[/collapse]',
      '[collapse=0,第一层]\n'
          '第一层开头。\n'
          '[collapse=0,第二层]\n'
          '第二层内容。\n'
          '[collapse=0,第三层]\n'
          '第三层深层数据。\n'
          '[/collapse]\n'
          '第二层结尾。\n'
          '[/collapse]\n'
          '第一层结尾。\n'
          '[/collapse]',
      '[collapse=0,主题A]\n'
          'A的概述。\n'
          '[collapse=0,子项A1]\n'
          'A1详情。\n'
          '[/collapse]\n'
          '[collapse=0,子项A2]\n'
          'A2详情。\n'
          '[/collapse]\n'
          '[/collapse]\n'
          '\n'
          '[collapse=0,主题B]\n'
          'B的概述。\n'
          '[collapse=0,子项B1]\n'
          'B1详情。\n'
          '[/collapse]\n'
          '[/collapse]',
    ]) {
      final document = codec.decodeDocument(source);

      expect(codec.encodeDocument(document), source, reason: source);
    }
  });

  test('nested bodies reuse formatting, sticker and attachment codecs', () {
    const source =
        '[collapse=0,标题,带逗号]\n'
        '[b]粗体[/b]{:9_656:}\n'
        '[attach]123456[/attach]\n'
        '[attachimg]1629685[/attachimg]\n'
        '[collapse=0,内层]\n'
        '[url=https://example.com]链接[/url]\n'
        '[/collapse]\n'
        '[/collapse]';

    final document = codec.decodeDocument(source);

    expect(codec.encodeDocument(document), source);
  });

  test('keeps the opening line break outside the editable collapse body', () {
    const source =
        '[collapse=0,标题1]\n'
        '嵌套1\n'
        '[collapse=0,标2]\n'
        '嵌套2\n'
        '[font=宋体]宋体[/font]\n'
        '默认字体\n'
        '[attachimg]1629685[/attachimg][/collapse][/collapse]';

    final root = codec.decodeDocument(source);
    final outerOperation = root.toDelta().toList().firstWhere(
      (operation) =>
          operation.data is Map &&
          (operation.data as Map).containsKey('collapse'),
    );
    final outer = composerQuillCollapseEmbedPayload(outerOperation.data)!;
    final outerBody = codec.decodeDocument(outer['body']! as String);

    expect(outer['body'], startsWith('嵌套1'));
    expect(outerBody.toPlainText(), startsWith('嵌套1'));
    expect(codec.encodeDocument(root), source);
  });

  test('preserves a valid CRLF opening until the title changes', () {
    const source = '[COLLAPSE = 0,标题]\r\n正文[/COLLAPSE ]';
    final document = codec.decodeDocument(source);
    final operation = document.toDelta().toList().firstWhere(
      (operation) =>
          operation.data is Map &&
          (operation.data as Map).containsKey('collapse'),
    );
    final payload = composerQuillCollapseEmbedPayload(operation.data)!;

    expect(payload['rawOpeningLine'], '[COLLAPSE = 0,标题]\r\n');
    expect(payload['rawClosing'], '[/COLLAPSE ]');
    expect(codec.encodeDocument(document), source);

    final changedPayload = <String, Object?>{...payload, 'title': '新标题'};
    final changedDocument = Document.fromDelta(
      Delta()
        ..insert(<String, Object?>{'collapse': changedPayload})
        ..insert('\n'),
    );

    expect(
      codec.encodeDocument(changedDocument),
      '[collapse=0,新标题]\n正文[/COLLAPSE ]',
    );
  });

  test('keeps collapse mode one and malformed collapse as editable text', () {
    for (final source in const [
      '[collapse=1,展开]正文[/collapse]',
      '[collapse=0,未完成]\n正文',
      '[collapse=0,行内]正文[/collapse]',
    ]) {
      final document = codec.decodeDocument(source);
      expect(
        document.toDelta().toList().every(
          (operation) => operation.data is String,
        ),
        isTrue,
        reason: source,
      );
      expect(codec.encodeDocument(document), source);
    }
  });

  test('encodes a versioned collapse payload and rejects unknown versions', () {
    final embed = composerQuillCollapseEmbed(
      id: 'session-1',
      title: '标题',
      body: '内容',
    );
    expect(
      composerQuillCollapseEmbedPayload(embed),
      containsPair('id', 'session-1'),
    );
    expect(
      composerQuillCollapseEmbedPayload({
        'collapse': {
          'version': 2,
          'id': 'session-1',
          'mode': 0,
          'title': '标题',
          'body': '内容',
        },
      }),
      isNull,
    );
  });

  test('maps a collapse source block to one atomic Quill selection unit', () {
    const source =
        'A\n'
        '[collapse=0,内层]\nB[/collapse]\n'
        'C';
    final document = codec.decodeDocument(source);
    const adapter = ComposerQuillSelectionAdapter();
    const beforeEmbed = TextSelection.collapsed(offset: 2);
    const afterEmbed = TextSelection.collapsed(offset: 3);

    expect(
      adapter.toSourceSelection(
        source: source,
        document: document,
        selection: beforeEmbed,
      ),
      ComposerSelection(
        start: source.indexOf('[collapse'),
        end: source.indexOf('[collapse'),
      ),
    );
    final rawAfterEmbed = source.indexOf('\nC');
    final mappedAfter = adapter.toSourceSelection(
      source: source,
      document: document,
      selection: afterEmbed,
    );
    expect(
      mappedAfter,
      ComposerSelection(start: rawAfterEmbed, end: rawAfterEmbed),
    );
    expect(
      adapter.toQuillSelection(
        source: source,
        document: document,
        selection: mappedAfter!,
      ),
      afterEmbed,
    );
  });
}
