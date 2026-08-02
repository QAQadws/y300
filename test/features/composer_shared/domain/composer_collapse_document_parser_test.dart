import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_collapse_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_collapse_document_parser.dart';
import 'package:y300/features/composer_shared/domain/services/composer_collapse_serializer.dart';

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

  test('consumes only the mandatory opening line break from the body', () {
    const source = '[collapse=0,标题]\n\n正文[/collapse]';
    final block = parser.parse(source).parts.single as ComposerCollapseBlock;

    expect(block.body.source, '\n正文');
    expect(serializer.serialize(block.body), '\n正文');
    expect(serializer.serialize(parser.parse(source)), source);
  });
}
