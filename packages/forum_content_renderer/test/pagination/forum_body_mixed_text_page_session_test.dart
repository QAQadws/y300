import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
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

// Exact native totals include the root's temporary empty font strut. It is
// released before child metrics and never adds a visible handle or picture.
// An identical anonymous base reuses that strut instead of shaping it twice.

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
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });

  for (final scale in [TextScaler.noScaling, const _ScriptCurve()]) {
    test(
      'HTML sup/sub use actual native baselines, colors and local copy: $scale',
      () {
        final f = _Fixture(
          '<p>A<sup style="font-size:12px;color:red"><b>2</b></sup>'
          'B<sub style="font-size:14px">3</sub>C</p>',
          width: 200,
          height: 100,
          textScaler: scale,
        );
        f.finish();
        expect(f.session.snapshot, hasLength(1));
        final fragments = f.prepare(0);
        try {
          final binding = fragments.single as ForumBodyPreparedInlineFragment;
          final base = binding.lines.single.baseline;
          expect(binding.projection.text, 'A2B3C');
          for (final (text, shift) in [
            ('2', scale.scale(20) * .4),
            ('3', -scale.scale(20) * .2),
          ]) {
            final context = binding.view.content.contexts.singleWhere(
              (c) => c.content.projection.text == text,
            );
            final actual = binding
                .glyphBoxes(context.startUtf16, context.endUtf16)
                .single;
            final native = f.cache.acquire(
              content: context.content,
              width: 200,
              textScaler: scale,
            );
            try {
              final raw = native.layout.selectionBoxes(0, 1).single;
              final baseline =
                  native.layout.alphabeticBaseline + actual.top - raw.top;
              expect(baseline, closeTo(base - shift, 1e-3));
            } finally {
              native.release();
            }
            final point = Offset(
              actual.left + (actual.right - actual.left) * .25,
              (actual.top + actual.bottom) * .5,
            );
            final copy = forumBodyTextSelectionAt(
              binding: binding,
              fragment: f.session.snapshot.single.fragments.single,
              pageSize: const Size(200, 100),
              point: point,
            )!;
            expect(copy.text, text);
            expect(copy.isAnnotation, isFalse);
            expect(copy.position.sourceRune, text == '2' ? 1 : 3);
            final part = context.content.projection.parts.single;
            final style = context.content.runs[part.runIndex].style;
            expect(style.textStyle.fontFamily, 'Ahem');
            if (text == '2') {
              expect(style.textStyle.color, const Color(0xffff0000));
              expect(style.textStyle.fontWeight, FontWeight.w700);
            }
          }
        } finally {
          for (final fragment in fragments) {
            fragment.close();
          }
        }
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  test('script hard breaks remain parent rows with code whitespace intact', () {
    for (final separator in ['\n', '\r\n', '\u2028']) {
      final f = _Fixture(
        '<pre>before<sup>A${separator}B</sup>after</pre>',
        width: 250,
        height: 100,
      );
      f.finish();
      final fragments = f.prepare(0);
      try {
        final b = fragments.single as ForumBodyPreparedInlineFragment;
        expect(b.projection.text, f.document.sourceText);
        final a = b.projection.text.indexOf('A'),
            next = b.projection.text.indexOf('B');
        expect(
          b.glyphBoxes(a, a + 1).single.top,
          lessThan(b.glyphBoxes(next, next + 1).single.top),
        );
      } finally {
        for (final f in fragments) {
          f.close();
        }
      }
    }
  });

  test(
    'HTML scripts retain original text and source through multi-page composition',
    () {
      final f = _Fixture(
        List.generate(
          25,
          (i) => '<p>段$i<sup>$i</sup>正文<sub>n</sub>。</p>',
        ).join(),
        width: 100,
        height: 50,
      );
      f.finish();
      expect(f.session.snapshot.length, greaterThan(3));
      final display = StringBuffer();
      final scriptSources = <int>{};
      for (var page = 0; page < f.session.snapshot.length; page++) {
        final fragments = f.prepare(page);
        try {
          for (final (i, binding) in fragments.indexed) {
            final meta = f.session.snapshot[page].fragments[i];
            display.write(
              binding.projection.text.substring(
                meta.coverageStartUtf16,
                meta.coverageEndUtf16,
              ),
            );
            if (binding is ForumBodyPreparedInlineFragment) {
              for (final context in binding.view.content.contexts) {
                if (!context.content.style.baselineShift.isEmpty &&
                    context.content.projection.text.isNotEmpty &&
                    context.startUtf16 >= meta.coverageStartUtf16 &&
                    context.endUtf16 <= meta.coverageEndUtf16) {
                  final box = binding
                      .glyphBoxes(context.startUtf16, context.startUtf16 + 1)
                      .first;
                  expect(box.top, greaterThanOrEqualTo(-1e-3));
                  expect(box.bottom, lessThanOrEqualTo(meta.height + 1e-3));
                  final hit = binding.view.sourceAt(
                    Offset(
                      box.left + (box.right - box.left) * .25,
                      (box.top + box.bottom) * .5,
                    ),
                  );
                  expect(hit.isExact, isTrue);
                  scriptSources.add(hit.sourceRune);
                }
              }
            }
          }
        } finally {
          for (final fragment in fragments) {
            fragment.close();
          }
        }
      }
      expect(display.toString(), f.document.sourceText);
      expect(scriptSources, hasLength(50));
    },
  );

  test(
    'baseline text stays independent beside single-layer ruby with soft gaps',
    () {
      final f = _Fixture(
        '<p><sup>2</sup><ruby><rb>A</rb> <rb>B</rb>'
        '<rtc><rt>x</rt> <rt>y</rt></rtc></ruby><sub>n</sub></p>',
        width: 100,
        height: 100,
      );
      f.finish();
      for (var page = 0; page < f.session.snapshot.length; page++) {
        final fragments = f.prepare(page);
        for (final binding in fragments) {
          expect(binding.isActive, isTrue);
          binding.close();
        }
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  for (final direction in ['ltr', 'rtl']) {
    test(
      'full-width ruby reduces reader indent without changing actual page binding $direction',
      () {
        final options = ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            height: 1,
          ),
          fontRevision: 'reader-fit',
          linkColor: const Color(0xff0000ff),
          paragraphAfter: 0,
          firstLineIndent: const ForumBodyLength(4, ForumBodyLengthUnit.em),
        );
        final f = _Fixture(
          '<p dir="$direction"><ruby>AB<rt>xy</rt></ruby> '
          '<ruby>C<rt>z</rt></ruby><br><ruby>D<rt>u</rt></ruby></p>',
          width: 40,
          height: 30,
          reader: options,
        );
        f.finish();
        final seen = <String>[];
        var sawReduced = false;
        var sawContinuation = false;
        for (var page = 0; page < f.session.snapshot.length; page++) {
          final fragments = f.prepare(page);
          try {
            validateForumBodyPreparedTextPageBinding(
              snapshot: f.session.snapshot,
              pageIndex: page,
              layoutId: 'formal-mixed',
              fragments: fragments,
            );
            for (final prepared
                in fragments.cast<ForumBodyPreparedInlineFragment>()) {
              final parent =
                  prepared.nativeLeases.first as ForumBodyInlineParagraphLease;
              if (prepared.view.content.appliesFirstLineIndent) {
                expect(parent.layout.projection.enginePrefix.length, 2);
                expect(parent.layout.firstLineIndent.requestedAdvance, 80);
                expect(parent.layout.firstLineIndent.appliedAdvance, 0);
                sawReduced = true;
              } else {
                expect(parent.layout.projection.enginePrefix, isEmpty);
                sawContinuation = true;
              }
              for (final letter in ['A', 'B', 'C', 'D']) {
                final start = prepared.projection.text.indexOf(letter);
                if (start >= 0 &&
                    prepared.glyphBoxes(start, start + 1).isNotEmpty) {
                  seen.add(letter);
                }
              }
            }
          } finally {
            for (final fragment in fragments) {
              fragment.close();
            }
          }
          expect(f.cache.activeLeases, 0);
        }
        expect(seen, ['A', 'B', 'C', 'D']);
        expect(sawReduced && sawContinuation, isTrue);
        expect(options.firstLineIndent.value, 4);
      },
    );
    test(
      'indented raw ruby gaps prepare every real page and BR continuation $direction',
      () {
        final f = _Fixture(
          '<p dir="$direction" style="text-indent:20px">'
          '<ruby>A<rt>x</rt></ruby> <ruby>B<rt>y</rt></ruby> '
          '<ruby>C<rt>z</rt></ruby><br><ruby>D<rt>u</rt></ruby> '
          '<ruby>E<rt>v</rt></ruby> <ruby>F<rt>w</rt></ruby></p>',
          width: 60,
          height: 30,
        );
        f.finish();
        final seen = <String>[];
        var continuedAfterBr = false;
        for (var page = 0; page < f.session.snapshot.length; page++) {
          final fragments = f.prepare(page);
          try {
            validateForumBodyPreparedTextPageBinding(
              snapshot: f.session.snapshot,
              pageIndex: page,
              layoutId: 'formal-mixed',
              fragments: fragments,
            );
            for (final prepared
                in fragments.cast<ForumBodyPreparedInlineFragment>()) {
              final parent =
                  prepared.nativeLeases.first as ForumBodyInlineParagraphLease;
              final ownsIndent = prepared.view.content.appliesFirstLineIndent;
              expect(
                parent.layout.projection.enginePrefix.length,
                ownsIndent ? 2 : 0,
              );
              if (!ownsIndent) continuedAfterBr = true;
              for (final letter in ['A', 'B', 'C', 'D', 'E', 'F']) {
                final offset = prepared.projection.text.indexOf(letter);
                if (offset < 0) continue;
                final boxes = prepared.glyphBoxes(offset, offset + 1);
                if (boxes.isEmpty) continue;
                seen.add(letter);
                final box = boxes.single;
                if (letter == 'A') {
                  final actual = direction == 'ltr' ? box.left : 60 - box.right;
                  expect(actual, closeTo(20, .001));
                } else if (letter == 'D') {
                  // A neutral opaque row's leading edge is a row property,
                  // not the visual position of one logical child in bidi.
                  expect(parent.layout.lines.first.left, closeTo(0, .001));
                  expect(parent.layout.lines.first.width, closeTo(60, .001));
                }
                final hit = prepared.view.sourceAt(
                  Offset(box.left + .1, (box.top + box.bottom) / 2),
                );
                expect(hit.isExact, isTrue);
                expect(
                  hit.sourceRune,
                  prepared.projection.sourceAtUtf16(offset).sourceRune,
                );
              }
            }
          } finally {
            for (final fragment in fragments) {
              fragment.close();
            }
          }
          expect(f.cache.activeLeases, 0);
          expect(f.session.activeIssuedLeases, 0);
        }
        expect(seen, ['A', 'B', 'C', 'D', 'E', 'F']);
        expect(continuedAfterBr, isTrue);
      },
    );
  }

  for (final (direction, position) in [
    ('ltr', 'alternate'),
    ('rtl', 'alternate under'),
    ('ltr', 'over'),
    ('rtl', 'under'),
  ]) {
    test(
      'raw mixed RT/RTC keeps real baselines and sources: $direction/$position',
      () {
        final f = _Fixture(
          '<p dir="$direction"><ruby style="ruby-position:$position"><rb style="font-size:30px">A</rb><rb>B</rb><rt>xx</rt><rt>yy</rt><rtc><rt style="font-size:15px">uu</rt><rt style="font-size:8px">vv</rt></rtc><rt>zz</rt><rt>ww</rt></ruby></p>',
          width: 200,
          height: 100,
        );
        f.finish();
        expect(f.cache.pictureBuildCount, 0);
        final builds = f.cache.layoutBuildCount;
        final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        try {
          expect(fragment.projection.text, 'AxxuuzzByyvvww');
          final leases = fragment.nativeLeases
              .skip(1)
              .cast<ForumBodyTextLease>()
              .toList();
          expect(leases.map((lease) => lease.content.projection.text), [
            'A',
            'xx',
            'uu',
            'zz',
            'B',
            'yy',
            'vv',
            'ww',
          ]);
          final starts = [0, 1, 3, 5, 7, 8, 10, 12];
          final boxes = [
            for (var i = 0; i < starts.length; i++)
              fragment.glyphBoxes(starts[i], starts[i] + 1).single,
          ];
          double baseline(int i) =>
              boxes[i].top -
              leases[i].layout.selectionBoxes(0, 1).single.top +
              leases[i].layout.alphabeticBaseline;
          for (var rank = 0; rank < 4; rank++) {
            expect(baseline(rank), closeTo(baseline(rank + 4), 1e-4));
          }
          final sides = [
            position == 'under' || position == 'alternate under',
            position == 'under' || position == 'alternate',
            position == 'under' || position == 'alternate under',
          ];
          for (var rank = 0; rank < 3; rank++) {
            expect(
              sides[rank]
                  ? boxes[rank + 1].top >= boxes[0].bottom
                  : boxes[rank + 1].bottom <= boxes[0].top,
              isTrue,
            );
            final start = starts[rank + 1] + 1;
            final box = fragment.glyphBoxes(start, start + 1).single;
            final hit = fragment.view.sourceAt(
              Offset(box.left + .1, (box.top + box.bottom) / 2),
            );
            expect(hit.isExact, isTrue);
            expect(
              hit.sourceRune,
              leases[rank + 1].content.projection.sourceAtUtf16(1).sourceRune,
            );
          }
          if (position == 'over') {
            expect(boxes[2].bottom, lessThanOrEqualTo(boxes[1].top));
            expect(boxes[3].bottom, lessThanOrEqualTo(boxes[2].top));
          }
          if (position == 'under') {
            expect(boxes[2].top, greaterThanOrEqualTo(boxes[1].bottom));
            expect(boxes[3].top, greaterThanOrEqualTo(boxes[2].bottom));
          }
          expect(f.cache.layoutBuildCount, builds);
        } finally {
          fragment.close();
        }
        expect(f.cache.activeLeases, 0);
        expect(f.session.activeIssuedLeases, 0);
      },
    );
  }

  test('raw multi-level wrapping keeps independent physical rows', () {
    final f = _Fixture(
      '<ruby><rb style="font-size:30px">A</rb><rb>B</rb><rtc><rt>xx</rt><rt>yy</rt></rtc><rtc><rt>uu</rt></rtc></ruby>',
      width: 30,
      height: 50,
    );
    f.finish();
    expect(f.session.snapshot, hasLength(2));
    final heights = <double>[];
    for (var page = 0; page < 2; page++) {
      final fragment =
          f.prepare(page).single as ForumBodyPreparedInlineFragment;
      try {
        heights.add(fragment.view.height);
        expect(fragment.view.atomIndices, [page]);
        expect(fragment.nativeLeases.length, page == 0 ? 4 : 3);
      } finally {
        fragment.close();
      }
    }
    expect(heights, [50, 30]);
    expect(f.cache.activeLeases, 0);
  });

  test(
    'raw 100 RTC levels use bounded preparation and current source identity',
    () {
      final f = _Fixture(
        '<ruby><rb style="font-size:30px">A</rb><rb>B</rb>${List.generate(100, (i) => '<rtc><rt style="font-size:1px">x$i</rt><rt style="font-size:2px">y$i</rt></rtc>').join()}</ruby>',
        width: 100,
        height: 400,
      );
      f.finish();
      expect(f.session.snapshot, hasLength(1));
      expect(f.cache.pictureBuildCount, 0);
      final builds = f.cache.layoutBuildCount;
      final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(fragment.nativeLeases.length, 203);
        expect(f.cache.pictureBuildCount, 202);
        final last = fragment.projection.text.lastIndexOf('y99');
        final box = fragment.glyphBoxes(last + 1, last + 2).single;
        final hit = fragment.view.sourceAt(
          Offset(box.left + .01, (box.top + box.bottom) / 2),
        );
        expect(hit.isExact, isTrue);
        expect(hit.sourceRune, 580);
        expect(f.cache.layoutBuildCount, builds);
      } finally {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
      expect(f.session.activeIssuedLeases, 0);
      f.close();
      expect(f.cache.estimatedRetainedBytes, 0);
    },
  );

  for (final (html, display, handles) in [
    ('<ruby>A<rtc>word</rtc></ruby>', 'Aword', 3),
    ('<ruby><rtc>word</rtc></ruby>', 'word', 3),
    ('<ruby>A<rtc> </rtc></ruby>', 'A', 2),
    ('<ruby>A<rtc>word<b>bold</b></rtc></ruby>', 'Awordbold', 3),
    ('<ruby>A<rtc>pre<rt>xx</rt>post</rtc></ruby>', 'Aprexxpost', 7),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc>pre<rt>xx</rt></rtc></ruby>',
      'ApreBxx',
      5,
    ),
    ('<ruby>A<rt>xx</rt><rtc>word</rtc><rt>zz</rt></ruby>', 'Axxwordzz', 5),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc><rt></rt><rt>yy</rt></rtc><rtc><rt>uu</rt></rtc></ruby>',
      'AuuByy',
      5,
    ),
    (
      '<ruby><rt>xx</rt><rt>yy</rt><rtc><rt>uu</rt><rt>vv</rt></rtc></ruby>',
      'xxuuyyvv',
      7,
    ),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc><rt>xx</rt></rtc><rtc><rt>uu</rt><rt>vv</rt><rt>ww</rt></rtc></ruby>',
      'AxxuuBvvww',
      8,
    ),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc></rtc><rtc><rt>xx</rt><rt>yy</rt></rtc></ruby>',
      'AxxByy',
      5,
    ),
    ('<ruby>A<rt>x<br>y</rt><rtc><rt>u<br>v</rt></rtc></ruby>', 'Ax yu v', 4),
    (
      '<ruby> A <rtc><rt>xx</rt></rtc><rtc><rt>uu</rt><rt>vv</rt></rtc></ruby>Z',
      'Axxuuvv Z',
      6,
    ),
  ]) {
    test('raw sparse/missing/break levels preserve native slots: $html', () {
      final f = _Fixture(html, width: 300, height: 100);
      f.finish();
      final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(fragment.projection.text, display);
        expect(fragment.nativeLeases.length, handles);
        for (final context in fragment.view.content.contexts) {
          if (context.content.projection.text.isEmpty) continue;
          final boxes = fragment.glyphBoxes(
            context.startUtf16,
            context.endUtf16,
          );
          expect(boxes, isNotEmpty);
          for (final box in boxes) {
            expect(box.top, greaterThanOrEqualTo(-1e-4));
            expect(box.bottom, lessThanOrEqualTo(fragment.view.height + 1e-4));
          }
        }
      } finally {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
      expect(f.session.activeIssuedLeases, 0);
    });
  }

  test(
    '100 actual anonymous RTC levels retain styles and complete native ownership',
    () {
      final f = _Fixture(
        '<ruby>A${List.generate(100, (i) => '<rtc style="font-size:1px">r$i</rtc>').join()}</ruby>',
        width: 100,
        height: 200,
      );
      f.finish();
      final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(fragment.nativeLeases.length, 102);
        expect(f.cache.pictureBuildCount, 101);
        final last = fragment.projection.text.lastIndexOf('r99');
        final box = fragment.glyphBoxes(last + 1, last + 2).single;
        final hit = fragment.view.sourceAt(
          Offset(box.left + .01, (box.top + box.bottom) / 2),
        );
        expect(hit.isExact, isTrue);
        expect(hit.sourceRune, 289);
        expect(fragment.runs.last.style.textStyle.fontSize, 1);
      } finally {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
      expect(f.session.activeIssuedLeases, 0);
      f.close();
      expect(f.cache.estimatedRetainedBytes, 0);
    },
  );

  test('canceling raw dense level planning releases all current glyph work', () {
    final f = _Fixture(
      '<ruby>A${List.generate(100, (i) => '<rtc><rt>x$i</rt></rtc>').join()}</ruby>',
      width: 100,
      height: 2000,
    );
    while (f.cache.layoutBuildCount < 1) {
      f.advance();
    }
    expect(f.session.snapshot, isEmpty);
    f.close();
    expect(f.session.state, ForumBodyTextPageSessionState.closed);
    expect(f.cache.activeLeases, 0);
    expect(f.cache.estimatedRetainedBytes, 0);
  });

  for (final (rootStyle, rtcStyle, rtStyle, under) in [
    ('ruby-position:under', '', '', true),
    ('', 'ruby-position:under', '', true),
    ('ruby-position:alternate under', '', '', true),
    ('ruby-position:under', 'ruby-position:initial', '', false),
    ('', '', 'ruby-position:under', false),
  ]) {
    test(
      'annotation position belongs to the actual level ($rootStyle/$rtcStyle/$rtStyle)',
      () {
        final f = _Fixture(
          '<ruby style="$rootStyle">A<rtc style="$rtcStyle"><rt style="$rtStyle">xx</rt></rtc></ruby>',
          width: 100,
          height: 60,
        );
        f.finish();
        final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        try {
          final base = fragment.glyphBoxes(0, 1).single;
          final rt = fragment.glyphBoxes(1, 3).single;
          expect(under ? rt.top >= base.bottom : rt.bottom <= base.top, isTrue);
          final glyph = fragment.glyphBoxes(2, 3).single;
          final hit = fragment.view.sourceAt(
            Offset(glyph.left + .1, (glyph.top + glyph.bottom) / 2),
          );
          expect(hit.sourceRune, 2);
          expect(hit.isExact, isTrue);
        } finally {
          fragment.close();
        }
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  test('over and under RTC segments do not share annotation-row extents', () {
    final f = _Fixture(
      '<ruby><rb style="font-size:30px">A</rb><rtc style="ruby-position:under"><rt>xx</rt></rtc><rb>B</rb><rtc style="ruby-position:over"><rt>yy</rt></rtc></ruby>',
      width: 200,
      height: 100,
      entries: 2,
    );
    f.finish();
    final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      expect(
        fragment.glyphBoxes(1, 3).single.top,
        greaterThanOrEqualTo(fragment.glyphBoxes(0, 1).single.bottom),
      );
      expect(
        fragment.glyphBoxes(4, 6).single.bottom,
        lessThanOrEqualTo(fragment.glyphBoxes(3, 4).single.top),
      );
    } finally {
      fragment.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  for (final (html, expected, source, exact) in [
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc><rt>x</rt><rt>y</rt></rtc></ruby>',
      'AxBy',
      3,
      false,
    ),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc> \n<rt>x</rt><rt>y</rt>\n </rtc></ruby>',
      'AxBy',
      5,
      false,
    ),
    ('<ruby>A<rtc><rt>x</rt><rt>y</rt></rtc></ruby>', 'Axy', 2, true),
    ('<ruby><rtc><rt>x</rt><rt>y</rt></rtc></ruby>', 'xy', 1, true),
    ('<ruby>A<rtc></rtc></ruby>', 'A', 0, true),
  ]) {
    test(
      'one actual RTC level pairs native columns without flattening: $html',
      () {
        final f = _Fixture(html, width: 100, height: 40, entries: 3);
        f.finish();
        expect(f.session.snapshot, hasLength(1));
        expect(f.cache.pictureBuildCount, 0);
        final builds = f.cache.layoutBuildCount;
        final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        try {
          expect(fragment.projection.text, expected);
          final box = fragment
              .glyphBoxes(expected.length - 1, expected.length)
              .single;
          final hit = fragment.view.sourceAt(
            Offset(box.left + .1, (box.top + box.bottom) / 2),
          );
          expect(hit.sourceRune, source);
          // The B/RT join has an actual source gap after column reordering.
          expect(hit.isExact, exact);
          expect(f.cache.layoutBuildCount, builds);
        } finally {
          fragment.close();
        }
        expect(f.cache.activeLeases, 0);
        expect(f.session.activeIssuedLeases, 0);
      },
    );
  }

  test(
    'RTC font inheritance uses current native RT styles and one shared baseline',
    () {
      final f = _Fixture(
        '<ruby><rb>A</rb><rb>B</rb><rtc style="font-size:30px"><rt>x</rt><rt style="font-size:12px">y</rt></rtc></ruby>',
        width: 100,
        height: 60,
        entries: 2,
      );
      f.finish();
      final builds = f.cache.layoutBuildCount;
      final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        final leases = fragment.nativeLeases.toList();
        final first = leases[2] as ForumBodyTextLease;
        final second = leases[4] as ForumBodyTextLease;
        expect(first.content.runs.single.style.textStyle.fontSize, 30);
        expect(second.content.runs.single.style.textStyle.fontSize, 12);
        expect(first.layout.width, 30);
        expect(first.layout.height, 30);
        expect(fragment.view.height, 50);
        double baseline(ForumBodyTextLease lease, int display) {
          final local = lease.layout.selectionBoxes(0, 1).single;
          final visible = fragment.glyphBoxes(display, display + 1).single;
          return visible.top - local.top + lease.layout.alphabeticBaseline;
        }

        expect(baseline(first, 1), closeTo(baseline(second, 3), 1e-4));
        expect(f.cache.layoutBuildCount, builds);
      } finally {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'RTC columns retain actual font alignment and independent wrapped rows',
    () {
      final f = _Fixture(
        '<ruby><rb style="font-size:30px">A</rb><rb>B</rb><rtc><rt>xx</rt><rt>yy</rt></rtc></ruby>',
        width: 30,
        height: 40,
        entries: 2,
      );
      f.finish();
      expect(f.session.snapshot, hasLength(2));
      expect(f.cache.layoutBuildCount, 3);
      for (var page = 0; page < 2; page++) {
        final fragment =
            f.prepare(page).single as ForumBodyPreparedInlineFragment;
        try {
          expect(fragment.view.height, page == 0 ? 40 : 30);
          final last = fragment
              .glyphBoxes(page == 0 ? 2 : 5, page == 0 ? 3 : 6)
              .single;
          expect(last.top, greaterThanOrEqualTo(0));
          expect(last.bottom, lessThanOrEqualTo(fragment.view.height));
        } finally {
          fragment.close();
        }
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test('dense RTC keeps its actual children in the shared bounded cache', () {
    final f = _Fixture(
      '<ruby>${List.generate(60, (i) => '<rb style="font-size:${i.isEven ? 30 : 20}px">A</rb>').join()}<rtc>${List.generate(60, (i) => '<rt>r$i</rt>').join()}</rtc></ruby>',
      width: 600,
      height: 200,
      entries: 3,
    );
    f.finish();
    expect(f.cache.layoutBuildCount, 5);
    expect(f.cache.pictureBuildCount, 0);
    expect(f.cache.entryCount, 3);
    final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      expect(fragment.nativeLeases, hasLength(121));
      expect(f.cache.layoutBuildCount, 5);
      expect(f.cache.pictureBuildCount, 120);
    } finally {
      fragment.close();
    }
    expect(f.cache.activeLeases, 0);
    expect(f.session.activeIssuedLeases, 0);
  });

  for (final mode in ['normal', 'pre', 'pre-wrap', 'pre-line']) {
    test('actual annotation BR lays out once on one native line ($mode)', () {
      final f = _Fixture(
        '<ruby>A<rt style="white-space:$mode">x<br><b>y</b></rt></ruby>',
        width: 60,
        entries: 2,
      );
      f.finish();
      expect(f.session.snapshot, hasLength(1));
      expect(f.cache.pictureBuildCount, 0);
      final builds = f.cache.layoutBuildCount;
      final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(fragment.projection.text, 'Ax y');
        final x = fragment.glyphBoxes(1, 2).single;
        final y = fragment.glyphBoxes(3, 4).single;
        expect(x.top, closeTo(y.top, 1e-4));
        final hit = fragment.view.sourceAt(
          Offset(y.left + .1, (y.top + y.bottom) / 2),
        );
        expect(hit.sourceRune, 3);
        expect(hit.isExact, isTrue);
        expect(f.cache.layoutBuildCount, builds);
      } finally {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
      expect(f.session.activeIssuedLeases, 0);
    });
  }

  test('aligned native paint matches independent native row formatting', () async {
    final f = _Fixture(
      '<ruby><rb style="font-size:30px">A</rb><rb>B</rb><rt>xx</rt><rt style="font-size:15px">yy</rt></ruby>',
      width: 200,
      height: 100,
      entries: 2,
    );
    f.finish();
    final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    final painters = <TextPainter>[];
    try {
      expect(fragment.view.height, 45);
      final leases = fragment.nativeLeases.toList();
      TextSpan span(int index) =>
          (leases[index] as ForumBodyTextLease).content.textSpan;
      const gap = TextSpan(
        text: ' ',
        style: TextStyle(fontFamily: 'Ahem', fontSize: 5, height: 1),
      );
      for (final children in [
        [span(1), gap, span(3), gap],
        [gap, span(2), gap, span(4)],
      ]) {
        painters.add(
          TextPainter(
            text: TextSpan(
              style: const TextStyle(
                fontFamily: 'Ahem',
                fontSize: 10,
                height: 1,
              ),
              children: children,
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
        );
      }
      Future<List<int>> rgba(void Function(Canvas) paint) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)
          ..clipRect(const Rect.fromLTWH(0, 0, 200, 45), doAntiAlias: false);
        paint(canvas);
        final picture = recorder.endRecording();
        try {
          final image = await picture.toImage(200, 45);
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            return bytes.buffer
                .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)
                .toList();
          } finally {
            image.dispose();
          }
        } finally {
          picture.dispose();
        }
      }

      final actual = await rgba(
        (canvas) => fragment.view.paint(canvas, Offset.zero),
      );
      final expected = await rgba((canvas) {
        // Independent native rows supply their own baselines. Ahem 5px gaps
        // center these glyphs in two 30px columns; no planned offsets are read.
        painters[0].paint(canvas, const Offset(0, 15));
        painters[1].paint(canvas, Offset.zero);
      });
      var mismatches = 0;
      for (var index = 0; index < actual.length; index++) {
        if (actual[index] != expected[index]) mismatches++;
      }
      expect(mismatches, 0);
    } finally {
      for (final painter in painters) {
        painter.dispose();
      }
      fragment.close();
    }
    expect(f.cache.activeLeases, 0);
    expect(f.session.activeIssuedLeases, 0);
  });

  for (final (baseSize, rtFirst, rtSecond, tight, nonlinear, under) in [
    (30, 10, 10, false, false, false),
    (20, 10, 15, false, false, false),
    (30, 8, 15, false, true, false),
    (30, 10, 15, true, false, false),
    (30, 10, 10, false, false, true),
    (20, 10, 15, false, false, true),
    (30, 8, 15, false, true, true),
    (30, 10, 15, true, false, true),
  ]) {
    test(
      'one ruby level aligns actual baselines (base=$baseSize, RT=$rtFirst/$rtSecond, tight=$tight, nonlinear=$nonlinear, under=$under)',
      () {
        final lineHeight = tight ? '.25' : '1';
        final f = _Fixture(
          '<ruby style="ruby-position:${under ? 'under' : 'over'}"><rb style="font-size:${baseSize}px;line-height:$lineHeight">A</rb><rb style="line-height:$lineHeight">B</rb><rt style="font-size:${rtFirst}px;line-height:$lineHeight">xx</rt><rt style="font-size:${rtSecond}px;line-height:$lineHeight">yy</rt></ruby>',
          width: 300,
          height: 200,
          entries: 2,
          textScaler: nonlinear
              ? _Scaler((size) => size >= 20 ? size * 1.5 : size * 1.1)
              : TextScaler.noScaling,
        );
        f.finish();
        final builds = f.cache.layoutBuildCount;
        final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        try {
          final leases = fragment.nativeLeases.toList();
          double baseline(int start, int end, int leaseIndex) {
            final lease = leases[leaseIndex] as ForumBodyTextLease;
            final local = lease.layout
                .selectionBoxes(0, lease.content.projection.text.length)
                .single;
            final visible = fragment.glyphBoxes(start, end).single;
            return visible.top - local.top + lease.layout.alphabeticBaseline;
          }

          expect(baseline(1, 3, 2), closeTo(baseline(4, 6, 4), 1e-4));
          expect(baseline(0, 1, 1), closeTo(baseline(3, 4, 3), 1e-4));
          final a = fragment.glyphBoxes(1, 3).single;
          final b = fragment.glyphBoxes(4, 6).single;
          final bases = [
            fragment.glyphBoxes(0, 1).single,
            fragment.glyphBoxes(3, 4).single,
          ];
          for (final annotation in [a, b]) {
            expect(annotation.top, greaterThanOrEqualTo(-1e-4));
            for (final base in bases) {
              if (under) {
                expect(
                  annotation.top,
                  greaterThanOrEqualTo(base.bottom - 1e-4),
                );
              } else {
                expect(annotation.bottom, lessThanOrEqualTo(base.top + 1e-4));
              }
            }
          }
          final glyph = fragment.glyphBoxes(5, 6).single;
          final hit = fragment.view.sourceAt(
            Offset(glyph.left + .1, (glyph.top + glyph.bottom) / 2),
          );
          expect(hit.sourceRune, 5);
          expect(hit.isExact, isTrue);
          expect(f.cache.layoutBuildCount, builds);
          expect(f.cache.entryCount, 2);
        } finally {
          fragment.close();
        }
        expect(f.cache.activeLeases, 0);
        expect(f.session.activeIssuedLeases, 0);
      },
    );
  }

  test(
    'wrapped ruby rows keep independent font extents and reuse their provisional parent',
    () {
      final f = _Fixture(
        '<ruby><rb style="font-size:30px">A</rb><rb>B</rb><rt>xx</rt><rt>yy</rt></ruby>',
        width: 30,
        height: 40,
        entries: 2,
      );
      f.finish();
      expect(f.session.snapshot, hasLength(2));
      expect(f.cache.layoutBuildCount, 3);
      for (var page = 0; page < 2; page++) {
        final fragment =
            f.prepare(page).single as ForumBodyPreparedInlineFragment;
        try {
          expect(fragment.view.height, page == 0 ? 40 : 30);
          final rt = fragment
              .glyphBoxes(page == 0 ? 1 : 4, page == 0 ? 3 : 6)
              .single;
          expect(rt.top, 0);
        } finally {
          fragment.close();
        }
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  for (final sameRoot in [true, false]) {
    test(
      'annotation level ownership follows the real ruby root (same=$sameRoot)',
      () {
        final f = _Fixture(
          sameRoot
              ? '<ruby><rb style="font-size:30px">A</rb><rt>xx</rt><rb>B</rb><rt>yy</rt></ruby>'
              : '<ruby><rb style="font-size:30px">A</rb><rt>xx</rt></ruby><ruby><rb>B</rb><rt>yy</rt></ruby>',
          width: 200,
          height: 100,
          entries: 2,
        );
        f.finish();
        expect(f.cache.layoutBuildCount, sameRoot ? 4 : 3);
        final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        try {
          final first = fragment.glyphBoxes(1, 3).single;
          final second = fragment.glyphBoxes(4, 6).single;
          expect(
            (second.top - first.top).abs(),
            sameRoot ? closeTo(0, 1e-4) : greaterThan(5),
          );
        } finally {
          fragment.close();
        }
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  test('canceling a pending row alignment drops its provisional shape', () {
    final f = _Fixture(
      '<ruby><rb style="font-size:30px">A</rb><rb>B</rb><rt>xx</rt><rt>yy</rt></ruby>',
      width: 200,
      height: 100,
      entries: 2,
    );
    for (var step = 0; f.cache.layoutBuildCount < 3 && step < 100; step++) {
      f.advance();
    }
    expect(f.cache.layoutBuildCount, 3);
    expect(f.session.snapshot, isEmpty);
    expect(f.cache.activeLeases, 1);
    f.session.close();
    expect(f.cache.activeLeases, 0);
    expect(f.cache.entryCount, 1);
    expect(f.session.activeIssuedLeases, 0);
  });

  test('many empty physical rows remain bounded while resolving ruby levels', () {
    final f = _Fixture(
      '<ruby style="white-space:pre-wrap"><rb style="font-size:30px">A</rb>${'\n' * 80}<rb>B</rb><rt>xx</rt><rt>yy</rt></ruby>',
      width: 200,
      height: 2000,
      entries: 2,
    );
    f.finish();
    expect(f.cache.layoutBuildCount, 3);
    final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    fragment.close();
    expect(f.cache.activeLeases, 0);
  });

  test(
    'dense level alignment evicts its probe without rebuilding glyph bands',
    () {
      final f = _Fixture(
        '<ruby>${List.generate(60, (i) => '<rb style="font-size:${i.isEven ? 30 : 20}px">A</rb>').join()}${List.generate(60, (i) => '<rt>r$i</rt>').join()}</ruby>',
        width: 600,
        height: 200,
        entries: 3,
      );
      f.finish();
      expect(f.cache.layoutBuildCount, 5);
      expect(f.cache.pictureBuildCount, 0);
      expect(f.cache.entryCount, 3);
      final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(fragment.nativeLeases, hasLength(121));
        expect(f.cache.layoutBuildCount, 5);
        expect(f.cache.pictureBuildCount, 120);
      } finally {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
      expect(f.session.activeIssuedLeases, 0);
    },
  );

  test(
    'orphan RT uses a real empty font strut without invented display text',
    () {
      final f = _Fixture('<ruby><rt>xy</rt></ruby>', width: 200, height: 100);
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(prepared.view.content.projection.display.text, 'xy');
        expect(prepared.view.content.projection.engineText, '\uFFFC');
        final leases = prepared.nativeLeases.toList();
        expect(leases, hasLength(3));
        final base = leases[1] as ForumBodyTextLease;
        expect(base.content.projection.text, isEmpty);
        expect(base.layout.width, 0);
        expect(base.layout.height, 20);
        expect(base.layout.alphabeticBaseline, greaterThan(0));
        expect(base.layout.selectionBoxes(0, 0), isEmpty);
        expect(prepared.glyphBoxes(0, 2).single.top, 0);
        expect(prepared.glyphBoxes(0, 2).single.bottom, 10);
        expect(prepared.view.height, 30);
      } finally {
        prepared.close();
      }
      expect(f.cache.activeLeases, 0);
      expect(f.session.activeIssuedLeases, 0);
    },
  );

  test(
    'empty base space is approximate while actual RT hits keep their source',
    () {
      final f = _Fixture(
        '<p>X<ruby><rt>xy</rt></ruby>Y</p>',
        width: 200,
        height: 100,
      );
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        final leases = prepared.nativeLeases.toList();
        final parent = leases[0] as ForumBodyInlineParagraphLease;
        final base = leases[1] as ForumBodyTextLease;
        final rt = leases[2] as ForumBodyTextLease;
        final metrics = ForumBodyRubyGroupMetrics.measure(
          cache: f.cache,
          baseLease: base,
          annotation: rt.content,
          annotationLease: rt,
          maxWidth: 200,
        );
        final origin = parent.layout.atomBoxes.single.toRect().topLeft;
        final glyph = rt.layout.selectionBoxes(1, 2).single.toRect();
        final hit = prepared.view.sourceAt(
          origin +
              metrics.annotationOffset +
              Offset(glyph.left + .1, (glyph.top + glyph.bottom) / 2),
        );
        expect(hit.isExact, isTrue);
        expect(hit.sourceRune, 2);
        final blank = prepared.view.sourceAt(
          origin + Offset(.1, metrics.size.height - .1),
        );
        expect(blank.isExact, isFalse);
        expect(blank.sourceRune, inInclusiveRange(1, 3));
      } finally {
        prepared.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test('anonymous font metrics never pollute later actual source envelopes', () {
    final f = _Fixture(
      '<p><span style="display:none">hidden</span><ruby><rt>xy</rt></ruby></p>',
      width: 200,
      height: 100,
    );
    f.finish();
    expect(f.session.snapshot.single.fragments.single.sourceHint, (
      runeStart: 6,
      runeEnd: 8,
    ));
    final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      expect(prepared.projection.text, 'xy');
      expect(prepared.projection.sourceAtUtf16(0).sourceRune, 6);
      final hit = prepared.view.sourceAt(Offset(.1, prepared.view.height - .1));
      expect(hit.isExact, isFalse);
      expect(hit.sourceRune, inInclusiveRange(6, 8));
    } finally {
      prepared.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  test('anonymous base and RT retain independent nonlinear font scaling', () {
    final f = _Fixture(
      '<ruby><rt>xy</rt></ruby>',
      width: 200,
      height: 100,
      textScaler: _Scaler((size) => size >= 20 ? size * 2 : size),
    );
    f.finish();
    final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      final leases = prepared.nativeLeases.toList();
      final base = leases[1] as ForumBodyTextLease;
      final rt = leases[2] as ForumBodyTextLease;
      expect(base.layout.height, 40);
      expect(rt.layout.height, 10);
      expect(prepared.view.height, 50);
      expect(prepared.projection.text, 'xy');
    } finally {
      prepared.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  for (final singleRoot in [false, true]) {
    test(
      'dense orphan RT shares its font strut and bounds annotation bands (singleRoot=$singleRoot)',
      () {
        final f = _Fixture(
          singleRoot
              ? '<p><ruby>${List.generate(60, (index) => '<rt>r$index</rt>').join()}</ruby></p>'
              : '<p>${List.generate(60, (index) => '<ruby><rt>r$index</rt></ruby>').join()}</p>',
          width: 600,
          height: 100,
          entries: 4,
        );
        f.finish();
        expect(f.session.snapshot, hasLength(1));
        expect(f.cache.layoutBuildCount, 3);
        expect(f.cache.pictureBuildCount, 0);
        final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        try {
          expect(prepared.view.atomIndices, hasLength(60));
          expect(prepared.nativeLeases, hasLength(121));
          expect(f.cache.entryCount, lessThanOrEqualTo(4));
          expect(f.cache.pictureBuildCount, 60);
        } finally {
          prepared.close();
        }
        expect(f.cache.activeLeases, 0);
        expect(f.session.activeIssuedLeases, 0);
      },
    );
  }

  test('consecutive orphan columns wrap with actual per-page RT sources', () {
    final f = _Fixture(
      '<ruby><rt>xy</rt><rt>zw</rt></ruby>',
      width: 20,
      height: 30,
    );
    f.finish();
    expect(f.session.snapshot, hasLength(2));
    for (var page = 0; page < 2; page++) {
      final fragment =
          f.prepare(page).single as ForumBodyPreparedInlineFragment;
      try {
        expect(fragment.view.atomIndices, [page]);
        expect(f.session.snapshot[page].fragments.single.sourceHint, (
          runeStart: page * 2,
          runeEnd: page * 2 + 2,
        ));
        final glyph = fragment.glyphBoxes(page * 2 + 1, page * 2 + 2).single;
        final hit = fragment.view.sourceAt(
          Offset(glyph.left + .1, (glyph.top + glyph.bottom) / 2),
        );
        expect(hit.sourceRune, page * 2 + 1);
        expect(hit.isExact, isTrue);
        expect(fragment.nativeLeases, hasLength(3));
      } finally {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
      expect(f.session.activeIssuedLeases, 0);
    }
  });

  test(
    'explicit bases pair in columns while retaining original source order',
    () {
      final f = _Fixture(
        '<ruby><rb>A</rb><rb>B</rb><rt>xx</rt><rt>yy</rt></ruby>',
        width: 200,
        height: 100,
      );
      f.finish();
      final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(fragment.projection.text, 'AxxByy');
        expect(fragment.view.content.projection.engineText, '\uFFFC\uFFFC');
        expect(fragment.projection.sourceAtUtf16(3).sourceRune, 1);
        expect(fragment.projection.sourceAtUtf16(3).isExact, isFalse);
        final leases = fragment.nativeLeases.toList();
        expect(leases, hasLength(5));
        expect((leases[3] as ForumBodyTextLease).content.projection.text, 'B');
        expect(
          leases.whereType<ForumBodyTextLease>().any(
            (lease) => lease.content.isSourceFree,
          ),
          isFalse,
        );
        final glyph = fragment.glyphBoxes(5, 6).single;
        final hit = fragment.view.sourceAt(
          Offset(glyph.left + .1, (glyph.top + glyph.bottom) / 2),
        );
        expect(hit.sourceRune, 5);
        expect(hit.isExact, isTrue);
        expect(f.session.snapshot.single.fragments.single.sourceHint, (
          runeStart: 0,
          runeEnd: 6,
        ));
      } finally {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'explicit columns publish overlapping hints but only visible RT glyphs',
    () {
      final f = _Fixture(
        '<ruby><rb>A</rb><rb>B</rb><rt>xx</rt><rt>yy</rt></ruby>',
        width: 20,
        height: 30,
      );
      f.finish();
      expect(f.session.snapshot, hasLength(2));
      for (var page = 0; page < 2; page++) {
        final fragment =
            f.prepare(page).single as ForumBodyPreparedInlineFragment;
        try {
          expect(fragment.view.atomIndices, [page]);
          expect(f.session.snapshot[page].fragments.single.sourceHint, (
            runeStart: page,
            runeEnd: page == 0 ? 4 : 6,
          ));
          final start = page == 0 ? 2 : 5;
          final glyph = fragment.glyphBoxes(start, start + 1).single;
          final hit = fragment.view.sourceAt(
            Offset(glyph.left + .1, (glyph.top + glyph.bottom) / 2),
          );
          expect(hit.sourceRune, page == 0 ? 3 : 5);
          expect(hit.isExact, isTrue);
        } finally {
          fragment.close();
        }
        expect(f.cache.activeLeases, 0);
        expect(f.session.activeIssuedLeases, 0);
      }
    },
  );

  for (final (html, text, engine) in [
    (
      '<ruby> \n<rb>A</rb> <rb>B</rb> \n<rt>xx</rt><rt>yy</rt></ruby>',
      'Axx Byy',
      '\uFFFC \uFFFC',
    ),
    (
      '<ruby><rb>A</rb><rb> </rb><rb>B</rb><rt>x</rt><rt>·</rt><rt>y</rt></ruby>',
      'Ax ·By',
      '\uFFFC\uFFFC\uFFFC',
    ),
    (
      '<ruby>A<rb>B</rb>C<rt>xx</rt><rt>yy</rt><rt>zz</rt></ruby>',
      'AxxByyCzz',
      '\uFFFC\uFFFC\uFFFC',
    ),
  ]) {
    test(
      'explicit base units and structural gaps retain distinct whitespace: $html',
      () {
        final f = _Fixture(html, width: 200, height: 100);
        f.finish();
        final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        try {
          expect(fragment.projection.text, text);
          expect(fragment.view.content.projection.engineText, engine);
        } finally {
          fragment.close();
        }
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  test('an actual empty RB retains its own native font metrics', () {
    final f = _Fixture(
      '<ruby><rb style="font-size:30px"></rb><rt>xy</rt></ruby>',
      width: 200,
      height: 100,
    );
    f.finish();
    final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      final base = fragment.nativeLeases.elementAt(1) as ForumBodyTextLease;
      expect(base.content.isSourceFree, isFalse);
      expect(base.content.projection.text, isEmpty);
      expect(base.layout.height, 30);
      expect(fragment.projection.text, 'xy');
      expect(fragment.view.height, 40);
      expect(f.cache.pictureBuildCount, 1);
    } finally {
      fragment.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  for (final (html, text, handles, end) in [
    ('<ruby><rb>A</rb><rb>B</rb><rt>xx</rt></ruby>', 'AxxB', 4, 4),
    ('<ruby><rb>A</rb><rt>xx</rt><rt>yy</rt></ruby>', 'Axxyy', 5, 5),
  ]) {
    test(
      'missing and excess RT units retain actual base/source coverage: $html',
      () {
        final f = _Fixture(html, width: 200, height: 100);
        f.finish();
        final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        try {
          expect(fragment.projection.text, text);
          expect(fragment.nativeLeases, hasLength(handles));
          expect(f.session.snapshot.single.fragments.single.sourceHint, (
            runeStart: 0,
            runeEnd: end,
          ));
        } finally {
          fragment.close();
        }
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  test(
    'sixty explicit base columns stay in the existing native cache budget',
    () {
      final f = _Fixture(
        '<ruby>${List.filled(60, '<rb>A</rb>').join()}${List.generate(60, (i) => '<rt>r$i</rt>').join()}</ruby>',
        width: 600,
        height: 100,
        entries: 4,
      );
      f.finish();
      expect(f.cache.layoutBuildCount, 4);
      expect(f.cache.pictureBuildCount, 0);
      final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(fragment.view.atomIndices, hasLength(60));
        expect(fragment.nativeLeases, hasLength(121));
        expect(f.cache.entryCount, lessThanOrEqualTo(4));
        expect(f.cache.pictureBuildCount, 120);
      } finally {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
      expect(f.session.activeIssuedLeases, 0);
    },
  );

  test('consecutive RTs pair with one actual and one anonymous base', () {
    final f = _Fixture(
      '<ruby>AB<rt>xy</rt><rt>z</rt></ruby>',
      width: 200,
      height: 100,
    );
    f.finish();
    final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      expect(fragment.projection.text, 'ABxyz');
      expect(fragment.view.content.projection.engineText, '\uFFFC\uFFFC');
      final leases = fragment.nativeLeases.toList();
      expect(leases, hasLength(5));
      expect((leases[1] as ForumBodyTextLease).content.projection.text, 'AB');
      expect((leases[3] as ForumBodyTextLease).content.isSourceFree, isTrue);
      expect(fragment.view.height, 30);
      final first = fragment.glyphBoxes(2, 3).single;
      final last = fragment.glyphBoxes(4, 5).single;
      expect(last.left, greaterThan(first.right));
      expect(last.top, first.top);
      final hit = fragment.view.sourceAt(
        Offset(last.left + .1, (last.top + last.bottom) / 2),
      );
      expect(hit.sourceRune, 4);
      expect(hit.isExact, isTrue);
    } finally {
      fragment.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  test(
    'base trailing space follows the whole annotation range with original source',
    () {
      final f = _Fixture(
        '<p>X<ruby>AB <rt>xy</rt><rt>z</rt></ruby>Y</p>',
        width: 200,
        height: 100,
      );
      f.finish();
      final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(fragment.projection.text, 'XABxyz Y');
        expect(fragment.view.content.projection.engineText, 'X\uFFFC\uFFFC Y');
        expect(fragment.projection.sourceAtUtf16(6).sourceRune, 3);
        expect(f.session.snapshot.single.fragments.single.sourceHint, (
          runeStart: 0,
          runeEnd: 8,
        ));
        final glyph = fragment.glyphBoxes(5, 6).single;
        final hit = fragment.view.sourceAt(
          Offset(glyph.left + .1, (glyph.top + glyph.bottom) / 2),
        );
        expect(hit.sourceRune, 6);
        expect(hit.isExact, isTrue);
      } finally {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test('extra annotation source retains fallback and hidden gaps', () {
    final f = _Fixture(
      '<ruby>AB<rt>xy</rt><rp>(</rp><span hidden>hidden</span><rt>zw</rt></ruby>',
      width: 200,
      height: 100,
    );
    f.finish();
    final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      expect(fragment.projection.text, 'ABxyzw');
      expect(fragment.projection.sourceAtUtf16(4).sourceRune, 11);
      expect(fragment.projection.sourceAtUtf16(4).isExact, isFalse);
      expect(f.session.snapshot.single.fragments.single.sourceHint, (
        runeStart: 0,
        runeEnd: 13,
      ));
      final glyph = fragment.glyphBoxes(5, 6).single;
      final hit = fragment.view.sourceAt(
        Offset(glyph.left + .1, (glyph.top + glyph.bottom) / 2),
      );
      expect(hit.sourceRune, 12);
      expect(hit.isExact, isTrue);
    } finally {
      fragment.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  test('actual and anonymous columns retain independent nonlinear scaling', () {
    final f = _Fixture(
      '<ruby>AB<rt>xy</rt><rt>z</rt></ruby>',
      width: 200,
      height: 100,
      textScaler: _Scaler((size) => size >= 20 ? size * 2 : size),
    );
    f.finish();
    final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      final leases = fragment.nativeLeases.toList();
      expect((leases[1] as ForumBodyTextLease).layout.height, 40);
      expect((leases[3] as ForumBodyTextLease).layout.height, 40);
      expect((leases[4] as ForumBodyTextLease).layout.height, 10);
      expect(fragment.view.height, 50);
    } finally {
      fragment.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  test(
    'an empty first RT preserves its base before the next annotation column',
    () {
      final f = _Fixture(
        '<ruby>A<rt></rt><rt>z</rt></ruby>',
        width: 200,
        height: 100,
      );
      f.finish();
      final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(fragment.projection.text, 'Az');
        expect(fragment.view.atomIndices, [0, 1]);
        expect(fragment.nativeLeases, hasLength(4));
        expect(f.cache.pictureBuildCount, 2);
        expect(fragment.glyphBoxes(0, 2), hasLength(2));
      } finally {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test('one base with sixty RTs shares existing bounded native requests', () {
    final f = _Fixture(
      '<p><ruby>A${List.generate(60, (index) => '<rt>r$index</rt>').join()}</ruby></p>',
      width: 600,
      height: 100,
      entries: 4,
    );
    f.finish();
    expect(f.cache.layoutBuildCount, 3);
    expect(f.cache.pictureBuildCount, 0);
    final fragment = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    try {
      expect(fragment.view.atomIndices, hasLength(60));
      expect(fragment.nativeLeases, hasLength(121));
      expect(f.cache.entryCount, lessThanOrEqualTo(4));
      expect(f.cache.pictureBuildCount, 61);
    } finally {
      fragment.close();
    }
    expect(f.cache.activeLeases, 0);
    expect(f.session.activeIssuedLeases, 0);
  });

  test(
    'consecutive RTs preserve actual source when their columns cross a page',
    () {
      final f = _Fixture(
        '<ruby>A<rt>xy</rt><rt>zw</rt></ruby>',
        width: 20,
        height: 30,
      );
      f.finish();
      expect(f.session.snapshot, hasLength(2));
      for (var page = 0; page < 2; page++) {
        final fragment =
            f.prepare(page).single as ForumBodyPreparedInlineFragment;
        try {
          expect(fragment.view.atomIndices, [page]);
          expect(f.session.snapshot[page].fragments.single.sourceHint, (
            runeStart: page == 0 ? 0 : 3,
            runeEnd: page == 0 ? 3 : 5,
          ));
          final glyph = fragment.glyphBoxes(page * 2 + 2, page * 2 + 3).single;
          final hit = fragment.view.sourceAt(
            Offset(glyph.left + .1, (glyph.top + glyph.bottom) / 2),
          );
          expect(hit.sourceRune, page * 2 + 2);
          expect(hit.isExact, isTrue);
        } finally {
          fragment.close();
        }
        expect(f.cache.activeLeases, 0);
        expect(f.session.activeIssuedLeases, 0);
      }
    },
  );

  test(
    'actual Session produces mixed pages and complete visible source-bound views',
    () {
      final f = _Fixture('<p>X<ruby>AB<rt>xy</rt></ruby>Y</p>');
      f.finish();
      expect(f.session.snapshot, hasLength(2));
      expect(f.session.retainedParagraphCount, 1);
      expect(f.session.retainedTextCodeUnits, 6);
      expect(f.cache.layoutBuildCount, 3);
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

  for (final ranks in [1, 100]) {
    test(
      'warm typed convenience completes cached $ranks ranks and plain delivery rejects inline upfront',
      () {
        final f = _Fixture(
          '<ruby><rb>AB</rb>${List.generate(ranks, (i) => '<rtc><rt style="font-size:1px">r$i</rt></rtc>').join()}</ruby>',
          width: 300,
          height: 500,
        );
        f.finish();
        for (final fragment in f.prepare(0)) {
          fragment.close();
        }
        final before = (f.cache.layoutBuildCount, f.cache.pictureBuildCount);
        final fragments = f.session.preparePageFragments(0);
        expect(fragments.single, isA<ForumBodyPreparedInlineFragment>());
        expect(fragments.single.nativeLeases.length, ranks + 2);
        for (final fragment in fragments) {
          fragment.close();
        }
        expect(f.session.activeIssuedLeases, 0);
        expect(() => f.session.preparePageLeases(0), throwsStateError);
        expect(f.cache.activeLeases, 0);
        expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), before);
      },
    );
  }

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
      expect(f.cache.layoutBuildCount, 6);
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
        expect(f.cache.layoutBuildCount, 7);
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
      expect(f.cache.layoutBuildCount, 3);
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
      expect(f.cache.layoutBuildCount, 4);
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
      expect(f.cache.layoutBuildCount, 4);
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
      expect(f.cache.layoutBuildCount, 3);
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
    '<ruby><rt> </rt></ruby>',
    '<ruby style="ruby-position:inter-character">A<rt>a</rt></ruby>',
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

  test(
    'admitted nested extra annotation still obeys the actual page height',
    () {
      final f = _Fixture(
        '<ruby>A<rt>a</rt><rt><ruby>B<rt>b</rt></ruby></rt></ruby>',
      );
      expect(
        f.finish,
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageFailure.oversizedGroup,
          ),
        ),
      );
      expect(f.session.snapshot, isEmpty);
      expect(f.cache.activeLeases, 0);
    },
  );

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

  test(
    'late unsupported input preserves the already published mixed prefix',
    () {
      final f = _Fixture(
        '<span>X<ruby>AB<rt>xy</rt></ruby>Y<br>Z<br>'
        '<ruby style="ruby-position:inter-character">A<rt>a</rt></ruby></span>',
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
    },
  );
}

final class _Scaler extends TextScaler {
  const _Scaler(this.callback);
  final double Function(double) callback;
  @override
  double scale(double size) => callback(size);
  @override
  double get textScaleFactor => 1;
}

final class _ScriptCurve extends TextScaler {
  const _ScriptCurve();
  @override
  double scale(double size) => size * (size < 18 ? 1.7 : 1.2);
  @override
  double get textScaleFactor => 1.2;
}
