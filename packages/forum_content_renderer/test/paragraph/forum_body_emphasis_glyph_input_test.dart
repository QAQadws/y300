import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_emphasis_text_input.dart';

const _emphasis = 'text-emphasis:open sesame red;';
const _html =
    '<p style="$_emphasis text-align:center;line-height:1.3;'
    'letter-spacing:.5px;text-indent:1em;margin:2px;padding:1px;">'
    'ffi <b>é</b> <small>ع</small> العربية 👩‍👩‍👧‍👦 中 '
    '<span style="visibility:hidden">隐</span><a href="/synthetic">链</a></p>';
ForumBodyParagraphContent _content(
  String html, {
  ForumBodyParagraphLayoutMode mode = ForumBodyParagraphLayoutMode.wrap,
  TextDirection direction = TextDirection.ltr,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'emphasis-glyphs',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        color: Color(0xff123456),
        wordSpacing: 2,
      ),
      fontRevision: 'glyph-input-font',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    ),
  );
  final content = const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: styles,
    path: '0',
    layoutMode: mode,
  );
  return mode == ForumBodyParagraphLayoutMode.fitSingleLine
      ? content.withFirstLineIndent(false)
      : content;
}

ForumBodyEmphasisGlyphInput _prepare(
  ForumBodyParagraphContent content, {
  int quantum = 1,
}) {
  final job = ForumBodyEmphasisGlyphPreparation(content: content);
  try {
    var steps = 0;
    while (!job.isReady) {
      expect(job.advance(maxParts: quantum), inInclusiveRange(1, quantum));
      expect(++steps, lessThan(1000));
    }
    expect(job.advance(maxParts: quantum), 0);
    return job.takeInput();
  } finally {
    job.close();
  }
}

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double fontSize) =>
      fontSize < 18 ? fontSize * 1.4 : fontSize * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual font sizes');
}

