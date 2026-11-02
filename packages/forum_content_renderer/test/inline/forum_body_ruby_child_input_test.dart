import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_child_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';

final class _Parsed {
  _Parsed(String html) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'structured-ruby-child',
      conversionIdentity: 'none',
    );
    styles = const ForumBodyStyleResolver().resolve(document, reader);
    final flow = ForumBodyTextFlowCursor(document: document, reader: reader);
    try {
      while (!flow.isComplete) {
        flow.advance(maxEvents: 1);
        if (flow.current case ForumBodyTextFlowInline(:final content)) {
          input = content;
          group = content.parts
              .whereType<ForumBodyInlineFlowRuby>()
              .first
              .group;
          break;
        }
      }
    } finally {
      flow.close();
    }
  }
  final reader = ForumBodyReaderStyle(
    textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
    fontRevision: 'ahem',
    linkColor: const Color(0xff0000ff),
  );
  late final ForumBodyDocument document;
  late final ForumBodyStyleResult styles;
  late final ForumBodyInlineFlowContent input;
  late final ForumBodyRubyGroupContent group;
}

void main() {
  test(
    'text children keep original identity and content after the flow closes',
    () {
      final parsed = _Parsed(
        '<ruby><rb style="font-size:30px">A</rb><rt>x</rt></ruby>',
      );
      final base = parsed.group.base.single as ForumBodyRubyBaseContent;
      final annotation =
          parsed.group.annotations.single as ForumBodyRubyTextAnnotationContent;
      final baseInput =
          ForumBodyRubyChildInput.base(parsed.group, base)
              as ForumBodyRubyTextChildInput;
      final annotationInput =
          ForumBodyRubyChildInput.annotation(parsed.group, annotation)
              as ForumBodyRubyTextChildInput;
      expect(
        baseInput.content,
        same((base.parts.single as ForumBodyRubyTextContent).content),
      );
      expect(
        annotationInput.content,
        same((annotation.parts.single as ForumBodyRubyTextContent).content),
      );
      expect(baseInput.requireText(), same(baseInput.content));
      expect(annotationInput.requireText(), same(annotationInput.content));
      expect(baseInput.content.style.textStyle.fontSize, 30);
      expect(annotationInput.content.style.textStyle.fontSize, 10);
    },
  );
  test(
    'nested base and RT sequences preserve real nodes, order, styles and ranges',
    () {
      final parsed = _Parsed(
        '<ruby><rb style="font-size:30px">before'
        '<ruby>漢<rt>kan</rt></ruby>after</rb><rt style="font-size:12px">outer'
        '<ruby>字<rt>ji</rt></ruby>end</rt></ruby>',
      );
      final base = parsed.group.base.single as ForumBodyRubyBaseContent;
      final annotation =
          parsed.group.annotations.single as ForumBodyRubyTextAnnotationContent;
      final inputs = [
        ForumBodyRubyChildInput.base(parsed.group, base)
            as ForumBodyRubySequenceChildInput,
        ForumBodyRubyChildInput.annotation(parsed.group, annotation)
            as ForumBodyRubySequenceChildInput,
      ];
      for (final (index, child) in inputs.indexed) {
        final parts = index == 0 ? base.parts : annotation.parts;
        expect(child.identity, parsed.group.identity);
        expect(child.fontRevision, parsed.group.fontRevision);
        expect(child.styleRevision, parsed.group.styleRevision);
        expect(child.path, index == 0 ? base.path : annotation.path);
        expect(
          child.source,
          same(index == 0 ? base.source : annotation.source),
        );
        expect(child.style, same(index == 0 ? base.style : annotation.style));
        expect(child.parts, hasLength(3));
        for (var part = 0; part < parts.length; part++) {
          expect(child.parts[part], same(parts[part]));
        }
        final nested = child.parts[1] as ForumBodyRubyNestedContent;
        final original = parts[1] as ForumBodyRubyNestedContent;
        expect(nested.groups.single, same(original.groups.single));
        expect(
          nested.groups.single.style.textStyle.fontSize,
          index == 0 ? 30 : 12,
        );
        expect(() => child.parts.clear(), throwsUnsupportedError);
        expect(
          () => child.requireText(),
          throwsA(
            isA<ForumBodyParagraphInputException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphInputFailure.structure,
            ),
          ),
        );
      }
      // Planning still refuses the structured box until its own native/source
      // transaction exists; this normalization must not broaden capability.
      expect(
        () => ForumBodyInlinePlanInput(parsed.input, 300),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );
  test(
    'implicit sequence retains actual parts without inventing a DOM range',
    () {
      final parsed = _Parsed(
        '<ruby>before<ruby>漢<rt>kan</rt></ruby>after<rt>outer</rt></ruby>',
      );
      final child =
          ForumBodyRubyChildInput.implicit(parsed.group, parsed.group.base)
              as ForumBodyRubySequenceChildInput;
      expect(child.path, parsed.group.rootPath);
      expect(child.source, isNull);
      expect(child.parts, orderedEquals(parsed.group.base));
      expect(child.style, same(parsed.group.style));
      expect(child.parts.whereType<ForumBodyRubyNestedContent>(), hasLength(1));
      expect(
        () => child.requireText(),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );
  test('empty annotation preserves its font context without invented text', () {
    final parsed = _Parsed('<ruby>A<rt style="font-size:12px"></rt></ruby>');
    final annotation =
        parsed.group.annotations.single as ForumBodyRubyTextAnnotationContent;
    final child = ForumBodyRubyChildInput.annotation(
      parsed.group,
      annotation,
    ).requireText();
    expect(
      child,
      same((annotation.parts.single as ForumBodyRubyTextContent).content),
    );
    expect(child.projection.text, isEmpty);
    final empty = ForumBodyRubyTextAnnotationContent(
      path: annotation.path,
      source: annotation.source,
      style: annotation.style,
      parts: const [],
    );
    final strut = ForumBodyRubyChildInput.annotation(
      parsed.group,
      empty,
    ).requireText();
    expect(strut.isSourceFree, true);
    expect(strut.projection.text, isEmpty);
    expect(strut.style, same(annotation.style));
    expect(strut.fontRevision, parsed.group.fontRevision);
    expect(strut.identity, parsed.group.identity);
  });
  test('an empty nested root remains structured rather than disappearing', () {
    final parsed = _Parsed(
      '<ruby><rb><ruby>A<rt>a</rt></ruby></rb><rt>b</rt></ruby>',
    );
    final base = parsed.group.base.single as ForumBodyRubyBaseContent;
    final nested = base.parts.single as ForumBodyRubyNestedContent;
    final empty = ForumBodyRubyNestedContent(
      path: nested.path,
      source: nested.source,
      style: nested.style,
      groups: const [],
    );
    final input = ForumBodyRubyBaseContent(
      path: base.path,
      source: base.source,
      style: base.style,
      parts: [empty],
    );
    final child =
        ForumBodyRubyChildInput.base(parsed.group, input)
            as ForumBodyRubySequenceChildInput;
    expect(child.parts.single, same(empty));
    expect(
      () => child.requireText(),
      throwsA(isA<ForumBodyParagraphInputException>()),
    );
  });
  test(
    'foreign direct text and nested groups are rejected before child planning',
    () {
      final parsed = _Parsed('<ruby><rb>A</rb><rt>a</rt></ruby>');
      final foreign = _Parsed('<ruby><rb>B</rb><rt>b</rt></ruby>');
      final base = parsed.group.base.single as ForumBodyRubyBaseContent;
      final otherBase = foreign.group.base.single as ForumBodyRubyBaseContent;
      for (final part in <ForumBodyRubyInlineContent>[
        otherBase.parts.single,
        ForumBodyRubyNestedContent(
          path: base.path,
          source: base.source,
          style: base.style,
          groups: [foreign.group],
        ),
      ]) {
        final input = ForumBodyRubyBaseContent(
          path: base.path,
          source: base.source,
          style: base.style,
          parts: [part],
        );
        expect(
          () => ForumBodyRubyChildInput.base(parsed.group, input),
          throwsA(
            isA<ForumBodyParagraphInputException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphInputFailure.identity,
            ),
          ),
        );
      }
    },
  );
  test(
    'wrong text layout mode and structural child types cannot masquerade as text',
    () {
      final parsed = _Parsed(
        '<p><span>unwrapped</span></p><ruby><rb>A</rb><rt>a</rt></ruby>',
      );
      final base = parsed.group.base.single as ForumBodyRubyBaseContent;
      final wrapped = const ForumBodyParagraphContentBuilder().build(
        document: parsed.document,
        styles: parsed.styles,
        path: '0/0',
      );
      for (final part in <ForumBodyRubyInlineContent>[
        ForumBodyRubyTextContent(wrapped),
        parsed.group.annotations.single,
      ]) {
        final input = ForumBodyRubyBaseContent(
          path: base.path,
          source: base.source,
          style: base.style,
          parts: [part],
        );
        expect(
          () => ForumBodyRubyChildInput.base(parsed.group, input),
          throwsA(
            isA<ForumBodyParagraphInputException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphInputFailure.structure,
            ),
          ),
        );
      }
    },
  );
  test('a previous font or style scope cannot enter the normalized child', () {
    final parsed = _Parsed('<ruby><rb>A</rb><rt>a</rt></ruby>');
    final base = parsed.group.base.single as ForumBodyRubyBaseContent;
    for (final fontChanged in [false, true]) {
      final stale = ForumBodyRubyGroupContent(
        identity: parsed.group.identity,
        fontRevision: fontChanged ? 'previous-font' : parsed.group.fontRevision,
          styleRevision: fontChanged
              ? parsed.group.styleRevision
              : parsed.group.styleRevision + 1,
        style: parsed.group.style,
        rootPath: parsed.group.rootPath,
        index: parsed.group.index,
        base: parsed.group.base,
        annotations: parsed.group.annotations,
      );
      expect(
        () => ForumBodyRubyChildInput.base(stale, base),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphInputFailure.identity,
          ),
        ),
      );
    }
  });
}
