import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
  fontRevision: 'mixed-flow-ahem',
  linkColor: const Color(0xff0000ff),
);

ForumBodyDocument _document(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'mixed-flow',
  conversionIdentity: 'none',
);

ForumBodyTextFlowCursor _cursor(
  String html, {
  ForumBodyParagraphContentBuilder builder =
      const ForumBodyParagraphContentBuilder(),
  ForumBodyRubyContentLimits limits = const ForumBodyRubyContentLimits(),
}) {
  final cursor = ForumBodyTextFlowCursor(
    document: _document(html),
    reader: _reader,
    paragraphBuilder: builder,
    rubyLimits: limits,
  );
  addTearDown(cursor.close);
  return cursor;
}

List<ForumBodyTextFlowUnit> _drain(
  ForumBodyTextFlowCursor cursor, {
  int budget = 1,
}) {
  final units = <ForumBodyTextFlowUnit>[];
  for (var i = 0; i < 20000; i++) {
    final step = cursor.advance(maxEvents: budget);
    expect(step.eventsRead, lessThanOrEqualTo(step.workDone));
    expect(step.workDone, lessThanOrEqualTo(budget));
    expect(step.workDone > 0 || step.hasOutput || step.isComplete, isTrue);
    if (step.hasOutput) units.add(cursor.current!);
    if (step.isComplete) return units;
  }
  fail('Mixed flow did not finish');
}

String _text(List<ForumBodyRubyInlineContent> parts) => parts
    .whereType<ForumBodyRubyTextContent>()
    .map((part) => part.content.projection.text)
    .join();

