import 'package:test/test.dart';
import 'package:forum_markup_core/forum_markup_core.dart';

void main() {
  const parser = ComposerCollapseDocumentParser();
  const serializer = ComposerCollapseSerializer();

  test(
    'parses a nested collapse while preserving title commas and body tags',
    () {
      const source =
          '[collapse=0,标题1,继续]\n'
          '嵌套1\n'
          '[collapse=0,标题2]\n'
          '嵌套2\n'
          '[attachimg]1629685[/attachimg]\n'
          '[/collapse]\n'
          '[/collapse]';

      final document = parser.parse(source);
      final outer = document.parts.whereType<ComposerCollapseBlock>().single;
      final inner = outer.body.parts.whereType<ComposerCollapseBlock>().single;

      expect(document.hasCollapse, isTrue);
      expect(outer.title, '标题1,继续');
      expect(inner.title, '标题2');
      expect(inner.body.source, contains('[attachimg]1629685[/attachimg]'));
      expect(serializer.serialize(document), source);
      expect(document.isLossless, isTrue);
    },
  );

  test('round-trips supported two-level, three-level and sibling nesting', () {
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
      final document = parser.parse(source);

      expect(document.isLossless, isTrue, reason: source);
      expect(document.hasCollapse, isTrue, reason: source);
      expect(serializer.serialize(document), source, reason: source);
    }
  });

  test(
    'keeps existing BBCode, stickers and both attachment tags in bodies',
    () {
      const source =
          '[collapse=0,标题,带逗号]\n'
          '[b]粗体[/b]{:9_656:}\n'
          '[attach]123456[/attach]\n'
          '[attachimg]1629685[/attachimg]\n'
          '[collapse=0,内层]\n'
          '[url=https://example.com]链接[/url]\n'
          '[/collapse]\n'
          '[/collapse]';

      final document = parser.parse(source);

      expect(document.isLossless, isTrue);
      expect(serializer.serialize(document), source);
    },
  );

  test('accepts empty title and body and ignores case in wire tags', () {
    const source = '[COLLAPSE=0,]\r\n[/COLLAPSE]';
    final document = parser.parse(source);

    expect(document.parts, hasLength(1));
    final block = document.parts.single as ComposerCollapseBlock;
    expect(block.title, isEmpty);
    expect(block.body.source, isEmpty);
    expect(serializer.serialize(document), source);
  });

  test('a title edit rewrites only the opening line of raw CRLF markup', () {
    const rawOpeningLine = '[CoLlApSe \t= \t0,原题,逗号]\r\n';
    const body = '[b]第一行[/b]\r\n第二行';
    const rawClosing = '[/CoLlApSe \t]';
    const source = '$rawOpeningLine$body$rawClosing';
    const newTitle = '新标题,仍有逗号';
    const expected = '[collapse=0,$newTitle]\n$body$rawClosing';
    final document = parser.parse(source);
    final block = document.parts.single as ComposerCollapseBlock;

    expect(document.isLossless, isTrue);
    expect(serializer.serialize(document), source);
    expect(
      serializer.serialize(
        document.copyWith(parts: [block.copyWith(title: newTitle)]),
      ),
      expected,
    );
    expect(
      serializer.serializeBlock(
        title: newTitle,
        bodyBbCode: block.body.source,
        rawOpeningLine: block.rawOpeningLine,
        rawClosing: block.rawClosing,
      ),
      expected,
    );
  });

  test('keeps unsupported or malformed collapse markup as raw text', () {
    for (final source in const [
      '[collapse=1,展开]\n正文[/collapse]',
      '[collapse=0,缺少结束]\n正文',
      '[collapse=0,行内]正文[/collapse]',
      '[collapse=0,含\uFFFC对象]\n正文[/collapse]',
      '前文[collapse=0,非行首]\n正文[/collapse]',
      '[collapse=\n0,跨行参数]\n正文[/collapse]',
      '[collapse=0,外层]\n[collapse=0,内层]\n正文[/collapse]',
      '[collapse=0,外层]\n[collapse=0,内层]\n正文[/外层][/内层]',
      '[collapse=0,外层]\n正文[/collapse]尾[/collapse]',
    ]) {
      final document = parser.parse(source);
      expect(document.parts, hasLength(1), reason: source);
      expect(document.parts.single, isA<ComposerCollapseText>());
      expect((document.parts.single as ComposerCollapseText).value, source);
      expect(document.isLossless, isFalse, reason: source);
      expect(serializer.serialize(document), source, reason: source);
    }
  });

  test('enforces the maximum nested depth', () {
    final source = StringBuffer();
    for (var index = 0; index < 3; index += 1) {
      source.write('[collapse=0,$index]\n');
    }
    source.write('正文');
    for (var index = 0; index < 3; index += 1) {
      source.write('[/collapse]');
    }

    final document = const ComposerCollapseDocumentParser(
      maxDepth: 2,
    ).parse(source.toString());
    expect(document.parts.single, isA<ComposerCollapseText>());
    expect(document.issues, isNotEmpty);
  });

  test('the default depth accepts 16 levels and preserves 17 as raw text', () {
    final supportedSource = _nestedCollapseSource(16);
    final supported = parser.parse(supportedSource);

    expect(supported.isLossless, isTrue);
    expect(supported.issues, isEmpty);
    expect(serializer.serialize(supported), supportedSource);
    var body = supported;
    for (var level = 0; level < 16; level += 1) {
      final block = body.parts.single as ComposerCollapseBlock;
      expect(block.title, '层$level');
      body = block.body;
    }
    expect((body.parts.single as ComposerCollapseText).value, '正文');

    final tooDeepSource = _nestedCollapseSource(17);
    final tooDeep = parser.parse(tooDeepSource);

    expect(tooDeep.isLossless, isFalse);
    expect(tooDeep.parts, hasLength(1));
    expect((tooDeep.parts.single as ComposerCollapseText).value, tooDeepSource);
    expect(
      tooDeep.issues.single.code,
      ComposerCollapseParseIssueCode.maximumDepthExceeded,
    );
    expect(serializer.serialize(tooDeep), tooDeepSource);
  });

  test('consumes only the mandatory opening line break from the body', () {
    const source = '[collapse=0,标题]\n\n正文[/collapse]';
    final block = parser.parse(source).parts.single as ComposerCollapseBlock;

    expect(block.body.source, '\n正文');
    expect(serializer.serialize(block.body), '\n正文');
    expect(serializer.serialize(parser.parse(source)), source);
  });
}

String _nestedCollapseSource(int depth) {
  final source = StringBuffer();
  for (var level = 0; level < depth; level += 1) {
    source.write('[collapse=0,层$level]\n');
  }
  source.write('正文');
  for (var level = 0; level < depth; level += 1) {
    source.write('[/collapse]');
  }
  return source.toString();
}
