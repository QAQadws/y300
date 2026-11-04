import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _ink = Color(0xff123456);

final class _Fixture {
  _Fixture(
    String html, {
    double height = 40,
    int entries = 64,
    double fontSize = 10,
    TextDirection direction = TextDirection.ltr,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'list-page',
      conversionIdentity: 'none',
    );
    reader = ForumBodyReaderStyle(
      textStyle: TextStyle(
        fontFamily: 'Ahem',
        fontSize: fontSize,
        height: 1,
        color: _ink,
      ),
      fontRevision: 'ahem-list-page',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    );
    cache = ForumBodyParagraphCache(
      maxEntries: entries,
      maxEstimatedBytes: 1 << 24,
    );
    session = ForumBodyTextPageSession(
      document: document,
      reader: reader,
      cache: cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 1000,
        maxParagraphs: 500,
        maxTextCodeUnits: 2000000,
        maxRuns: 10000,
        maxIssuedLeases: 256,
      ),
      layoutId: 'list-page',
      width: 240,
      height: height,
      maxNativeEntriesPerPage: entries,
      maxNativeEstimatedBytesPerPage: 1 << 24,
      maxNativeHandlesPerPage: 256,
      textScaler: textScaler,
    );
    addTearDown(() {
      session.close();
      cache.close();
    });
  }
  late final ForumBodyDocument document;
  late final ForumBodyReaderStyle reader;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;
  void drain() {
    var calls = 0;
    while (!session.isComplete) {
      if (++calls > 100000) fail('list session stalled');
      final step = session.advance(
        maxEvents: 1,
        maxLines: 1,
        maxFormatParts: 1,
      );
      expect(step.layoutsBuilt, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(step.madeProgress, isTrue);
    }
  }

  List<ForumBodyPreparedTextFragment> prepare(int page) {
    final job = session.openPagePreparation(page);
    try {
      for (var i = 0; !job.isReady && i < 100000; i++) {
        final step = job.advance(maxFragments: 1, maxParts: 1);
        expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
        expect(step.waitingForLayoutBudget, isFalse);
      }
      expect(job.isReady, isTrue);
      return job.takeFragments();
    } finally {
      job.close();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'wide scaled numbers reserve item gutter before body layout in both directions',
    () {
      for (final direction in TextDirection.values) {
        final f = _Fixture(
          '<ol start="12"><li>body<p>child</p></li><li>tail</li></ol>',
          height: 150,
          fontSize: 24,
          direction: direction,
          textScaler: TextScaler.linear(1.5),
        );
        f.drain();
        final placements = f.session.snapshot
            .expand((p) => p.fragments)
            .toList();
        expect(placements.first.width, lessThan(200));
        expect(placements[1].width, placements.first.width);
        for (var i = 0; i < f.session.snapshot.length; i++) {
          final bindings = f.prepare(i);
          for (final (j, body) in bindings.indexed) {
            final fragment = f.session.snapshot[i].fragments[j];
            for (final box in body.decorationBounds) {
              expect(box.left + fragment.left, greaterThanOrEqualTo(-1e-6));
              expect(box.right + fragment.left, lessThanOrEqualTo(240 + 1e-6));
            }
            body.close();
          }
        }
        expect(f.cache.activeLeases, 0);
      }
    },
  );
  test(
    'numbered pages retain one marker per item across body continuations',
    () {
      final f = _Fixture(
        '<ol><li>${List.filled(80, 'word').join(' ')}</li><li>last</li></ol>',
      );
      f.drain();
      expect(f.session.snapshot.length, greaterThan(2));
      expect(
        f.session.snapshot
            .expand((p) => p.fragments)
            .where((p) => p.listMarker != null),
        hasLength(2),
      );
      final labels = <String>[];
      for (var page = 0; page < f.session.snapshot.length; page++) {
        final bindings = f.prepare(page);
        for (final b in bindings) {
          if (b is ForumBodyPreparedListItemFragment) {
            labels.add(b.plan.picture.commands.length.toString());
            expect(b.projection, same(b.body.projection));
            expect(b.decorationBounds.single.left, isNegative);
          }
          expect(b.projection.text, isNot(contains('1.')));
          b.close();
        }
      }
      expect(labels, ['1', '1']);
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'empty rows and single-level ruby prepare source-bound body plus marker pictures',
    () {
      final f = _Fixture(
        '<ol><li></li><li><ruby>字<rt>じ</rt></ruby></li><li>tail</li></ol>',
        height: 80,
      );
      f.drain();
      final bindings = f.prepare(0);
      try {
        expect(bindings, hasLength(3));
        expect(
          bindings.every((b) => b is ForumBodyPreparedListItemFragment),
          isTrue,
        );
        final empty = bindings.first as ForumBodyPreparedListItemFragment;
        expect(empty.projection.text, isEmpty);
        expect(empty.body.lines, isEmpty);
        expect(empty.placement.baseline, greaterThan(0));
        expect(
          (bindings[1] as ForumBodyPreparedListItemFragment).body,
          isA<ForumBodyPreparedInlineFragment>(),
        );
        expect(() => f.session.preparePageLeases(0), throwsStateError);
      } finally {
        for (final b in bindings) {
          b.close();
        }
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'cached-only preparation never shapes or records and cold work resumes the same page',
    () {
      final f = _Fixture('<ol><li>body</li></ol>');
      f.drain();
      final job = f.session.openPagePreparation(0);
      final builds = f.cache.layoutBuildCount,
          pictures = f.cache.pictureBuildCount;
      try {
        for (var i = 0; !job.cacheMiss && i < 1000; i++) {
          expect(job.tryPrepareCached(maxParts: 1), isFalse);
        }
        expect(job.cacheMiss, isTrue);
        expect(f.cache.layoutBuildCount, builds);
        expect(f.cache.pictureBuildCount, pictures);
        for (var i = 0; !job.isReady && i < 1000; i++) {
          job.advance(maxFragments: 1, maxParts: 1);
        }
        expect(job.isReady, isTrue);
        for (final b in job.takeFragments()) {
          b.close();
        }
      } finally {
        job.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'cancel after body adoption releases body and all partial marker fonts',
    () {
      final f = _Fixture('<ol><li>body</li></ol>');
      f.drain();
      final job = f.session.openPagePreparation(0);
      for (var i = 0; f.cache.activeLeases == 0 && i < 1000; i++) {
        job.advance(maxFragments: 1, maxParts: 1);
      }
      expect(f.cache.activeLeases, greaterThan(0));
      job.close();
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'genuine external pin wait resumes without rebuilding body or losing marker input',
    () {
      final f = _Fixture('<ol><li>body</li></ol>', entries: 3);
      f.drain();
      final externalDoc = const ForumBodyParser().parse(
        html: '<p>external</p>',
        sourceId: 'other',
        conversionIdentity: 'none',
      );
      final styles = const ForumBodyStyleResolver().resolve(
        externalDoc,
        f.reader,
      );
      final content = const ForumBodyParagraphContentBuilder().build(
        document: externalDoc,
        styles: styles,
        path: '0',
      );
      final external = f.cache.acquire(content: content, width: 240);
      final job = f.session.openPagePreparation(0);
      try {
        for (var i = 0; !job.waitingForLayoutBudget && i < 1000; i++) {
          job.advance(maxFragments: 1, maxParts: 1);
        }
        expect(job.waitingForLayoutBudget, isTrue);
        external.release();
        for (var i = 0; !job.isReady && i < 1000; i++) {
          job.advance(maxFragments: 1, maxParts: 1);
        }
        expect(job.isReady, isTrue);
        for (final b in job.takeFragments()) {
          b.close();
        }
      } finally {
        external.release();
        job.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  testWidgets(
    'actual page pixels and body tap match independently shaped body and label',
    (tester) async {
      final f = _Fixture('<ol><li>one</li></ol>');
      f.drain();
      final bindings = f.prepare(0);
      const key = ValueKey('list-pixels');
      int? source;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              height: 40,
              child: RepaintBoundary(
                key: key,
                child: ForumBodyTextPageSurface.prepared(
                  snapshot: f.session.snapshot,
                  pageIndex: 0,
                  layoutId: 'list-page',
                  fragments: bindings,
                  onSourceTap: (_, p) {
                    source = p.sourceRune;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final body = TextPainter(
        text: const TextSpan(
          text: 'one',
          style: TextStyle(
            inherit: false,
            fontFamily: 'Ahem',
            fontSize: 10,
            height: 1,
            color: _ink,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 200, maxWidth: 200);
      final label = TextPainter(
        text: const TextSpan(
          text: '1.',
          style: TextStyle(
            inherit: false,
            fontFamily: 'Ahem',
            fontSize: 10,
            height: kTextHeightNone,
            color: _ink,
            decoration: TextDecoration.none,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      body.paint(canvas, const Offset(40, 0));
      label.paint(
        canvas,
        Offset(
          40 - label.width - label.height * .25,
          body.computeLineMetrics().first.baseline -
              label.computeLineMetrics().first.baseline,
        ),
      );
      final picture = recorder.endRecording();
      await tester.runAsync(() async {
        final expected = await picture.toImage(240, 40);
        final actual = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage(pixelRatio: 1);
        try {
          expect(
            (await actual.toByteData())!.buffer.asUint8List(),
            (await expected.toByteData())!.buffer.asUint8List(),
          );
        } finally {
          actual.dispose();
          expected.dispose();
          picture.dispose();
          body.dispose();
          label.dispose();
        }
      });
      tester.element(find.byType(ForumBodyTextPageSurface)).markNeedsBuild();
      await tester.pump();
      expect(bindings.first.isActive, isTrue);
      expect(tester.takeException(), isNull);
      await tester.tapAt(
        tester.getTopLeft(find.byKey(key)) + const Offset(42, 5),
      );
      expect(source, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(f.cache.activeLeases, 0);
    },
  );
}
