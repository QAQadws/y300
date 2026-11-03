import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';
import 'test_support/ruby_soft_space_row_fixture.dart';

({ForumBodyInlineEmphasisTextInput input, int parts}) _prepare(
  ForumBodyInlineSpanContent content, {
  int quantum = 1,
  int maxUnits = 512,
  ForumBodyInlineEmphasisGlyphInput? glyphInput,
}) {
  final work = glyphInput == null
      ? ForumBodyInlineEmphasisTextPreparation(
          content: content,
          maxUnits: maxUnits,
          ensureOwner: () {},
        )
      : ForumBodyInlineEmphasisTextPreparation.fromGlyphInput(
          glyphInput: glyphInput,
          maxUnits: maxUnits,
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

List<Object> _units(ForumBodyInlineEmphasisTextInput input) => [
  for (final u in input.units)
    (u.startUtf16, u.endUtf16, u.governingUtf16, u.runIndex),
];

ForumBodyInlineSpanContent _mixed({
  String prefix = 'A',
  String base = 'B',
  String annotation = 'rt',
  String suffix = 'Z',
  String direction = 'ltr',
}) => mixedInlineInput(
  prefix: prefix,
  base: base,
  annotation: annotation,
  suffix: suffix,
  direction: direction,
  paragraphStyle: 'text-emphasis:circle;white-space:pre-wrap',
).content;

ForumBodyInlineSpanContent _contexts(String html, int count) {
  final doc = const ForumBodyParser().parse(
    html: '<p style="text-emphasis:circle;white-space:pre-wrap">$html</p>',
    sourceId: 'inline-target-contexts',
    conversionIdentity: 'none',
  );
  final reader = ForumBodyReaderStyle(
    textStyle: const TextStyle(fontSize: 20),
    fontRevision: 'target-font',
    linkColor: const Color(0xff0000ff),
  );
  final styles = const ForumBodyStyleResolver().resolve(doc, reader);
  return ForumBodyInlineSpanContent.compose(
    identity: doc.identity,
    path: '0',
    fontRevision: styles.fontRevision,
    styleRevision: styles.resolverRevision,
    style: styles.byPath['0']!,
    contexts: [
      for (var i = 0; i < count; i++)
        const ForumBodyParagraphContentBuilder().build(
          document: doc,
          styles: styles,
          path: '0/$i',
        ),
    ],
    atomicRanges: const [],
  );
}

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
        'only original parent text becomes targets $direction q=$quantum',
        () {
          final content = _mixed(
            prefix: 'A',
            base: 'AAA',
            annotation: 'A',
            suffix: 'A',
            direction: direction,
          );
          final input = _prepare(content, quantum: quantum).input;
          expect(input.content, same(content));
          expect(input.glyphInput.original, same(content));
          expect(input.glyphInput.glyphs.contexts, same(content.contexts));
          expect(input.glyphInput.glyphs.projection, same(content.projection));
          expect(input.units.map((u) => (u.startUtf16, u.endUtf16)), [
            (0, 1),
            (5, 6),
          ]);
          expect(input.content.runs[input.units.first.runIndex].path, '0/0/0');
          expect(input.content.runs[input.units.last.runIndex].path, '0/2/0');
          expect(() => input.units.clear(), throwsUnsupportedError);
        },
      );
    }
  }
  test('base style and complete grapheme survive styled seams', () {
    final content = _mixed(
      prefix:
          '<span style="text-emphasis:triangle blue">e</span><i style="text-emphasis:none">́</i>',
      suffix:
          '<span style="text-emphasis:none">A</span><b style="text-emphasis:circle red">́</b>',
    );
    final input = _prepare(content).input;
    expect(input.units, hasLength(1));
    final u = input.units.single;
    expect((u.startUtf16, u.endUtf16, u.governingUtf16), (0, 2, 0));
    final style = content.runs[u.runIndex].style;
    expect(style.textEmphasis.mark, '▲');
    expect(style.textEmphasis.color, const Color(0xff0000ff));
    expect(style.textStyle.fontStyle, isNot(FontStyle.italic));
  });
  test(
    'a styled family emoji within one original context stays one target',
    () {
      final input = _prepare(
        _mixed(prefix: '<span>👩</span><b>‍👩‍</b><i>👧‍👦</i>', suffix: ''),
      ).input;
      expect(input.units, hasLength(1));
      expect(
        (input.units.single.startUtf16, input.units.single.endUtf16),
        (0, '👩‍👩‍👧‍👦'.length),
      );
    },
  );
  for (final (html, text, ranges, mark) in [
    (
      '<span>e</span><i style="text-emphasis:none">́</i>',
      'é',
      [(0, 1, 0)],
      '●',
    ),
    (
      '<span style="text-emphasis:none">؀</span><b style="text-emphasis:triangle">١</b>',
      '؀١',
      [(1, 2, 1)],
      '▲',
    ),
    ('<span>🇨</span><b>🇳</b>', '🇨🇳', [(0, 2, 0), (2, 4, 2)], '●'),
  ]) {
    test(
      'independent context fences retain the original grapheme ranges $text',
      () {
        final content = _contexts(html, 2);
        expect(content.projection.display.text, text);
        final input = _prepare(content).input;
        expect(
          input.units.map((u) => (u.startUtf16, u.endUtf16, u.governingUtf16)),
          ranges,
        );
        for (final u in input.units) {
          expect(content.runs[u.runIndex].style.textEmphasis.mark, mark);
        }
      },
    );
  }
  test(
    'literal replacement character stays a parent target beside a real atom',
    () {
      final input = _prepare(_mixed(prefix: '\uFFFC', suffix: '')).input;
      expect(input.units, hasLength(1));
      expect(
        (input.units.single.startUtf16, input.units.single.endUtf16),
        (0, 1),
      );
      expect(input.content.projection.atoms.single.displayStartUtf16, 1);
    },
  );
  test('long child text costs no extra parent classification steps', () {
    final short = _prepare(_mixed()),
        long = _prepare(_mixed(base: 'B' * 2000, annotation: 'x' * 2000));
    expect(short.parts, long.parts);
    expect(long.parts, lessThan(100));
    expect(long.input.units, hasLength(2));
    expect(long.input.units.last.startUtf16, 4001);
  });
  test(
    'a pathological parent combining cluster is processed one scalar per part',
    () {
      final text = 'e${'́' * 2048}';
      final result = _prepare(_mixed(prefix: text, suffix: ''), maxUnits: 1);
      expect(result.parts, greaterThan(2048));
      expect(result.input.units, hasLength(1));
      expect(result.input.units.single.endUtf16, text.length);
    },
  );
  test('soft glue and both real neighbouring atoms have no parent targets', () {
    final f = RubySoftSpaceRowFixture();
    addTearDown(f.close);
    expect(f.content.projection.hasSoftSpaces, isTrue);
    final input = _prepare(f.content, maxUnits: 0).input;
    expect(input.units, isEmpty);
    expect(input.content.contexts, same(f.content.contexts));
    expect(input.nativeFontSizes.toSet(), {20.0});
  });
  test(
    'font samples include actual parent and half marker sizes, excluding child-only fonts',
    () {
      final input = _prepare(
        _mixed(
          prefix:
              '<span style="font-size:26px">甲</span><span style="font-size:18px">乙</span>',
          annotation: '<span style="font-size:50px">x</span>',
          suffix: '',
        ),
      ).input;
      expect(input.nativeFontSizes.toSet(), {20.0, 26.0, 18.0, 13.0, 9.0});
    },
  );
  test(
    'fromGlyphInput retains the exact supplied association without repeating derivation',
    () {
      final content = _mixed(prefix: '甲é', suffix: '👩‍👩‍👧‍👦'),
          first = _prepare(content);
      final repeated = _prepare(content, glyphInput: first.input.glyphInput);
      expect(repeated.input.glyphInput, same(first.input.glyphInput));
      expect(repeated.parts, lessThan(first.parts));
      expect(_units(repeated.input), _units(first.input));
    },
  );
  test(
    'empty and all-atomic input can use zero targets; overflow retires the worker',
    () {
      final content = _mixed(prefix: '', suffix: '');
      expect(_prepare(content, maxUnits: 0).input.units, isEmpty);
      final empty = _contexts('', 0);
      expect(_prepare(empty, maxUnits: 0).input.units, isEmpty);
      final work = ForumBodyInlineEmphasisTextPreparation(
        content: _mixed(),
        maxUnits: 1,
        ensureOwner: () {},
      );
      expect(
        () {
          while (!work.isReady) {
            work.advance(maxParts: 1);
          }
        },
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphInputFailure.inputLimit,
          ),
        ),
      );
      expect(work.isReady, isFalse);
      expect(work.takeInput, throwsStateError);
      work.close();
      expect(
        () => ForumBodyInlineEmphasisTextPreparation(
          content: content,
          maxUnits: -1,
          ensureOwner: () {},
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'every classification and publication boundary rejects retired owners',
    () {
      final content = _mixed(prefix: '<span>e</span><i>́</i>'),
          parts = _prepare(content).parts;
      for (var boundary = 0; boundary <= parts; boundary++) {
        var active = true;
        final work = ForumBodyInlineEmphasisTextPreparation(
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
    },
  );
  test('reentry or owner close cannot publish a target list', () {
    for (final reenter in [false, true]) {
      late ForumBodyInlineEmphasisTextPreparation work;
      work = ForumBodyInlineEmphasisTextPreparation(
        content: _mixed(),
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
}