Future<List<int>> _pixels(ForumBodyParagraphLayout layout, int dpr) async {
  final recorder = ui.PictureRecorder();
  layout.paint(Canvas(recorder)..scale(dpr.toDouble()), const Offset(10, 10));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(260 * dpr, 260 * dpr);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  test(
    'derivation preserves actual source, native styles and interaction metadata',
    () {
      final original = _content(_html);
      final input = _prepare(original);
      final glyphs = input.glyphs;
      expect(input.original, same(original));
      expect(glyphs, isNot(same(original)));
      expect(glyphs.identity, original.identity);
      expect(glyphs.path, original.path);
      expect(glyphs.projection, same(original.projection));
      expect(glyphs.fontRevision, original.fontRevision);
      expect(glyphs.styleRevision, original.styleRevision);
      expect(glyphs.layoutMode, original.layoutMode);
      expect(glyphs.appliesFirstLineIndent, original.appliesFirstLineIndent);
      expect(glyphs.issues, same(original.issues));
      expect(glyphs.style.textStyle, same(original.style.textStyle));
      expect(glyphs.style.margin, same(original.style.margin));
      expect(glyphs.style.padding, same(original.style.padding));
      expect(glyphs.style.box, same(original.style.box));
      expect(glyphs.style.lineHeight, same(original.style.lineHeight));
      expect(glyphs.style.indent, original.style.indent);
      expect(
        glyphs.style.alignmentFromReader,
        original.style.alignmentFromReader,
      );
      expect(glyphs.style.indentFromReader, original.style.indentFromReader);
      expect(glyphs.style.textEmphasis.isEnabled, isFalse);
      expect(original.style.textEmphasis.mark, '﹆');
      expect(glyphs.runs, hasLength(original.runs.length));
      for (var index = 0; index < original.runs.length; index++) {
        final from = original.runs[index], to = glyphs.runs[index];
        expect(to.path, from.path);
        expect(to.style.textStyle, same(from.style.textStyle));
        expect(to.style.role, from.style.role);
        expect(to.style.linkTarget, from.style.linkTarget);
        expect(to.style.strong, from.style.strong);
        expect(to.style.visibilityHidden, from.style.visibilityHidden);
        expect(to.style.ownDecoration, from.style.ownDecoration);
        expect(to.style.ownBackground, from.style.ownBackground);
        expect(to.style.textEmphasis.isEnabled, isFalse);
      }
      expect(() => glyphs.runs.clear(), throwsUnsupportedError);
      expect(original.runs.any((run) => run.style.visibilityHidden), isTrue);
      expect(
        original.runs.any((run) => run.style.linkTarget == '/synthetic'),
        isTrue,
      );
    },
  );
  for (final mode in ForumBodyParagraphLayoutMode.values) {
    for (final direction in TextDirection.values) {
      for (final dpr in [1, 3]) {
        test(
          'whole base $mode $direction DPR$dpr matches original plain native shaping',
          () async {
            final original = _content(_html, mode: mode, direction: direction);
            final input = _prepare(original);
            final reference = _content(
              _html.replaceFirst(_emphasis, ''),
              mode: mode,
              direction: direction,
            );
            final cache = ForumBodyParagraphCache(
              maxEntries: 8,
              maxEstimatedBytes: 1 << 24,
            );
            try {
              expect(
                () => cache.acquire(
                  content: original,
                  width: 180,
                  textScaler: const _Nonlinear(),
                ),
                throwsA(
                  isA<ForumBodyParagraphLayoutException>().having(
                    (e) => e.failure,
                    'failure',
                    ForumBodyParagraphLayoutFailure.emphasis,
                  ),
                ),
              );
              expect(cache.layoutBuildCount, 0);
              final glyphs = cache.acquire(
                content: input.glyphs,
                width: 180,
                textScaler: const _Nonlinear(),
              );
              final plain = cache.acquire(
                content: reference,
                width: 180,
                textScaler: const _Nonlinear(),
              );
              try {
                expect(glyphs.layout.width, plain.layout.width);
                expect(glyphs.layout.height, plain.layout.height);
                expect(
                  glyphs.layout.lines,
                  hasLength(plain.layout.lines.length),
                );
                expect(
                  await _pixels(glyphs.layout, dpr),
                  await _pixels(plain.layout, dpr),
                );
                expect(
                  input.glyphs.projection.hasSameSourceMapping(
                    reference.projection,
                  ),
                  isTrue,
                );
                for (final range in original.projection.graphemeRanges(
                  startUtf16: 0,
                  endUtf16: original.projection.text.length,
                )) {
                  expect(
                    glyphs.layout.selectionBoxes(
                      range.startUtf16,
                      range.endUtf16,
                    ),
                    plain.layout.selectionBoxes(
                      range.startUtf16,
                      range.endUtf16,
                    ),
                  );
                }
                final point = Offset(
                  glyphs.layout.width * .5,
                  glyphs.layout.height * .5,
                );
                final hit = glyphs.layout.sourceAt(point),
                    expected = plain.layout.sourceAt(point);
                expect(
                  (hit.sourceRune, hit.displayUtf16, hit.isExact),
                  (
                    expected.sourceRune,
                    expected.displayUtf16,
                    expected.isExact,
                  ),
                );
                expect(
                  () => cache.acquire(content: original, width: 180),
                  throwsA(isA<ForumBodyParagraphLayoutException>()),
                );
              } finally {
                glyphs.release();
                plain.release();
              }
            } finally {
              cache.close();
            }
            expect(cache.activeLeases, 0);
            expect(cache.estimatedRetainedBytes, 0);
          },
        );
      }
    }
  }
  test(
    'no active marker reuses original input and suppression keeps other failures',
    () {
      final plain = _content('<p>A<b>B</b></p>');
      expect(_prepare(plain).glyphs, same(plain));
      final invalid = _content(
        '<p style="text-emphasis:dot;white-space:pre">A B</p>',
      );
      final glyphs = _prepare(invalid).glyphs;
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      try {
        expect(
          () => cache.acquire(content: glyphs, width: 100),
          throwsA(
            isA<ForumBodyParagraphLayoutException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphLayoutFailure.noWrap,
            ),
          ),
        );
        expect(cache.layoutBuildCount, 0);
      } finally {
        cache.close();
      }
    },
  );
  test(
    'long style table is cooperative and retired writer cannot mutate its output',
    () {
      final original = _content(
        '<p style="text-emphasis:dot">${List.generate(160, (i) => '<span style="font-size:${12 + i % 5}px">x</span>').join()}</p>',
      );
      final job = ForumBodyEmphasisGlyphPreparation(content: original);
      expect(() => job.takeInput(), throwsStateError);
      var calls = 0;
      while (!job.isReady) {
        expect(job.advance(maxParts: 1), 1);
        calls++;
      }
      expect(calls, original.runs.length + 2);
      final input = job.takeInput();
      job.close();
      expect(() => job.advance(maxParts: 1), throwsStateError);
      expect(() => job.takeInput(), throwsStateError);
      expect(input.glyphs.runs, hasLength(160));
      expect(() => input.glyphs.runs.removeLast(), throwsUnsupportedError);
      expect(
        input.original.runs.every((run) => run.style.textEmphasis.isEnabled),
        isTrue,
      );
      expect(
        input.glyphs.runs.every((run) => !run.style.textEmphasis.isEnabled),
        isTrue,
      );
    },
  );
  test('cancellation at every style phase drops incomplete derivation', () {
    final original = _content(_html);
    for (var steps = 0; steps <= original.runs.length + 2; steps++) {
      final job = ForumBodyEmphasisGlyphPreparation(content: original);
      for (var i = 0; i < steps && !job.isReady; i++) {
        job.advance(maxParts: 1);
      }
      job.close();
      job.close();
      expect(job.isReady, isFalse);
      expect(() => job.takeInput(), throwsStateError);
      expect(() => job.advance(maxParts: 1), throwsStateError);
      expect(original.style.textEmphasis.isEnabled, isTrue);
    }
  });
  test(
    'source window keeps its own source mapping and original run indices',
    () {
      final all = _content('<p style="text-emphasis:dot">前👩‍👩‍👧‍👦é后</p>');
      final original = all.displayWindow(
        startUtf16: 1,
        endUtf16: 1 + '👩‍👩‍👧‍👦é'.length,
      );
      final job = ForumBodyEmphasisTextPreparation(content: original);
      while (!job.isReady) {
        expect(job.advance(maxParts: 1), 1);
      }
      final input = job.takeInput();
      expect(input.content, same(original));
      expect(input.glyphInput.original, same(original));
      expect(input.glyphInput.glyphs.projection, same(original.projection));
      expect(input.units, hasLength(2));
      expect(input.units.first.startUtf16, 0);
      expect(input.glyphInput.glyphs.projection.sourceAtUtf16(0).sourceRune, 1);
      expect(input.units.last.endUtf16, original.projection.text.length);
      expect(input.glyphInput.glyphs.runs, hasLength(all.runs.length));
    },
  );
  test(
    'empty actual source and inactive children do not invent marker or source text',
    () {
      for (final html in [
        '<p style="text-emphasis:dot"></p>',
        '<p style="text-emphasis:dot"><span style="text-emphasis:none">A</span></p>',
      ]) {
        final original = _content(html);
        final job = ForumBodyEmphasisTextPreparation(content: original);
        while (!job.isReady) {
          job.advance(maxParts: 3);
        }
        final input = job.takeInput();
        expect(input.units, isEmpty);
        expect(input.glyphInput.glyphs.projection, same(original.projection));
        expect(input.glyphInput.glyphs.isSourceFree, isFalse);
        expect(input.glyphInput.original.style.textEmphasis.isEnabled, isTrue);
        expect(input.glyphInput.glyphs.style.textEmphasis.isEnabled, isFalse);
      }
    },
  );
  test(
    'source-free struts and excess styles cannot enter the actual base derivation',
    () {
      final original = _content('<p>A<b>B</b></p>');
      final empty = ForumBodyParagraphContent.anonymousInline(
        identity: original.identity,
        fontRevision: original.fontRevision,
        styleRevision: original.styleRevision,
        style: original.style,
      );
      expect(
        () => ForumBodyEmphasisGlyphPreparation(content: empty),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyEmphasisGlyphPreparation(content: original, maxRuns: 1),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphInputFailure.runLimit,
          ),
        ),
      );
      expect(
        () => ForumBodyEmphasisGlyphPreparation(content: original, maxRuns: -1),
        throwsArgumentError,
      );
      final job = ForumBodyEmphasisGlyphPreparation(content: original);
      expect(() => job.advance(maxParts: 0), throwsArgumentError);
      job.close();
    },
  );
}
