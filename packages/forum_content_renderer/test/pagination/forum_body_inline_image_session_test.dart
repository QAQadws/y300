import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../inline/test_support/inline_image_fixture.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
  fontRevision: 'inline-images',
  linkColor: const Color(0xff0000ff),
  paragraphBefore: 0,
  paragraphAfter: 0,
);

final class _Fixture {
  _Fixture(
    String html, {
    double width = 100,
    double height = 100,
    int imageCapacity = 16,
    int? pageImages,
    int textLimit = 10000,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'inline-image-session',
      conversionIdentity: 'none',
    );
    session = ForumBodyTextPageSession(
      document: document,
      reader: _reader,
      cache: cache,
      limits: ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 1000,
        maxParagraphs: 100,
        maxTextCodeUnits: textLimit,
        maxRuns: 1000,
        maxIssuedLeases: 16,
        maxIssuedImages: imageCapacity,
      ),
      layoutId: 'inline-image-session',
      width: width,
      height: height,
      maxImagesPerPage: pageImages,
      textScaler: textScaler,
      inlineImageResolver: (identity, element, style) {
        expect(identity, document.identity);
        final input = ForumBodyInlineImageInput(
          document: document,
          element: element,
          image: const InlineImageDescription(),
          dimensions: inlineImageDimensions(const Size(40, 20)),
        );
        images.add(input);
        return input;
      },
    );
    addTearDown(() {
      session.close();
      cache.close();
    });
  }
  late final ForumBodyDocument document;
  late final ForumBodyTextPageSession session;
  final cache = ForumBodyParagraphCache(
    maxEntries: 32,
    maxEstimatedBytes: 1 << 24,
  );
  final images = <ForumBodyInlineImageInput>[];

  void finish() {
    for (var i = 0; !session.isComplete && i < 10000; i++) {
      final step = session.advance(
        maxEvents: 1,
        maxLines: 1,
        maxFormatParts: 1,
      );
      expect(step.layoutsBuilt, lessThanOrEqualTo(1));
      expect(step.linesInspected, lessThanOrEqualTo(1));
      expect(step.pagesPublished, lessThanOrEqualTo(1));
      expect(step.madeProgress, isTrue);
    }
    expect(session.isComplete, isTrue);
  }

  List<ForumBodyPreparedTextFragment> prepare(int page) {
    final job = session.openPagePreparation(page);
    return take(job);
  }

  List<ForumBodyPreparedTextFragment> take(ForumBodyTextPagePreparation job) {
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real traversal produces text and distinct inline image source bindings',
    () {
      final f = _Fixture('<p>A<img src="a"><img src="a">B</p>');
      f.finish();
      final page = f.session.snapshot.single;
      expect(page.fragments.single.kind, ForumBodyTextPageFragmentKind.inline);
      final prepared = f.prepare(0);
      final view = (prepared.single as ForumBodyPreparedInlineFragment).view;
      expect(view.content.projection.display.text, 'AB');
      expect(view.images.values.map((i) => i.input), f.images);
      expect(view.nativeLeases, hasLength(1));
      expect(view.atomIndices, isEmpty);
      expect(view.engineRange, page.fragments.single.engineRange);
      prepared.single.close();
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'resource-only pages share no text interval but keep unique engine windows',
    () {
      final f = _Fixture(
        '<p><img src="a"><img src="a"><img src="a"></p>',
        width: 50,
        height: 30,
      );
      f.finish();
      expect(f.session.snapshot, hasLength(3));
      for (var i = 0; i < 3; i++) {
        final fragment = f.session.snapshot[i].fragments.single;
        expect(
          (fragment.coverageStartUtf16, fragment.coverageEndUtf16),
          (0, 0),
        );
        expect(fragment.sourceHint, isNull);
        expect(fragment.engineRange, (startUtf16: i, endUtf16: i + 1));
        expect(fragment.imageCount, 1);
        final prepared = f.prepare(i);
        final view = (prepared.single as ForumBodyPreparedInlineFragment).view;
        expect(view.images.keys, [i]);
        expect(view.images[i]!.input, same(f.images[i]));
        expect(view.engineRange, fragment.engineRange);
        expect(view.glyphBoxes(0, 0), isEmpty);
        expect(view.sourceAt(view.images[i]!.rect.center).isExact, isFalse);
        prepared.single.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test('image after BR survives terminal normalization as a separate row', () {
    final f = _Fixture('<p>A<br><img src="a"></p>');
    f.finish();
    final prepared = f.prepare(0);
    expect(prepared, hasLength(2));
    expect(prepared.first.projection.text, 'A\n');
    final view = (prepared.last as ForumBodyPreparedInlineFragment).view;
    expect(view.content.projection.display.text, isEmpty);
    expect(view.images, hasLength(1));
    for (final p in prepared) {
      p.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  test(
    'single-level ruby and adjacent images retain actual base and RT sources',
    () {
      final f = _Fixture(
        '<p><img src="a"><ruby>A<rt>a</rt></ruby><img src="a"></p>',
        width: 150,
      );
      f.finish();
      final prepared = f.prepare(0);
      final view = (prepared.single as ForumBodyPreparedInlineFragment).view;
      expect(view.images.keys, [0, 2]);
      expect(view.atomIndices, [1]);
      expect(view.content.projection.display.text, 'Aa');
      expect(view.nativeLeases, hasLength(3));
      expect(view.images.values.map((i) => i.input), f.images);
      expect(
        view.content.runs.map((r) => r.path),
        containsAll(['0/1/0', '0/1/1/0']),
      );
      prepared.single.close();
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'per-page image budget splits a zero-text continuation by actual rows',
    () {
      final f = _Fixture(
        '<p><img src="a"><img src="a"><img src="a"></p>',
        width: 50,
        pageImages: 1,
      );
      f.finish();
      expect(f.session.snapshot, hasLength(3));
      for (var i = 0; i < 3; i++) {
        final fragment = f.session.snapshot[i].fragments.single;
        expect(
          (fragment.startLine, fragment.endLine, fragment.imageCount),
          (i, i + 1, 1),
        );
        expect(fragment.engineRange, (startUtf16: i, endUtf16: i + 1));
        final bindings = f.prepare(i);
        expect(f.session.activeIssuedImages, 1);
        expect(f.session.activeIssuedLeases, 1);
        bindings.single.close();
        expect(f.session.activeIssuedImages, 0);
      }
    },
  );

  test(
    'an indivisible image row over budget keeps a materializable published prefix',
    () {
      final f = _Fixture(
        '<p>A</p><p><img src="a"><img src="a"></p>',
        pageImages: 1,
      );
      expect(
        f.finish,
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageFailure.imageLimit,
          ),
        ),
      );
      expect(f.session.state, ForumBodyTextPageSessionState.failed);
      expect(f.session.snapshot, hasLength(1));
      final bindings = f.prepare(0);
      expect(bindings.single.projection.text, 'A');
      bindings.single.close();
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'reservations and transferred image bindings use an independent capacity',
    () {
      final f = _Fixture(
        '<p><img src="a"><img src="a"><img src="a"></p>',
        width: 50,
        imageCapacity: 2,
        pageImages: 1,
      );
      f.finish();
      final first = f.session.openPagePreparation(0);
      final second = f.session.openPagePreparation(1);
      expect((first.expectedImageCount, second.expectedImageCount), (1, 1));
      expect(f.session.reservedViewImages, 2);
      expect(
        () => f.session.openPagePreparation(2),
        throwsA(
          isA<ForumBodyTextPageSessionException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageSessionFailure.imageLimit,
          ),
        ),
      );
      first.close();
      expect(f.session.reservedViewImages, 1);
      final current = f.take(second);
      expect(f.session.reservedViewImages, 0);
      expect(f.session.activeIssuedImages, 1);
      expect(f.session.activeIssuedLeases, 1);
      final next = f.session.openPagePreparation(2);
      expect(f.session.reservedViewImages, 1);
      current.single.close();
      expect(f.session.activeIssuedImages, 0);
      f.session.close();
      expect(next.state, ForumBodyTextPagePreparationState.closed);
      expect(f.session.reservedViewImages, 0);
      expect(f.cache.activeLeases, 0);
    },
  );

  test('accepted frames and resource handles retire with their Session', () {
    final f = _Fixture('<p>A<img src="a">B</p>');
    f.finish();
    final prepared = f.prepare(0);
    final view = (prepared.single as ForumBodyPreparedInlineFragment).view;
    final image = view.images.values.single;
    image.reportDisplayFrame(true);
    expect(image.hasRenderedFrame, isTrue);
    f.session.close();
    expect(prepared.single.isActive, isFalse);
    expect(image.reportDisplayFrame(true), isFalse);
    expect(image.hasRenderedFrame, isFalse);
    expect(f.session.activeIssuedImages, 0);
    expect(f.cache.activeLeases, 0);
  });

  test(
    'resource strings enter retained text budgets without becoming display text',
    () {
      final f = _Fixture(
        '<p><img src="a" alt="server description"></p>',
        textLimit: 8,
      );
      expect(
        f.finish,
        throwsA(
          isA<ForumBodyTextPageSessionException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageSessionFailure.textLimit,
          ),
        ),
      );
      expect(f.session.snapshot, isEmpty);
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'whitespace on either side of an image keeps its actual source seam',
    () {
      final f = _Fixture('<p>  A  <img src="a">  B  </p>');
      f.finish();
      final prepared = f.prepare(0);
      final view = (prepared.single as ForumBodyPreparedInlineFragment).view;
      expect(view.content.projection.display.text, 'A  B');
      expect(view.content.projection.atoms.single.displayStartUtf16, 2);
      expect(view.images.values.single.input, same(f.images.single));
      prepared.single.close();
    },
  );

  test('text scaling preserves already resolved image dimensions', () {
    final f = _Fixture(
      '<p>A<img src="a">B</p>',
      textScaler: TextScaler.linear(2),
    );
    f.finish();
    final prepared = f.prepare(0);
    final view = (prepared.single as ForumBodyPreparedInlineFragment).view;
    final image = view.images.values.single;
    expect(image.rect.size, const Size(40, 20));
    expect(view.glyphBoxes(0, 1).single.toRect().width, 20);
    prepared.single.close();
  });

  test('unclassified and explicitly block images retain the block flow', () {
    final document = const ForumBodyParser().parse(
      html: '<p>A<img src="a"><img src="b" style="display:block">B</p>',
      sourceId: 'inline-classification',
      conversionIdentity: 'none',
    );
    var calls = 0;
    final cursor = ForumBodyTextFlowCursor(
      document: document,
      reader: _reader,
      inlineImageResolver: (_, element, _) {
        calls++;
        return null;
      },
    );
    addTearDown(cursor.close);
    final outputs = <ForumBodyTextFlowUnit>[];
    for (var i = 0; !cursor.isComplete && i < 1000; i++) {
      final step = cursor.advance(maxEvents: 1);
      if (step.hasOutput) outputs.add(cursor.current!);
    }
    expect(cursor.isComplete, isTrue);
    expect(calls, 1);
    expect(
      outputs.whereType<ForumBodyTextFlowImage>().map((i) => i.event.node.path),
      ['0/1', '0/2'],
    );
    expect(outputs.whereType<ForumBodyTextFlowInline>(), isEmpty);
  });

  test('a resolver cannot publish an input for a different actual node', () {
    final f = InlineImageFixture();
    final cursor = ForumBodyTextFlowCursor(
      document: f.document,
      reader: _reader,
      inlineImageResolver: (_, element, _) => f.images[1],
    );
    addTearDown(cursor.close);
    expect(
      () {
        while (!cursor.isComplete) {
          cursor.advance(maxEvents: 1);
        }
      },
      throwsA(
        isA<ForumBodyParagraphInputException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyParagraphInputFailure.identity,
        ),
      ),
    );
    expect(cursor.isClosed, isTrue);
  });

  test(
    'reentrant resolver retirement rejects the result before publication',
    () {
      final f = InlineImageFixture();
      late final ForumBodyTextFlowCursor cursor;
      cursor = ForumBodyTextFlowCursor(
        document: f.document,
        reader: _reader,
        inlineImageResolver: (_, element, _) {
          cursor.close();
          return f.images[0];
        },
      );
      addTearDown(cursor.close);
      expect(() {
        while (!cursor.isComplete) {
          cursor.advance(maxEvents: 1);
        }
      }, throwsStateError);
      expect(cursor.isClosed, isTrue);
      expect(cursor.current, isNull);
    },
  );
}
