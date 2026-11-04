import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:html_pagination_core/html_pagination_core.dart';

import '../conformance/forum_body_corpus.dart';

ForumBodyDocument parse(
  String html, {
  String conversion = 'none',
  ForumBodyParser parser = const ForumBodyParser(),
}) => parser.parse(
  html: html,
  sourceId: 'synthetic',
  conversionIdentity: conversion,
);

void main() {
  test(
    'Discuz code toolbar is hidden without deleting source or event diagnostics',
    () {
      const code =
          r'''<div class="blockcode"><div id="code_a1B"><ol><li>  code(); </li></ol></div><em onclick="copycode($('code_a1B'));">Copy code</em></div>''';
      final parser = _CountingParser();
      final document = parse(
        '<p>A</p>$code<p>Z</p>',
        parser: ForumBodyParser(fragmentParser: parser),
      );
      final control = document.descendants
          .whereType<ForumBodyElement>()
          .singleWhere((node) => node.tag == 'em');
      expect(control.kind, ForumBodyElementKind.hidden);
      expect(control.attributes, isNot(contains('onclick')));
      expect(document.sourceText, 'A  code(); Copy codeZ');
      expect(control.source.runeStart, 'A  code(); '.runes.length);
      expect(
        document.nodeAtPath('2/0')!.source.runeStart,
        'A  code(); Copy code'.runes.length,
      );
      expect(
        document.issues.map((i) => i.code),
        contains(ForumBodyIssueCode.removedEventAttribute),
      );
      expect(parser.calls, 1);
      final styles = const ForumBodyStyleResolver().resolve(
        document,
        ForumBodyReaderStyle(
          textStyle: const TextStyle(fontSize: 10),
          fontRevision: 'code-chrome',
          linkColor: const Color(0xff0000ff),
        ),
      );
      expect(styles.byPath[control.path]!.hidden, isTrue);
    },
  );

  test(
    'code toolbar accepts only its adjacent wrapper and actual copy handler',
    () {
      const code =
          r'''<div class="blockcode"><div id="code_a1B"><ol><li>x</li></ol></div><em onclick="copycode($('code_a1B'));">Copy code</em></div>''';
      for (final html in [
        code,
        code.replaceFirst('</div><em', '</div> \n<!--gap--><em'),
        code.replaceFirst('Copy code', '複製程式碼'),
        code.replaceFirst(
          r"copycode($('code_a1B'));",
          r''' copycode( $( &quot;code_a1B&quot; ) ) ; ''',
        ),
      ]) {
        final control = parse(html).descendants
            .whereType<ForumBodyElement>()
            .singleWhere((node) => node.tag == 'em');
        expect(control.kind, ForumBodyElementKind.hidden, reason: html);
      }
      for (final html in [
        code.replaceFirst('class="blockcode"', 'class="ordinary"'),
        code.replaceFirst('id="code_a1B"', 'id="code_z9Z"'),
        code.replaceAll('code_a1B', 'unrelated'),
        code.replaceFirst(r''' onclick="copycode($('code_a1B'));"''', ''),
        code.replaceFirst(
          r"copycode($('code_a1B'));",
          r"copycode($('code_a1B')); other();",
        ),
        code.replaceFirst('</div><em', '</div>authored text<em'),
        code.replaceFirst('<ol><li>x</li></ol>', '<p>x</p>'),
        code.replaceFirst(
          '<ol><li>x</li></ol>',
          '<ol><li>x</li></ol><ol><li>y</li></ol>',
        ),
        '<p><em>Copy code</em></p>',
        r'''<div class="blockcode"><ol><li><em onclick="copycode($('code_a1B'));">authored</em></li></ol></div>''',
      ]) {
        final control = parse(html).descendants
            .whereType<ForumBodyElement>()
            .singleWhere((node) => node.tag == 'em');
        expect(control.kind, ForumBodyElementKind.inline, reason: html);
      }
    },
  );

  for (final sample in forumBodyCases) {
    test(
      'IR preserves source content and coordinate coverage: ${sample.id}',
      () {
        final document = parse(sample.html);
        for (final token in sample.visibleTokens) {
          expect(document.sourceText, contains(token));
        }
        expect(document.sourceText.runes.length, document.sourceMap.runeLength);
        for (final node in document.descendants) {
          expect(document.nodeAtPath(node.path), same(node));
          expect(
            node.source.runeStart,
            inInclusiveRange(0, document.sourceMap.runeLength),
          );
          expect(
            node.source.runeEnd,
            greaterThanOrEqualTo(node.source.runeStart),
          );
          expect(
            identical(node.source, document.sourceMap.rangesByPath[node.path]),
            isTrue,
          );
        }
      },
    );
  }

  test('path lookup follows numeric child indices and removed-node gaps', () {
    final document = parse(
      '<!--root gap--><script>active</script>'
      '<div><!--nested gap--><span>first</span>'
      '${List.generate(20, (index) => '<b>$index</b>').join()}'
      '<style>removed</style><i>last</i></div><p>tail</p>',
    );
    for (final node in document.descendants) {
      expect(document.nodeAtPath(node.path), same(node));
    }
    for (final path in [
      '',
      '0',
      '1',
      '2/0',
      '2/22',
      '2/1/0/0',
      '999',
      '02',
      '2//1',
      '/2',
      '2/',
      '2/-1',
      '2/+1',
      '2/ 1',
      'x',
    ]) {
      expect(document.nodeAtPath(path), isNull, reason: path);
    }
  });

  test('single parse yields immutable data, never a retained mutable DOM', () {
    final source = _CountingParser();
    final document = parse(
      '<!--comment--><p class="original">甲<br>😀'
      '<img src="x">乙</p>',
      parser: ForumBodyParser(fragmentParser: source),
    );
    expect(source.calls, 1);
    source.fragment!.querySelector('p')!.attributes['class'] = 'changed';
    source.fragment!.nodes.clear();
    final paragraph = document.nodes.single as ForumBodyElement;
    expect(paragraph.path, '1');
    expect(paragraph.attributes['class'], 'original');
    expect(document.sourceText, '甲\n😀乙');
    expect(() => document.nodes.clear(), throwsUnsupportedError);
    expect(() => paragraph.children.clear(), throwsUnsupportedError);
    expect(() => paragraph.attributes.clear(), throwsUnsupportedError);
    final emoji = paragraph.children.whereType<ForumBodyText>().elementAt(1);
    expect(emoji.sourceRuneAtUtf16(1), emoji.source.runeStart);
    expect(emoji.sourceRuneAtUtf16(2), emoji.source.runeEnd);
    expect(() => emoji.sourceRuneAtUtf16(3), throwsRangeError);
  });

  test(
    'style data is shared, immutable and respects important declarations',
    () {
      const style = 'color:red!important;color:blue;letter-spacing:1px';
      final document = parse('<p style="$style">甲</p><p style="$style">乙</p>');
      final paragraphs = document.nodes.cast<ForumBodyElement>();
      final first = paragraphs.first.style;
      expect(document.uniqueStyleCount, 1);
      expect(identical(first, paragraphs.last.style), isTrue);
      expect(first.value('color'), 'red');
      expect(first.value('letter-spacing'), '1px');
      expect(() => first.declarations.clear(), throwsUnsupportedError);
    },
  );

  test(
    'active content/events are removed, unknown visible structure retained',
    () {
      final document = parse(
        '<script>secretScript()</script><style>secretStyle</style>'
        '<extension onclick="secretEvent()">保留内容</extension>'
        '<template><p>模板来源</p></template>',
      );
      expect(document.sourceText, '保留内容模板来源');
      expect(document.sourceText.runes.length, document.sourceMap.runeLength);
      final element = document.nodes.first as ForumBodyElement;
      expect(element.kind, ForumBodyElementKind.unknown);
      expect(element.attributes, isNot(contains('onclick')));
      expect(
        (document.nodes.last as ForumBodyElement).kind,
        ForumBodyElementKind.hidden,
      );
      expect(
        document.issues.map((issue) => issue.code),
        containsAll([
          ForumBodyIssueCode.removedActiveContent,
          ForumBodyIssueCode.removedEventAttribute,
          ForumBodyIssueCode.unknownElement,
        ]),
      );
    },
  );

  test('identity isolates markup, source and conversion provenance', () {
    final first = parse('<p>文字</p>');
    final same = parse('<p>文字</p>');
    expect(first.identity, same.identity);
    expect(first.identity.cacheIdentity, same.identity.cacheIdentity);
    expect(first.identity, isNot(parse('<div>文字</div>').identity));
    expect(
      first.identity,
      isNot(parse('<p>文字</p>', conversion: 'toTraditional').identity),
    );
    expect(first.identity.inputHash, hasLength(64));
  });

  test('resource references use shared lazy-image precedence and no Host', () {
    final document = parse(
      '<img src="none.gif" file="medium.png" '
      'zoomfile="original.png" aid="23" width="80" height="40" '
      'data-y300-readable-image-index="2"><img width="Infinity" height="-1">',
    );
    final first = (document.nodes.first as ForumBodyElement).resource!;
    expect(first.rawSource, 'original.png');
    expect(first.readableImageIndex, 2);
    expect(first.attachmentId, '23');
    expect((first.width, first.height), (80, 40));
    final invalid = (document.nodes.last as ForumBodyElement).resource!;
    expect((invalid.width, invalid.height), (null, null));
  });

  test(
    'admission rejects length before parse, and node/depth before indexing',
    () {
      final source = _CountingParser();
      expect(
        () => parse(
          '12345',
          parser: ForumBodyParser(
            fragmentParser: source,
            limits: const ForumBodyParseLimits(maxCodeUnits: 4),
          ),
        ),
        throwsA(
          isA<ForumBodyParseException>().having(
            (e) => e.failure,
            'code',
            ForumBodyParseFailure.inputLimit,
          ),
        ),
      );
      expect(source.calls, 0);
      expect(
        () => parse(
          '<p>A</p><p>B</p>',
          parser: const ForumBodyParser(
            limits: ForumBodyParseLimits(maxNodes: 2),
          ),
        ),
        throwsA(
          isA<ForumBodyParseException>().having(
            (e) => e.failure,
            'code',
            ForumBodyParseFailure.nodeLimit,
          ),
        ),
      );
      final deep =
          '${List.filled(150, '<span>').join()}body'
          '${List.filled(150, '</span>').join()}';
      expect(
        () => parse(deep),
        throwsA(
          isA<ForumBodyParseException>().having(
            (e) => e.failure,
            'code',
            ForumBodyParseFailure.depthLimit,
          ),
        ),
      );
    },
  );

  for (final length in [10000, 100000]) {
    test('bounded long-chapter generation retains $length source units', () {
      final document = parse(forumBodyStressHtml(length));
      expect(document.sourceMap.runeLength, length);
      expect(document.sourceText.length, length);
      expect(document.nodes.length, length ~/ 100);
      final single = parse(forumBodyStressHtml(length, singleParagraph: true));
      expect(single.sourceMap.runeLength, length);
      expect(single.nodes.length, 1);
    });
  }
}

final class _CountingParser implements HtmlFragmentParser {
  var calls = 0;
  dom.DocumentFragment? fragment;
  @override
  dom.DocumentFragment parse(String html) {
    calls++;
    return fragment = html_parser.parseFragment(html);
  }
}
