import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyReaderStyle reader({
  ForumBodyLength indent = ForumBodyLength.zero,
  TextDirection direction = TextDirection.ltr,
  TextAlign alignment = TextAlign.start,
  ForumBodyStylePolicy? policy,
}) => ForumBodyReaderStyle(
  textStyle: const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 10,
    height: 1,
    color: Color(0xff000000),
  ),
  fontRevision: 'indent-test',
  linkColor: const Color(0xff0000ff),
  paragraphAfter: 0,
  firstLineIndent: indent,
  textDirection: direction,
  textAlign: alignment,
  policy: policy,
);

ForumBodyDocument parse(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'indent',
  conversionIdentity: 'none',
);

ForumBodyParagraphContent content(
  String html, {
  ForumBodyReaderStyle? options,
}) {
  final body = parse(html);
  return const ForumBodyParagraphContentBuilder().build(
    document: body,
    styles: const ForumBodyStyleResolver().resolve(body, options ?? reader()),
    path: '0',
  );
}

const limits = ForumBodyTextPageSessionLimits(
  maxPages: 100,
  maxFragments: 100,
  maxParagraphs: 100,
  maxTextCodeUnits: 1000,
  maxRuns: 100,
  maxIssuedLeases: 100,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });

  for (final direction in TextDirection.values) {
    for (final alignment in [
      TextAlign.start,
      TextAlign.center,
      TextAlign.end,
      TextAlign.justify,
    ]) {
      test(
        'real first-line advance and continuation positions $direction $alignment',
        () {
          final input = content(
            '<p style="text-indent:20px">abcdefgh ijklmnop</p>',
            options: reader(direction: direction, alignment: alignment),
          );
          final layout = ForumBodyParagraphLayout.create(
            content: input,
            width: 60,
          );
          addTearDown(layout.dispose);
          expect(layout.lines.first.coverageEndUtf16, 4);
          expect(layout.lines.first.engineCoverageEndUtf16, 6);
          final first = layout.selectionBoxes(0, 4).single;
          expect(
            first.left,
            closeTo(direction == TextDirection.ltr ? 20 : 0, 1e-3),
          );
          expect(
            first.right,
            closeTo(direction == TextDirection.ltr ? 60 : 40, 1e-3),
          );
          expect(layout.lines[1].coverageStartUtf16, 4);
          expect(
            layout.lines.first.bottom - layout.lines.first.top,
            closeTo(10, 1e-3),
          );
          expect(layout.projection.text, 'abcdefgh ijklmnop');
          final hit = layout.sourceAt(Offset(first.left + 1, 5));
          expect(hit.sourceRune, inInclusiveRange(0, 4));
          expect(
            layout
                .sourceAt(Offset(direction == TextDirection.ltr ? 1 : 59, 5))
                .isExact,
            isFalse,
          );
        },
      );
    }
  }

  test('reader em uses the actual nonlinear root scale exactly once', () {
    final input = content(
      '<p>abcdefgh</p>',
      options: reader(indent: const ForumBodyLength(2, ForumBodyLengthUnit.em)),
    );
    final layout = ForumBodyParagraphLayout.create(
      content: input,
      width: 100,
      textScaler: const _Scaler(),
    );
    addTearDown(layout.dispose);
    expect(
      input.style.indent,
      const ForumBodyLength(2, ForumBodyLengthUnit.em),
    );
    expect(layout.selectionBoxes(0, 1).single.left, closeTo(30, 1e-3));
    expect(layout.selectionBoxes(0, 1).single.right, closeTo(45, 1e-3));
  });

  test('percent indentation resolves against each current content width', () {
    final input = content('<p style="text-indent:25%">abcdef</p>');
    final cache = ForumBodyParagraphCache(
      maxEntries: 10,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    for (final width in [80.0, 120.0, 80.0]) {
      final lease = cache.acquire(content: input, width: width);
      expect(
        lease.layout.selectionBoxes(0, 1).single.left,
        closeTo(width / 4, 1e-3),
      );
      lease.release();
    }
    expect(cache.layoutBuildCount, 2);
  });

  test(
    'mechanical prefix preserves leading marks and whole emoji coverage',
    () {
      for (final text in ['\u0301a', '👩‍👩‍👧‍👦a', 'a\u0301b']) {
        final input = content('<p style="text-indent:20px">$text</p>');
        final layout = ForumBodyParagraphLayout.create(
          content: input,
          width: 200,
        );
        addTearDown(layout.dispose);
        expect(layout.projection.text, text);
        expect(layout.lines.single.coverageStartUtf16, 0);
        expect(layout.lines.single.coverageEndUtf16, text.length);
        expect(layout.lines.single.engineCoverageEndUtf16, text.length + 2);
        expect(layout.selectionBoxes(0, text.length), isNotEmpty);
        expect(layout.sourceAt(const Offset(1, 5)).isExact, isFalse);
      }
    },
  );

  test('unrepresentable narrow indents fail without a prefix-only page', () {
    for (final width in [10.0, 20.0]) {
      expect(
        () => ForumBodyParagraphLayout.create(
          content: content('<p style="text-indent:20px">a</p>'),
          width: width,
        ),
        throwsA(
          isA<ForumBodyParagraphLayoutException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParagraphLayoutFailure.indent,
          ),
        ),
      );
    }
  });

  test(
    'forced reader em and explicit author layout lengths remain distinct',
    () {
      final source = '<p style="text-indent:2em">abcdefgh</p>';
      final author = ForumBodyParagraphLayout.create(
        content: content(source),
        width: 100,
        textScaler: const _Scaler(),
      );
      final forced = ForumBodyParagraphLayout.create(
        content: content(
          source,
          options: reader(
            indent: const ForumBodyLength(2, ForumBodyLengthUnit.em),
            policy: ForumBodyStylePolicy({
              ForumBodyStyleProperty.textIndent: ForumBodyStyleScope.forceBody,
            }),
          ),
        ),
        width: 100,
        textScaler: const _Scaler(),
      );
      addTearDown(author.dispose);
      addTearDown(forced.dispose);
      expect(author.selectionBoxes(0, 1).single.left, closeTo(20, 1e-3));
      expect(forced.selectionBoxes(0, 1).single.left, closeTo(30, 1e-3));
    },
  );

  test(
    'manual preserved whitespace suppresses reader addition without rewriting source',
    () {
      for (final space in ['\u3000', '\u00a0', ' ']) {
        final input = content(
          '<p style="white-space:pre-wrap">${space}ab</p>',
          options: reader(
            indent: const ForumBodyLength(2, ForumBodyLengthUnit.em),
          ),
        );
        final layout = ForumBodyParagraphLayout.create(
          content: input,
          width: 100,
        );
        addTearDown(layout.dispose);
        expect(input.projection.text, '${space}ab');
        expect(
          layout.lines.first.engineCoverageEndUtf16,
          input.projection.text.length,
        );
        expect(layout.selectionBoxes(1, 2).single.left, closeTo(10, 1e-3));
      }
      final explicit = ForumBodyParagraphLayout.create(
        content: content('<p style="text-indent:20px">\u3000ab</p>'),
        width: 100,
      );
      addTearDown(explicit.dispose);
      expect(explicit.selectionBoxes(1, 2).single.left, closeTo(30, 1e-3));
    },
  );

  test('one painter carries the indent across pages only on its first row', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 10,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final session = ForumBodyTextPageSession(
      document: parse(
        '<p style="text-indent:20px">abcdefghijklmnopqrstuvwx</p>',
      ),
      reader: reader(),
      cache: cache,
      limits: limits,
      layoutId: 'indent-pages',
      width: 60,
      height: 10,
    );
    addTearDown(session.close);
    for (var step = 0; !session.isComplete; step++) {
      if (step > 100) fail('Indent session did not finish');
      session.advance(maxEvents: 32, maxLines: 8);
    }
    expect(session.snapshot.first.fragments.single.coverageEndUtf16, 4);
    expect(session.snapshot[1].fragments.single.coverageStartUtf16, 4);
    expect(session.snapshot[1].fragments.single.coverageEndUtf16, 10);
    expect(session.snapshot.last.fragments.single.coverageEndUtf16, 24);
    expect(cache.layoutBuildCount, 1);
    expect(cache.activeLeases, 0);
  });

  test(
    'BR continuations including ruby retire indentation, new blocks own it again',
    () {
      final body = parse(
        '<p style="text-indent:20px">ab<br>cd<br><ruby>e<rt>x</rt></ruby></p>'
        '<p style="text-indent:20px">fg</p>',
      );
      final flow = ForumBodyTextFlowCursor(document: body, reader: reader());
      addTearDown(flow.close);
      final owned = <bool>[];
      while (!flow.isComplete) {
        flow.advance(maxEvents: 1);
        switch (flow.current) {
          case ForumBodyTextFlowParagraph(:final content):
            owned.add(content.appliesFirstLineIndent);
          case ForumBodyTextFlowInline(:final content):
            owned.add(content.appliesFirstLineIndent);
          default:
            break;
        }
      }
      expect(owned, [true, false, false, true]);
      final cache = ForumBodyParagraphCache(
        maxEntries: 20,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final session = ForumBodyTextPageSession(
        document: body,
        reader: reader(),
        cache: cache,
        limits: limits,
        layoutId: 'br-indent',
        width: 100,
        height: 100,
      );
      addTearDown(session.close);
      for (var step = 0; !session.isComplete; step++) {
        if (step > 1000) fail('BR indent session did not finish');
        session.advance(maxEvents: 32, maxLines: 8);
      }
      expect(session.snapshot, isNotEmpty);
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'cache and budget admission distinguish actual indent from the same continuation',
    () {
      final input = content('<p style="text-indent:20px">a</p>');
      final cache = ForumBodyParagraphCache(
        maxEntries: 10,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final first = cache.acquire(content: input, width: 100);
      final bytes = cache.estimatedRetainedBytes;
      first.release();
      cache.clearUnpinned();
      final continuation = cache.acquire(
        content: input.withFirstLineIndent(false),
        width: 100,
      );
      expect(bytes - cache.estimatedRetainedBytes, 192);
      expect(continuation.layout.selectionBoxes(0, 1).single.left, 0);
      final rebuilt = cache.acquire(content: input, width: 100);
      expect(
        rebuilt.layout.selectionBoxes(0, 1).single.left,
        closeTo(20, 1e-3),
      );
      expect(cache.layoutBuildCount, 3);
      continuation.release();
      rebuilt.release();
    },
  );

  test(
    'prefix has no painted ink and selection excludes its source-free cells',
    () async {
      final input = content('<p style="text-indent:20px">a</p>');
      final layout = ForumBodyParagraphLayout.create(
        content: input,
        width: 100,
      );
      addTearDown(layout.dispose);
      final recorder = ui.PictureRecorder();
      layout.paint(Canvas(recorder), Offset.zero);
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 20);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      try {
        var ink = 0;
        for (var y = 0; y < 20; y++) {
          for (var x = 0; x < 30; x++) {
            final alpha = pixels.getUint8((y * 100 + x) * 4 + 3);
            if (x < 20) {
              expect(alpha, 0);
            } else {
              ink += alpha;
            }
          }
        }
        expect(ink, greaterThan(0));
        expect(layout.selectionBoxes(0, 1).single.left, closeTo(20, 1e-3));
        expect(input.projection.text, 'a');
      } finally {
        image.dispose();
        picture.dispose();
      }
    },
  );
}

final class _Scaler extends TextScaler {
  const _Scaler();
  @override
  double scale(double size) => size <= 10 ? size * 1.5 : size * 1.2;
  @override
  double get textScaleFactor => 1.5;
}
