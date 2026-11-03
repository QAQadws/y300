import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';

({ForumBodyInlineEmphasisGlyphInput input, int parts}) _prepare(
  ForumBodyInlineSpanContent content, {
  int quantum = 1,
}) {
  final work = ForumBodyInlineEmphasisGlyphPreparation(
    content: content,
    ensureOwner: () {},
  );
  var parts = 0;
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(50000));
      final used = work.advance(maxParts: quantum);
      expect(used, inInclusiveRange(1, quantum));
      parts += used;
    }
    expect(work.advance(maxParts: 1), 0);
    return (input: work.takeInput(), parts: parts);
  } finally {
    work.close();
  }
}

ForumBodyInlineSpanContent _source({
  String direction = 'ltr',
}) => mixedInlineInput(
  prefix: '<span style="font-size:31px">e</span><span>́</span> 👩‍👩‍👧‍👦 ',
  suffix: ' Z',
  direction: direction,
  paragraphStyle:
      'text-emphasis:circle red;text-indent:7.25px;letter-spacing:1px;word-spacing:2px;line-height:.4;text-decoration:underline;text-shadow:1px 2px 2px blue',
).content;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in ['ltr', 'rtl']) {
    for (final quantum in [1, 7, 100]) {
      test(
        'explicit parent glyph derivation preserves source/child/font inputs $direction q=$quantum',
        () {
          final original = _source(direction: direction),
              input = _prepare(original, quantum: quantum).input;
          final glyphs = input.glyphs;
          expect(input.original, same(original));
          expect(glyphs, isNot(same(original)));
          expect(glyphs.style.textEmphasis.isEnabled, isFalse);
          expect(
            glyphs.parentRuns.every((r) => !r.style.textEmphasis.isEnabled),
            isTrue,
          );
          expect(glyphs.projection, same(original.projection));
          for (final mode in ForumBodyParagraphLayoutMode.values) {
            expect(
              glyphs.projectionForLayout(mode),
              same(original.projectionForLayout(mode)),
            );
          }
          expect(glyphs.contexts, same(original.contexts));
          expect(glyphs.style.textStyle, same(original.style.textStyle));
          expect(glyphs.style.textAlign, original.style.textAlign);
          expect(glyphs.style.textDirection, original.style.textDirection);
          expect(glyphs.horizontalInset, original.horizontalInset);
          expect(
            glyphs.appliesFirstLineIndent,
            original.appliesFirstLineIndent,
          );
          expect(glyphs.textSpan, original.textSpan);
          expect(input.extraRuns, glyphs.runs.length);
          expect(() => glyphs.runs.clear(), throwsUnsupportedError);
          for (final (i, run) in original.runs.indexed) {
            if (run.path.startsWith('0/1')) {
              expect(glyphs.runs[i], same(run));
            } else {
              expect(glyphs.runs[i].style.textEmphasis.isEnabled, isFalse);
              expect(glyphs.runs[i].style.textStyle, same(run.style.textStyle));
            }
          }
          expect(original.style.textEmphasis.isEnabled, isTrue);
          final children = original.contexts
              .getRange(1, original.contexts.length - 1)
              .map((w) => w.content)
              .toList();
          final actual = glyphs.resolveAtomicContexts(0, children);
          expect(actual, [
            for (final w in original.contexts.getRange(
              1,
              original.contexts.length - 1,
            ))
              same(w),
          ]);
          final cache = ForumBodyParagraphCache(
            maxEntries: 4,
            maxEstimatedBytes: 1 << 22,
          );
          addTearDown(cache.close);
          const dims = [
            PlaceholderDimensions(
              size: Size(40, 35),
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: 27,
            ),
          ];
          expect(
            () => cache.acquireInline(
              content: original,
              width: 300,
              dimensions: dims,
            ),
            throwsA(isA<ForumBodyParagraphLayoutException>()),
          );
          final lease = cache.acquireInline(
            content: glyphs,
            width: 300,
            dimensions: dims,
          );
          try {
            expect(lease.content, same(glyphs));
            expect(lease.layout.queryMaximumLineFrames(), isNotEmpty);
            expect(
              lease.layout.glyphAtEngineUtf16(
                lease.layout.projection.atoms.single.engineUtf16,
              ),
              isNull,
            );
          } finally {
            lease.release();
          }
          expect(cache.activeLeases, 0);
        },
      );
    }
  }
  test('child-only emphasis does not rewrite a plain parent', () {
    final original = mixedInlineInput(
      base: '<span style="text-emphasis:circle">A</span>',
    ).content;
    final input = _prepare(original).input;
    expect(original.runs.any((r) => r.style.textEmphasis.isEnabled), isTrue);
    expect(input.glyphs, same(original));
    expect(input.extraRuns, 0);
  });
  test('an all-atomic parent keeps every original child run', () {
    final original = mixedInlineInput(
      prefix: '',
      suffix: '',
      paragraphStyle: 'text-emphasis:circle',
    ).content;
    final glyphs = _prepare(original).input.glyphs;
    expect(original.parentRuns, isEmpty);
    expect(glyphs.parentRuns, isEmpty);
    expect(glyphs.contexts, same(original.contexts));
    for (final (i, run) in original.runs.indexed) {
      expect(glyphs.runs[i], same(run));
    }
    expect(glyphs.style.textEmphasis.isEnabled, isFalse);
  });
  test(
    'one run used by text and an atom never rewrites the actual child context',
    () {
      final doc = const ForumBodyParser().parse(
        html: '<p style="text-emphasis:circle">ABCD</p>',
        sourceId: 'shared-run',
        conversionIdentity: 'none',
      );
      final reader = ForumBodyReaderStyle(
        textStyle: const TextStyle(fontSize: 20),
        fontRevision: 'shared',
        linkColor: const Color(0xff0000ff),
      );
      final styles = const ForumBodyStyleResolver().resolve(doc, reader);
      final full = const ForumBodyParagraphContentBuilder().build(
        document: doc,
        styles: styles,
        path: '0',
      );
      final windows = [
        for (final (a, b) in [(0, 1), (1, 3), (3, 4)])
          full.displayWindow(startUtf16: a, endUtf16: b),
      ];
      final original = ForumBodyInlineSpanContent.compose(
        identity: doc.identity,
        path: '0',
        fontRevision: styles.fontRevision,
        styleRevision: styles.resolverRevision,
        style: styles.byPath['0']!,
        contexts: windows,
        atomicRanges: [(startUtf16: 1, endUtf16: 3)],
      );
      expect(original.runs, hasLength(1));
      final input = _prepare(original).input;
      expect(input.glyphs.runs.single.style.textEmphasis.isEnabled, isFalse);
      expect(input.glyphs.contexts[1].content, same(windows[1]));
      expect(windows[1].runs.single.style.textEmphasis.isEnabled, isTrue);
      expect(
        input.glyphs.resolveAtomicContexts(0, [windows[1]]).single,
        same(original.contexts[1]),
      );
    },
  );
  test(
    'hidden child parts are scanned in bounded units before later parent text',
    () {
      final doc = const ForumBodyParser().parse(
        html:
            '<p style="text-emphasis:circle">A${[for (var i = 0; i < 120; i++) '<span style="font-size:${i + 10}px">B</span>'].join()}Z</p>',
        sourceId: 'long-parent-parts',
        conversionIdentity: 'none',
      );
      final reader = ForumBodyReaderStyle(
        textStyle: const TextStyle(fontSize: 20),
        fontRevision: 'long',
        linkColor: const Color(0xff0000ff),
      );
      final styles = const ForumBodyStyleResolver().resolve(doc, reader);
      final full = const ForumBodyParagraphContentBuilder().build(
        document: doc,
        styles: styles,
        path: '0',
      );
      final original = ForumBodyInlineSpanContent.compose(
        identity: doc.identity,
        path: '0',
        fontRevision: full.fontRevision,
        styleRevision: full.styleRevision,
        style: full.style,
        contexts: [
          for (final (a, b) in [(0, 1), (1, 121), (121, 122)])
            full.displayWindow(startUtf16: a, endUtf16: b),
        ],
        atomicRanges: [(startUtf16: 1, endUtf16: 121)],
      );
      final result = _prepare(original);
      expect(result.parts, greaterThan(240));
      expect(
        result.input.glyphs.parentRuns.every(
          (r) => !r.style.textEmphasis.isEnabled,
        ),
        isTrue,
      );
      expect(result.input.glyphs.runs.length, original.runs.length);
    },
  );
  test('every work boundary and ready publication reject a retired owner', () {
    final content = _source(), parts = _prepare(content).parts;
    for (var boundary = 0; boundary <= parts; boundary++) {
      var active = true;
      final work = ForumBodyInlineEmphasisGlyphPreparation(
        content: content,
        ensureOwner: () {
          if (!active) throw StateError('Retired');
        },
      );
      for (var n = 0; n < boundary; n++) {
        work.advance(maxParts: 1);
      }
      active = false;
      if (work.isReady) {
        expect(work.takeInput, throwsStateError);
      } else {
        expect(() => work.advance(maxParts: 1), throwsStateError);
      }
      expect(work.isReady, isFalse);
      expect(work.takeInput, throwsStateError);
      work.close();
    }
  });
  test('owner callbacks cannot close or reenter a publication', () {
    for (final reenter in [false, true]) {
      late ForumBodyInlineEmphasisGlyphPreparation work;
      work = ForumBodyInlineEmphasisGlyphPreparation(
        content: _source(),
        ensureOwner: () {
          if (reenter) {
            work.advance(maxParts: 1);
          } else {
            work.close();
          }
        },
      );
      expect(() => work.advance(maxParts: 1), throwsStateError);
      expect(work.isReady, isFalse);
      expect(work.takeInput, throwsStateError);
      work.close();
    }
  });
  test('input bounds, close and single transfer keep the writer retired', () {
    final content = _source();
    expect(
      () => ForumBodyInlineEmphasisGlyphPreparation(
        content: content,
        ensureOwner: () {},
        maxRuns: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ForumBodyInlineEmphasisGlyphPreparation(
        content: content,
        ensureOwner: () {},
        maxRuns: 0,
      ),
      throwsA(isA<ForumBodyParagraphInputException>()),
    );
    final work = ForumBodyInlineEmphasisGlyphPreparation(
      content: content,
      ensureOwner: () {},
    );
    expect(() => work.advance(maxParts: 0), throwsArgumentError);
    while (!work.isReady) {
      work.advance(maxParts: 1);
    }
    final input = work.takeInput(), count = input.glyphs.runs.length;
    expect(() => work.advance(maxParts: 1), throwsStateError);
    expect(work.takeInput, throwsStateError);
    work.close();
    expect(input.glyphs.runs.length, count);
    expect(input.glyphs.projection, same(content.projection));
  });
}
