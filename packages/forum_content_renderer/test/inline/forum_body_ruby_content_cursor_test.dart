import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(
    fontSize: 20,
    height: 1,
    fontFamily: 'Ahem',
    color: Color(0xff000000),
  ),
  fontRevision: 'ahem',
  linkColor: const Color(0xff0000ff),
);

({ForumBodyStyledFlowCursor flow, ForumBodyRubyContentCursor cursor}) open(
  String html, {
  ForumBodyRubyContentLimits limits = const ForumBodyRubyContentLimits(),
  ForumBodyParagraphContentBuilder builder =
      const ForumBodyParagraphContentBuilder(),
  ForumBodyReaderStyle? reader,
}) {
  final doc = const ForumBodyParser().parse(
    html: html,
    sourceId: 'ruby-content',
    conversionIdentity: 'none',
  );
  final flow = ForumBodyStyledFlowCursor(
    document: doc,
    reader: reader ?? _reader,
  );
  while (flow.moveNext()) {
    final event = flow.current!;
    if (event.phase == ForumBodyFlowPhase.open &&
        event.node is ForumBodyElement &&
        (event.node as ForumBodyElement).kind == ForumBodyElementKind.ruby) {
      final cursor = ForumBodyRubyContentCursor.openCurrent(
        flow,
        paragraphBuilder: builder,
        limits: limits,
      );
      addTearDown(cursor.close);
      addTearDown(flow.close);
      return (flow: flow, cursor: cursor);
    }
    flow.takePendingIssues();
  }
  flow.close();
  throw StateError('Fixture has no ruby');
}

List<ForumBodyRubyGroupContent> drain(
  ForumBodyRubyContentCursor cursor, {
  int budget = 1,
}) {
  final groups = <ForumBodyRubyGroupContent>[];
  for (var i = 0; i < 5000; i++) {
    final step = cursor.advance(maxEvents: budget);
    expect(step.workDone, lessThanOrEqualTo(budget));
    expect(step.eventsRead, lessThanOrEqualTo(step.workDone));
    if (step.hasOutput) groups.add(cursor.current!);
    if (step.isComplete) return groups;
  }
  throw StateError('Ruby cursor did not complete');
}

List<ForumBodyParagraphContent> texts(List<ForumBodyRubyInlineContent> parts) =>
    parts
        .whereType<ForumBodyRubyTextContent>()
        .map((part) => part.content)
        .toList();