String _signature(ForumBodyInlineFlowContent input) => input.parts
    .map(
      (part) => switch (part) {
        ForumBodyInlineFlowText() => 'text:${part.content.projection.text}',
        ForumBodyInlineFlowRuby() =>
          'ruby:${_text(part.group.base)}:${part.group.annotations.map((rt) => _text(rt.parts)).join("/")}',
      },
    )
    .join('|');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prefix, ruby groups and suffix remain one source-bound context', () {
    final cursor = _cursor(
      '<p>前 <b>粗</b> <ruby>漢<rt>かん</rt>字<rt>じ</rt></ruby> 后</p>',
    );
    final units = _drain(cursor);
    expect(units.whereType<ForumBodyTextFlowParagraph>(), isEmpty);
    final unit = units.whereType<ForumBodyTextFlowInline>().single;
    expect(unit.index, 0);
    expect(unit.window, ForumBodyParagraphWindow.full);
    expect(unit.content.path, '0');
    expect(_signature(unit.content), 'text:前 粗 |ruby:漢:かん|ruby:字:じ|text: 后');
    final prefix =
        (unit.content.parts.first as ForumBodyInlineFlowText).content;
    expect(prefix.runs[1].style.textStyle.fontWeight, FontWeight.bold);
    final first = (unit.content.parts[1] as ForumBodyInlineFlowRuby).group;
    final base = (first.base.single as ForumBodyRubyTextContent).content;
    final rt =
        (first.annotations.single.parts.single as ForumBodyRubyTextContent)
            .content;
    expect(base.projection.sourceAtUtf16(0).sourceRune, 4);
    expect(rt.projection.sourceAtUtf16(0).sourceRune, 5);
    expect(base.style.role, ForumBodyTextRole.body);
    expect(rt.style.role, ForumBodyTextRole.ruby);
    expect(rt.style.textStyle.fontSize, 10);
    expect(unit.content.identity, cursor.identity);
    expect(unit.content.fontRevision, cursor.fontRevision);
    expect(unit.content.styleRevision, cursor.styleRevision);
    expect(() => unit.content.parts.clear(), throwsUnsupportedError);
    cursor.close();
    expect(_signature(unit.content), startsWith('text:前 粗 |ruby:漢:かん'));
  });

  test('multiple, nested and orphan annotations keep their actual grammar', () {
    final unit = _drain(
      _cursor(
        '前<ruby>漢<ruby>字<rt>ji</rt></ruby><rt>kan<ruby>音<rt>on</rt></ruby></rt><rt>second</rt></ruby>'
        '<ruby><rt>orphan</rt></ruby>后',
      ),
    ).whereType<ForumBodyTextFlowInline>().single;
    final rubies = unit.content.parts
        .whereType<ForumBodyInlineFlowRuby>()
        .toList();
    expect(rubies, hasLength(2));
    expect(rubies.first.group.base[1], isA<ForumBodyRubyNestedContent>());
    expect(rubies.first.group.annotations, hasLength(2));
    expect(
      rubies.first.group.annotations.first.parts[1],
      isA<ForumBodyRubyNestedContent>(),
    );
    expect(rubies.last.group.base, isEmpty);
    expect(_text(rubies.last.group.annotations.single.parts), 'orphan');
    expect(rubies.first.group.rootPath, isNot(rubies.last.group.rootPath));
  });

  test(
    'RP, hidden and annotation whitespace are omissions with source only',
    () {
      final input = _drain(
        _cursor(
          '前<ruby>漢<rp>(</rp> <rt>kan</rt> <span hidden>private</span>'
          '<rp>)</rp> </ruby>后',
        ),
      ).whereType<ForumBodyTextFlowInline>().single.content;
      expect(_signature(input), 'text:前|ruby:漢:kan|text:后');
      expect(
        input.ignored.map((item) => item.reason),
        containsAll([
          ForumBodyRubyIgnoredReason.fallback,
          ForumBodyRubyIgnoredReason.hidden,
          ForumBodyRubyIgnoredReason.annotationWhitespace,
        ]),
      );
      expect(
        input.ignored.every(
          (item) => item.source.runeEnd > item.source.runeStart,
        ),
        isTrue,
      );
      expect(() => input.ignored.clear(), throwsUnsupportedError);
    },
  );

  test(
    'mixed and ordinary BR windows share one monotonically indexed stream',
    () {
      final units = _drain(
        _cursor('<span>plain<br>前<ruby>A<rt>a</rt></ruby>后<br><br></span>'),
      );
      final ordinary = units.whereType<ForumBodyTextFlowParagraph>().single;
      final mixed = units.whereType<ForumBodyTextFlowInline>().toList();
      expect(ordinary.index, 0);
      expect(ordinary.content.projection.text, 'plain\n');
      expect(mixed.map((unit) => unit.index), [1, 2]);
      expect(mixed.map((unit) => unit.window), [
        ForumBodyParagraphWindow.beforeTerminalEmptyLine,
        ForumBodyParagraphWindow.terminalEmptyLine,
      ]);
      expect(mixed[1].content, same(mixed[0].content));
      expect(_signature(mixed.first.content), 'text:前|ruby:A:a|text:后\n');
    },
  );

  test(
    'trimmed terminal BR keeps its own provenance after a mixed context',
    () {
      final units = _drain(_cursor('<p><ruby>A<rt>a</rt></ruby><br> \t </p>'));
      final mixed = units.whereType<ForumBodyTextFlowInline>().single;
      expect(mixed.window, ForumBodyParagraphWindow.full);
      expect(_signature(mixed.content), 'ruby:A:a|text: ');
      final boundary = units.whereType<ForumBodyTextFlowBoundary>().firstWhere(
        (unit) => unit.kind == ForumBodyTextFlowBoundaryKind.closeBlock,
      );
      expect(boundary.trimmedTerminalBreak!.node.path, '0/1');
      expect(boundary.trimmedTerminalBreak!.node.source.runeStart, 2);
    },
  );

  test('ruby replay consumes a bounded work unit even without a new event', () {
    const html = '<ruby>A<rt>a</rt> <b>B</b><rt>b</rt></ruby>';
    final cursor = _cursor(html);
    var replaySteps = 0;
    for (var i = 0; !cursor.isComplete && i < 1000; i++) {
      final step = cursor.advance(maxEvents: 1);
      expect(step.workDone, lessThanOrEqualTo(1));
      if (step.eventsRead == 0 && step.workDone == 1 && !step.hasOutput) {
        replaySteps++;
      }
    }
    expect(cursor.isComplete, isTrue);
    expect(replaySteps, greaterThan(0));
    final signatures = [
      for (final budget in [1, 2, 1000])
        _signature(
          _drain(
            _cursor(html),
            budget: budget,
          ).whereType<ForumBodyTextFlowInline>().single.content,
        ),
    ];
    expect(signatures.toSet(), hasLength(1));
  });

  test('a mixed prefix is delivered before resolving a long chapter tail', () {
    final cursor = _cursor(
      List.generate(2000, (index) => '前<ruby>字<rt>zi</rt></ruby>后<br>').join(),
    );
    while (cursor.current is! ForumBodyTextFlowInline) {
      final step = cursor.advance(maxEvents: 1);
      expect(step.workDone, lessThanOrEqualTo(1));
    }
    final first = cursor.current as ForumBodyTextFlowInline;
    expect(first.window, ForumBodyParagraphWindow.beforeTerminalEmptyLine);
    expect(_signature(first.content), 'text:前|ruby:字:zi|text:后\n');
    expect(cursor.resolvedNodeCount, lessThan(20));
    expect(cursor.isComplete, isFalse);
    cursor.close();
    expect(_signature(first.content), 'text:前|ruby:字:zi|text:后\n');
  });

  test('style diagnostics inside ruby drain once with the current source', () {
    final cursor = _cursor(
      '前<ruby style="filter:blur(1px)">字<rt style="float:left">zi</rt></ruby>后',
    );
    final diagnostics = <ForumBodyStyleIssue>[];
    ForumBodyInlineFlowContent? input;
    while (!cursor.isComplete) {
      cursor.advance(maxEvents: 1);
      diagnostics.addAll(cursor.takePendingIssues());
      if (cursor.current case ForumBodyTextFlowInline(:final content)) {
        input = content;
      }
    }
    expect(diagnostics.map((issue) => issue.property), ['filter', 'float']);
    expect(diagnostics.map((issue) => issue.path), ['1', '1/1']);
    expect(input!.issues.map((issue) => issue.property), ['filter', 'float']);
    expect(cursor.takePendingIssues(), isEmpty);
    expect(() => input!.issues.clear(), throwsUnsupportedError);
  });

  test('a late aggregate limit failure leaves earlier mixed output intact', () {
    final cursor = _cursor(
      '前<ruby>A<rt>a</rt></ruby><br>后<br>'
      '<ruby>BB<rt>bb</rt></ruby><ruby>CC<rt>cc</rt></ruby>',
      builder: const ForumBodyParagraphContentBuilder(maxInputCodeUnits: 7),
    );
    while (cursor.current is! ForumBodyTextFlowInline) {
      cursor.advance(maxEvents: 1);
    }
    final first = (cursor.current as ForumBodyTextFlowInline).content;
    final signature = _signature(first);
    expect(
      () => _drain(cursor),
      throwsA(isA<ForumBodyParagraphInputException>()),
    );
    expect(cursor.isClosed, isTrue);
    expect(_signature(first), signature);
  });

  for (final (builder, failure) in [
    (
      const ForumBodyParagraphContentBuilder(maxInputCodeUnits: 7),
      ForumBodyParagraphInputFailure.inputLimit,
    ),
    (
      const ForumBodyParagraphContentBuilder(maxRuns: 3),
      ForumBodyParagraphInputFailure.runLimit,
    ),
  ]) {
    test('ordinary and repeated ruby roots share the $failure budget', () {
      final cursor = _cursor(
        '前<ruby>AA<rt>aa</rt></ruby><ruby>BB<rt>bb</rt></ruby>后',
        builder: builder,
      );
      expect(
        () => _drain(cursor),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (e) => e.failure,
            'failure',
            failure,
          ),
        ),
      );
      expect(cursor.isClosed, isTrue);
      expect(cursor.current, isNull);
    });
  }

  for (final (limits, failure) in [
    (
      const ForumBodyRubyContentLimits(maxGroups: 1),
      ForumBodyRubyContentFailure.groupLimit,
    ),
    (
      const ForumBodyRubyContentLimits(maxStructureItems: 5),
      ForumBodyRubyContentFailure.structureLimit,
    ),
  ]) {
    test('separate roots cannot bypass the paragraph $failure budget', () {
      final cursor = _cursor(
        'x<ruby>A<rt>a</rt></ruby><ruby>B<rt>b</rt></ruby>',
        limits: limits,
      );
      expect(
        () => _drain(cursor),
        throwsA(
          isA<ForumBodyRubyContentException>().having(
            (e) => e.failure,
            'failure',
            failure,
          ),
        ),
      );
      expect(cursor.isClosed, isTrue);
    });
  }

  for (final builder in [
    const ForumBodyParagraphContentBuilder(maxInputCodeUnits: 1),
    const ForumBodyParagraphContentBuilder(maxRuns: 1),
  ]) {
    test(
      'hard breaks across ruby roots cannot bypass the aggregate budget: ${builder.maxRuns}/${builder.maxInputCodeUnits}',
      () {
        final cursor = _cursor(
          '<ruby><br><rt></rt></ruby><ruby><br><rt></rt></ruby>',
          builder: builder,
        );
        expect(
          () => _drain(cursor),
          throwsA(isA<ForumBodyParagraphInputException>()),
        );
        expect(cursor.isClosed, isTrue);
      },
    );
  }

  test(
    'close while borrowing ruby retires unpublished text and diagnostics',
    () {
      final cursor = _cursor(
        'prefix<ruby style="filter:blur(1px)">A<rt>a</rt></ruby>tail',
      );
      cursor.advance(maxEvents: 2);
      expect(cursor.current, isNull);
      expect(cursor.takePendingIssues().single.property, 'filter');
      cursor.close();
      cursor.close();
      expect(cursor.current, isNull);
      expect(() => cursor.advance(maxEvents: 1), throwsStateError);
      expect(cursor.takePendingIssues, throwsStateError);
    },
  );

  test('block flow preserves mixed width, margins and zero-read work limits', () {
    final cursor = ForumBodyBlockFlowCursor(
      document: _document(
        '<div style="padding:5px;margin:3px">前<ruby>A<rt>a</rt> <b>B</b><rt>b</rt></ruby>后</div>',
      ),
      reader: _reader,
      width: 200,
    );
    addTearDown(cursor.close);
    final units = <ForumBodyBlockFlowUnit>[];
    var replays = 0;
    for (var i = 0; !cursor.isComplete && i < 1000; i++) {
      final step = cursor.advance(maxEvents: 1);
      expect(step.eventsRead, lessThanOrEqualTo(step.workDone));
      expect(step.workDone, lessThanOrEqualTo(1));
      if (step.eventsRead == 0 && step.workDone == 1) replays++;
      if (step.hasOutput) units.add(cursor.current!);
    }
    final mixed = units.whereType<ForumBodyBlockFlowInline>().single;
    expect(mixed.contentLeft, 8);
    expect(mixed.contentWidth, 184);
    expect(replays, greaterThan(0));
    expect(units.whereType<ForumBodyBlockFlowParagraph>(), isEmpty);
    expect(
      units.whereType<ForumBodyBlockFlowSpace>().map((unit) => unit.kind),
      [
        ForumBodyBlockSpaceKind.paddingTop,
        ForumBodyBlockSpaceKind.paddingBottom,
      ],
    );
  });

  test(
    'resolved base whitespace retains bounded replay progress through shaping',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final session = ForumBodyTextPageSession(
        document: _document('前<ruby>A<rt>a</rt> <b>B</b><rt>b</rt></ruby>后'),
        reader: _reader,
        cache: cache,
        limits: const ForumBodyTextPageSessionLimits(
          maxPages: 100,
          maxFragments: 100,
          maxParagraphs: 100,
          maxTextCodeUnits: 10000,
          maxRuns: 1000,
          maxIssuedLeases: 32,
        ),
        layoutId: 'unmeasured-format',
        width: 200,
        height: 100,
      );
      addTearDown(session.close);
      var replaySteps = 0;
      for (var i = 0; !session.isComplete && i < 1000; i++) {
        final step = session.advance(maxEvents: 1, maxLines: 1);
        expect(step.flowWorkDone, lessThanOrEqualTo(1));
        expect(step.layoutsBuilt, lessThanOrEqualTo(1));
        if (step.eventsRead == 0 && step.flowWorkDone == 1) {
          expect(step.madeProgress, isTrue);
          replaySteps++;
        }
      }
      expect(replaySteps, greaterThan(0));
      expect(session.state, ForumBodyTextPageSessionState.complete);
      expect(cache.pictureBuildCount, 0);
      final preparation = session.openPagePreparation(0);
      addTearDown(preparation.close);
      for (var i = 0; !preparation.isReady && i < 1000; i++) {
        final step = preparation.advance(maxFragments: 1, maxParts: 1);
        expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
      }
      expect(preparation.isReady, isTrue);
      final fragments = preparation.takeFragments();
      try {
        final mixed = fragments.single as ForumBodyPreparedInlineFragment;
        expect(mixed.view.content.projection.display.text, '前Aa Bb后');
        expect(mixed.view.atomIndices, [0, 1]);
      } finally {
        for (final fragment in fragments) {
          fragment.close();
        }
      }
      expect(cache.activeLeases, 0);
    },
  );
}
