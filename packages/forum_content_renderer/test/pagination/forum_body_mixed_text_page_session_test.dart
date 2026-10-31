import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../inline/test_support/ruby_pair_fixture.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
  fontRevision: 'formal-mixed-ahem',
  linkColor: const Color(0xff0000ff),
  paragraphBefore: 0,
  paragraphAfter: 0,
);

final class _Fixture {
  _Fixture(
    String html, {
    double width = 60,
    double height = 30,
    int entries = 8,
    int text = 100000,
    int runs = 10000,
    TextScaler textScaler = TextScaler.noScaling,
    ForumBodyReaderStyle? reader,
  }) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'formal-mixed-session',
      conversionIdentity: 'none',
    );
    cache = ForumBodyParagraphCache(
      maxEntries: entries,
      maxEstimatedBytes: 1 << 24,
    );
    session = ForumBodyTextPageSession(
      document: document,
      reader: reader ?? _reader,
      cache: cache,
      limits: ForumBodyTextPageSessionLimits(
        maxPages: 1000,
        maxFragments: 10000,
        maxParagraphs: 10000,
        maxTextCodeUnits: text,
        maxRuns: runs,
        maxIssuedLeases: 512,
      ),
      layoutId: 'formal-mixed',
      width: width,
      height: height,
      textScaler: textScaler,
    );
    addTearDown(close);
  }
  late final ForumBodyDocument document;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;
  ForumBodyTextPageSessionStep advance() {
    final builds = cache.layoutBuildCount;
    final step = session.advance(maxEvents: 2, maxLines: 1);
    expect(step.layoutsBuilt, cache.layoutBuildCount - builds);
    expect(step.layoutsBuilt, lessThanOrEqualTo(1));
    expect(step.formatUnitsPrepared, lessThanOrEqualTo(32));
    expect(step.linesInspected, lessThanOrEqualTo(1));
    expect(step.pagesPublished, lessThanOrEqualTo(1));
    expect(step.madeProgress || step.waitingForLayoutBudget, isTrue);
    return step;
  }

  void finish() {
    for (var i = 0; !session.isComplete && i < 10000; i++) {
      expect(advance().waitingForLayoutBudget, isFalse);
    }
    expect(session.isComplete, isTrue);
  }

  List<ForumBodyPreparedTextFragment> prepare(int page) {
    final job = session.openPagePreparation(page);
    try {
      for (var i = 0; !job.isReady && i < 10000; i++) {
        final step = job.advance(maxFragments: 1, maxParts: 1);
        expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
        expect(step.waitingForLayoutBudget, isFalse);
      }
      return job.takeFragments();
    } finally {
      job.close();
    }
  }

  void close() {
    session.close();
    cache.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'actual Session produces mixed pages and complete visible source-bound views',
    () {
      final f = _Fixture('<p>X<ruby>AB<rt>xy</rt></ruby>Y</p>');
      f.finish();
      expect(f.session.snapshot, hasLength(2));
      expect(f.session.retainedParagraphCount, 1);
      expect(f.session.retainedTextCodeUnits, 6);
      expect(f.cache.layoutBuildCount, 2);
      expect(f.cache.pictureBuildCount, 0);
      expect(f.cache.activeLeases, 0);
      final first = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(first.view.atomIndices, [0]);
        expect(first.nativeLeases, hasLength(3));
        expect(f.session.activeIssuedLeases, 3);
        expect(f.cache.pictureBuildCount, 2);
        expect(first.view.sourceAt(const Offset(21, 20)).sourceRune, 1);
        expect(first.view.sourceAt(const Offset(31, 5)).sourceRune, 3);
        expect(first.view.sourceAt(const Offset(31, 5)).isExact, isTrue);
        final last =
            f.session.preparePageFragments(1).single
                as ForumBodyPreparedInlineFragment;
        try {
          expect(last.view.atomIndices, isEmpty);
          expect(last.nativeLeases, hasLength(1));
          expect(last.view.sourceAt(const Offset(1, 5)).sourceRune, 5);
          expect(f.session.activeIssuedLeases, 4);
        } finally {
          last.close();
        }
        expect(() => f.session.preparePageLeases(0), throwsStateError);
        expect(first.isActive, isTrue);
        expect(f.session.activeIssuedLeases, 3);
      } finally {
        first.close();
      }
      expect(f.session.activeIssuedLeases, 0);
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    '120 actual groups shape in bounded bands and record only the requested page',
    () {
      final f = _Fixture(
        '<ruby>${List.generate(120, (i) => '${String.fromCharCode(0x4e00 + i)}<rt>r$i</rt>').join()}</ruby>',
        width: 320,
        height: 60,
        entries: 4,
      );
      f.finish();
      expect(f.cache.layoutBuildCount, 5);
      expect(f.cache.pictureBuildCount, 0);
      expect(f.cache.activeLeases, 0);
      expect(f.session.snapshot.length, greaterThan(1));
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        final visible = prepared.view.atomIndices.length;
        expect(visible, greaterThan(0));
        expect(visible, lessThan(120));
        expect(prepared.nativeLeases.length, 1 + visible * 2);
        expect(f.cache.pictureBuildCount, visible * 2);
        expect(f.cache.layoutBuildCount, 6);
        expect(f.cache.entryCount, lessThanOrEqualTo(4));
      } finally {
        prepared.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'a long actual chapter publishes its first mixed page before traversing the tail',
    () {
      final f = _Fixture(
        List.filled(2000, '<ruby>AB<rt>xy</rt></ruby><br>').join(),
      );
      while (f.session.snapshot.isEmpty) {
        f.advance();
      }
      expect(f.session.isComplete, isFalse);
      expect(f.session.resolvedNodeCount, lessThan(30));
      expect(f.cache.layoutBuildCount, 2);
      expect(f.cache.pictureBuildCount, 0);
      expect(f.cache.activeLeases, 0);
      final prefix = f.session.snapshot;
      expect(prefix, hasLength(1));
      final view = f.prepare(0).single;
      expect(view.isActive, isTrue);
      view.close();
      f.session.close();
      expect(prefix, hasLength(1));
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'base and annotation with different directions use separate native bands',
    () {
      final f = _Fixture(
        '<ruby dir="rtl">A<rt dir="ltr">a</rt></ruby>',
        width: 100,
      );
      f.finish();
      expect(f.cache.layoutBuildCount, 3);
      expect(f.cache.pictureBuildCount, 0);
      final page = f.prepare(0).single;
      expect(page.nativeLeases, hasLength(3));
      page.close();
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'unbatchable native paint uses ordinary glyph requests without another renderer',
    () {
      final f = _Fixture(
        '<ruby>AB<rt>xy</rt></ruby>',
        width: 100,
        reader: ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            height: 1,
            shadows: [Shadow(color: Color(0xff000000))],
          ),
          fontRevision: 'native-shadow',
          linkColor: const Color(0xff0000ff),
        ),
      );
      f.finish();
      expect(f.cache.layoutBuildCount, 3);
      final page = f.prepare(0).single;
      expect(page.nativeLeases, hasLength(3));
      expect(f.cache.pictureBuildCount, 0);
      page.close();
    },
  );

  test('foreign native pins wait and resume the same pending format', () {
    final f = _Fixture('<ruby>AB<rt>xy</rt></ruby>', width: 100, entries: 2);
    final one = f.cache.acquire(
      content: rubyPairInput(base: 'ZZ').base,
      width: 100,
    );
    final two = f.cache.acquire(
      content: rubyPairInput(base: 'WW').base,
      width: 100,
    );
    addTearDown(one.release);
    addTearDown(two.release);
    var waiting = false;
    for (var i = 0; !waiting && i < 100; i++) {
      waiting = f.advance().waitingForLayoutBudget;
    }
    expect(waiting, isTrue);
    expect(f.cache.layoutBuildCount, 2);
    final idle = f.advance();
    expect(idle.waitingForLayoutBudget, isTrue);
    expect(idle.madeProgress, isFalse);
    one.release();
    f.finish();
    expect(two.isActive, isTrue);
    expect(f.cache.activeLeases, 1);
    f.session.close();
    expect(two.isActive, isTrue);
  });

  test(
    'formal mixed BR windows retain numeric plans and prepare an empty tail without pictures',
    () {
      final f = _Fixture(
        '<p><ruby>AB<rt>xy</rt></ruby>Y<br><br></p>',
        width: 100,
      );
      f.finish();
      expect(f.session.snapshot, hasLength(2));
      expect(f.session.retainedParagraphCount, 2);
      expect(f.cache.layoutBuildCount, 2);
      expect(f.cache.pictureBuildCount, 0);
      final page = f.session.snapshot.last.fragments.single;
      expect((page.startLine, page.endLine), (1, 2));
      expect((page.coverageStartUtf16, page.coverageEndUtf16), (6, 6));
      expect(page.sourceHint, isNull);
      final tail =
          f.session.preparePageFragments(1).single
              as ForumBodyPreparedInlineFragment;
      try {
        expect(tail.nativeLeases, hasLength(1));
        expect(tail.view.atomIndices, isEmpty);
        expect(tail.view.sourceAt(const Offset(5, 5)).isExact, isFalse);
        expect(tail.view.selectionBoxes(0, 6), isEmpty);
        expect(f.cache.pictureBuildCount, 0);
      } finally {
        tail.close();
      }
    },
  );

  test(
    'unannotated ruby tails flow as ordinary parent glyphs rather than oversized atoms',
    () {
      final f = _Fixture('<ruby>AB<rt>xy</rt>longunannotatedtail</ruby>');
      f.finish();
      expect(f.session.snapshot.length, greaterThan(2));
      final first = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      expect(first.view.atomIndices, [0]);
      first.close();
      final last =
          f.prepare(f.session.snapshot.length - 1).single
              as ForumBodyPreparedInlineFragment;
      expect(last.view.atomIndices, isEmpty);
      last.close();
    },
  );

  test(
    'ordinary outer collapsed edges trim through explicit source windows',
    () {
      final f = _Fixture(
        '<p> X <ruby>AB<rt>xy</rt></ruby> Y </p>',
        width: 200,
        height: 100,
      );
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(prepared.view.content.projection.display.text, 'X ABxy Y');
        expect(prepared.view.sourceAt(const Offset(1, 20)).sourceRune, 1);
        expect(
          prepared.view.content.contexts.first.content.projection
              .sourceAtUtf16(0)
              .sourceRune,
          1,
        );
      } finally {
        prepared.close();
      }
    },
  );

  test(
    'annotation line edges trim without moving surviving source or glyphs',
    () {
      final f = _Fixture(
        '<p>X<ruby>AB<rt> \t<span>a\u0301😀</span> \t</rt></ruby>Y</p>',
        width: 200,
        height: 100,
      );
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(prepared.view.content.projection.display.text, 'XABa\u0301😀Y');
        expect(prepared.view.content.projection.engineText, 'X\uFFFCY');
        final leases = prepared.nativeLeases.toList();
        final parent = leases.first as ForumBodyInlineParagraphLease;
        final base = leases[1] as ForumBodyTextLease;
        final rt = leases[2] as ForumBodyTextLease;
        expect(rt.content.projection.text, 'a\u0301😀');
        expect(rt.content.projection.sourceAtUtf16(0).sourceRune, 5);
        expect(rt.content.projection.sourceAtUtf16(2).sourceRune, 7);
        final metrics = ForumBodyRubyGroupMetrics.measure(
          cache: f.cache,
          baseLease: base,
          annotation: rt.content,
          annotationLease: rt,
          maxWidth: 200,
        );
        // Query an interior grapheme; the trimmed join also has the preceding
        // base's upstream source and must keep its existing affinity rules.
        final box = rt.layout.selectionBoxes(2, 4).first.toRect();
        final hit = prepared.view.sourceAt(
          parent.layout.atomBoxes.single.toRect().topLeft +
              metrics.annotationOffset +
              Offset(box.left + .1, (box.top + box.bottom) / 2),
        );
        expect(hit.isExact, isTrue);
        expect(hit.sourceRune, 7);
      } finally {
        prepared.close();
      }
      expect(f.session.activeIssuedLeases, 0);
      expect(f.cache.activeLeases, 0);
    },
  );

  for (final (annotation, display) in [
    (' xy ', 'xy'),
    ('<span style="white-space:pre-line"> xy </span>', 'xy'),
    ('&nbsp;xy&nbsp;', '\u00a0xy\u00a0'),
    ('<span style="white-space:pre"> xy </span>', ' xy '),
  ]) {
    test('annotation whitespace follows its own run style: $annotation', () {
      final f = _Fixture(
        '<ruby>AB<rt>$annotation</rt></ruby>',
        width: 200,
        height: 100,
      );
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        final rt = prepared.nativeLeases.last as ForumBodyTextLease;
        expect(rt.content.projection.text, display);
        expect(prepared.view.content.projection.display.text, 'AB$display');
      } finally {
        prepared.close();
      }
      expect(f.cache.activeLeases, 0);
    });
  }

  test('whitespace-only collapsed annotation leaves no empty upper line', () {
    final f = _Fixture('<ruby>AB<rt> \t </rt></ruby>', height: 100);
    f.finish();
    final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      expect(prepared.view.content.projection.display.text, 'AB');
      expect(prepared.nativeLeases, hasLength(2));
      expect(prepared.view.height, 20);
      expect(f.cache.pictureBuildCount, 1);
    } finally {
      prepared.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  test('annotation trimming never cuts a space joined to a combining mark', () {
    final f = _Fixture('<ruby>AB<rt> \u0301a</rt></ruby>');
    expect(f.finish, throwsA(isA<ForumBodyParagraphInputException>()));
    expect(f.session.snapshot, isEmpty);
    expect(f.cache.layoutBuildCount, 0);
    expect(f.cache.activeLeases, 0);
  });

  for (final (baseText, suffix, display, engine) in [
    ('AB ', '', 'ABxy', '\uFFFC'),
    ('AB ', 'Y', 'ABxy Y', '\uFFFC Y'),
    ('AB ', ' Y', 'ABxy Y', '\uFFFC Y'),
    (' AB ', ' Y', 'ABxy Y', '\uFFFC Y'),
    ('AB ', '<span> </span>', 'ABxy', '\uFFFC'),
    (
      'AB ',
      '<span style="white-space:pre-wrap"> Y</span>',
      'ABxy  Y',
      '\uFFFC  Y',
    ),
    ('AB ', '&nbsp;Y', 'ABxy \u00a0Y', '\uFFFC \u00a0Y'),
  ]) {
    test(
      'base trailing space uses source-bound parent text: $baseText/$suffix',
      () {
        final f = _Fixture(
          '<p><ruby>$baseText<rt>xy</rt></ruby>$suffix</p>',
          width: 200,
          height: 100,
        );
        f.finish();
        final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        try {
          expect(prepared.view.content.projection.display.text, display);
          expect(prepared.view.content.projection.engineText, engine);
          final base = prepared.nativeLeases.elementAt(1) as ForumBodyTextLease;
          expect(base.content.projection.text, 'AB');
          expect(base.layout.width, 40);
          expect(
            base.content.projection.sourceAtUtf16(1).sourceRune,
            baseText.indexOf('B'),
          );
          if (suffix.isEmpty && baseText == 'AB ') {
            expect(f.session.snapshot.single.fragments.single.sourceHint, (
              runeStart: 0,
              runeEnd: 5,
            ));
          }
        } finally {
          prepared.close();
        }
        expect(f.cache.activeLeases, 0);
        expect(f.session.activeIssuedLeases, 0);
      },
    );
  }

  test('extracted trailing space allows an actual native break after ruby', () {
    final f = _Fixture('<p><ruby>AB <rt>xy</rt></ruby>Y</p>', height: 100);
    f.finish();
    final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      final parent =
          prepared.nativeLeases.first as ForumBodyInlineParagraphLease;
      expect(parent.layout.lines, hasLength(2));
      expect(parent.layout.lines.last.left, 0);
      expect(parent.layout.atomBoxes.single.right, 40);
      final leases = prepared.nativeLeases.toList();
      final base = leases[1] as ForumBodyTextLease;
      final rt = leases[2] as ForumBodyTextLease;
      final metrics = ForumBodyRubyGroupMetrics.measure(
        cache: f.cache,
        baseLease: base,
        annotation: rt.content,
        annotationLease: rt,
        maxWidth: 60,
      );
      final box = rt.layout.selectionBoxes(1, 2).single.toRect();
      final hit = prepared.view.sourceAt(
        parent.layout.atomBoxes.single.toRect().topLeft +
            metrics.annotationOffset +
            Offset(box.left + .1, (box.top + box.bottom) / 2),
      );
      expect(hit.isExact, isTrue);
      expect(hit.sourceRune, 4);
    } finally {
      prepared.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  test(
    'base trailing and next leading edges collapse between native atoms',
    () {
      final f = _Fixture(
        '<p><ruby>AB <rt>xy</rt> CD<rt>z</rt></ruby></p>',
        width: 200,
        height: 100,
      );
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(prepared.view.content.projection.display.text, 'ABxy CDz');
        expect(prepared.view.content.projection.engineText, '\uFFFC \uFFFC');
        expect(prepared.view.atomIndices, [0, 1]);
      } finally {
        prepared.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test('real BR trims an extracted trailing space before the separator', () {
    final f = _Fixture(
      '<p><ruby>AB <rt>xy</rt></ruby><br>Y</p>',
      width: 200,
      height: 100,
    );
    f.finish();
    final fragments = f.prepare(0);
    try {
      final mixed = fragments
          .whereType<ForumBodyPreparedInlineFragment>()
          .first;
      expect(mixed.view.content.projection.display.text, 'ABxy\n');
      expect(mixed.view.content.projection.engineText, '\uFFFC\n');
    } finally {
      for (final fragment in fragments) {
        fragment.close();
      }
    }
    expect(f.cache.activeLeases, 0);
  });

  test('preserved literal newline resets the base-level leading edge', () {
    final f = _Fixture(
      '<p><span style="white-space:pre-wrap">X\n</span>'
      '<ruby> AB <rt>xy</rt></ruby>Y</p>',
      width: 200,
      height: 100,
    );
    f.finish();
    final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      expect(prepared.view.content.projection.display.text, 'X\nABxy Y');
      expect(prepared.view.content.projection.engineText, 'X\n\uFFFC Y');
    } finally {
      prepared.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  for (final (prefix, display, source) in [
    ('', 'ABxy', 1),
    ('X', 'X ABxy', 2),
    ('X ', 'X ABxy', 3),
  ]) {
    test('base leading whitespace belongs to its ordinary parent: $prefix', () {
      final f = _Fixture(
        '<p>$prefix<ruby> AB<rt>xy</rt></ruby></p>',
        width: 200,
        height: 100,
      );
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(prepared.view.content.projection.display.text, display);
        final leases = prepared.nativeLeases.toList();
        final base = leases[1] as ForumBodyTextLease;
        expect(base.content.projection.text, 'AB');
        expect(base.layout.width, 40);
        expect(base.content.projection.sourceAtUtf16(0).sourceRune, source);
        final parent = leases.first as ForumBodyInlineParagraphLease;
        expect(
          parent.layout.atomBoxes.single.right -
              parent.layout.atomBoxes.single.left,
          40,
        );
      } finally {
        prepared.close();
      }
      expect(f.cache.activeLeases, 0);
      expect(f.session.activeIssuedLeases, 0);
    });
  }

  test('extracted leading space trims at the actual native line edge', () {
    final f = _Fixture('<p>X<ruby> AB<rt>xy</rt></ruby></p>', height: 100);
    f.finish();
    final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      final parent =
          prepared.nativeLeases.first as ForumBodyInlineParagraphLease;
      expect(parent.layout.lines, hasLength(2));
      expect(parent.layout.atomBoxes.single.left, 0);
      expect(prepared.view.content.projection.engineText, 'X \uFFFC');
      final base = prepared.nativeLeases.elementAt(1) as ForumBodyTextLease;
      final rt = prepared.nativeLeases.elementAt(2) as ForumBodyTextLease;
      final metrics = ForumBodyRubyGroupMetrics.measure(
        cache: f.cache,
        baseLease: base,
        annotation: rt.content,
        annotationLease: rt,
        maxWidth: 60,
      );
      final box = base.layout.selectionBoxes(1, 2).single.toRect();
      final hit = prepared.view.sourceAt(
        parent.layout.atomBoxes.single.toRect().topLeft +
            metrics.baseOffset +
            Offset(box.left + .1, (box.top + box.bottom) / 2),
      );
      expect(hit.isExact, isTrue);
      expect(hit.sourceRune, 3);
    } finally {
      prepared.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  test(
    'base leading space folds against an unannotated ordinary ruby tail',
    () {
      final f = _Fixture(
        '<p><ruby>AB<rt>xy</rt>T </ruby><ruby> CD<rt>z</rt></ruby></p>',
        width: 200,
        height: 100,
      );
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(prepared.view.content.projection.display.text, 'ABxyT CDz');
        expect(prepared.view.content.projection.engineText, '\uFFFCT \uFFFC');
        expect(prepared.view.atomIndices, [0, 1]);
      } finally {
        prepared.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test('extracting a styled leading space preserves both run owners', () {
    final f = _Fixture(
      '<p>X<ruby><span style="color:red"> </span>'
      '<span style="color:green">AB</span><rt>xy</rt></ruby></p>',
      width: 200,
      height: 100,
    );
    f.finish();
    final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      final content = prepared.view.content;
      expect(content.projection.display.text, 'X ABxy');
      expect(content.runs, hasLength(4));
      final space = content.projection.display.parts.singleWhere(
        (part) => part.utf16Start == 1,
      );
      expect(
        content.runs[space.runIndex].style.textStyle.color,
        const Color(0xffff0000),
      );
      final base = prepared.nativeLeases.elementAt(1) as ForumBodyTextLease;
      expect(base.content.projection.text, 'AB');
      final baseRun = base.content.projection.parts.single.runIndex;
      expect(
        base.content.runs[baseRun].style.textStyle.color,
        const Color(0xff008000),
      );
    } finally {
      prepared.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  for (final (prefix, display) in [
    ('<span style="white-space:pre-wrap">X </span>', 'X  ABxy'),
    ('X&nbsp;', 'X\u00a0 ABxy'),
  ]) {
    test(
      'base space does not collapse preserved preceding whitespace: $prefix',
      () {
        final f = _Fixture(
          '<p>$prefix<ruby> AB<rt>xy</rt></ruby></p>',
          width: 200,
          height: 100,
        );
        f.finish();
        final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        try {
          expect(prepared.view.content.projection.display.text, display);
        } finally {
          prepared.close();
        }
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  test('a real BR resets the base leading edge without moving source', () {
    final f = _Fixture(
      '<p>X<br> <ruby> AB<rt>xy</rt></ruby></p>',
      width: 200,
      height: 100,
    );
    f.finish();
    final fragments = f.prepare(0);
    try {
      final mixed = fragments
          .whereType<ForumBodyPreparedInlineFragment>()
          .single;
      expect(mixed.view.content.projection.display.text, 'ABxy');
      expect(mixed.view.content.projection.engineText, '\uFFFC');
      final base = mixed.nativeLeases.elementAt(1) as ForumBodyTextLease;
      expect(base.content.projection.sourceAtUtf16(0).sourceRune, 4);
    } finally {
      for (final fragment in fragments) {
        fragment.close();
      }
    }
    expect(f.cache.activeLeases, 0);
  });

  test('a leading base space joined to a combining mark is not cut', () {
    final f = _Fixture('<ruby> \u0301AB<rt>xy</rt></ruby>');
    expect(f.finish, throwsA(isA<ForumBodyParagraphInputException>()));
    expect(f.cache.layoutBuildCount, 0);
    expect(f.session.snapshot, isEmpty);
  });

  for (final base in [
    '&nbsp;AB',
    '<span style="white-space:pre"> AB </span>',
  ]) {
    test('literal/preformatted base edges retain author whitespace: $base', () {
      final f = _Fixture(
        '<ruby>$base<rt>xy</rt></ruby>',
        width: 200,
        height: 100,
      );
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      expect(prepared.view.content.projection.display.text, contains('AB'));
      expect(prepared.view.atomIndices, [0]);
      prepared.close();
    });
  }

  for (final html in [
    '<ruby> <rt>a</rt></ruby>',
    '<ruby>A<rt>a</rt><rt>b</rt></ruby>',
    '<ruby><rt>orphan</rt></ruby>',
    '<ruby>A<ruby>B<rt>b</rt></ruby><rt>a</rt></ruby>',
  ]) {
    test('pending complex format never flattens or loses source: $html', () {
      final f = _Fixture(html);
      expect(f.finish, throwsA(isA<ForumBodyParagraphInputException>()));
      expect(f.session.state, ForumBodyTextPageSessionState.failed);
      expect(f.session.snapshot, isEmpty);
      expect(f.cache.layoutBuildCount, 0);
      expect(f.cache.activeLeases, 0);
    });
  }

  for (final (text, runs, failure) in [
    (1, 100, ForumBodyTextPageSessionFailure.textLimit),
    (100, 1, ForumBodyTextPageSessionFailure.runLimit),
  ]) {
    test('pure retained $failure is enforced before glyph shaping', () {
      final f = _Fixture('<ruby>AB<rt>xy</rt></ruby>', text: text, runs: runs);
      expect(
        f.finish,
        throwsA(
          isA<ForumBodyTextPageSessionException>().having(
            (e) => e.failure,
            'failure',
            failure,
          ),
        ),
      );
      expect(f.cache.layoutBuildCount, 0);
      expect(f.cache.activeLeases, 0);
    });
  }

  test(
    'retiring the generation inside a native scaler cannot publish or leak the plan',
    () {
      late _Fixture f;
      f = _Fixture(
        '<ruby>AB<rt>xy</rt></ruby>',
        textScaler: _Scaler((size) {
          f.session.close();
          return size;
        }),
      );
      expect(f.finish, throwsStateError);
      expect(f.session.state, ForumBodyTextPageSessionState.closed);
      expect(f.session.snapshot, isEmpty);
      expect(f.cache.activeLeases, 0);
      expect(f.cache.isClosed, isFalse);
    },
  );

  test('late unsupported input preserves the already published mixed prefix', () {
    final f = _Fixture(
      '<span>X<ruby>AB<rt>xy</rt></ruby>Y<br>Z<br><ruby>A<rt>a</rt><rt>b</rt></ruby></span>',
    );
    while (f.session.snapshot.isEmpty) {
      f.advance();
    }
    final prefix = f.session.snapshot;
    final page = prefix.first;
    expect(f.finish, throwsA(isA<ForumBodyParagraphInputException>()));
    expect(f.session.snapshot.first, same(page));
    expect(prefix, hasLength(1));
    final visible = f.prepare(0);
    expect(visible.single.isActive, isTrue);
    visible.single.close();
    expect(f.cache.activeLeases, 0);
  });
}

final class _Scaler extends TextScaler {
  const _Scaler(this.callback);
  final double Function(double) callback;
  @override
  double scale(double size) => callback(size);
  @override
  double get textScaleFactor => 1;
}