String text(List<ForumBodyRubyInlineContent> parts) =>
    texts(parts).map((part) => part.projection.text).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'ruby base retains reader body inputs while inline geometry excludes block indentation',
    () {
      final run = open(
        '<ruby>AB<rt>abc</rt></ruby>',
        reader: ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontSize: 20,
            height: 1,
            fontFamily: 'Ahem',
          ),
          fontRevision: 'ahem',
          linkColor: const Color(0xff0000ff),
          firstLineIndent: const ForumBodyLength(2, ForumBodyLengthUnit.em),
        ),
      );
      final group = drain(run.cursor).single;
      final base = texts(group.base).single;
      final annotation = texts(group.annotations.single.parts).single;
      expect(base.style.role, ForumBodyTextRole.body);
      expect(base.style.indent.value, 2);
      expect(base.style.indent.unit, ForumBodyLengthUnit.em);
      expect(annotation.style.role, ForumBodyTextRole.ruby);
      expect(annotation.style.textStyle.fontSize, 10);
      expect(annotation.style.indent.value, 0);
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final layout = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: base,
        annotation: annotation,
      );
      expect(layout.size, const Size(40, 30));
      expect(
        layout
            .selectionBoxes(
              part: ForumBodyRubyPart.base,
              startUtf16: 0,
              endUtf16: 1,
            )
            .single
            .left,
        0,
      );
      layout.close();
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'real IR groups alternate base and annotation with original styles and coordinates',
    () {
      final run = open(
        '<p>前<ruby><b>漢</b><rt style="font-size:10px;color:red">かん</rt>字<rt>じ</rt></ruby>後</p>',
      );
      final groups = drain(run.cursor);
      expect(groups, hasLength(2));
      expect(groups.map((group) => text(group.base)), ['漢', '字']);
      expect(groups.map((group) => text(group.annotations.single.parts)), [
        'かん',
        'じ',
      ]);
      expect(texts(groups.first.base).single.runs.single.style.strong, isTrue);
      final annotation = texts(groups.first.annotations.single.parts).single;
      expect(annotation.style.textStyle.fontSize, 10);
      expect(
        annotation.runs.single.style.textStyle.color,
        const Color(0xffff0000),
      );
      expect(
        texts(groups.first.base).single.projection.sourceAtUtf16(0).sourceRune,
        1,
      );
      expect(annotation.projection.sourceAtUtf16(0).sourceRune, 2);
      expect(
        texts(groups.last.base).single.projection.sourceAtUtf16(0).sourceRune,
        4,
      );
      expect(groups.map((group) => group.index), [0, 1]);
      expect(groups.first.fontRevision, 'ahem');
      expect(groups.first.styleRevision, ForumBodyStyleResolver.revision);
      expect(groups.first.style, same(run.cursor.rootStyle));
      expect(run.flow.current!.phase, ForumBodyFlowPhase.close);
      expect(run.flow.current!.node.path, groups.first.rootPath);
      expect(
        run.flow.moveNext(),
        isTrue,
      ); // Caller still owns following content.
      expect(run.flow.current!.node, isA<ForumBodyText>());
      expect((run.flow.current!.node as ForumBodyText).text, '後');
      expect(run.cursor.advance(maxEvents: 1).isComplete, isTrue);
    },
  );

  test(
    'hidden siblings do not terminate annotation mode or create a space base',
    () {
      final run = open(
        '<ruby>A<rt>a</rt> <span hidden>hidden</span> <rt>b</rt> </ruby>',
      );
      final groups = drain(run.cursor);
      expect(groups, hasLength(1));
      expect(text(groups.single.base), 'A');
      expect(groups.single.annotations.map((rt) => text(rt.parts)), ['a', 'b']);
      expect(
        run.cursor.takeIgnored().map((item) => item.reason),
        containsAll([
          ForumBodyRubyIgnoredReason.hidden,
          ForumBodyRubyIgnoredReason.annotationWhitespace,
        ]),
      );
    },
  );

  test(
    'hard breaks count as raw text and runs before any layout admission',
    () {
      final run = open('<ruby><br><rt>a</rt><br><rt>b</rt></ruby>');
      final groups = drain(run.cursor);
      expect(groups.map((group) => text(group.base)), ['\n', '\n']);
      expect(run.cursor.inputCodeUnits, 4);
      expect(run.cursor.textRunCount, 4);
      final bounded = open(
        '<ruby><br><rt></rt></ruby>',
        limits: const ForumBodyRubyContentLimits(maxTextRuns: 0),
      );
      expect(
        () => drain(bounded.cursor),
        throwsA(
          isA<ForumBodyRubyContentException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyRubyContentFailure.runLimit,
          ),
        ),
      );
      expect(bounded.cursor.isClosed, isTrue);
    },
  );

  test('multiple RTs share their base without becoming ordinary body text', () {
    final run = open(
      '<ruby>漢字<rt>かんじ</rt><rt lang="en">characters</rt></ruby>',
    );
    final groups = drain(run.cursor);
    expect(groups, hasLength(1));
    expect(text(groups.single.base), '漢字');
    expect(
      groups.single.annotations.map((annotation) => text(annotation.parts)),
      ['かんじ', 'characters'],
    );
    expect(groups.single.base.length, 1);
    expect(run.cursor.inputCodeUnits, 15);
    expect(run.cursor.textRunCount, 3);
    expect(() => groups.single.annotations.clear(), throwsUnsupportedError);
  });

  test(
    'fallback and inter-annotation whitespace remain explicit ignored source ranges',
    () {
      final run = open(
        '<ruby>漢<rp>(</rp> \n<rt>kan</rt> \t<rp>)</rp> <rt>han</rt>  </ruby>',
      );
      final groups = drain(run.cursor);
      expect(text(groups.single.base), '漢');
      expect(
        groups.single.annotations.map((annotation) => text(annotation.parts)),
        ['kan', 'han'],
      );
      final ignored = run.cursor.takeIgnored();
      expect(
        ignored.where(
          (value) => value.reason == ForumBodyRubyIgnoredReason.fallback,
        ),
        hasLength(2),
      );
      expect(
        ignored.where(
          (value) =>
              value.reason == ForumBodyRubyIgnoredReason.annotationWhitespace,
        ),
        hasLength(4),
      );
      expect(
        ignored.every((value) => value.source.runeEnd > value.source.runeStart),
        isTrue,
      );
      expect(run.cursor.takeIgnored(), isEmpty);
      expect(
        run.cursor.inputCodeUnits,
        16,
      ); // Includes ignored text and parentheses.
    },
  );

  test(
    'spaces followed by a new base are carried into that base rather than ignored',
    () {
      final run = open('<ruby>A<rt>a</rt> \tB<rt>b</rt></ruby>');
      final groups = drain(run.cursor);
      expect(groups.map((group) => text(group.base)), ['A', ' B']);
      expect(run.cursor.takeIgnored(), isEmpty);
      expect(
        texts(groups.last.base).single.projection.sourceAtUtf16(0).sourceRune,
        2,
      );
      expect(
        texts(groups.last.base).single.projection.sourceAtUtf16(1).sourceRune,
        4,
      );
    },
  );

  test(
    'nested ruby remains structured in base and annotation, including edge whitespace',
    () {
      final run = open(
        '<ruby>前 <ruby>漢<rt>かん</rt>字<rt>じ</rt></ruby> 後<rt>outer <ruby>X<rt>x</rt></ruby> tail</rt></ruby>',
      );
      final groups = drain(run.cursor);
      final base = groups.single.base;
      expect(base, hasLength(3));
      expect(
        (base.first as ForumBodyRubyTextContent).content.projection.text,
        '前 ',
      );
      expect(
        (base.last as ForumBodyRubyTextContent).content.projection.text,
        ' 後',
      );
      final nested = base[1] as ForumBodyRubyNestedContent;
      expect(nested.groups.map((group) => text(group.base)), ['漢', '字']);
      final annotation = groups.single.annotations.single.parts;
      expect(annotation, hasLength(3));
      expect(
        (annotation.first as ForumBodyRubyTextContent).content.projection.text,
        'outer ',
      );
      expect(
        (annotation.last as ForumBodyRubyTextContent).content.projection.text,
        ' tail',
      );
      expect(
        (annotation[1] as ForumBodyRubyNestedContent)
            .groups
            .single
            .annotations
            .single
            .parts,
        hasLength(1),
      );
      expect(run.cursor.groupCount, 4);
      expect(() => nested.groups.clear(), throwsUnsupportedError);
    },
  );

  test(
    'empty, orphan and unannotated trailing segments are represented without invented text',
    () {
      final run = open('<ruby><rt>orphan</rt>A<rt></rt>B</ruby>');
      final groups = drain(run.cursor);
      expect(groups, hasLength(3));
      expect(groups.first.base, isEmpty);
      expect(text(groups.first.annotations.single.parts), 'orphan');
      expect(text(groups[1].base), 'A');
      expect(text(groups[1].annotations.single.parts), '');
      expect(groups[1].annotations.single.parts, hasLength(1));
      expect(text(groups.last.base), 'B');
      expect(groups.last.annotations, isEmpty);
      final empty = open('<ruby></ruby>');
      expect(drain(empty.cursor), isEmpty);
    },
  );

  test(
    'hidden subtrees retain provenance and charge input without leaking visible text',
    () {
      final run = open(
        '<ruby><span style="display:none">秘密</span>A<rt style="display:none">hidden</rt>B<rt>b</rt></ruby>',
      );
      final groups = drain(run.cursor);
      expect(groups.map((group) => text(group.base)), ['A', 'B']);
      expect(groups.first.annotations, isEmpty);
      expect(
        run.cursor.takeIgnored().where(
          (value) => value.reason == ForumBodyRubyIgnoredReason.hidden,
        ),
        hasLength(2),
      );
      expect(run.cursor.inputCodeUnits, 11);
      final root = open('<ruby style="display:none">hidden<rt>rt</rt></ruby>');
      expect(drain(root.cursor), isEmpty);
      expect(root.cursor.inputCodeUnits, 8);
      expect(
        root.cursor.takeIgnored().single.reason,
        ForumBodyRubyIgnoredReason.hidden,
      );
    },
  );

  test(
    'sibling whitespace cannot bypass a one-event work budget during deferred replay',
    () {
      final run = open(
        '<ruby>A<rt>a</rt> <!--1--> <!--2--> <!--3--> B<rt>b</rt></ruby>',
      );
      var sawReplay = false;
      final groups = <ForumBodyRubyGroupContent>[];
      while (!run.cursor.isComplete) {
        final step = run.cursor.advance(maxEvents: 1);
        expect(step.workDone, 1);
        expect(step.eventsRead, inInclusiveRange(0, 1));
        sawReplay |= step.eventsRead == 0;
        if (step.hasOutput) groups.add(run.cursor.current!);
      }
      expect(sawReplay, isTrue);
      expect(groups.map((group) => text(group.base)), ['A', ' B']);
    },
  );

  for (final (limits, failure, html) in [
    (
      const ForumBodyRubyContentLimits(maxInputCodeUnits: 3),
      ForumBodyRubyContentFailure.inputLimit,
      '<ruby>A<rp>long</rp><rt>a</rt></ruby>',
    ),
    (
      const ForumBodyRubyContentLimits(maxTextRuns: 1),
      ForumBodyRubyContentFailure.runLimit,
      '<ruby>A<rt>a</rt></ruby>',
    ),
    (
      const ForumBodyRubyContentLimits(maxGroups: 1),
      ForumBodyRubyContentFailure.groupLimit,
      '<ruby>A<rt>a</rt>B<rt>b</rt></ruby>',
    ),
    (
      const ForumBodyRubyContentLimits(maxGroups: 1),
      ForumBodyRubyContentFailure.groupLimit,
      '<ruby><ruby>A<rt>a</rt></ruby><rt>outer</rt></ruby>',
    ),
    (
      const ForumBodyRubyContentLimits(maxDepth: 1),
      ForumBodyRubyContentFailure.depthLimit,
      '<ruby><ruby>A<rt>a</rt></ruby><rt>outer</rt></ruby>',
    ),
  ]) {
    test(
      'bounded ruby rejects $failure while leaving the borrowed flow caller-owned',
      () {
        final run = open(html, limits: limits);
        expect(
          () => drain(run.cursor),
          throwsA(
            isA<ForumBodyRubyContentException>().having(
              (error) => error.failure,
              'failure',
              failure,
            ),
          ),
        );
        expect(run.cursor.isClosed, isTrue);
        expect(run.flow.isClosed, isFalse);
        expect(run.cursor.current, isNull);
      },
    );
  }

  test(
    'foreign flow advancement and cancellation cannot publish a partial group',
    () {
      final run = open('<ruby>A<rt>a</rt></ruby>');
      run.cursor.advance(maxEvents: 1);
      run.flow.moveNext();
      expect(
        () => run.cursor.advance(maxEvents: 1),
        throwsA(isA<ForumBodyRubyContentException>()),
      );
      expect(run.cursor.current, isNull);
      final canceled = open('<ruby>A<rt>a</rt></ruby>');
      canceled.cursor.advance(maxEvents: 1);
      canceled.cursor.close();
      canceled.cursor.close();
      expect(canceled.flow.isClosed, isFalse);
      expect(() => canceled.cursor.advance(maxEvents: 1), throwsStateError);
    },
  );

  test(
    'empty annotation and fallback metadata also have a bounded structural budget',
    () {
      for (final html in [
        '<ruby>A<rt></rt><rt></rt><rt></rt></ruby>',
        '<ruby><rp></rp><rp></rp><rp></rp><rp></rp></ruby>',
        '<ruby><ruby>A<rt>a</rt></ruby><rt>outer</rt></ruby>',
      ]) {
        final run = open(
          html,
          limits: const ForumBodyRubyContentLimits(maxStructureItems: 3),
        );
        expect(
          () => drain(run.cursor),
          throwsA(
            isA<ForumBodyRubyContentException>().having(
              (error) => error.failure,
              'failure',
              ForumBodyRubyContentFailure.structureLimit,
            ),
          ),
        );
        expect(run.cursor.isClosed, isTrue);
        expect(run.flow.isClosed, isFalse);
      }
    },
  );

  test('a published group remains immutable when a later input fails', () {
    final run = open('<ruby>A<rt>a</rt>B<img src="x"><rt>b</rt></ruby>');
    ForumBodyRubyGroupContent? first;
    while (first == null) {
      final step = run.cursor.advance(maxEvents: 1);
      if (step.hasOutput) first = run.cursor.current!;
    }
    expect(text(first.base), 'A');
    expect(
      () => drain(run.cursor),
      throwsA(isA<ForumBodyParagraphInputException>()),
    );
    expect(text(first.base), 'A');
    expect(text(first.annotations.single.parts), 'a');
    expect(() => first!.base.clear(), throwsUnsupportedError);
  });

  test(
    'batch size changes scheduling without changing nested groups or source data',
    () {
      const html =
          '<ruby>A <ruby>漢<rp>(</rp><rt>かん</rt><rp>)</rp></ruby> B<rt>outer</rt><rt>second</rt> C<rt>c</rt></ruby>';
      Object describeParts(List<ForumBodyRubyInlineContent> parts) => [
        for (final part in parts)
          if (part is ForumBodyRubyTextContent)
            [
              part.content.path,
              part.content.projection.text,
              part.content.projection.sourceAtUtf16(0).sourceRune,
              part.content.projection
                  .sourceAtUtf16(part.content.projection.text.length)
                  .sourceRune,
            ]
          else if (part is ForumBodyRubyNestedContent)
            [
              part.path,
              for (final group in part.groups)
                [
                  describeParts(group.base),
                  for (final annotation in group.annotations)
                    describeParts(annotation.parts),
                ],
            ],
      ];
      final values = <Object>[];
      for (final budget in [1, 3, 128]) {
        final run = open(html);
        final groups = drain(run.cursor, budget: budget);
        values.add([
          for (final group in groups)
            [
              group.rootPath,
              group.index,
              describeParts(group.base),
              for (final annotation in group.annotations)
                [annotation.path, describeParts(annotation.parts)],
            ],
          [
            run.cursor.inputCodeUnits,
            run.cursor.textRunCount,
            run.cursor.groupCount,
            run.cursor.structureItemCount,
          ],
          [
            for (final ignored in run.cursor.takeIgnored())
              [
                ignored.path,
                ignored.reason,
                ignored.source.runeStart,
                ignored.source.runeEnd,
              ],
          ],
        ]);
      }
      expect(values[1], values[0]);
      expect(values[2], values[0]);
    },
  );

  test(
    'resources are not flattened and style diagnostics stay with the flow owner',
    () {
      final broken = open('<ruby>A<img src="x"><rt>a</rt></ruby>');
      expect(
        () => drain(broken.cursor),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
      expect(broken.cursor.isClosed, isTrue);
      final styled = open(
        '<ruby>A<rt style="unsupported-test:yes">a</rt></ruby>',
      );
      drain(styled.cursor);
      expect(
        styled.flow.takePendingIssues().any(
          (issue) => issue.property == 'unsupported-test',
        ),
        isTrue,
      );
    },
  );

  test(
    'a real IR pair feeds native ruby geometry without reparsing or inventing source',
    () {
      final run = open('<ruby>漢字<rt style="font-size:10px">かんじ</rt></ruby>');
      final group = drain(run.cursor).single;
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final layout = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: texts(group.base).single,
        annotation: texts(group.annotations.single.parts).single,
      );
      expect(layout.size.width, greaterThan(0));
      expect(layout.projectionFor(ForumBodyRubyPart.base).text, '漢字');
      expect(
        layout
            .projectionFor(ForumBodyRubyPart.annotation)
            .sourceAtUtf16(0)
            .sourceRune,
        2,
      );
      expect(cache.layoutBuildCount, 2);
      layout.close();
      expect(cache.activeLeases, 0);
    },
  );
}
